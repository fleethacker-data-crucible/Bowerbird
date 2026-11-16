# Bowerbird AI client: every call goes to Fairlead, the Fleet model router on this PC.
#requires -Version 5.1
# Fairlead owns the endpoint choice, the provider keys and the fallbacks. Bowerbird sends a route name and
# its own Fairlead client key, and nothing else about where the model lives.
#   BOWERBIRD_FAIRLEAD_URL      Fairlead's chat address (loopback only); default http://127.0.0.1:8776/v1/chat/completions
#   BOWERBIRD_FAIRLEAD_MODEL    the Fairlead route name to ask for; default auto
#   BOWERBIRD_FAIRLEAD_PRIVACY  local (default) keeps prompts on local models; any lets Fairlead use cloud models.
#                               Launching with -AllowCloudAI sets it to any for that run.
# The client key is the Windows Credential Manager generic credential Fairlead/Bowerbird when that
# exists (Fairlead's "Install for this app"), otherwise the first line of
# %LOCALAPPDATA%\Fairlead\local-token, which Fairlead writes for this Windows account. There is no
# environment variable and no vault item for it. The key is sent only after GET /__fleethacker/id
# on that address says tool fairlead, the pid owns the port, and path is that process's executable
# or -File script. Nothing listening on port 8776 is started with Start-FleetService -Name fairlead.
$script:BowerbirdLlmDefaults=@{
 UrlEnv='BOWERBIRD_FAIRLEAD_URL'
 Url='http://127.0.0.1:8776/v1/chat/completions'
 ModelEnv='BOWERBIRD_FAIRLEAD_MODEL'
 Model='auto'
 PrivacyEnv='BOWERBIRD_FAIRLEAD_PRIVACY'
 AppName='Bowerbird'
}
$script:BowerbirdCredentialTarget='Fairlead/Bowerbird'
$script:BowerbirdAppRoot=Split-Path $PSScriptRoot -Parent
# Empty unless a test points at its own file. Production reads %LOCALAPPDATA%\Fairlead\local-token.
$script:BowerbirdLocalTokenPath=$null
# Empty unless a test limits where FleetPort.psm1 is looked up.
$script:BowerbirdFleetPortRoots=$null
# Replaceable so tests never read the real credential store, the real token file, or a live Fairlead.
$script:BowerbirdCredentialReader={param([string]$Target) Read-BowerbirdWindowsCredential -Target $Target}
$script:BowerbirdLocalTokenReader={param([string]$Path) Read-BowerbirdLocalTokenFile -Path $Path}
$script:BowerbirdPortListeners={param([int]$Port) Get-BowerbirdLoopbackListeners -Port $Port}
$script:BowerbirdProcessInfo={param([int]$ProcessId) Get-BowerbirdProcessInfo -ProcessId $ProcessId}
$script:BowerbirdIdFetch={param([string]$Url) Invoke-BowerbirdFairleadId -Url $Url}
$script:BowerbirdFleetServiceStart={param($Config) Start-BowerbirdFairleadService -Config $Config}
$script:BowerbirdFairleadPrepare={param($Config) Resolve-BowerbirdFairlead -Config $Config}

