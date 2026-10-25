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
 Assert ($landing.StatusCode -eq 200 -and $landing.Content -match 'BOWERBIRD') 'GUI HTML is not served'
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
   $dump=Join-Path $temp 'edge-dom.txt'
   $edgeErr=Join-Path $temp 'edge-errors.txt'
   $profile=Join-Path $temp 'edge-profile'
   $flags=@('--headless=new','--disable-gpu','--disable-extensions','--disable-background-networking','--no-first-run','--no-default-browser-check','--virtual-time-budget=6500',('--user-data-dir="'+$profile+'"'),'--dump-dom',('"'+$session+'"'))
   $edge=Start-Process -FilePath $edgeBinary[0] -ArgumentList $flags -RedirectStandardOutput $dump -RedirectStandardError $edgeErr -PassThru
   for($n=0;$n -lt 100 -and -not $edge.HasExited;$n++){Start-Sleep -Milliseconds 250}
   if(-not $edge.HasExited){try{Stop-Process -Id $edge.Id -Force}catch{};throw 'Edge headless DOM rendering timed out'}
   $html=if(Test-Path -LiteralPath $dump){Get-Content -LiteralPath $dump -Raw}else{''}
   if($html -notmatch 'Local server connected' -or $html -notmatch 'BowerbirdGuiProbe\.txt'){
    foreach($name in @('notice','file-table','connection')){
     $at=$html.IndexOf('id="'+$name+'"')
     if($at -ge 0){Write-Host ("DOM "+$name+": "+$html.Substring([Math]::Max(0,$at-110),[Math]::Min(550,$html.Length-[Math]::Max(0,$at-110))))}
    }
    $diagnostic=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Bowerbird\Logs'
    $latest=Get-ChildItem -LiteralPath $diagnostic -Filter 'studio-*.jsonl' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
    if($latest){Write-Host 'Recent local request events:';Get-Content -LiteralPath $latest.FullName -Tail 14|ForEach-Object {Write-Host $_}}
    if(Test-Path $edgeErr){Write-Host ((Get-Content $edgeErr -Tail 8) -join [Environment]::NewLine)}
   }
   Assert ($html -match 'Local server connected') 'Browser JavaScript never populated connection status'
   Assert ($html -match 'BowerbirdGuiProbe\.txt') 'Browser JavaScript never populated the file explorer'
   Write-Host 'PASS: Edge executed GUI JavaScript and rendered file explorer' -ForegroundColor Green
   if(Get-Command node -ErrorAction SilentlyContinue){
    $alternate=Join-Path $temp 'AlternateForGui'
    [IO.Directory]::CreateDirectory($alternate)|Out-Null
    [IO.File]::WriteAllText((Join-Path $alternate 'BrowserSelected.txt'),'Selected from the actual GUI')
    & node (Join-Path $repo 'Tests\GuiFolderSwitch.js') $session $alternate $edgeBinary[0]
    if($LASTEXITCODE -ne 0){throw 'Real Edge GUI folder selector test failed'}
   }else{Write-Host 'SKIP: Node is unavailable on CI; browser-only folder selector test omitted'}

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
 Assert ($stopOutput -match ('Stopped PID '+$mine[0].Pid)) 'Stop-Bowerbird.ps1 reports the PID it stopped'
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
  & taskkill.exe /PID $child.Id /T /F 2>$null|Out-Null
 }
 Start-Sleep -Milliseconds 200
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
