#requires -Version 5.1
# No external modules. Execute in a disposable workspace:
# powershell -NoProfile -File .\Tests\Smoke.ps1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $root 'Private\BowerbirdActions.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdTest_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'input';$dest=Join-Path $temp 'output'
New-Item -ItemType Directory -Path $source,$dest -Force|Out-Null
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
try{
 Set-Content -LiteralPath (Join-Path $source 'first.txt') -Value 'Hello bowerbird search test' -Encoding UTF8
 Copy-Item -LiteralPath (Join-Path $source 'first.txt') -Destination (Join-Path $source 'copy.txt')
 Set-Content -LiteralPath (Join-Path $source 'empty.txt') -Value '' -NoNewline
 $index=New-BowerbirdIndex -Path $source -Recurse
 Assert ($index.Files.Count -eq 3) 'Index file count'
 Assert ((Get-BowerbirdText (Join-Path $source 'empty.txt')) -eq '') 'Empty text extraction'
 $hits=@(Search-BowerbirdIndex -Index $index -Query 'bowerbird')
 Assert ($hits.Count -eq 2) 'Search matches'
 $dups=@(Find-BowerbirdDuplicates -Index $index)
 Assert ($dups.Count -eq 1) 'Exact duplicates'
 $rulesPath=Join-Path $temp 'rules.json'
 '[{"Name":"Text","Extension":[".txt"],"Folder":"Text"}]'|Set-Content -LiteralPath $rulesPath
 $plan=New-BowerbirdPlan -Index $index -RulesPath $rulesPath -DestinationRoot $dest
 Assert ($plan.Operations.Count -eq 3) 'Plan count'
 $journal=Join-Path $temp 'journal.json'
 $applied=@(Invoke-BowerbirdPlan -Plan $plan -JournalPath $journal -Apply -Confirm:$false)
 Assert (@($applied|Where-Object {$_.Status -eq 'Applied'}).Count -eq 3) 'Applied statuses'
 Assert ((Get-ChildItem (Join-Path $dest 'Text') -File).Count -eq 3) 'Moved files'
 $restored=@(Undo-BowerbirdPlan -JournalPath $journal -Confirm:$false)
 Assert ($restored.Count -eq 3) 'Undo count'
 Assert ((Get-ChildItem $source -File).Count -eq 3) 'Restored files'
 Write-Host 'PASS: Bowerbird intelligence, duplicate, search, plan, apply and undo smoke test' -ForegroundColor Green
 # Lazarette item names: the override variable if set, else the default item.
 . (Join-Path $root 'Private\LazaretteBridge.ps1')
 . (Join-Path $root 'Private\BowerbirdLlm.ps1')
 $spec=$script:BowerbirdLlmVaultItems.AiEndpoint
 $keys=@($spec.EnvKeys)
 $itemVars=@('LLM_TOKEN','LLM_URL','BOWERBIRD_AI_ENDPOINT_URL','BOWERBIRD_GROK_URL','DATABRICKS_TOKEN')+@($script:BowerbirdLlmTokenEnv.AiEndpoint)+$keys
 $savedVars=@{};foreach($n in $itemVars){$savedVars[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
 try{
  function Import-BowerbirdLazaretteSession {param([switch]$Quiet);return $true}
  function Get-BowerbirdLazaretteSecretByName {param([string]$ServiceName);return ('secret-for-'+$ServiceName)}
  $cases=@(
   @{Set=@{};Want=$spec.Name},
   @{Set=@{$keys[0]='b-laz'};Want='b-laz'}
  )
  foreach($case in $cases){
   foreach($n in $keys){[Environment]::SetEnvironmentVariable($n,$null)}
   foreach($k in $case.Set.Keys){[Environment]::SetEnvironmentVariable($k,$case.Set[$k])}
   $got=Get-BowerbirdLlmToken -ForProfile AiEndpoint
   Assert ($got -eq ('secret-for-'+$case.Want)) ("Lazarette item order: expected $($case.Want), got $got")
   foreach($n in @($script:BowerbirdLlmTokenEnv.AiEndpoint)){[Environment]::SetEnvironmentVariable($n,$null)}
  }
  foreach($n in $keys){[Environment]::SetEnvironmentVariable($n,$null)}
  # Only the current names exist: a vault holding just a differently named item is not read.
  function Get-BowerbirdLazaretteSecretByName {param([string]$ServiceName);if($ServiceName -eq 'some-other-item'){return 'other-secret'};return $null}
  $threw=$false;try{$null=Get-BowerbirdLlmToken -ForProfile AiEndpoint}catch{$threw=$true}
  Assert $threw 'A differently named vault item is not read'
  Assert (@($script:BowerbirdLlmTokenEnv.AiEndpoint).Count -eq 1 -and @($script:BowerbirdLlmTokenEnv.AiEndpoint)[0] -eq 'AI_ENDPOINT_TOKEN') 'One token variable per profile'
  $env:AI_ENDPOINT_TOKEN='new-token'
  Assert ((Get-BowerbirdLlmToken -ForProfile AiEndpoint) -eq 'new-token') 'Current token variable read'
  # Profiles and endpoint configuration.
  $oldName='Gen'+'Ai';$threw=$false;try{$null=ConvertTo-BowerbirdLlmProfile -Profile $oldName}catch{$threw=$true}
  Assert $threw 'The retired profile name is rejected'
  $threw=$false;try{$null=ConvertTo-BowerbirdLlmProfile -Profile 'Nope'}catch{$threw=$true}
  Assert $threw 'Unknown profile rejected'
  # Default: the local phoenix-lai API on loopback, with its loaded-model name; no token needed there.
  foreach($n in @($script:BowerbirdLlmTokenEnv.AiEndpoint)){[Environment]::SetEnvironmentVariable($n,$null)}
  $cfg=Get-BowerbirdLlmConfig -Profile Auto
  Assert ($cfg.Profile -eq 'AiEndpoint' -and $cfg.Url -eq 'http://127.0.0.1:1234/v1/chat/completions') 'AiEndpoint defaults to local phoenix-lai'
  Assert ($cfg.DefaultUrl -and $cfg.Model -eq 'phoenixlai') 'Local default uses the loaded phoenix-lai model'
  Assert (Test-BowerbirdLoopbackUrl -Url $cfg.Url) 'Default endpoint is loopback'
  Assert (-not (Test-BowerbirdLoopbackUrl -Url 'https://ai.example.org/v1/chat/completions')) 'Remote URL is not loopback'
  Assert ($null -eq (Get-BowerbirdLlmAuthToken -Config $cfg)) 'No token needed for the local default'
  $global:sentHeaders=$null;$global:sentUri=$null
  function global:Invoke-RestMethod {param($Uri,$Method,$Headers,$Body,$ContentType,$TimeoutSec);$global:sentUri=$Uri;$global:sentHeaders=$Headers;return [pscustomobject]@{choices=@([pscustomobject]@{message=[pscustomobject]@{content='ok'}})}}
  try{
   $reply=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
   Assert ($reply.Text -eq 'ok' -and $global:sentUri -eq 'http://127.0.0.1:1234/v1/chat/completions') 'Chat posts to the local default'
   Assert (-not $global:sentHeaders.ContainsKey('Authorization')) 'No Authorization header without a token'
   $env:LLM_TOKEN='local-key'
   $null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
   Assert ($global:sentHeaders['Authorization'] -eq 'Bearer local-key') 'Optional token sent to the local endpoint when set'
   $env:LLM_TOKEN=$null
  }finally{Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue}
  # Overrides: the profile variable replaces the default; LLM_URL (shared) wins over both.
  $env:BOWERBIRD_AI_ENDPOINT_URL='https://ai.example.org/v1/chat/completions/'
  $cfg=Get-BowerbirdLlmConfig -Profile AiEndpoint
  Assert ($cfg.Url -eq 'https://ai.example.org/v1/chat/completions' -and -not $cfg.DefaultUrl -and $cfg.Model -ne 'phoenixlai') 'BOWERBIRD_AI_ENDPOINT_URL overrides the default'
  $env:LLM_URL='http://localhost:5000/v1/chat/completions'
  Assert ((Get-BowerbirdLlmConfig -Profile AiEndpoint).Url -eq $env:LLM_URL) 'LLM_URL overrides every profile'
  $env:LLM_URL=$null;$env:BOWERBIRD_AI_ENDPOINT_URL=$null
  # Grok is an outside provider: no built-in URL, explained before any token or network use.
  Assert ((Get-BowerbirdLlmConfig -Profile Grok).Url -eq '') 'No Grok URL built in'
  $msg='';try{$null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'}) -Profile Grok}catch{$msg=$_.Exception.Message}
  Assert ($msg -match 'BOWERBIRD_GROK_URL') 'Missing Grok URL explained'
  $env:BOWERBIRD_GROK_URL='https://databricks.example.org/serving-endpoints/x/invocations/'
  Assert ((Get-BowerbirdLlmConfig -Profile Grok).Url -eq 'https://databricks.example.org/serving-endpoints/x/invocations') 'Grok URL read from configuration'
  Write-Host 'PASS: Lazarette item names, token variables, profile names and endpoint configuration' -ForegroundColor Green
 }finally{foreach($n in $itemVars){[Environment]::SetEnvironmentVariable($n,$savedVars[$n])}}
}catch{Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