function Initialize-BowerbirdCredentialType {
 if('Bowerbird.WinCredential' -as [type]){return}
 Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace Bowerbird {
 public static class WinCredential {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  private struct CREDENTIAL {
   public int Flags; public int Type; public string TargetName; public string Comment;
   public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
   public int CredentialBlobSize; public IntPtr CredentialBlob; public int Persist;
   public int AttributeCount; public IntPtr Attributes; public string TargetAlias; public string UserName;
  }
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern bool CredRead(string target, int type, int flags, out IntPtr credential);
  [DllImport("advapi32.dll")] private static extern void CredFree(IntPtr buffer);
  public static byte[] Read(string target) {
   IntPtr p;
   if (!CredRead(target, 1, 0, out p)) return null;
   try {
    CREDENTIAL c = (CREDENTIAL)Marshal.PtrToStructure(p, typeof(CREDENTIAL));
    byte[] b = new byte[c.CredentialBlobSize];
    if (c.CredentialBlobSize > 0) Marshal.Copy(c.CredentialBlob, b, 0, c.CredentialBlobSize);
    return b;
   } finally { CredFree(p); }
  }
 }
}
'@
}
function ConvertFrom-BowerbirdCredentialBytes {
 # Fairlead stores the key as UTF-16 text; a key saved another way may be UTF-8. Take the first reading that is
 # printable ASCII after trimming.
 param([byte[]]$Bytes)
 if($null -eq $Bytes -or $Bytes.Length -eq 0){return $null}
 foreach($enc in @([Text.Encoding]::Unicode,[Text.Encoding]::UTF8)){
  $t=$enc.GetString($Bytes).Trim([char]0).Trim()
  if($t -match '^[\x21-\x7E]+$'){return $t}
 }
 return $null
}
function Read-BowerbirdWindowsCredential {
 param([Parameter(Mandatory)][string]$Target)
 if($env:OS -ne 'Windows_NT'){return $null}
 Initialize-BowerbirdCredentialType
 return (ConvertFrom-BowerbirdCredentialBytes -Bytes ([Bowerbird.WinCredential]::Read($Target)))
}
function ConvertTo-BowerbirdFairleadKey {
 # A usable key is one line of printable ASCII. A Bearer prefix, quotes and line breaks are stripped.
 # Anything else is treated as no key. The value is never written here.
 param($Raw)
 $key=([string]$Raw).Trim()
 if($key -match '^(?i)Bearer\s+(.+)$'){$key=$Matches[1].Trim()}
 $key=($key -replace '[\r\n]','').Trim().Trim("'").Trim('"').Trim()
 if([string]::IsNullOrWhiteSpace($key) -or $key -notmatch '^[\x21-\x7E]+$'){return $null}
 return $key
}
function Get-BowerbirdLocalTokenPath {
 if(-not [string]::IsNullOrWhiteSpace([string]$script:BowerbirdLocalTokenPath)){return [string]$script:BowerbirdLocalTokenPath}
 $base=$env:LOCALAPPDATA
 if([string]::IsNullOrWhiteSpace($base)){$base=[Environment]::GetFolderPath('LocalApplicationData')}
 return [IO.Path]::Combine($base,'Fairlead','local-token')
}
function Read-BowerbirdLocalTokenFile {
 # The first line, or $null when the file is missing, unreadable, empty, or larger than 4 KB.
 param([string]$Path)
 try{
  if([string]::IsNullOrWhiteSpace($Path) -or -not [IO.File]::Exists($Path)){return $null}
  if((New-Object IO.FileInfo $Path).Length -gt 4096){return $null}
  $text=[IO.File]::ReadAllText($Path)
  $parts=$text -split '\r?\n',2
  $line=[string]$parts[0]
  $line=$line.Trim().TrimStart([char]0xFEFF)
  if([string]::IsNullOrWhiteSpace($line)){return $null}
  return $line
 }catch{return $null}
}
function Get-BowerbirdFairleadKey {
 # Credential Manager first. The local token is read only when that credential is absent.
 $key=ConvertTo-BowerbirdFairleadKey (& $script:BowerbirdCredentialReader $script:BowerbirdCredentialTarget)
 if($key){return $key}
 $key=ConvertTo-BowerbirdFairleadKey (& $script:BowerbirdLocalTokenReader (Get-BowerbirdLocalTokenPath))
 if($key){return $key}
 throw 'Open Fairlead and install a key for Bowerbird.'
}
function Test-BowerbirdLoopbackUrl {
 # True when the URL points at this PC (127.0.0.0/8, ::1 or localhost).
 param([AllowEmptyString()][string]$Url)
 $u=$null
 if([string]::IsNullOrWhiteSpace($Url) -or -not [Uri]::TryCreate($Url.Trim(),[UriKind]::Absolute,[ref]$u)){return $false}
 return [bool]$u.IsLoopback
}
function Get-BowerbirdLlmConfig {
 [CmdletBinding()]param()
 $url=[Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults.UrlEnv)
 if([string]::IsNullOrWhiteSpace($url)){$url=$script:BowerbirdLlmDefaults.Url}
 $model=[Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults.ModelEnv)
 if([string]::IsNullOrWhiteSpace($model)){$model=$script:BowerbirdLlmDefaults.Model}
 $privacy=([string][Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults.PrivacyEnv)).Trim().ToLowerInvariant()
 if($privacy -ne 'any'){$privacy='local'}
 return [pscustomobject]@{Url=$url.Trim().TrimEnd('/');Model=$model.Trim();Privacy=$privacy;Label=$script:BowerbirdLlmDefaults.AppName}
}
function Assert-BowerbirdLlmUrl {
 param($Config)
 $url=[string]$Config.Url
 $u=$null
 $bad=("Fairlead must be on this PC: set $($script:BowerbirdLlmDefaults.UrlEnv) to a 127.0.0.1 address (default $($script:BowerbirdLlmDefaults.Url)).")
 if([string]::IsNullOrWhiteSpace($url) -or -not [Uri]::TryCreate($url.Trim(),[UriKind]::Absolute,[ref]$u)){throw $bad}
 if($u.UserInfo){throw 'The Fairlead address must not contain a user name or password.'}
 if(-not (Test-BowerbirdLoopbackUrl -Url $url)){throw $bad}
}
function Split-BowerbirdCommandLine {
 # CommandLineToArgvW splitting, the same rules FleetPort uses for a process's -File script.
 param([string]$CommandLine)
 $out=New-Object System.Collections.Generic.List[string]
 if(-not $CommandLine){return ,$out.ToArray()}
 $sb=New-Object System.Text.StringBuilder
 $inQuote=$false;$have=$false;$i=0;$n=$CommandLine.Length
 while($i -lt $n){
  $c=$CommandLine[$i]
  if($c -eq '\'){
   $j=$i;while($j -lt $n -and $CommandLine[$j] -eq '\'){$j++}
   $count=$j-$i
   if($j -lt $n -and $CommandLine[$j] -eq '"'){
    [void]$sb.Append('\',[int][Math]::Floor($count/2))
    if($count % 2 -eq 1){[void]$sb.Append('"');$i=$j+1}else{$i=$j}
   }else{[void]$sb.Append('\',$count);$i=$j}
   $have=$true;continue
  }
  if($c -eq '"'){
   if($inQuote -and ($i+1) -lt $n -and $CommandLine[$i+1] -eq '"'){[void]$sb.Append('"');$i+=2;$have=$true;continue}
   $inQuote=-not $inQuote;$have=$true;$i++;continue
  }
  if(-not $inQuote -and ($c -eq ' ' -or $c -eq "`t")){
   if($have){$out.Add($sb.ToString());[void]$sb.Clear();$have=$false}
   $i++;continue
  }
  [void]$sb.Append($c);$have=$true;$i++
 }
 if($have){$out.Add($sb.ToString())}
 return ,$out.ToArray()
}
function Get-BowerbirdScriptFromCommandLine {
 # The script passed to powershell.exe or pwsh with -File, or $null. -Command before -File is not a script launch.
 param([string]$CommandLine)
 [string[]]$argv=Split-BowerbirdCommandLine $CommandLine
 if($null -eq $argv -or $argv.Count -lt 3){return $null}
 $exeLeaf=($argv[0] -split '[\\/]')[-1]
 if(@('powershell','powershell.exe','pwsh','pwsh.exe') -notcontains $exeLeaf.ToLowerInvariant()){return $null}
 for($k=1;$k -lt $argv.Count-1;$k++){
  $a=$argv[$k].ToLowerInvariant()
  if($a -eq '-file' -or $a -eq '-f' -or $a -eq '/file'){return $argv[$k+1]}
  if($a -match '^[-/](c|command|e|ec|encodedcommand|commandwithargs|cwa)$'){return $null}
  if($a -match '^[-/](executionpolicy|ep|ex|windowstyle|w|version|v|inputformat|if|outputformat|of|psconsolefile|configurationname|workingdirectory|wd|settingsfile)$'){$k++;continue}
  if($a -notmatch '^[-/]'){return $null}
 }
 return $null
}
function ConvertTo-BowerbirdAbsolutePath {
 # An absolute Windows path with no trailing separator, or $null. A relative path is refused.
 param([string]$Path)
 if(-not $Path){return $null}
 $p=$Path.Trim().Trim('"').Replace('/','\')
 if($p -notmatch '^(?:[A-Za-z]:\\|\\\\[^\\?.]+\\[^\\]+)'){return $null}
 if($env:OS -eq 'Windows_NT'){
  try{$p=[IO.Path]::GetFullPath($p)}catch{return $null}
 }elseif($p -match '\\\.{1,2}(\\|$)'){return $null}
 return $p.TrimEnd('\')
}
function Test-BowerbirdProcessPath {
 # $true only when $Path is exactly the process executable or its -File script. Never a substring.
 param([string]$Path,[string]$CommandLine,[string]$ExecutablePath)
 $want=ConvertTo-BowerbirdAbsolutePath $Path
 if(-not $want){return $false}
 $exe=ConvertTo-BowerbirdAbsolutePath $ExecutablePath
 if($exe -and [string]::Equals($exe,$want,[StringComparison]::OrdinalIgnoreCase)){return $true}
 $scriptPath=ConvertTo-BowerbirdAbsolutePath (Get-BowerbirdScriptFromCommandLine $CommandLine)
 if($scriptPath -and [string]::Equals($scriptPath,$want,[StringComparison]::OrdinalIgnoreCase)){return $true}
 return $false
}
function Test-BowerbirdLoopbackBind {
 param([string]$Address)
 $a=([string]$Address).Trim().TrimStart('[').TrimEnd(']')
 return @('127.0.0.1','0.0.0.0','::1','::','localhost') -contains $a.ToLowerInvariant()
}
function Get-BowerbirdLoopbackListeners {
 # @{ Known; Pids }. Known is $false when this PC cannot say who listens (the key is then not sent).
 param([Parameter(Mandatory)][int]$Port)
 if($env:OS -ne 'Windows_NT'){return @{Known=$false;Reason='windows';Pids=@()}}
 $pids=New-Object System.Collections.Generic.List[int]
 if(Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue){
  try{$rows=@(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop)}catch{return @{Known=$false;Reason='read';Pids=@()}}
  foreach($row in $rows){
   if(Test-BowerbirdLoopbackBind ([string]$row.LocalAddress)){$pids.Add([int]$row.OwningProcess)}
  }
 }else{
  $sys=[Environment]::SystemDirectory
  if(-not $sys){return @{Known=$false;Reason='read';Pids=@()}}
  $netstat=Join-Path $sys 'netstat.exe'
  if(-not (Test-Path -LiteralPath $netstat)){return @{Known=$false;Reason='read';Pids=@()}}
  $lines=@(& $netstat -ano -p TCP 2>$null)+@(& $netstat -ano -p TCPv6 2>$null)
  foreach($line in $lines){
   $m=[regex]::Match([string]$line,'^\s*TCP\s+(\[[^\]]+\]|[^:\s]+):(\d+)\s+\S+\s+LISTENING\s+(\d+)\s*$')
   if(-not $m.Success){continue}
   if([int]$m.Groups[2].Value -ne $Port){continue}
   if(Test-BowerbirdLoopbackBind $m.Groups[1].Value){$pids.Add([int]$m.Groups[3].Value)}
  }
 }
 return @{Known=$true;Reason='';Pids=@($pids|Sort-Object -Unique)}
}
function Get-BowerbirdProcessInfo {
 param([Parameter(Mandatory)][int]$ProcessId)
 if($env:OS -ne 'Windows_NT'){return $null}
 try{$p=Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction Stop}catch{return $null}
 if(-not $p){return $null}
 return @{CommandLine=[string]$p.CommandLine;ExecutablePath=[string]$p.ExecutablePath}
}
function Invoke-BowerbirdFairleadId {
 # GET /__fleethacker/id with no key, no proxy and no redirect. $null when the body is not usable.
 param([Parameter(Mandatory)][string]$Url,[int]$TimeoutSec=3)
 $req=[Net.HttpWebRequest]::Create($Url)
 $req.Method='GET'
 $req.Timeout=$TimeoutSec*1000
 $req.ReadWriteTimeout=$TimeoutSec*1000
 $req.Proxy=$null
 $req.AllowAutoRedirect=$false
 $req.Accept='application/json'
 $req.UserAgent='Bowerbird'
 $resp=$null
 try{
  $resp=$req.GetResponse()
  $reader=New-Object IO.StreamReader($resp.GetResponseStream(),[Text.Encoding]::UTF8)
  try{$text=$reader.ReadToEnd()}finally{$reader.Dispose()}
  if([string]::IsNullOrEmpty($text) -or $text.Length -gt 4096){return $null}
  try{return ($text|ConvertFrom-Json)}catch{return $null}
 }finally{if($null -ne $resp){try{$resp.Close()}catch{}}}
}
function Test-BowerbirdFairleadIdentity {
 # $null when this address is Fairlead, else @{ Code; Error }. The id request carries no key.
 param([Parameter(Mandatory)]$Config)
 $u=[Uri]([string]$Config.Url)
 $port=$u.Port
 $notFairlead='Something other than Fairlead is answering on port '+$port+'; the key was not sent.'
 $probe=& $script:BowerbirdPortListeners $port
 if(-not $probe -or -not $probe.Known){
  if($probe -and $probe.Reason -eq 'windows'){return @{Code='port-check';Error='Bowerbird can check which program holds Fairlead''s port only on Windows, so the Fairlead key is not sent.'}}
  return @{Code='port-check';Error=('Bowerbird could not read which program listens on port '+$port+', so the Fairlead key was not sent.')}
 }
 $pids=@()
 if($probe.Pids){$pids=@($probe.Pids|ForEach-Object {[int]$_}|Sort-Object -Unique)}
 if($pids.Count -eq 0){return @{Code='down';Error=('Nothing is listening on port '+$port+', so the Fairlead key was not sent.')}}
 if($pids.Count -gt 1){return @{Code='not-fairlead';Error=$notFairlead}}
 $owner=[int]$pids[0]
 if($owner -le 4){return @{Code='not-fairlead';Error=$notFairlead}}
 $idUrl=$u.GetLeftPart([UriPartial]::Authority)+'/__fleethacker/id'
 try{$id=& $script:BowerbirdIdFetch $idUrl}catch{return @{Code='not-fairlead';Error=$notFairlead}}
 $tool=$null
 if($id -and $id.PSObject.Properties['tool']){$tool=[string]$id.tool}
 if(-not [string]::Equals($tool,'fairlead',[StringComparison]::Ordinal)){return @{Code='not-fairlead';Error=$notFairlead}}
 $idPid=0
 $pidText=''
 if($id.PSObject.Properties['pid']){$pidText=[string]$id.pid}
 if(-not [int]::TryParse($pidText,[ref]$idPid) -or $idPid -ne $owner){return @{Code='not-fairlead';Error=$notFairlead}}
 $reported=$null
 if($id.PSObject.Properties['path']){$reported=$id.path}
 if($reported -isnot [string] -or [string]::IsNullOrWhiteSpace($reported)){return @{Code='not-fairlead';Error=$notFairlead}}
 $info=& $script:BowerbirdProcessInfo $owner
 $command='';$exe=''
 if($info){$command=[string]$info.CommandLine;$exe=[string]$info.ExecutablePath}
 if(-not (Test-BowerbirdProcessPath -Path $reported -CommandLine $command -ExecutablePath $exe)){return @{Code='not-fairlead';Error=$notFairlead}}
 return $null
}
function Find-BowerbirdFleetPortModule {
 # FleetPort.psm1 beside this repo (../edge-ops/tools/fleet-port) or under %USERPROFILE%\Projects\edge-ops.
 param([string[]]$Roots)
 $list=@()
 if($Roots){$list=@($Roots)}
 elseif($script:BowerbirdFleetPortRoots){$list=@($script:BowerbirdFleetPortRoots)}
 else{
  $parent=Split-Path $script:BowerbirdAppRoot -Parent
  if($parent){$list+=$parent}
  if($env:USERPROFILE){$list+=(Join-Path $env:USERPROFILE 'Projects')}
 }
 foreach($root in $list){
  if([string]::IsNullOrWhiteSpace([string]$root)){continue}
  $p=Join-Path (Join-Path (Join-Path (Join-Path $root 'edge-ops') 'tools') 'fleet-port') 'FleetPort.psm1'
  if(Test-Path -LiteralPath $p -PathType Leaf){return $p}
 }
 return $null
}
function Start-BowerbirdFairleadService {
 # Start-FleetService -Name fairlead, then the caller waits on its State. No environment is passed.
 param([Parameter(Mandatory)]$Config)
 if(-not (Get-Command Start-FleetService -ErrorAction SilentlyContinue)){
  $module=Find-BowerbirdFleetPortModule
  if(-not $module){return [pscustomobject]@{State='unavailable';Message='Fairlead is not running, and FleetPort (Start-FleetService) was not found next to this app or in Projects\edge-ops. Put the edge-ops repo beside Bowerbird, or start Fairlead.'}}
  try{Import-Module -Name $module -ErrorAction Stop}catch{return [pscustomobject]@{State='unavailable';Message='Fairlead is not running, and FleetPort could not be loaded. Start Fairlead itself.'}}
 }
 return Start-FleetService -Name fairlead -WaitSeconds 40 -CallerRoot $script:BowerbirdAppRoot
}
function Resolve-BowerbirdFairlead {
 # Confirm the address is Fairlead. When nothing is on port 8776, start it and check once more.
 # The key is not read here. A failure throws; the message does not contain a key.
 param([Parameter(Mandatory)]$Config)
 Assert-BowerbirdLlmUrl -Config $Config
 $why=Test-BowerbirdFairleadIdentity -Config $Config
 if($why -and $why.Code -eq 'down'){
  $port=([Uri]([string]$Config.Url)).Port
  if($port -ne 8776){throw "Fairlead is not running at $($Config.Url). Bowerbird starts Fairlead only on port 8776."}
  try{$started=& $script:BowerbirdFleetServiceStart $Config}catch{throw 'Fairlead could not be started. The key was not sent.'}
  $state=''
  $message='Fairlead is not running.'
  if($started){$state=[string]$started.State;if($started.Message){$message=[string]$started.Message}}
  if($state -ne 'running'){throw $message}
  $why=Test-BowerbirdFairleadIdentity -Config $Config
 }
 if($why){throw [string]$why.Error}
}
function Get-BowerbirdLlmHeaders {
 # The headers every Fairlead call carries. The address is checked before the key is read, and the key is not kept.
 param([Parameter(Mandatory)]$Config)
 & $script:BowerbirdFairleadPrepare $Config
 return @{Authorization=('Bearer '+(Get-BowerbirdFairleadKey));'X-Fairlead-Label'=$Config.Label;'X-Fairlead-Privacy'=$Config.Privacy}
}
function Invoke-BowerbirdChat {
 [CmdletBinding()]param([Parameter(Mandatory)][object[]]$Messages,[string]$Model,[int]$MaxTokens=1024,[double]$Temperature=0.15,[int]$TimeoutSec=180)
 $cfg=Get-BowerbirdLlmConfig
 Assert-BowerbirdLlmUrl -Config $cfg
 if($Model){$cfg.Model=$Model}
 $headers=Get-BowerbirdLlmHeaders -Config $cfg
 $headers['Accept']='application/json'
 $msgList=@()
 foreach($m in $Messages){
  $role=if($m -is [hashtable]){[string]$m['role']}else{[string]$m.role}
  $content=if($m -is [hashtable]){$m['content']}else{$m.content}
  $msgList+=@{role=$role;content=$content}
 }
 $payload=[ordered]@{messages=$msgList;max_tokens=$MaxTokens;model=$cfg.Model;temperature=$Temperature;stream=$false}
 $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 12))
 $resp=Invoke-RestMethod -Uri $cfg.Url -Method Post -Headers $headers -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
 $text=$null
 if($resp.choices -and $resp.choices[0].message.content){$text=[string]$resp.choices[0].message.content}
 elseif($resp.choices -and $resp.choices[0].text){$text=[string]$resp.choices[0].text}
 return [pscustomobject]@{Model=$cfg.Model;Raw=$resp;Text=$text}
}
