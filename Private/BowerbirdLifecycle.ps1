#requires -Version 5.1
# Bowerbird Studio lifecycle: the browser tab owns the server.
# Dot-sourced by Start-BowerbirdStudio.ps1 (presence rule, runtime file, single-instance guard)
# and by Stop-Bowerbird.ps1 (find and stop every running server without knowing PIDs).
# Presence functions take -Now so tests can simulate time instead of sleeping.

function New-BowerbirdPresence {
 [CmdletBinding()]param([bool]$AutoStop=$true,[int]$TimeoutSeconds=20,[int]$LeavingGraceSeconds=5)
 return [pscustomobject]@{
  AutoStop=$AutoStop
  Timeout=[TimeSpan]::FromSeconds($TimeoutSeconds)
  LeavingGrace=[TimeSpan]::FromSeconds($LeavingGraceSeconds)
  Tabs=@{}
  Jobs=0
  BusyEndedAt=$null
 }
}

function Get-BowerbirdTabGoneAt {
 # A tab counts as gone 20 s after its last heartbeat, or 5 s after its leaving signal. The server
 # is single-threaded, so heartbeats sent while a long request (index, apply, AI...) ran are still
 # queued when it ends: give them the leaving grace (5 s) after the job to arrive before judging.
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence,[Parameter(Mandatory)]$Tab)
 if($null -ne $Tab.LeavingAt){$goneAt=([DateTime]$Tab.LeavingAt).Add($Presence.LeavingGrace)}
 else{$goneAt=([DateTime]$Tab.LastSeen).Add($Presence.Timeout)}
 if($null -ne $Presence.BusyEndedAt){
  $afterJob=([DateTime]$Presence.BusyEndedAt).Add($Presence.LeavingGrace)
  if($afterJob -gt $goneAt){$goneAt=$afterJob}
 }
 return $goneAt
}

function Register-BowerbirdPresence {
 # Recorded by POST /api/heartbeat. Each page load has its own tab id, so a reload (leaving, then a
 # heartbeat from the new page) and several open tabs both keep the server alive.
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence,[string]$Tab,[switch]$Leaving,[DateTime]$Now=[DateTime]::UtcNow)
 if([string]::IsNullOrEmpty($Tab) -or $Tab -notmatch '^[A-Za-z0-9_-]{1,64}$'){$Tab='default'}
 $entry=$Presence.Tabs[$Tab]
 if($null -eq $entry){
  if($Presence.Tabs.Count -ge 64){
   foreach($key in @($Presence.Tabs.Keys)){
    if((Get-BowerbirdTabGoneAt -Presence $Presence -Tab $Presence.Tabs[$key]) -le $Now){$Presence.Tabs.Remove($key)}
   }
  }
  $entry=[pscustomobject]@{LastSeen=$Now;LeavingAt=$null}
  $Presence.Tabs[$Tab]=$entry
 }
 if($Leaving){$entry.LeavingAt=$Now}
 else{$entry.LastSeen=$Now;$entry.LeavingAt=$null}
}

function Enter-BowerbirdJob {
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence)
 $Presence.Jobs=$Presence.Jobs+1
}

function Exit-BowerbirdJob {
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence,[DateTime]$Now=[DateTime]::UtcNow)
 if($Presence.Jobs -gt 0){$Presence.Jobs=$Presence.Jobs-1}
 $Presence.BusyEndedAt=$Now
}

function Test-BowerbirdBrowserGone {
 # True when every tab that ever connected is gone and no job is running: the server should stop.
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence,[DateTime]$Now=[DateTime]::UtcNow)
 if(-not $Presence.AutoStop){return $false}
 if($Presence.Jobs -gt 0){return $false}
 # Nothing ever connected (for example -NoBrowser, or the browser could not open): never auto-stop.
 if($Presence.Tabs.Count -eq 0){return $false}
 foreach($entry in @($Presence.Tabs.Values)){
  if((Get-BowerbirdTabGoneAt -Presence $Presence -Tab $entry) -gt $Now){return $false}
 }
 return $true
}

