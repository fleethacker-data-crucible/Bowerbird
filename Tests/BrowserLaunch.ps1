#requires -Version 5.1
# End-to-end test of Start-Bowerbird.bat and real Edge browser rendering.
[CmdletBinding()]param([switch]$SkipBrowser)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$launcher=Join-Path $repo 'Start-Bowerbird.bat'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdGuiLaunch_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
$stdout=Join-Path $temp 'gui.stdout.txt';$stderr=Join-Path $temp 'gui.stderr.txt'
$child=$null;$edge=$null
function Assert([bool]$Value,[string]$Reason){if(-not $Value){throw ('GUI LAUNCH TEST: '+$Reason)}}
try{
 [IO.File]::WriteAllText((Join-Path $temp 'BowerbirdGuiProbe.txt'),'Bowerbird GUI integration test')
 # --stay: several headless Edge sessions open and close this one server below, which would
 # otherwise stop itself when the first tab closes. It also proves the BAT passes --options through.
 $cmd='""'+$launcher+'" -Root "'+$temp+'" -Port 0 -NoBrowser --stay"'
 $child=Start-Process -FilePath $env:ComSpec -ArgumentList @('/d','/c',$cmd) -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $session=''
 for($i=0;$i -lt 80;$i++){
  Start-Sleep -Milliseconds 250
  if(Test-Path -LiteralPath $stdout){
   $lines=@(Get-Content -LiteralPath $stdout -ErrorAction SilentlyContinue)
   $match=@($lines|Where-Object {$_ -like 'Session URL:*'}|Select-Object -First 1)
   if($match.Count){$session=([string]$match[0]).Substring(13).Trim();break}
  }
  if($child.HasExited){throw ('GUI BAT launcher exited: '+$child.ExitCode+' '+(Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue))}
 }
 Assert ([bool]$session) 'Main BAT never produced a Studio session URL'
 $site=[uri]$session
 Assert ($site.Host -eq '127.0.0.1') 'GUI URL must be loopback-only'
 $landing=Invoke-WebRequest -Uri $session -UseBasicParsing -TimeoutSec 15
 Assert ($landing.StatusCode -eq 200 -and [bool]($landing.Content -match 'BOWERBIRD')) 'GUI HTML is not served'
 $token=[uri]::UnescapeDataString(($site.Query.TrimStart('?') -split '=')[1])
 $health=Invoke-RestMethod -Uri ($site.GetLeftPart([UriPartial]::Authority)+'/api/status') -Method Post -ContentType 'application/json' -Headers @{'X-Bowerbird-Token'=$token} -Body '{}' -TimeoutSec 15
 Assert ($health.ok -and $health.port -eq $site.Port) 'GUI status is unreachable'
 if(-not $SkipBrowser){
  $programFiles86=[Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  $edgePaths=@(
   (Join-Path $programFiles86 'Microsoft\Edge\Application\msedge.exe')
   (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe')
  )|Where-Object {$_ -and (Test-Path -LiteralPath $_ -PathType Leaf)}
  $edgeBinary=@($edgePaths|Select-Object -First 1)
  if($edgeBinary.Count){
   # The CDP harness waits for Running and BowerbirdGuiProbe.txt in the live DOM
   # before exercising folder switching and diagnostics. Edge --dump-dom can exit
   # successfully with empty stdout on the runner; do not use that as a render gate.
   Assert ([bool](Get-Command node -ErrorAction SilentlyContinue)) 'Node is required for the real Edge GUI test'
   $alternate=Join-Path $temp 'AlternateForGui'
   [IO.Directory]::CreateDirectory($alternate)|Out-Null
   [IO.File]::WriteAllText((Join-Path $alternate 'BrowserSelected.txt'),'Selected from the actual GUI')
   & node (Join-Path $repo 'Tests\GuiFolderSwitch.js') $session $alternate $edgeBinary[0]
   if($LASTEXITCODE -ne 0){throw 'Real Edge GUI rendering and folder selector test failed'}

  }else{Write-Host 'SKIP: Edge not present; launcher + HTTP integration checks passed' -ForegroundColor Yellow}
 }
 Write-Host 'PASS: Start-Bowerbird.bat launched Studio and served authenticated browser/API responses' -ForegroundColor Green
 # --stay kept the server alive after the browser tabs closed; Stop-Bowerbird.ps1 must find and stop it without a PID.
 . (Join-Path $repo 'Private\BowerbirdLifecycle.ps1')
 $mine=@(Get-BowerbirdProcesses|Where-Object {$_.Port -eq $site.Port})
 Assert ($mine.Count -eq 1) 'Runtime file lists the launched server'
 $presence=Invoke-RestMethod -Uri ($site.GetLeftPart([UriPartial]::Authority)+'/api/heartbeat') -Method Post -ContentType 'application/json' -Headers @{'X-Bowerbird-Token'=$token} -Body '{"tab":"launch-test"}' -TimeoutSec 15
 Assert (-not $presence.autoStop) '--stay passed through the BAT launcher turns auto-stop off'
 $stopOutput=& powershell.exe -NoProfile -NonInteractive -File (Join-Path $repo 'Stop-Bowerbird.ps1') -Port $site.Port 2>&1|Out-String
 Write-Host $stopOutput.Trim()
 Assert ([bool]($stopOutput -match ('Stopped PID '+$mine[0].Pid))) 'Stop-Bowerbird.ps1 reports the PID it stopped'
 Assert (-not (Get-Process -Id $mine[0].Pid -ErrorAction SilentlyContinue)) 'Stop-Bowerbird.ps1 stopped the server'
 Assert (-not (Test-Path -LiteralPath $mine[0].RuntimeFile)) 'Stop-Bowerbird.ps1 removed the runtime file'
 Write-Host 'PASS: --stay pass-through and Stop-Bowerbird.ps1 stopped the running server' -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 if(Test-Path -LiteralPath $stderr){Write-Host (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}
 if(Test-Path -LiteralPath $stdout){Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
 throw
}finally{
 if($edge -and -not $edge.HasExited){try{Stop-Process -Id $edge.Id -Force}catch{}}
 if($child -and -not $child.HasExited){
  # The child can exit between the HasExited check and taskkill; under Stop, taskkill's 'not found' on stderr would fail the run.
  try{& taskkill.exe /PID $child.Id /T /F 2>$null|Out-Null}catch{}
 }
 Start-Sleep -Milliseconds 200
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
