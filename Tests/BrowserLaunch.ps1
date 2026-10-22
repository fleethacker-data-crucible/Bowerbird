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
 $cmd='""'+$launcher+'" -Root "'+$temp+'" -Port 0 -NoBrowser"'
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
   $flags=@('--headless=new','--disable-gpu','--disable-extensions','--disable-background-networking','--no-first-run','--no-default-browser-check',('--user-data-dir="'+$profile+'"'),'--dump-dom',('"'+$session+'"'))
   $edge=Start-Process -FilePath $edgeBinary[0] -ArgumentList $flags -RedirectStandardOutput $dump -RedirectStandardError $edgeErr -PassThru
   for($n=0;$n -lt 100 -and -not $edge.HasExited;$n++){Start-Sleep -Milliseconds 250}
   if(-not $edge.HasExited){try{Stop-Process -Id $edge.Id -Force}catch{};throw 'Edge headless DOM rendering timed out'}
   $html=if(Test-Path -LiteralPath $dump){Get-Content -LiteralPath $dump -Raw}else{''}
   Assert ($html -match 'Local server connected') 'Browser JavaScript never populated connection status'
   Assert ($html -match 'BowerbirdGuiProbe\.txt') 'Browser JavaScript never populated the file explorer'
   Write-Host 'PASS: Edge executed GUI JavaScript and rendered file explorer' -ForegroundColor Green
  }else{Write-Host 'SKIP: Edge not present; launcher + HTTP integration checks passed' -ForegroundColor Yellow}
 }
 Write-Host 'PASS: Start-Bowerbird.bat launched Studio and served authenticated browser/API responses' -ForegroundColor Green
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
