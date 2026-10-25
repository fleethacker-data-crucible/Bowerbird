#requires -Version 5.1
<#
.SYNOPSIS
  Stops every running Bowerbird Studio server on this machine.
.DESCRIPTION
  Studio normally stops itself when its browser tab closes, or from End session in the sidebar.
  This script is the fallback for a hidden or forgotten window: it reads the runtime files that
  each server writes under %LOCALAPPDATA%\Bowerbird\Logs (and LocalDev\Logs), deleting stale
  ones, then looks for any PowerShell still running Start-BowerbirdStudio.ps1, and stops them all.
  No PIDs needed.
.PARAMETER Quiet
  Print nothing unless something was stopped.
.PARAMETER Port
  Stop only the server listening on this port (the tests use it so they never stop your own session).
.EXAMPLE
  powershell.exe -NoProfile -File .\Stop-Bowerbird.ps1
#>
[CmdletBinding()]param([switch]$Quiet,[ValidateRange(0,65535)][int]$Port=0)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Private\BowerbirdLifecycle.ps1')
$running=@(Get-BowerbirdProcesses)
if($Port -gt 0){$running=@($running|Where-Object {$_.Port -and [int]$_.Port -eq $Port})}
if($running.Count -eq 0){
 if(-not $Quiet){Write-Host 'No Bowerbird Studio server is running.' -ForegroundColor DarkGray}
 exit 0
}
foreach($p in $running){
 $where=if($p.Url){' at '+$p.Url}else{''}
 if(-not $Quiet){Write-Host ('Stopping Bowerbird Studio PID '+$p.Pid+$where) -ForegroundColor DarkGray}
}
$stopped=@(Stop-BowerbirdProcesses -Processes $running)
foreach($id in $stopped){Write-Host ('Stopped PID '+$id+'.') -ForegroundColor Yellow}
if($stopped.Count -lt $running.Count){exit 1}
exit 0
