#requires -Version 5.1
<#
 AI chat, SSE streaming, the vision rename pass and the opt-in Fairlead router, against a mock OpenAI-compatible
 provider on loopback (Tests\MockProvider.ps1). The responses in Tests\Fixtures are hand-written in the OpenAI
 wire format; none was recorded from a live model. Nothing here leaves this PC and no model is needed.
 What still needs a live model or a real Fairlead is listed in README.md under "Not verified here".
 Run: powershell.exe -NoProfile -File .\Tests\AiMock.ps1
#>
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'MockProvider.ps1')
. (Join-Path $root 'Private\BowerbirdLlm.ps1')
. (Join-Path $root 'Private\BowerbirdStreaming.ps1')
. (Join-Path $root 'Private\BowerbirdPass2.ps1')
$fixtures=Join-Path $PSScriptRoot 'Fixtures'
function Fixture([string]$Name){return [IO.File]::ReadAllText((Join-Path $fixtures $Name))}
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
$envNames=@('LLM_URL','LLM_MODEL','LLM_TOKEN','BOWERBIRD_AI_ENDPOINT_URL','BOWERBIRD_GROK_URL','AI_ENDPOINT_TOKEN','GENAI_TOKEN','DATABRICKS_TOKEN','BOWERBIRD_USE_FAIRLEAD','BOWERBIRD_FAIRLEAD_URL','BOWERBIRD_FAIRLEAD_MODEL','FAIRLEAD_TOKEN')
$savedEnv=@{};foreach($n in $envNames){$savedEnv[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
function Reset-Env{foreach($n in $envNames){[Environment]::SetEnvironmentVariable($n,$null)}}
function Read-Sse($Stream){
 # The events the browser would see: event name and parsed JSON data, in order.
 $text=[Text.Encoding]::UTF8.GetString($Stream.ToArray());$events=@()
 foreach($block in ($text -split "\n\n")){
  if($block -match '(?s)^event: (?<e>\w+)\ndata: (?<d>.+)$'){$events+=,@{event=$Matches['e'];data=($Matches['d']|ConvertFrom-Json)}}
 }
 return ,$events
}
function Invoke-Stream($Mock,[string]$Profile='Auto'){
 $response=[pscustomobject]@{OutputStream=(New-Object IO.MemoryStream)}
 Invoke-BowerbirdStreamingChat -Response $response -Messages @(@{role='user';content='tidy my screenshots'}) -Profile $Profile -TimeoutSeconds 20
 return ,(Read-Sse $response.OutputStream)
}
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdAiMock_'+[guid]::NewGuid().ToString('N'))
$mock=$null
try{
 New-Item -ItemType Directory -Path $work -Force|Out-Null
 $mock=Start-MockProvider
 $env:LLM_URL=$mock.Url;$env:LLM_MODEL='fixture-model'

 # --- Chat ---
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $reply=Invoke-BowerbirdChat -Messages @(@{role='system';content='You help.'},@{role='user';content='how do I sort invoices?'}) -MaxTokens 300
 Assert ($reply.Text -eq 'Group the invoices by year, then by vendor.') 'Chat returns the assistant text'
 Assert ($reply.Model -eq 'fixture-model' -and $reply.Profile -eq 'AiEndpoint') 'Chat reports model and profile'
 $request=$mock.State.Requests[$mock.State.Requests.Count-1]
 $sent=$request.Body|ConvertFrom-Json
 Assert ($request.Method -eq 'POST' -and $request.Path -eq '/v1/chat/completions') 'Chat POSTs to the configured path'
 Assert ($sent.model -eq 'fixture-model' -and $sent.max_tokens -eq 300 -and $sent.stream -eq $false -and @($sent.messages).Count -eq 2) 'Chat payload: model, max_tokens, stream=false, messages'
 Assert (-not $request.Headers.ContainsKey('authorization')) 'No Authorization header without a token on loopback'
 $env:LLM_TOKEN='  Bearer test-token-123 '
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
 $request=$mock.State.Requests[$mock.State.Requests.Count-1]
 Assert ($request.Headers['authorization'] -ceq 'Bearer test-token-123') 'Token is sanitized and sent once as Bearer'
 $env:LLM_TOKEN=$null
 Push-MockResponse $mock -Status 500 -Body 'upstream failure'
 $failed=$false;try{$null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})}catch{$failed=$true}
 Assert $failed 'A provider error fails the chat call'
 Pass 'AI chat against the mock provider (payload, token handling, errors)'

 # --- Streaming ---
 Push-MockResponse $mock -ContentType 'text/event-stream' -Body (Fixture 'chat-stream.sse')
 $events=Invoke-Stream $mock
 $names=@($events|ForEach-Object {$_.event})
 Assert ($names[0] -eq 'start' -and $names[-1] -eq 'done') ('Stream starts and ends: '+($names -join ','))
 $deltas=@($events|Where-Object {$_.event -eq 'delta'}|ForEach-Object {$_.data.text})
 Assert (($deltas -join '') -eq 'Move the screenshots into one folder.' -and $deltas.Count -eq 3) ('Deltas arrive in order, empty and malformed chunks skipped: '+($deltas -join '|'))
 Assert ($events[-1].data.characters -eq 'Move the screenshots into one folder.'.Length -and $events[0].data.model -eq 'fixture-model') 'done reports the character count; start reports the model'
 $sent=$mock.State.Requests[$mock.State.Requests.Count-1].Body|ConvertFrom-Json
 Assert ($sent.stream -eq $true -and $mock.State.Requests[$mock.State.Requests.Count-1].Headers['accept'] -match 'text/event-stream') 'Streaming request asks for stream=true and SSE'
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $events=Invoke-Stream $mock
 $deltas=@($events|Where-Object {$_.event -eq 'delta'}|ForEach-Object {$_.data.text})
 Assert ($deltas.Count -eq 1 -and $deltas[0] -eq 'Group the invoices by year, then by vendor.' -and $events[-1].event -eq 'done') 'A provider that declines streaming still delivers its JSON reply'
 Push-MockResponse $mock -Status 503 -Body 'busy'
 $events=Invoke-Stream $mock
 Assert ($events[-1].event -eq 'failure' -and $events[-1].data.error) 'A provider error ends the stream with a failure event'
 Pass 'SSE streaming: ordered deltas, JSON fallback, failure event'

 # --- Vision rename pass (second pass) ---
 $png=Join-Path $work 'Screenshot 2026-10-30 101500.png'
 [IO.File]::WriteAllBytes($png,[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='))
 $file=Get-Item -LiteralPath $png
 $pass1=[pscustomobject]@{Metadata=$null;Confidence=0.4;SuggestedName='2026-10-30_screenshot.png';Reasoning='filename pattern';DatePart='2026-10-30'}
 Push-MockResponse $mock -Body (Fixture 'vision-reply.json')
 $result=Invoke-BowerbirdPass2 -File $file -Pass1Result $pass1
 Assert ($result.Source -eq 'vision' -and $result.SuggestedName -ceq '2026-10-30_powershell-access-denied-error.png' -and $result.Confidence -gt 0.8) ('Vision reply becomes a dated slug name: '+$result.SuggestedName)
 $sent=$mock.State.Requests[$mock.State.Requests.Count-1].Body|ConvertFrom-Json
 $parts=@($sent.messages[1].content)
 Assert ($parts[0].type -eq 'text' -and $parts[1].type -eq 'image_url' -and $parts[1].image_url.url -match '^data:image/png;base64,iVBOR') 'The image goes as a data URL in an OpenAI image_url part'
 Push-MockResponse $mock -Body (Fixture 'vision-reply-fenced.json')
 $result=Invoke-BowerbirdPass2 -File $file -Pass1Result $pass1
 Assert ($result.SuggestedName -ceq '2026-10-30_outlook-inbox-triage.png') 'JSON inside a fenced or chatty reply is still found'
 Push-MockResponse $mock -Body (Fixture 'vision-reply-unsafe.json')
 $result=Invoke-BowerbirdPass2 -File $file -Pass1Result $pass1
 Assert ($result.SuggestedName -cmatch '^[0-9a-z_.-]+\.png$' -and $result.SuggestedName -notmatch '\.\.|[\\/:*?]') ('A hostile slug cannot reach the file name: '+$result.SuggestedName)
 Push-MockResponse $mock -Body '{"choices":[{"message":{"content":"I cannot describe this image."}}]}'
 $result=Invoke-BowerbirdPass2 -File $file -Pass1Result $pass1
 Assert ($result.Source -eq 'pass1-fallback' -and $result.SuggestedName -eq $pass1.SuggestedName) 'An unusable reply keeps the first-pass name'
 Push-MockResponse $mock -Status 500 -Body 'down'
 $result=Invoke-BowerbirdPass2 -File $file -Pass1Result $pass1 -WarningAction SilentlyContinue
 Assert ($result.Source -eq 'pass1-fallback' -and $result.Reasoning -match 'vision error') 'A provider error falls back to the first pass'
 Assert ((ConvertTo-BowerbirdSlug 'Hello, World! Extra words go on and on forever') -ceq 'hello-world-extra-words-go-on') 'Slugs are kebab-case, six words at most'
 Assert ($null -eq (ConvertTo-BowerbirdSlug '..\\**')) 'A slug with nothing safe in it is empty'
 Pass 'Vision rename pass: mock reply, image part, fenced JSON, hostile slug, fallbacks'

 # --- Fairlead: opt-in, off by default ---
 Reset-Env
 $env:BOWERBIRD_FAIRLEAD_URL=$mock.Url
 $cfg=Get-BowerbirdLlmConfig -Profile Auto
 Assert ($cfg.Profile -eq 'AiEndpoint' -and $cfg.Url -eq 'http://127.0.0.1:1234/v1/chat/completions') 'A configured Fairlead URL alone changes nothing: Auto stays on the local default'
 Assert (-not (Test-BowerbirdFairleadEnabled)) 'Fairlead is off by default'
 foreach($off in '0','false','no','off',' '){$env:BOWERBIRD_USE_FAIRLEAD=$off;Assert (-not (Test-BowerbirdFairleadEnabled)) ("BOWERBIRD_USE_FAIRLEAD='$off' stays off")}
 $env:BOWERBIRD_USE_FAIRLEAD='1'
 $cfg=Get-BowerbirdLlmConfig -Profile Auto
 Assert ($cfg.Profile -eq 'Fairlead' -and $cfg.Url -eq $mock.Url -and $cfg.Model -eq 'auto' -and -not $cfg.DefaultUrl) 'BOWERBIRD_USE_FAIRLEAD=1 routes Auto through Fairlead (model auto)'
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $reply=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
 $request=$mock.State.Requests[$mock.State.Requests.Count-1]
 $sent=$request.Body|ConvertFrom-Json
 Assert ($reply.Profile -eq 'Fairlead' -and $sent.model -eq 'auto' -and -not $request.Headers.ContainsKey('authorization')) 'Chat goes to the router without a token or a vault lookup'
 $env:BOWERBIRD_FAIRLEAD_MODEL='fleet-small'
 Assert ((Get-BowerbirdLlmConfig).Model -eq 'fleet-small') 'BOWERBIRD_FAIRLEAD_MODEL sets the model'
 $env:LLM_MODEL='explicit';Assert ((Get-BowerbirdLlmConfig).Model -eq 'explicit') 'LLM_MODEL wins';$env:LLM_MODEL=$null
 $env:FAIRLEAD_TOKEN='router-token'
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
 Assert ($mock.State.Requests[$mock.State.Requests.Count-1].Headers['authorization'] -ceq 'Bearer router-token') 'FAIRLEAD_TOKEN is sent when the router asks for one'
 $env:FAIRLEAD_TOKEN=$null
 Push-MockResponse $mock -ContentType 'text/event-stream' -Body (Fixture 'chat-stream.sse')
 $events=Invoke-Stream $mock
 Assert ($events[0].data.profile -eq 'Fairlead' -and $events[-1].event -eq 'done') 'Streaming also goes through Fairlead'
 $env:BOWERBIRD_USE_FAIRLEAD=$null
 Push-MockResponse $mock -Body (Fixture 'chat-completion.json')
 $reply=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'}) -Profile Fairlead
 Assert ($reply.Profile -eq 'Fairlead') 'Naming the Fairlead profile works with a configured URL, flag or not'
 $env:BOWERBIRD_FAIRLEAD_URL=$null;$env:BOWERBIRD_USE_FAIRLEAD='yes'
 $message='';try{$null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})}catch{$message=$_.Exception.Message}
 Assert ($message -match 'BOWERBIRD_FAIRLEAD_URL') 'Fairlead on without a URL says what to set (no silent fallback)'
 Assert ((ConvertTo-BowerbirdLlmProfile -Profile 'fairlead') -ceq 'Fairlead') 'Profile name is case-insensitive'
 $message='';try{$null=ConvertTo-BowerbirdLlmProfile -Profile 'Nope'}catch{$message=$_.Exception.Message}
 Assert ($message -match 'Fairlead') 'Unknown profile message lists Fairlead'
 Pass 'Fairlead is opt-in: off by default, needs a configured endpoint, routes chat and streaming'
 Write-Host ("PASS: Bowerbird AI mock tests ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Stop-MockProvider $mock
 foreach($n in $envNames){[Environment]::SetEnvironmentVariable($n,$savedEnv[$n])}
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
