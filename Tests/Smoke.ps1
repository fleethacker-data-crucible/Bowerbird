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
 # Fairlead client: defaults, overrides, loopback only, key from Credential Manager, headers, and a real HTTP round trip against a fake Fairlead.
 . (Join-Path $root 'Private\BowerbirdLlm.ps1')
 . (Join-Path $root 'Private\BowerbirdStreaming.ps1')
 $llmVars=@('BOWERBIRD_FAIRLEAD_URL','BOWERBIRD_FAIRLEAD_MODEL','BOWERBIRD_FAIRLEAD_PRIVACY')
 $savedVars=@{};foreach($n in $llmVars){$savedVars[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
 $savedReader=$script:BowerbirdCredentialReader
 $job=$null
 try{
  $cfg=Get-BowerbirdLlmConfig
  Assert ($cfg.Url -eq 'http://127.0.0.1:8776/v1/chat/completions' -and $cfg.Model -eq 'auto' -and $cfg.Privacy -eq 'local' -and $cfg.Label -eq 'Bowerbird') 'Fairlead defaults'
  Assert (Test-BowerbirdLoopbackUrl -Url $cfg.Url) 'Default address is loopback'
  $env:BOWERBIRD_FAIRLEAD_URL='http://localhost:9000/v1/chat/completions/';$env:BOWERBIRD_FAIRLEAD_MODEL='smart';$env:BOWERBIRD_FAIRLEAD_PRIVACY='ANY'
  $cfg=Get-BowerbirdLlmConfig
  Assert ($cfg.Url -eq 'http://localhost:9000/v1/chat/completions' -and $cfg.Model -eq 'smart' -and $cfg.Privacy -eq 'any') 'Fairlead overrides'
  $env:BOWERBIRD_FAIRLEAD_PRIVACY='whatever'
  Assert ((Get-BowerbirdLlmConfig).Privacy -eq 'local') 'Unknown privacy value means local'
  $env:BOWERBIRD_FAIRLEAD_URL='https://ai.example.org/v1/chat/completions'
  $threw=$false;try{Assert-BowerbirdLlmUrl -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
  Assert ($threw -and $msg -match 'BOWERBIRD_FAIRLEAD_URL') 'A non-loopback address is refused and explained'
  foreach($n in $llmVars){[Environment]::SetEnvironmentVariable($n,$null)}
  # The stored key: UTF-16 text (as Fairlead writes it) or UTF-8; never anything else.
  Assert ((ConvertFrom-BowerbirdCredentialBytes -Bytes ([Text.Encoding]::Unicode.GetBytes('fl-abc123'))) -eq 'fl-abc123') 'UTF-16 key decoded'
  Assert ((ConvertFrom-BowerbirdCredentialBytes -Bytes ([Text.Encoding]::UTF8.GetBytes('fl-abc123'))) -eq 'fl-abc123') 'UTF-8 key decoded'
  Assert ($null -eq (ConvertFrom-BowerbirdCredentialBytes -Bytes ([byte[]](1,2,3,4)))) 'Unreadable bytes give no key'
  $script:BowerbirdCredentialReader={param([string]$Target) $global:askedTarget=$Target;return $null}
  $threw=$false;try{$null=Get-BowerbirdFairleadKey}catch{$threw=$true;$msg=$_.Exception.Message}
  Assert ($threw -and $msg -eq 'Open Fairlead and install a key for Bowerbird.' -and $global:askedTarget -eq 'Fairlead/Bowerbird') 'Missing credential is explained and asked for by name'
  $script:BowerbirdCredentialReader={param([string]$Target) return " Bearer 'fl-testkey123'`r`n"}
  Assert ((Get-BowerbirdFairleadKey) -eq 'fl-testkey123') 'Stored key is cleaned'
  $h=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)
  Assert ($h['Authorization'] -eq 'Bearer fl-testkey123' -and $h['X-Fairlead-Label'] -eq 'Bowerbird' -and $h['X-Fairlead-Privacy'] -eq 'local') 'Headers carry the key, the label and the privacy setting'
  # Real HTTP against a fake Fairlead on loopback: one JSON answer, one SSE answer.
  $probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0);$probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
  $cap=Join-Path $temp 'fake-fairlead-requests.txt';$ready=Join-Path $temp 'fake-fairlead-ready.txt'
  $job=Start-Job -ArgumentList $port,$cap,$ready -ScriptBlock {
   param($port,$cap,$ready)
   $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port);$l.Start()
   [IO.File]::WriteAllText($ready,'ok')
   try{
    for($n=0;$n -lt 2;$n++){
     $c=$l.AcceptTcpClient();$s=$c.GetStream();$s.ReadTimeout=5000
     $buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream;$need=-1
     while($true){
      $r=$s.Read($buf,0,$buf.Length);if($r -le 0){break};$ms.Write($buf,0,$r)
      $t=[Text.Encoding]::UTF8.GetString($ms.ToArray());$i=$t.IndexOf("`r`n`r`n")
      if($i -ge 0){
       if($need -lt 0){$m=[regex]::Match($t,'(?i)content-length:\s*(\d+)');$need=$i+4+[int]$m.Groups[1].Value}
       if($ms.Length -ge $need){break}
      }
     }
     $req=[Text.Encoding]::UTF8.GetString($ms.ToArray())
     [IO.File]::AppendAllText($cap,$req+"`n=====`n")
     if($req -match '"stream":\s*true'){
      $ct='text/event-stream'
      $body="data: {`"choices`":[{`"delta`":{`"content`":`"Hel`"}}]}`n`ndata: {`"choices`":[{`"delta`":{`"content`":`"lo`"}}]}`n`ndata: [DONE]`n`n"
     }else{
      $ct='application/json'
      $body='{"choices":[{"message":{"role":"assistant","content":"ok from fairlead"}}]}'
     }
     $bytes=[Text.Encoding]::UTF8.GetBytes($body)
     $head="HTTP/1.1 200 OK`r`nContent-Type: $ct`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
     $hb=[Text.Encoding]::ASCII.GetBytes($head);$s.Write($hb,0,$hb.Length);$s.Write($bytes,0,$bytes.Length);$s.Flush();$c.Close()
    }
   }finally{$l.Stop()}
  }
  $waited=0;while(-not (Test-Path -LiteralPath $ready) -and $waited -lt 100){Start-Sleep -Milliseconds 100;$waited++}
  Assert (Test-Path -LiteralPath $ready) 'Fake Fairlead started'
  $env:BOWERBIRD_FAIRLEAD_URL="http://127.0.0.1:$port/v1/chat/completions"
  $reply=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})
  Assert ($reply.Text -eq 'ok from fairlead' -and $reply.Model -eq 'auto') 'Chat goes to Fairlead and the answer is read'
  $out=New-Object IO.MemoryStream
  Invoke-BowerbirdStreamingChat -Response ([pscustomobject]@{OutputStream=$out}) -Messages @(@{role='user';content='x'})
  $sse=[Text.Encoding]::UTF8.GetString($out.ToArray())
  Assert ($sse -match 'event: start' -and $sse -match '"text":"Hel"' -and $sse -match '"text":"lo"' -and $sse -match 'event: done') 'Streaming relays Fairlead SSE'
  $null=Wait-Job -Job $job -Timeout 10
  $seen=[IO.File]::ReadAllText($cap)
  Assert (([regex]::Matches($seen,'(?im)^authorization:\s*Bearer fl-testkey123\s*$')).Count -eq 2) 'Both calls send the Fairlead key'
  Assert (([regex]::Matches($seen,'(?im)^x-fairlead-label:\s*Bowerbird\s*$')).Count -eq 2) 'Both calls send the label'
  Assert (([regex]::Matches($seen,'(?im)^x-fairlead-privacy:\s*local\s*$')).Count -eq 2) 'Both calls keep prompts local by default'
  Write-Host 'PASS: Fairlead configuration, loopback-only address, Credential Manager key, headers, chat and streaming' -ForegroundColor Green
 }finally{
  $script:BowerbirdCredentialReader=$savedReader
  foreach($n in $llmVars){[Environment]::SetEnvironmentVariable($n,$savedVars[$n])}
  if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
 }
}catch{Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
