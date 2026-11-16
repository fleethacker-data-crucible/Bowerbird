#requires -Version 5.1
# Fairlead turnkey connection: credential then local token, /__fleethacker/id before the key, and
# Start-FleetService when nothing is listening on port 8776. No real credential, token file, or Fairlead.
# Run: powershell -NoProfile -File .\Tests\FairleadConnection.ps1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdLlm.ps1')
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
$saved=@{
 Reader=$script:BowerbirdCredentialReader
 TokenReader=$script:BowerbirdLocalTokenReader
 TokenPath=$script:BowerbirdLocalTokenPath
 Listeners=$script:BowerbirdPortListeners
 Process=$script:BowerbirdProcessInfo
 Id=$script:BowerbirdIdFetch
 Start=$script:BowerbirdFleetServiceStart
 Prepare=$script:BowerbirdFairleadPrepare
 Roots=$script:BowerbirdFleetPortRoots
}
$llmVars=@('BOWERBIRD_FAIRLEAD_URL','BOWERBIRD_FAIRLEAD_MODEL','BOWERBIRD_FAIRLEAD_PRIVACY')
$savedVars=@{}
foreach($n in $llmVars){$savedVars[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdFairlead_' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -Force | Out-Null
$script:BowerbirdLocalTokenPath=$null
$script:BowerbirdFleetPortRoots=$null
$global:credReads=0
$global:tokenReads=0
$global:starts=0
function Reset-FairleadStubs {
 $global:credReads=0
 $global:tokenReads=0
 $global:starts=0
 $script:BowerbirdCredentialReader={param([string]$Target) $global:credReads++; return $null}
 $script:BowerbirdLocalTokenReader={param([string]$Path) $global:tokenReads++; return $null}
 $script:BowerbirdFleetServiceStart={param($Config) $global:starts++; return [pscustomobject]@{State='running';Message='Fairlead is running.'}}
 $script:BowerbirdFairleadPrepare={param($Config) Resolve-BowerbirdFairlead -Config $Config}
 $script:BowerbirdPortListeners={param([int]$Port) return @{Known=$true;Reason='';Pids=@(4242)}}
 $script:BowerbirdProcessInfo={param([int]$ProcessId) return @{CommandLine='powershell.exe -NoProfile -File "C:\Fairlead\scripts\Start-Fairlead.ps1"';ExecutablePath='C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'}}
 $script:BowerbirdIdFetch={param([string]$Url) return [pscustomobject]@{tool='fairlead';pid=4242;path='C:\Fairlead\scripts\Start-Fairlead.ps1';version='1'}}
}
function Assert-KeyNotRead([string]$Message){
 Assert ($global:credReads -eq 0 -and $global:tokenReads -eq 0) $Message
}
try{
 # Path rules: exact executable or -File script, never a substring, never -Command.
 $fairlead='C:\Fairlead\scripts\Start-Fairlead.ps1'
 $cmd='powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' + $fairlead + '"'
 Assert (Test-BowerbirdProcessPath -Path $fairlead -CommandLine $cmd -ExecutablePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe') 'quoted -File script matches'
 Assert (Test-BowerbirdProcessPath -Path 'C:\Fairlead\Fairlead.exe' -CommandLine 'C:\Fairlead\Fairlead.exe' -ExecutablePath 'C:\Fairlead\Fairlead.exe') 'executable path matches'
 Assert (-not (Test-BowerbirdProcessPath -Path 'C:\Fairlead' -CommandLine $cmd -ExecutablePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')) 'a parent folder is not a match'
 Assert (-not (Test-BowerbirdProcessPath -Path 'scripts\Start-Fairlead.ps1' -CommandLine $cmd -ExecutablePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe')) 'a relative path is refused'
 Assert ($null -eq (Get-BowerbirdScriptFromCommandLine 'powershell.exe -Command "C:\Fairlead\scripts\Start-Fairlead.ps1"')) '-Command is not a -File launch'
 $unquoted='powershell.exe -File C:\Fairlead\scripts\Start-Fairlead.ps1 --no-browser'
 Assert ((Get-BowerbirdScriptFromCommandLine $unquoted) -eq $fairlead) 'unquoted -File script is read'

 # Key order. The local token is not opened when the credential is present.
 Reset-FairleadStubs
 $script:BowerbirdCredentialReader={param([string]$Target) $global:credReads++; return " Bearer 'fl-credkey123'`r`n"}
 $script:BowerbirdLocalTokenReader={param([string]$Path) $global:tokenReads++; return 'fl-localkey9'}
 Assert ((Get-BowerbirdFairleadKey) -eq 'fl-credkey123' -and $global:credReads -eq 1 -and $global:tokenReads -eq 0) 'Credential Manager wins and the token file is not read'
 $script:BowerbirdCredentialReader={param([string]$Target) $global:credReads++; return $null}
 $token=Join-Path $temp 'local-token'
 $utf8=New-Object Text.UTF8Encoding $true
 [IO.File]::WriteAllText($token,"fl-filekey123`r`nignored line",[Text.Encoding]::UTF8)
 $script:BowerbirdLocalTokenPath=$token
 $script:BowerbirdLocalTokenReader={param([string]$Path) $global:tokenReads++; return (Read-BowerbirdLocalTokenFile -Path $Path)}
 Assert ((Get-BowerbirdFairleadKey) -eq 'fl-filekey123' -and $global:tokenReads -eq 1) 'missing credential uses the first line of the local token'
 [IO.File]::WriteAllText($token,"fl-bomkey123`nignored",$utf8)
 Assert ((Read-BowerbirdLocalTokenFile -Path $token) -eq 'fl-bomkey123') 'a byte-order mark is not part of the key'
 [IO.File]::WriteAllBytes((Join-Path $temp 'big-token'),(New-Object byte[] 4097))
 Assert ($null -eq (Read-BowerbirdLocalTokenFile -Path (Join-Path $temp 'big-token'))) 'a token file over 4 KB is ignored'
 $script:BowerbirdLocalTokenPath=Join-Path $temp 'missing-token'
 $script:BowerbirdCredentialReader={param([string]$Target) return $null}
 $threw=$false;try{$null=Get-BowerbirdFairleadKey}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Open Fairlead and install a key for Bowerbird.') 'no credential and no token file keeps the install-a-key error'

 # A verified Fairlead may receive the key. The header still names Bowerbird.
 Reset-FairleadStubs
 $script:BowerbirdLocalTokenReader={param([string]$Path) $global:tokenReads++; return 'fl-localkey9'}
 $h=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)
 Assert ($h['Authorization'] -eq 'Bearer fl-localkey9' -and $h['X-Fairlead-Label'] -eq 'Bowerbird' -and $h['X-Fairlead-Privacy'] -eq 'local' -and $global:starts -eq 0) 'a verified Fairlead gets the local token and the label'

 # The wrong tool, the wrong pid, a missing path, pid 4, or two listeners: the key is not read.
 $refused=$false
 foreach($case in @('tool','pid','path','system','two')){
  Reset-FairleadStubs
  if($case -eq 'tool'){$script:BowerbirdIdFetch={param([string]$Url) return [pscustomobject]@{tool='other';pid=4242;path='C:\Fairlead\scripts\Start-Fairlead.ps1'}}}
  elseif($case -eq 'pid'){$script:BowerbirdIdFetch={param([string]$Url) return [pscustomobject]@{tool='fairlead';pid=99;path='C:\Fairlead\scripts\Start-Fairlead.ps1'}}}
  elseif($case -eq 'path'){$script:BowerbirdIdFetch={param([string]$Url) return [pscustomobject]@{tool='fairlead';pid=4242}}}
  elseif($case -eq 'system'){$script:BowerbirdPortListeners={param([int]$Port) return @{Known=$true;Reason='';Pids=@(4)}}}
  else{$script:BowerbirdPortListeners={param([int]$Port) return @{Known=$true;Reason='';Pids=@(4242,4243)}}}
  $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
  Assert ($threw -and $msg -eq 'Something other than Fairlead is answering on port 8776; the key was not sent.' -and $global:starts -eq 0) ('refused when the id check fails ('+$case+')')
  Assert-KeyNotRead ('the key is not read when the id check fails ('+$case+')')
  $refused=$true
 }
 Assert $refused 'the refusal cases ran'

 # Nothing listening on 8776 starts Fairlead, waits, then checks again before the key is read.
 Reset-FairleadStubs
 $global:passes=0
 $script:BowerbirdPortListeners={param([int]$Port) $global:passes++; if($global:passes -eq 1){return @{Known=$true;Reason='';Pids=@()}}; return @{Known=$true;Reason='';Pids=@(4242)}}
 $script:BowerbirdLocalTokenReader={param([string]$Path) $global:tokenReads++; return 'fl-localkey9'}
 $h=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)
 Assert ($global:starts -eq 1 -and $global:passes -eq 2 -and $h['Authorization'] -eq 'Bearer fl-localkey9' -and $global:tokenReads -eq 1) 'an empty port 8776 starts Fairlead and the key is read only after the second check'
 Reset-FairleadStubs
 $script:BowerbirdPortListeners={param([int]$Port) return @{Known=$true;Reason='';Pids=@()}}
 $script:BowerbirdFleetServiceStart={param($Config) $global:starts++; return [pscustomobject]@{State='unavailable';Message='Fairlead was not found next to this app.'}}
 $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Fairlead was not found next to this app.' -and $global:starts -eq 1) 'a start that does not reach running is the error, and the key is not read'
 Assert-KeyNotRead 'the key is not read when Fairlead did not start'

 # Another loopback port is checked and not started. A non-loopback address is refused first.
 Reset-FairleadStubs
 $env:BOWERBIRD_FAIRLEAD_URL='http://127.0.0.1:9000/v1/chat/completions'
 $script:BowerbirdPortListeners={param([int]$Port) return @{Known=$true;Reason='';Pids=@()}}
 $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Fairlead is not running at http://127.0.0.1:9000/v1/chat/completions. Bowerbird starts Fairlead only on port 8776.' -and $global:starts -eq 0) 'a down port other than 8776 is not started'
 Assert-KeyNotRead 'the key is not read for a down port other than 8776'
 $env:BOWERBIRD_FAIRLEAD_URL='https://ai.example.org/v1/chat/completions'
 $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -match 'BOWERBIRD_FAIRLEAD_URL' -and $global:starts -eq 0) 'a non-loopback address is refused before the id check'
 Assert-KeyNotRead 'the key is not read for a non-loopback address'
 $env:BOWERBIRD_FAIRLEAD_URL='http://user:secret@127.0.0.1:8776/v1/chat/completions'
 $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'The Fairlead address must not contain a user name or password.' -and $msg -notmatch 'secret') 'a user name in the address is refused and not repeated'
 foreach($n in $llmVars){[Environment]::SetEnvironmentVariable($n,$null)}

 # The port check failing closed does not start Fairlead and does not read the key.
 Reset-FairleadStubs
 $script:BowerbirdPortListeners={param([int]$Port) return @{Known=$false;Reason='windows';Pids=@()}}
 $threw=$false;try{$null=Get-BowerbirdLlmHeaders -Config (Get-BowerbirdLlmConfig)}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Bowerbird can check which program holds Fairlead''s port only on Windows, so the Fairlead key is not sent.' -and $global:starts -eq 0) 'without a port check the key is not sent'
 Assert-KeyNotRead 'the key is not read when the port check cannot run'

 # FleetPort is loaded from beside this app and called as Start-FleetService -Name fairlead -WaitSeconds 40.
 $modDir=Join-Path (Join-Path (Join-Path $temp 'edge-ops') 'tools') 'fleet-port'
 New-Item -ItemType Directory -Path $modDir -Force | Out-Null
 $module=Join-Path $modDir 'FleetPort.psm1'
 @(
  'function Start-FleetService {'
  ' param([Parameter(Mandatory)][string]$Name,[int]$WaitSeconds=0,[string]$CallerRoot,[hashtable]$Environment)'
  ' $global:fleetSeen=@{Name=$Name;WaitSeconds=$WaitSeconds;CallerRoot=$CallerRoot;EnvCount=$(if($Environment){$Environment.Count}else{0})}'
  ' return [pscustomobject]@{State=''running'';Message=''Fairlead is running.''}'
  '}'
  'Export-ModuleMember -Function Start-FleetService'
 ) | Set-Content -LiteralPath $module -Encoding ASCII
 $script:BowerbirdFleetPortRoots=@(Join-Path $temp 'no-such-root')
 Assert ($null -eq (Find-BowerbirdFleetPortModule)) 'a root without edge-ops does not invent a module'
 $gone=Start-BowerbirdFairleadService -Config (Get-BowerbirdLlmConfig)
 Assert ($gone.State -eq 'unavailable' -and $gone.Message -match 'FleetPort') 'a missing FleetPort is reported and nothing is started'
 $script:BowerbirdFleetPortRoots=@($temp)
 Assert ((Find-BowerbirdFleetPortModule) -eq $module) 'FleetPort.psm1 is found under edge-ops\tools\fleet-port'
 $started=Start-BowerbirdFairleadService -Config (Get-BowerbirdLlmConfig)
 Assert ($started.State -eq 'running' -and $global:fleetSeen.Name -eq 'fairlead' -and $global:fleetSeen.WaitSeconds -eq 40 -and $global:fleetSeen.EnvCount -eq 0 -and $global:fleetSeen.CallerRoot -eq $script:BowerbirdAppRoot) 'Start-FleetService is called for fairlead, with a wait and no environment'
 Remove-Module FleetPort -ErrorAction SilentlyContinue

 if($env:OS -ne 'Windows_NT'){
  $off=Get-BowerbirdLoopbackListeners -Port 8776
  Assert ((-not $off.Known) -and $off.Reason -eq 'windows') 'off Windows the listener check reports that it cannot run'
 }
 Write-Host 'PASS: Fairlead local token, id check and Start-FleetService' -ForegroundColor Green
}catch{
 Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
 exit 1
}finally{
 $script:BowerbirdCredentialReader=$saved.Reader
 $script:BowerbirdLocalTokenReader=$saved.TokenReader
 $script:BowerbirdLocalTokenPath=$saved.TokenPath
 $script:BowerbirdPortListeners=$saved.Listeners
 $script:BowerbirdProcessInfo=$saved.Process
 $script:BowerbirdIdFetch=$saved.Id
 $script:BowerbirdFleetServiceStart=$saved.Start
 $script:BowerbirdFairleadPrepare=$saved.Prepare
 $script:BowerbirdFleetPortRoots=$saved.Roots
 foreach($n in $llmVars){[Environment]::SetEnvironmentVariable($n,$savedVars[$n])}
 Remove-Module FleetPort -ErrorAction SilentlyContinue
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
