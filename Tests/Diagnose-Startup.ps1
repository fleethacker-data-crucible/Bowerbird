#requires -Version 5.1
# Safe, no-network diagnostic probe for Bowerbird GUI startup.
[CmdletBinding()]param([int]$PreferredPort=8767)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$checks=New-Object 'Collections.Generic.List[object]'
function Add-Check([string]$Name,[bool]$Ok,[string]$Detail){
 $checks.Add([pscustomobject]@{Check=$Name;Result=if($Ok){'PASS'}else{'FAIL'};Details=$Detail})
}
$ok=$true
try{
 Add-Check 'Windows PowerShell 5.1' ($PSVersionTable.PSVersion.Major -eq 5) ("Version "+$PSVersionTable.PSVersion)
 Add-Check 'Apartment state' ($host.Runspace.ApartmentState -eq 'STA') ([string]$host.Runspace.ApartmentState)
 $required=@('Start-BowerbirdStudio.ps1','Stop-Bowerbird.ps1','Private\BowerbirdLoopback.ps1','Private\BowerbirdLifecycle.ps1','Web\index.html','Web\app.js','Web\lifecycle.js','Web\style.css','Web\shell.js','Web\icons.js','Web\vendor\fleet\fleet.css','assets\brand\mark.svg')
 foreach($file in $required){
  $exists=Test-Path -LiteralPath (Join-Path $repo $file) -PathType Leaf
  Add-Check ('Required file: '+$file) $exists $(if($exists){'Present'}else{'Missing'})
 }
 $syntax=New-Object 'Collections.Generic.List[string]'
 foreach($file in Get-ChildItem -LiteralPath $repo -Filter '*.ps1' -File -Recurse){
  $tokens=$null;$errors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  foreach($error in $errors){$syntax.Add(($file.Name+': '+$error.Message))}
 }
 Add-Check 'PowerShell source syntax' ($syntax.Count -eq 0) $(if($syntax.Count){$syntax -join '; '}else{'All scripts parse'})
 $base=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
 if(-not $base){$base=[IO.Path]::GetTempPath()}
 $dir=Join-Path $base 'Bowerbird\State'
 try{
  [IO.Directory]::CreateDirectory($dir)|Out-Null
  $test=Join-Path $dir ('write-test-'+[guid]::NewGuid().ToString('N'))
  [IO.File]::WriteAllText($test,'ok');Remove-Item -LiteralPath $test -Force
  Add-Check 'User state directory' $true 'Writable'
 }catch{Add-Check 'User state directory' $false $_.Exception.Message}
 . (Join-Path $repo 'Private\BowerbirdLoopback.ps1')
 $binding=Start-BowerbirdLoopback -Port 0
 try{Add-Check 'Loopback TCP listener' ($binding.Port -gt 0) ('127.0.0.1:'+$binding.Port)}
 finally{$binding.Listener.Stop()}
 try{
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,$PreferredPort)
  $listener.Start()
  $listener.Stop()
  Add-Check 'Preferred GUI port' $true ("$PreferredPort available")
 }catch{
  # This is not a startup failure. Studio dynamically selects another free port.
  Add-Check 'Preferred GUI port' $true ("$PreferredPort busy or reserved; automatic port allocation will be used")
 }
 . (Join-Path $repo 'Private\BowerbirdLifecycle.ps1')
 $running=@(Get-BowerbirdProcesses)
 # Informational: a running server is not a failure, but the launcher will offer to replace it.
 Add-Check 'Running Studio servers' $true $(if($running.Count){($running|ForEach-Object {'PID '+$_.Pid}) -join ', '}else{'None'})
 $machine=Get-ExecutionPolicy -List
 Write-Host ''
 Write-Host 'Effective PowerShell execution policy (read-only):' -ForegroundColor Cyan
 $machine|Format-Table -AutoSize
}catch{
 Add-Check 'Diagnostic initialization' $false $_.Exception.Message
}
Write-Host ''
Write-Host 'BOWERBIRD STARTUP DIAGNOSTICS' -ForegroundColor Cyan
$checks|Format-Table -AutoSize -Wrap
Write-Host ('Logs: '+(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Bowerbird\Logs')) -ForegroundColor DarkGray
if(@($checks|Where-Object {$_.Result -eq 'FAIL'}).Count){
 Write-Host 'A startup prerequisite failed. Review the table before launching.' -ForegroundColor Red
 exit 1
}
Write-Host 'Diagnostics passed. Run Start-Bowerbird.bat to launch GUI.' -ForegroundColor Green