function Get-BowerbirdPresenceState {
 [CmdletBinding()]param([Parameter(Mandatory)]$Presence,[DateTime]$Now=[DateTime]::UtcNow)
 $alive=0
 foreach($entry in @($Presence.Tabs.Values)){
  if($null -eq $entry.LeavingAt -and (Get-BowerbirdTabGoneAt -Presence $Presence -Tab $entry) -gt $Now){$alive++}
 }
 return @{ok=$true;autoStop=[bool]$Presence.AutoStop;alive=$alive;busy=($Presence.Jobs -gt 0)
  timeoutSeconds=[int]$Presence.Timeout.TotalSeconds;leavingGraceSeconds=[int]$Presence.LeavingGrace.TotalSeconds}
}

function Get-BowerbirdAutoStopSetting {
 # Off switch: BOWERBIRD_AUTO_STOP=0 (also false/no/off) in the environment, or in Config\bowerbird.env.
 # The environment variable wins when both are set.
 [CmdletBinding()]param([string]$ConfigPath,[string]$EnvironmentValue=$env:BOWERBIRD_AUTO_STOP)
 $value=$EnvironmentValue
 if([string]::IsNullOrWhiteSpace($value) -and $ConfigPath -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)){
  foreach($line in @(Get-Content -LiteralPath $ConfigPath -ErrorAction SilentlyContinue)){
   if([string]$line -match '^\s*BOWERBIRD_AUTO_STOP\s*=\s*(.*?)\s*$'){$value=$Matches[1].Trim([char]34,[char]39)}
  }
 }
 if([string]::IsNullOrWhiteSpace($value)){return $true}
 return ($value.Trim() -notmatch '^(0|false|no|off)$')
}

function Test-BowerbirdCanPrompt {
 # Read-Host on a redirected or -NonInteractive console either throws or reads an empty line
 # (which would count as "yes"), so never prompt there.
 # Redirected output means nobody can see the question either (CI, a hidden window).
 try{if([Console]::IsInputRedirected -or [Console]::IsOutputRedirected){return $false}}catch{return $false}
 if(-not [Environment]::UserInteractive){return $false}
 foreach($arg in [Environment]::GetCommandLineArgs()){if([string]$arg -match '^-NonI'){return $false}}
 return $true
}

function Get-BowerbirdRuntimeDirectories {
 # The app keeps its logs under %LOCALAPPDATA%\Bowerbird (never the program folder, which may be
 # read-only), so runtime files live in those Logs folders, not in a logs\ folder next to the scripts.
 $base=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
 if(-not $base){$base=[IO.Path]::GetTempPath()}
 $dirs=@((Join-Path $base 'Bowerbird\Logs'),(Join-Path $base 'Bowerbird\LocalDev\Logs'))
 if($env:BOWERBIRD_DATA_DIR){try{. (Join-Path $PSScriptRoot 'BowerbirdDataDir.ps1');$dirs+=(Resolve-BowerbirdDataLocations).Logs}catch{}}
 return $dirs
}

function Write-BowerbirdRuntimeFile {
 # logs\bowerbird-server-<pid>.json: pid, port, url and start time. Never the session token.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Directory,[int]$Port,[string]$Url,[string]$Transport,[switch]$LocalDev)
 [IO.Directory]::CreateDirectory($Directory)|Out-Null
 $path=Join-Path $Directory ('bowerbird-server-'+$PID+'.json')
 $info=[ordered]@{app='Bowerbird Studio';pid=$PID;port=$Port;url=$Url;startedAt=[DateTime]::UtcNow.ToString('o');transport=$Transport;localDev=[bool]$LocalDev}
 [IO.File]::WriteAllText($path,(ConvertTo-Json -InputObject $info -Compress),(New-Object Text.UTF8Encoding $false))
 return $path
}

function Remove-BowerbirdRuntimeFile {
 [CmdletBinding()]param([string]$Path)
 if($Path){Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue}
}

