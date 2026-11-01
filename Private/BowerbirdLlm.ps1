# Bowerbird AI client: every call goes to Fairlead, the Fleet model router on this PC.
#requires -Version 5.1
# Fairlead owns the endpoint choice, the provider keys and the fallbacks. Bowerbird sends a route name and
# its own Fairlead client key, and nothing else about where the model lives.
#   BOWERBIRD_FAIRLEAD_URL      Fairlead's chat address (loopback only); default http://127.0.0.1:8776/v1/chat/completions
#   BOWERBIRD_FAIRLEAD_MODEL    the Fairlead route name to ask for; default auto
#   BOWERBIRD_FAIRLEAD_PRIVACY  local (default) keeps prompts on local models; any lets Fairlead use cloud models.
#                               Launching with -AllowCloudAI sets it to any for that run.
# The client key is read only from Windows Credential Manager, generic credential Fairlead/Bowerbird, which
# Fairlead writes ("Install for this app"). There is no environment variable and no vault item for it.
$script:BowerbirdLlmDefaults=@{
 UrlEnv='BOWERBIRD_FAIRLEAD_URL'
 Url='http://127.0.0.1:8776/v1/chat/completions'
 ModelEnv='BOWERBIRD_FAIRLEAD_MODEL'
 Model='auto'
 PrivacyEnv='BOWERBIRD_FAIRLEAD_PRIVACY'
 AppName='Bowerbird'
}
$script:BowerbirdCredentialTarget='Fairlead/Bowerbird'
# Returns the stored credential's text, or $null when there is none. Replaceable so tests never read the real store.
$script:BowerbirdCredentialReader={param([string]$Target) Read-BowerbirdWindowsCredential -Target $Target}

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
function Get-BowerbirdFairleadKey {
 $key=& $script:BowerbirdCredentialReader $script:BowerbirdCredentialTarget
 $key=([string]$key).Trim()
 if($key -match '^(?i)Bearer\s+(.+)$'){$key=$Matches[1].Trim()}
 $key=($key -replace '[\r\n]','').Trim().Trim("'").Trim('"').Trim()
 if([string]::IsNullOrWhiteSpace($key)){throw 'Open Fairlead and install a key for Bowerbird.'}
 return $key
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
 if(-not (Test-BowerbirdLoopbackUrl -Url ([string]$Config.Url))){
  throw ("Fairlead must be on this PC: set $($script:BowerbirdLlmDefaults.UrlEnv) to a 127.0.0.1 address (default $($script:BowerbirdLlmDefaults.Url)).")
 }
}
function Get-BowerbirdLlmHeaders {
 # The headers every Fairlead call carries. The key is read for this call and not kept.
 param([Parameter(Mandatory)]$Config)
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
