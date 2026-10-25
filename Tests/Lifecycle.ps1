#requires -Version 5.1
# Unit test of the Studio lifecycle rule (the browser tab owns the server), the off switch and the
# runtime files. Time is simulated with -Now, so nothing sleeps for 20 s.
# Run: powershell.exe -NoProfile -File .\Tests\Lifecycle.ps1
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
. (Join-Path $repo 'Private\BowerbirdLifecycle.ps1')
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdLifecycle_'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp)|Out-Null
try{
 $t0=[DateTime]::UtcNow
 $p=New-BowerbirdPresence
 Assert (-not (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddHours(1))) 'Nothing ever connected (-NoBrowser): never auto-stop'

 Register-BowerbirdPresence -Presence $p -Tab 'a' -Now $t0
 Assert (-not (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddSeconds(19))) 'Within 20 s of the last heartbeat'
 Assert (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddSeconds(21)) 'No heartbeat for longer than 20 s'

 Register-BowerbirdPresence -Presence $p -Tab 'a' -Now $t0.AddSeconds(10)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddSeconds(21))) 'A newer heartbeat restarts the 20 s'

 # Tab closed: leaving signal, then 5 s grace.
 Register-BowerbirdPresence -Presence $p -Tab 'a' -Leaving -Now $t0.AddSeconds(12)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddSeconds(16))) 'Inside the leaving grace: a reload may follow'
 Assert (Test-BowerbirdBrowserGone -Presence $p -Now $t0.AddSeconds(17.5)) 'Tab closed and the 5 s grace passed'

 # Reload: the old page leaves, the new page (new tab id) heartbeats inside the grace.
 $r=New-BowerbirdPresence
 Register-BowerbirdPresence -Presence $r -Tab 'old' -Now $t0
 Register-BowerbirdPresence -Presence $r -Tab 'old' -Leaving -Now $t0.AddSeconds(1)
 Register-BowerbirdPresence -Presence $r -Tab 'new' -Now $t0.AddSeconds(2)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $r -Now $t0.AddSeconds(10))) 'Reload does not stop the server'
 Assert ((Get-BowerbirdPresenceState -Presence $r -Now $t0.AddSeconds(10)).alive -eq 1) 'One live tab after a reload'
 # Same page restored from the back/forward cache: leaving then a heartbeat from the same tab id.
 Register-BowerbirdPresence -Presence $r -Tab 'new' -Leaving -Now $t0.AddSeconds(11)
 Register-BowerbirdPresence -Presence $r -Tab 'new' -Now $t0.AddSeconds(12)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $r -Now $t0.AddSeconds(20))) 'A heartbeat clears the leaving mark'

 # Two tabs: closing one keeps the server; it stops only when none is alive.
 $m=New-BowerbirdPresence
 Register-BowerbirdPresence -Presence $m -Tab 'one' -Now $t0
 Register-BowerbirdPresence -Presence $m -Tab 'two' -Now $t0
 Register-BowerbirdPresence -Presence $m -Tab 'one' -Leaving -Now $t0.AddSeconds(3)
 Register-BowerbirdPresence -Presence $m -Tab 'two' -Now $t0.AddSeconds(5)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $m -Now $t0.AddSeconds(15))) 'Other tab still open'
 Register-BowerbirdPresence -Presence $m -Tab 'two' -Leaving -Now $t0.AddSeconds(16)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $m -Now $t0.AddSeconds(20))) 'Last tab inside its grace'
 Assert (Test-BowerbirdBrowserGone -Presence $m -Now $t0.AddSeconds(22)) 'All tabs gone'

 # Never stop mid-write: a running job blocks auto-stop; afterwards a short grace lets queued heartbeats in.
 $j=New-BowerbirdPresence
 Register-BowerbirdPresence -Presence $j -Tab 'a' -Now $t0
 Enter-BowerbirdJob -Presence $j
 Assert (-not (Test-BowerbirdBrowserGone -Presence $j -Now $t0.AddMinutes(10))) 'Job running: no auto-stop even long after the last heartbeat'
 Assert ((Get-BowerbirdPresenceState -Presence $j -Now $t0.AddSeconds(1)).busy) 'Presence state reports busy'
 Exit-BowerbirdJob -Presence $j -Now $t0.AddMinutes(10)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $j -Now $t0.AddMinutes(10).AddSeconds(2))) 'Grace after the job for queued heartbeats'
 Assert (Test-BowerbirdBrowserGone -Presence $j -Now $t0.AddMinutes(10).AddSeconds(6)) 'Stops on the next tick after the job when no heartbeat came'
 Enter-BowerbirdJob -Presence $j;Enter-BowerbirdJob -Presence $j;Exit-BowerbirdJob -Presence $j -Now $t0.AddMinutes(11)
 Assert (-not (Test-BowerbirdBrowserGone -Presence $j -Now $t0.AddHours(1))) 'Nested jobs: one still running'
 Exit-BowerbirdJob -Presence $j -Now $t0.AddMinutes(11)

 # Off switch and -Stay.
 $off=New-BowerbirdPresence -AutoStop $false
 Register-BowerbirdPresence -Presence $off -Tab 'a' -Leaving -Now $t0
 Assert (-not (Test-BowerbirdBrowserGone -Presence $off -Now $t0.AddHours(1))) 'Auto-stop off keeps the server'
 $cfg=Join-Path $temp 'bowerbird.env'
 Assert (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '') 'Default is on'
 Assert (-not (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '0')) 'BOWERBIRD_AUTO_STOP=0 env var'
 Assert (-not (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue 'false')) 'BOWERBIRD_AUTO_STOP=false env var'
 Assert (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '1') 'BOWERBIRD_AUTO_STOP=1 env var'
 [IO.File]::WriteAllText($cfg,"# comment`r`nBOWERBIRD_LLM_PROFILE=Auto`r`nBOWERBIRD_AUTO_STOP=0`r`n")
 Assert (-not (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '')) 'BOWERBIRD_AUTO_STOP=0 in Config\bowerbird.env'
 Assert (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '1') 'Environment variable wins over the env file'
 [IO.File]::WriteAllText($cfg,"# BOWERBIRD_AUTO_STOP=0`r`n")
 Assert (Get-BowerbirdAutoStopSetting -ConfigPath $cfg -EnvironmentValue '') 'A commented-out line is ignored'
 Write-Host 'PASS: Presence rule (20 s timeout, 5 s leaving grace, reload, multiple tabs, jobs, off switch)' -ForegroundColor Green

 # Runtime files: written without the token, found while the pid lives, stale ones removed on sight.
 $runtime=Join-Path $temp 'Logs'
 $file=Write-BowerbirdRuntimeFile -Directory $runtime -Port 4321 -Url 'http://127.0.0.1:4321/' -Transport 'TcpListener'
 Assert ((Split-Path $file -Leaf) -eq ('bowerbird-server-'+$PID+'.json')) 'Runtime file is named after the pid'
 $info=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
 Assert ($info.pid -eq $PID -and $info.port -eq 4321 -and $info.url -eq 'http://127.0.0.1:4321/' -and $info.startedAt) 'Runtime file has pid, port, url and start time'
 Assert (-not ((Get-Content -LiteralPath $file -Raw) -match '(?i)token|session')) 'Runtime file never holds the session token'
 $self=@(Get-BowerbirdProcesses -Directory $runtime -ExcludePid 0|Where-Object {$_.Pid -eq $PID})
 Assert ($self.Count -eq 1 -and $self[0].Port -eq 4321) 'A live runtime file is reported'
 Assert (@(Get-BowerbirdProcesses -Directory $runtime|Where-Object {$_.Pid -eq $PID}).Count -eq 0) 'The calling process never reports itself'
 # A finished process gives a pid that is certainly dead.
 $dead=Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-Command','exit 0') -PassThru -WindowStyle Hidden
 $dead.WaitForExit()
 $stale=Join-Path $runtime ('bowerbird-server-'+$dead.Id+'.json')
 [IO.File]::WriteAllText($stale,('{"pid":'+$dead.Id+',"port":1,"url":"http://127.0.0.1:1/","startedAt":"2020-01-01T00:00:00Z"}'))
 $broken=Join-Path $runtime 'bowerbird-server-0.json'
 [IO.File]::WriteAllText($broken,'not json')
 $null=@(Get-BowerbirdProcesses -Directory $runtime)
 Assert (-not (Test-Path -LiteralPath $stale)) 'Stale runtime file (dead pid) removed on sight'
 Assert (-not (Test-Path -LiteralPath $broken)) 'Unreadable runtime file removed on sight'
 Remove-BowerbirdRuntimeFile -Path $file
 Assert (-not (Test-Path -LiteralPath $file)) 'Runtime file deleted on stop'
 # A reused pid: the live process started long after the file was written, so the file is stale.
 $reused=Join-Path $runtime ('bowerbird-server-'+$PID+'.json')
 [IO.File]::WriteAllText($reused,('{"pid":'+$PID+',"port":2,"url":"http://127.0.0.1:2/","startedAt":"2000-01-01T00:00:00Z"}'))
 Assert (@(Get-BowerbirdProcesses -Directory $runtime -ExcludePid 0|Where-Object {$_.Pid -eq $PID}).Count -eq 0) 'A pid reused by a newer process is not reported'
 Assert (-not (Test-Path -LiteralPath $reused)) 'Runtime file of a reused pid removed on sight'
 Write-Host 'PASS: Runtime files (no token, stale cleanup, deleted on stop)' -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