function Test-BowerbirdServerProcess {
 # The PID in a runtime file is live only while it is still a PowerShell process that started
 # before the file was written (a reused PID belongs to a newer process).
 [CmdletBinding()]param([int]$ProcessId,$StartedAt)
 $proc=Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
 if(-not $proc){return $false}
 if($proc.ProcessName -notmatch '^(powershell|pwsh)$'){return $false}
 $started=[DateTime]::MinValue
 if($StartedAt -is [DateTime]){$started=$StartedAt.ToUniversalTime()}
 elseif($StartedAt -and [DateTime]::TryParse([string]$StartedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$started)){$started=$started.ToUniversalTime()}
 else{return $true}
 try{if($proc.StartTime.ToUniversalTime() -gt $started.AddSeconds(5)){return $false}}catch{}
 return $true
}

function Get-BowerbirdProcesses {
 # Running Bowerbird Studio servers: from the runtime files first (stale ones, whose PID is dead,
 # are deleted on sight), then any PowerShell whose command line runs Start-BowerbirdStudio.ps1.
 [CmdletBinding()]param([string[]]$Directory=(Get-BowerbirdRuntimeDirectories),[int]$ExcludePid=$PID)
 $found=@{}
 foreach($dir in @($Directory)){
  if(-not $dir -or -not (Test-Path -LiteralPath $dir -PathType Container)){continue}
  foreach($file in @(Get-ChildItem -LiteralPath $dir -Filter 'bowerbird-server-*.json' -File -ErrorAction SilentlyContinue)){
   $info=$null
   try{$info=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop|ConvertFrom-Json}catch{}
   $id=0
   if($info -and $info.pid){$id=[int]$info.pid}
   if($id -le 0 -or -not (Test-BowerbirdServerProcess -ProcessId $id -StartedAt $info.startedAt)){
    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
    continue
   }
   if($id -eq $ExcludePid){continue}
   $found[$id]=[pscustomobject]@{Pid=$id;Port=$info.port;Url=[string]$info.url;StartedAt=$info.startedAt;RuntimeFile=$file.FullName}
  }
 }
 try{
  foreach($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop)){
   $id=[int]$p.ProcessId
   if($id -eq $ExcludePid -or $found.ContainsKey($id)){continue}
   if([string]$p.CommandLine -match 'Start-BowerbirdStudio\.ps1'){
    $found[$id]=[pscustomobject]@{Pid=$id;Port=$null;Url='';StartedAt=$p.CreationDate;RuntimeFile=''}
   }
  }
 }catch{}
 return @($found.Values|Sort-Object Pid)
}

function Stop-BowerbirdProcesses {
 # Stops the given (or every running) Bowerbird Studio server, waits for it to exit so its port is
 # free, removes its runtime file and returns the PIDs stopped. Failures are warnings, not errors.
 [CmdletBinding()]param([object[]]$Processes,[string[]]$Directory=(Get-BowerbirdRuntimeDirectories))
 if($null -eq $Processes){$Processes=@(Get-BowerbirdProcesses -Directory $Directory)}
 $stopped=New-Object 'System.Collections.Generic.List[int]'
 foreach($p in @($Processes)){
  if($null -eq $p -or [int]$p.Pid -eq $PID){continue}
  $id=[int]$p.Pid
  try{
   Stop-Process -Id $id -Force -ErrorAction Stop
   $stopped.Add($id)
  }catch{
   if(-not (Get-Process -Id $id -ErrorAction SilentlyContinue)){$stopped.Add($id)}
   else{Write-Warning ('Could not stop Bowerbird Studio PID '+$id+': '+$_.Exception.Message)}
  }
  if($p.RuntimeFile){Remove-BowerbirdRuntimeFile -Path $p.RuntimeFile}
  foreach($dir in @($Directory)){if($dir){Remove-BowerbirdRuntimeFile -Path (Join-Path $dir ('bowerbird-server-'+$id+'.json'))}}
 }
 foreach($id in $stopped){try{Wait-Process -Id $id -Timeout 10 -ErrorAction SilentlyContinue}catch{}}
 return @($stopped.ToArray())
}
