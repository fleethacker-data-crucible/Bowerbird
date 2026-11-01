#requires -Version 5.1
<#
 Bowerbird Studio: dependency-free, localhost-only PowerShell web service.
 Launch: powershell -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root "$env:USERPROFILE\Pictures"
 No admin install required. Browser assets are static, served from Web/.
 Lifecycle: the browser tab owns the server. It stops itself 20 s after the last heartbeat from
 any open tab, or 5 s after the tab says it is leaving; End session in the sidebar stops it now.
  -Stay (or --stay)        keep running after the tab closes. BOWERBIRD_AUTO_STOP=0 does the same,
                           as an environment variable or in Config\bowerbird.env.
  -Replace (or --replace)  if Bowerbird Studio is already running, stop it without asking.
 Stop-Bowerbird.ps1 stops every running instance from a shell.
#>
[CmdletBinding(PositionalBinding=$false)]param(
 [Parameter(Position=0)][string]$Root='',
 [ValidateRange(0,65535)][int]$Port=8767,
 [switch]$NoBrowser,
 [switch]$AllowCloudAI,
 [ValidateSet('Auto','HttpListener','Tcp','CompiledTcp')][string]$Transport='Auto',
 [switch]$FixedPort,
 [switch]$LocalDev,
 [string]$DataDir='',
 [switch]$Stay,
 [switch]$Replace,
 [Parameter(ValueFromRemainingArguments=$true)][string[]]$Rest
)
$ErrorActionPreference='Stop'
$script:AppRoot=$PSScriptRoot
. (Join-Path $PSScriptRoot 'Private\BowerbirdDataDir.ps1')
# The .bat launchers pass their arguments through, so accept --stay / --replace as well.
$options=@($Rest)
if($Root -match '^--?[A-Za-z]'){$options=@($Root)+$options;$Root=''}
$expectDataDir=$false
foreach($option in $options){
 if($expectDataDir){$DataDir=[string]$option;$expectDataDir=$false;continue}
 if([string]$option -match '^--?data-dir=(.+)$'){$DataDir=$Matches[1];continue}
 switch -Regex ([string]$option){
  '^--?stay$' {$Stay=[switch]$true}
  '^--?replace$' {$Replace=[switch]$true}
  '^--?no-browser$' {$NoBrowser=[switch]$true}
  '^--?data-dir$' {$expectDataDir=$true}
  default {if($option){Write-Warning ('Ignoring unknown option '+$option)}}
 }
}
# Never write state to the downloaded/program installation directory, which may be read-only.
$locations=Resolve-BowerbirdDataLocations -DataDir $DataDir -LocalDev:$LocalDev
$script:DataDirOverride=$locations.Override
$script:DataRoot=$locations.State
$script:LogDir=$locations.Logs
try{
 [IO.Directory]::CreateDirectory($script:DataRoot)|Out-Null
 [IO.Directory]::CreateDirectory($script:LogDir)|Out-Null
}catch{throw "Cannot initialize Bowerbird user data directory: $($_.Exception.Message)"}
$script:LogFile=Join-Path $script:LogDir ('studio-'+(Get-Date -Format 'yyyyMMdd')+'.jsonl')
function Write-BowerbirdDiagnostic {
 [CmdletBinding()]param([string]$Level='INFO',[string]$Event,[string]$Message='',[string]$Route='',[string]$RequestId='')
 try{
  # No HTTP query strings, prompt text, credentials, or document content are logged.
  $safe=([string]$Message -replace '(?i)(token|password|secret|api[_-]?key|bearer|authorization)\s*[:=]\s*\S+','$1=[REDACTED]')
  $safe=$safe -replace '(?i)https?://[^\s]+','[URL REDACTED]'
  if(Get-Command Get-BowerbirdSafeDiagnosticText -ErrorAction SilentlyContinue){$safe=Get-BowerbirdSafeDiagnosticText -Value $safe -Limit 480}
  elseif($safe.Length -gt 480){$safe=$safe.Substring(0,480)}
  $line=[pscustomobject]@{
   time=[DateTime]::UtcNow.ToString('o');level=$Level;event=$Event;route=$Route;requestId=$RequestId;message=$safe
  }|ConvertTo-Json -Compress
  [IO.File]::AppendAllText($script:LogFile,$line+[Environment]::NewLine,[Text.Encoding]::UTF8)
 }catch{Write-Warning 'Unable to write Bowerbird diagnostics'}
}
trap {
 $message=if($_.Exception){$_.Exception.Message}else{[string]$_}
 Write-BowerbirdDiagnostic -Level ERROR -Event 'FATAL_STARTUP' -Message $message
 Write-Host ('Bowerbird Studio failed: '+$message) -ForegroundColor Red
 Write-Host ('Diagnostic log: '+$script:LogFile) -ForegroundColor Yellow
 exit 1
}
# The Pictures folder is not guaranteed to exist on locked-down workstations.
if([string]::IsNullOrWhiteSpace($Root)){
 $candidates=New-Object Collections.Generic.List[string]
 if($env:USERPROFILE){
  $candidates.Add((Join-Path $env:USERPROFILE 'Pictures'))
  $candidates.Add((Join-Path $env:USERPROFILE 'Documents'))
  $candidates.Add($env:USERPROFILE)
 }
 $candidates.Add([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile))
 $candidates.Add((Get-Location).ProviderPath)
 foreach($candidate in $candidates){
  if($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)){$Root=$candidate;break}
 }
}
if(-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)){
 throw "Workspace folder does not exist: $Root . Supply -Root with an existing authorized folder."
}
$rootFull=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Root).ProviderPath)
$volumeRoot=[IO.Path]::GetPathRoot($rootFull)
$script:AllowedRoot=if($rootFull.Length -gt $volumeRoot.Length){$rootFull.TrimEnd([char]92,[char]47)}else{$rootFull}
Write-BowerbirdDiagnostic -Event 'BOOT' -Message 'Starting Bowerbird Studio.'
. (Join-Path $AppRoot 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdAdvanced.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdStreaming.ps1')
. (Join-Path $AppRoot 'Private\Get-ImageMetadata.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdPass1.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdPass2.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdNamer.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdRenameStudio.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdSidecarRename.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdSemaphoreExport.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdActions.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdLlm.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdLoopback.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdWorkspace.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdSupport.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdLifecycle.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdApi.ps1')
. (Join-Path $AppRoot 'Private\BowerbirdCommands.ps1')
# One instance: offer to stop a running server before binding a new one.
$running=@(Get-BowerbirdProcesses)
if($running.Count -gt 0){
 $where=($running|ForEach-Object {if($_.Url){$_.Url+' (PID '+$_.Pid+')'}else{'PID '+$_.Pid}}) -join ', '
 Write-Host ('Bowerbird Studio is already running: '+$where) -ForegroundColor Yellow
 $answer=''
 if($Replace){$answer='y'}
 elseif(Test-BowerbirdCanPrompt){
  try{$answer=[string](Read-Host 'Stop it and start fresh? [Y/n]')}catch{$answer='n'}
  if([string]::IsNullOrWhiteSpace($answer)){$answer='y'}
 }
 else{$answer='keep';Write-Host 'Non-interactive start: leaving it running and starting another instance. Use -Replace to stop it first.' -ForegroundColor Yellow}
 if($answer -match '^[Yy]'){
  foreach($stoppedPid in @(Stop-BowerbirdProcesses -Processes $running)){Write-Host ('  stopped PID '+$stoppedPid) -ForegroundColor DarkGray}
  Write-BowerbirdDiagnostic -Event 'REPLACED' -Message 'Stopped a running instance before starting.'
 }elseif($answer -ne 'keep'){
  Write-Host 'Leaving the running server alone. Use End session in its browser tab, or Stop-Bowerbird.ps1.' -ForegroundColor DarkGray
  exit 0
 }
}
$autoStop=(-not $Stay) -and (Get-BowerbirdAutoStopSetting -ConfigPath (Join-Path $AppRoot 'Config\bowerbird.env'))
$script:Presence=New-BowerbirdPresence -AutoStop $autoStop
$script:StopReason=''
$script:RuntimeFile=''
$script:PendingHttpContext=$null
$null=Set-BowerbirdWorkspace -Folder $script:AllowedRoot -Initial
$tokenBytes=New-Object byte[] 32
$rng=[Security.Cryptography.RandomNumberGenerator]::Create()
try{$rng.GetBytes($tokenBytes)}finally{$rng.Dispose()}
$script:Token=[Convert]::ToBase64String($tokenBytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$script:Session=$null
$script:PureTcp=$false
$script:PortRequested=$Port
if($Transport -in @('Auto','Tcp')){
 # Default to Lazarette/Halyard-style pure PowerShell sockets. Never compile C# or
 # request an HTTP.sys URL reservation on the normal startup path.
 $binding=Start-BowerbirdLoopback -Port $Port -FixedPort:$FixedPort
 $script:Session=$binding.Listener
 $script:PureTcp=$true
 $Port=[int]$binding.Port
}elseif($Transport -eq 'HttpListener'){
 if($Port -eq 0){
  $probe=Start-BowerbirdLoopback -Port 0
  $Port=$probe.Port
  $probe.Listener.Stop()
 }
 $http=New-Object Net.HttpListener
 $http.Prefixes.Add("http://127.0.0.1:$Port/")
 $http.Start()
 $script:Session=$http
}else{
 if($Port -eq 0){
  $probe=Start-BowerbirdLoopback -Port 0
  $Port=$probe.Port
  $probe.Listener.Stop()
 }
 Add-Type -Path (Join-Path $script:AppRoot 'Private\BowerbirdTcpBridge.cs') -ErrorAction Stop
 $script:Session=New-Object Bowerbird.Transport.Server($Port)
 $script:Session.Start()
}
$script:CurrentPort=$Port
$script:CloudEnabled=[bool]$AllowCloudAI
if($AllowCloudAI){$env:BOWERBIRD_FAIRLEAD_PRIVACY='any'}   # Fairlead may then use cloud models for this run
Write-BowerbirdDiagnostic -Event 'BOUND' -Message ("Transport=$Transport Port=$Port")
function Read-Body($Request){
 if($Request.ContentLength64 -gt 1048576){throw 'Request too large'}
 $reader=New-Object IO.StreamReader($Request.InputStream,$Request.ContentEncoding)
 try{$raw=$reader.ReadToEnd();if($raw.Length -gt 1048576){throw 'Request too large'};if(-not $raw){return @{}};return ($raw|ConvertFrom-Json)}
 finally{$reader.Dispose()}
}
function Send-Json($Response,$Object,[int]$Status=200){
 $json=ConvertTo-Json -InputObject $Object -Depth 12 -Compress
 $bytes=[Text.Encoding]::UTF8.GetBytes($json)
 $Response.StatusCode=$Status;$Response.ContentType='application/json; charset=utf-8'
 $Response.Headers.Add('Cache-Control','no-store')
 $Response.OutputStream.Write($bytes,0,$bytes.Length)
}
function Read-BowerbirdHttpListenerContext($Listener,[int]$TimeoutMilliseconds){
 # Same contract as Read-BowerbirdLoopbackContext -TimeoutMilliseconds: $null when nothing arrived.
 if($null -eq $script:PendingHttpContext){$script:PendingHttpContext=$Listener.BeginGetContext($null,$null)}
 if(-not $script:PendingHttpContext.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)){return $null}
 $pending=$script:PendingHttpContext
 $script:PendingHttpContext=$null
 return $Listener.EndGetContext($pending)
}
function Write-BowerbirdMedia($Response,[string]$Relative){
 $full=Resolve-WorkspacePath $Relative
 if(-not (Test-Path -LiteralPath $full -PathType Leaf)){throw 'Media file not found'}
 $file=Get-Item -LiteralPath $full
 if($file.Length -gt 52428800){throw 'Media preview limit: 50 MB'}
 $mime=switch($file.Extension.ToLowerInvariant()){
  '.png' {'image/png'}
  '.jpg' {'image/jpeg'}
  '.jpeg' {'image/jpeg'}
  '.gif' {'image/gif'}
  '.webp' {'image/webp'}
  '.bmp' {'image/bmp'}
  '.pdf' {'application/pdf'}
  default {throw 'Unsupported media type'}
 }
 $Response.ContentType=$mime
 $Response.Headers.Add('Content-Disposition','inline')
 $Response.ContentLength64=$file.Length
 $fs=[IO.File]::Open($full,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
 try{$fs.CopyTo($Response.OutputStream)}finally{$fs.Dispose()}
}
# Browser assets served by GET, by URL path. Only these files are served.
$script:StaticFiles=@{
 '/app.js'=@{File='Web\app.js';Type='application/javascript; charset=utf-8'}
 '/lifecycle.js'=@{File='Web\lifecycle.js';Type='application/javascript; charset=utf-8'}
 '/diagnostics.js'=@{File='Web\diagnostics.js';Type='application/javascript; charset=utf-8'}
 '/voice.js'=@{File='Web\voice.js';Type='application/javascript; charset=utf-8'}
 '/shell.js'=@{File='Web\shell.js';Type='application/javascript; charset=utf-8'}
 '/icons.js'=@{File='Web\icons.js';Type='application/javascript; charset=utf-8'}
 '/style.css'=@{File='Web\style.css';Type='text/css; charset=utf-8'}
 '/vendor/fleet/fleet.css'=@{File='Web\vendor\fleet\fleet.css';Type='text/css; charset=utf-8'}
 '/mark.svg'=@{File='assets\brand\mark.svg';Type='image/svg+xml'}
 # The emblem (backdrop made transparent, one per theme) and the favicon / icon cut from its circle.
 '/brand/emblem-dark.png'=@{File='Web\brand\emblem-dark.png';Type='image/png'}
 '/brand/emblem-light.png'=@{File='Web\brand\emblem-light.png';Type='image/png'}
 '/brand/icon-256.png'=@{File='Web\brand\icon-256.png';Type='image/png'}
 '/favicon.ico'=@{File='Web\brand\favicon.ico';Type='image/x-icon'}
}
$url="http://127.0.0.1:$Port/"
Write-Host "Bowerbird Studio running at $url" -ForegroundColor Cyan
Write-Host "Workspace: $script:AllowedRoot"
if($script:PortRequested -ne $Port){Write-Host "Port $($script:PortRequested) was busy; selected free localhost port $Port instead." -ForegroundColor Yellow}
Write-Host "Transport: $($script:Session.GetType().Name)"
Write-Host ('Session URL: '+$url+'?token='+[uri]::EscapeDataString($script:Token)) -ForegroundColor DarkGray
Write-Host ('Diagnostic log: '+$script:LogFile)
if($script:Presence.AutoStop){Write-Host 'Closing the browser tab stops the server (End session in the sidebar, Ctrl+C or Stop-Bowerbird.ps1 also stop it).'}
else{Write-Host 'Auto-stop is off (-Stay or BOWERBIRD_AUTO_STOP=0): use End session, Ctrl+C or Stop-Bowerbird.ps1 to stop.' -ForegroundColor Yellow}
Write-Host 'Press Ctrl+C to stop.'
try{
 # Runtime file (pid, port, url, start time; never the token) lets Stop-Bowerbird.ps1 and the next
 # launcher find this server. It lives in the app's existing %LOCALAPPDATA%\Bowerbird\Logs folder.
 $script:RuntimeFile=Write-BowerbirdRuntimeFile -Directory $script:LogDir -Port $Port -Url $url -Transport $script:Session.GetType().Name -LocalDev:$LocalDev
 if(-not $NoBrowser){
  try{Start-Process ($url+'?token='+[uri]::EscapeDataString($script:Token)) -ErrorAction Stop}
  catch{
   Write-BowerbirdDiagnostic -Level WARN -Event 'BROWSER_LAUNCH' -Message $_.Exception.Message
   Write-Warning 'Browser did not open automatically. Copy the Session URL printed above into your browser.'
  }
 }
 while(-not $script:StopReason){
  # Presence rule, checked at least once a second and between requests: stop when every tab is gone.
  if(Test-BowerbirdBrowserGone -Presence $script:Presence){
   $script:StopReason='AUTO_STOP'
   Write-BowerbirdDiagnostic -Event 'AUTO_STOP' -Message 'No browser tab is open; the server stops itself (BOWERBIRD_AUTO_STOP=0 or -Stay keeps it running).'
   Write-Host 'The browser tab closed; Bowerbird Studio stopped itself. Relaunch Start-Bowerbird.bat to continue.' -ForegroundColor Cyan
   break
  }
  # Wait up to a second for a request so the check above keeps running while the server is idle.
  if($script:PureTcp){$ctx=Read-BowerbirdLoopbackContext -Listener $script:Session -Port $Port -TimeoutMilliseconds 1000}
  elseif($Transport -eq 'HttpListener'){$ctx=Read-BowerbirdHttpListenerContext -Listener $script:Session -TimeoutMilliseconds 1000}
  else{$ctx=$script:Session.TryGetContext(1000)}
  if($null -eq $ctx){continue}
  $req=$ctx.Request;$res=$ctx.Response
  $quietRoute=$false
  $job=$false
  $requestId=[guid]::NewGuid().ToString('N').Substring(0,12)
  $clock=[Diagnostics.Stopwatch]::StartNew()
  try{
   $res.Headers.Add('X-Bowerbird-Request-ID',$requestId)
   $res.Headers.Add('X-Content-Type-Options','nosniff')
   $res.Headers.Add('Referrer-Policy','no-referrer')
   $res.Headers.Add('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data:; connect-src 'self'; object-src 'none'; frame-src blob:; frame-ancestors 'none'; base-uri 'none'")
   if($req.Url.AbsolutePath -eq '/' -and $req.HttpMethod -eq 'GET'){
    $page=Join-Path $AppRoot 'Web\index.html'
    $html=[IO.File]::ReadAllText($page)
    $bytes=[Text.Encoding]::UTF8.GetBytes($html)
    $res.ContentType='text/html; charset=utf-8';$res.OutputStream.Write($bytes,0,$bytes.Length)
   }elseif($script:StaticFiles.ContainsKey($req.Url.AbsolutePath) -and $req.HttpMethod -eq 'GET'){
    # Fixed allow-list of browser assets (see $script:StaticFiles); nothing else on disk is served.
    $asset=$script:StaticFiles[$req.Url.AbsolutePath]
    $bytes=[IO.File]::ReadAllBytes((Join-Path $AppRoot $asset.File));$res.ContentType=$asset.Type;$res.OutputStream.Write($bytes,0,$bytes.Length)
   }elseif($req.Url.AbsolutePath -eq '/api/heartbeat' -and $req.HttpMethod -eq 'POST'){
    # The leaving beacon (navigator.sendBeacon) cannot set headers, so this one route also accepts
    # the session token as "session" in the JSON body. Never in the query string; bodies are never logged.
    # A parse error message can quote the body (which may hold the token), so it is never logged.
    $body=$null
    if(-not $req.Headers['Origin'] -or $req.Headers['Origin'] -ceq "http://127.0.0.1:$Port"){
     try{$body=Read-Body $req}catch{$body=$null}
    }
    if($req.Headers['Origin'] -and $req.Headers['Origin'] -cne "http://127.0.0.1:$Port"){Send-Json $res @{error='Origin denied'} 403}
    elseif($null -eq $body){Send-Json $res @{error='Invalid heartbeat'} 400}
    elseif($req.Headers['X-Bowerbird-Token'] -cne $script:Token -and [string]$body.session -cne $script:Token){Send-Json $res @{error='Invalid session token'} 403}
    else{
     $quietRoute=$true
     Register-BowerbirdPresence -Presence $script:Presence -Tab ([string]$body.tab) -Leaving:([bool]$body.leaving)
     Send-Json $res (Get-BowerbirdPresenceState -Presence $script:Presence)
    }
   }elseif($req.Url.AbsolutePath -eq '/api/commands' -and $req.HttpMethod -eq 'GET'){
    # The command list for agents (see docs/CLI.md): same token and Origin rules as every POST /api route.
    if($req.Headers['X-Bowerbird-Token'] -cne $script:Token){Send-Json $res @{error='Invalid session token'} 403}
    elseif($req.Headers['Origin'] -and $req.Headers['Origin'] -cne "http://127.0.0.1:$Port"){Send-Json $res @{error='Origin denied'} 403}
    else{Send-Json $res (Get-BowerbirdCommandCatalog)}
   }elseif($req.Url.AbsolutePath.StartsWith('/api/') -and $req.HttpMethod -eq 'POST'){
    if($req.Headers['X-Bowerbird-Token'] -cne $script:Token){Send-Json $res @{error='Invalid session token'} 403}
    elseif($req.Headers['Origin'] -and $req.Headers['Origin'] -cne "http://127.0.0.1:$Port"){Send-Json $res @{error='Origin denied'} 403}
    elseif($req.Url.AbsolutePath -eq '/api/session/stop'){
     if($req.Headers['X-Bowerbird-Intent'] -cne 'end-session'){Send-Json $res @{error='End session requires the End session control'} 400}
     else{
      # The loop is single-threaded, so no request (save, apply, index...) is running now.
      $script:StopReason='END_SESSION'
      Write-BowerbirdDiagnostic -Event 'END_SESSION' -Message 'End session requested from the browser.'
      Write-Host 'End session was selected in the browser; Bowerbird Studio stopped.' -ForegroundColor Cyan
      Send-Json $res @{ok=$true;stopping=$true}
     }
    }
    else{
     # Every other API request counts as a job: auto-stop never fires while one runs, and allows
     # a short grace after it so heartbeats queued during a long index/apply/AI request are read.
     $job=$true
     Enter-BowerbirdJob -Presence $script:Presence
     $body=Read-Body $req
     if($req.Url.AbsolutePath -eq '/api/media'){Write-BowerbirdMedia $res ([string]$body.path)}
     elseif($req.Url.AbsolutePath -eq '/api/stream'){
      if(-not $AllowCloudAI){throw 'Cloud AI disabled. Restart with -AllowCloudAI using an approved provider.'}
      $messages=Get-BowerbirdMessages $body
      $res.SendChunked=$true;$res.ContentType='text/event-stream; charset=utf-8'
      Invoke-BowerbirdStreamingChat -Response $res -Messages $messages
     }
     else{$data=Invoke-Api $req.Url.AbsolutePath $body;Send-Json $res $data}
    }
   }else{Send-Json $res @{error='Not found'} 404}
  }catch{
   $msg=$_.Exception.Message
   Write-BowerbirdDiagnostic -Level ERROR -Event 'HTTP_ERROR' -Route $req.Url.AbsolutePath -RequestId $requestId -Message $msg
   $safeError=Get-BowerbirdSafeDiagnosticText -Value $msg -Limit 360
   try{Send-Json $res @{error=$safeError;requestId=$requestId} 400}catch{}
  }finally{
   if($job){Exit-BowerbirdJob -Presence $script:Presence}
   # Heartbeats arrive every 5 s; log them only when they fail.
   if(-not $quietRoute -or [int]$res.StatusCode -ne 200){
    try{$clock.Stop();Write-BowerbirdDiagnostic -Event 'REQUEST' -Route $req.Url.AbsolutePath -RequestId $requestId -Message ('HTTP '+[string]$res.StatusCode+' '+$clock.ElapsedMilliseconds+'ms')}catch{}
   }
   try{$res.Close()}catch{}
  }
 }
}finally{
 # Runs on End session, auto-stop, Ctrl+C and fatal errors alike.
 Remove-BowerbirdRuntimeFile -Path $script:RuntimeFile
 try{$script:Session.Stop()}catch{}
 try{$script:Session.Close()}catch{}
 $reason='Service stopped'
 if($script:StopReason){$reason='Service stopped ('+$script:StopReason+')'}
 Write-BowerbirdDiagnostic -Event 'STOP' -Message $reason
}
exit 0
