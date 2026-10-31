# Bowerbird AI endpoint / Grok multimodal client
#requires -Version 5.1
# AiEndpoint defaults to the local phoenix-lai server's OpenAI-compatible API on this PC (loopback only).
# BOWERBIRD_AI_ENDPOINT_URL overrides it, and LLM_URL overrides every profile. Grok is an outside provider
# with no built-in URL: set BOWERBIRD_GROK_URL (or LLM_URL) in Config\bowerbird.env. No other host is built in.
$script:BowerbirdLlmDefaults=@{
 GrokUrlEnv='BOWERBIRD_GROK_URL'
 GrokModel='system.ai.grok-4-6'
 AiEndpointUrlEnv='BOWERBIRD_AI_ENDPOINT_URL'
 AiEndpointUrl='http://127.0.0.1:1234/v1/chat/completions'   # local phoenix-lai
 AiEndpointModel='gemini-3.8-flash'
 LocalDefaultModel='phoenixlai'   # phoenix-lai's name for "the model it has loaded"
 # Fairlead, the Fleet intelligence router, is opt-in and has no built-in address. Selecting it by name needs
 # BOWERBIRD_FAIRLEAD_URL; Auto picks it only when BOWERBIRD_USE_FAIRLEAD is on. Fairlead owns credentials and
 # routing, so no vault item is read and a token (FAIRLEAD_TOKEN) is optional.
 FairleadUrlEnv='BOWERBIRD_FAIRLEAD_URL'
 FairleadModelEnv='BOWERBIRD_FAIRLEAD_MODEL'
 FairleadModel='auto'
}
# Profiles are Auto | AiEndpoint | Grok | Fairlead. The former AI-endpoint profile name is a legacy alias (deprecated).
$script:BowerbirdLlmProfileAliases=@{'GenAi'='AiEndpoint'}   # legacy alias
# Token variables per profile, current name first; the second AiEndpoint entry is a legacy alias (deprecated).
$script:BowerbirdLlmTokenEnv=@{AiEndpoint=@('AI_ENDPOINT_TOKEN','GENAI_TOKEN');Grok=@('DATABRICKS_TOKEN');Fairlead=@('FAIRLEAD_TOKEN')}   # legacy alias
# Lazarette vault items. Name is canonical; Legacy names (deprecated) are tried when the canonical item is missing.
# EnvKeys override the item name: Bowerbird's current name, then its former names (legacy alias), then Halyard's
# shared HALYARD_LAZARETTE_ITEM_* and the names Halyard used under its previous name (legacy alias).
$script:BowerbirdLlmVaultItems=@{
 AiEndpoint=@{Name='ai-endpoint-api';Legacy=@('genapi')   # legacy alias
  EnvKeys=@('BOWERBIRD_LAZARETTE_ITEM_AiEndpoint','BOWERBIRD_LAZARETTE_ITEM_GenAi','BOWERBIRD_ARC_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_Llm','CASCADE_ARC_ITEM_GenAi','CASCADE_ARC_ITEM_Llm')}   # legacy alias
 Grok=@{Name='grok-api';Legacy=@('advana-api')   # legacy alias
  EnvKeys=@('BOWERBIRD_LAZARETTE_ITEM_Grok','BOWERBIRD_ARC_ITEM_Grok','HALYARD_LAZARETTE_ITEM_Grok','CASCADE_ARC_ITEM_Grok')}   # legacy alias
}
function ConvertTo-BowerbirdLlmProfile {
 [CmdletBinding()]param([string]$Profile='Auto')
 if([string]::IsNullOrWhiteSpace($Profile)){return 'Auto'}
 $p=$Profile.Trim()
 foreach($k in $script:BowerbirdLlmProfileAliases.Keys){if($p -eq $k){return $script:BowerbirdLlmProfileAliases[$k]}}
 foreach($known in @('Auto','AiEndpoint','Grok','Fairlead')){if($p -eq $known){return $known}}
 throw "Unknown LLM profile '$Profile'. Use Auto, AiEndpoint, Grok or Fairlead."
}
function Get-BowerbirdLlmEnvToken {
 param([string]$ForProfile)
 foreach($n in @($script:BowerbirdLlmTokenEnv[$ForProfile])){
  $v=[Environment]::GetEnvironmentVariable($n);if(-not [string]::IsNullOrWhiteSpace($v)){return $v.Trim()}
 }
 return $null
}
function Test-BowerbirdFairleadEnabled {
 # Off unless BOWERBIRD_USE_FAIRLEAD is set (1, true, yes or on). Only then does Auto route through Fairlead.
 $v=[Environment]::GetEnvironmentVariable('BOWERBIRD_USE_FAIRLEAD')
 return (-not [string]::IsNullOrWhiteSpace($v) -and $v.Trim() -match '^(?i)(1|true|yes|on)$')
}
function Get-BowerbirdLlmConfig {
 [CmdletBinding()]param([string]$Profile='Auto')
 $Profile=ConvertTo-BowerbirdLlmProfile -Profile $Profile
 $url=$env:LLM_URL;$model=$env:LLM_MODEL;$resolved=$Profile
 if($Profile -eq 'Auto'){
  if(Test-BowerbirdFairleadEnabled){$resolved='Fairlead'}
  elseif($url -match 'serving-endpoints'){$resolved='Grok'}
  elseif((Get-BowerbirdLlmEnvToken -ForProfile Grok) -and -not (Get-BowerbirdLlmEnvToken -ForProfile AiEndpoint)){$resolved='Grok'}
  else{$resolved='AiEndpoint'}
 }
 if([string]::IsNullOrWhiteSpace($url)){$url=[Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults[$resolved+'UrlEnv'])}
 $isDefault=$false
 if([string]::IsNullOrWhiteSpace($url) -and $resolved -eq 'AiEndpoint'){$url=$script:BowerbirdLlmDefaults.AiEndpointUrl;$isDefault=$true}
 if([string]::IsNullOrWhiteSpace($model) -and $resolved -eq 'Fairlead'){$model=[Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults.FairleadModelEnv)}
 if([string]::IsNullOrWhiteSpace($model)){
  if($resolved -eq 'Fairlead'){$model=$script:BowerbirdLlmDefaults.FairleadModel}
  elseif($isDefault){$model=$script:BowerbirdLlmDefaults.LocalDefaultModel}else{$model=$script:BowerbirdLlmDefaults[$resolved+'Model']}
 }
 if($null -eq $url){$url=''}
 return [pscustomobject]@{Profile=$resolved;Url=$url.Trim().TrimEnd('/');Model=$model;DefaultUrl=$isDefault}
}
function Test-BowerbirdLoopbackUrl {
 # True when the URL points at this PC (127.0.0.0/8, ::1 or localhost).
 param([AllowEmptyString()][string]$Url)
 $u=$null
 if([string]::IsNullOrWhiteSpace($Url) -or -not [Uri]::TryCreate($Url.Trim(),[UriKind]::Absolute,[ref]$u)){return $false}
 return [bool]$u.IsLoopback
}
function Assert-BowerbirdLlmUrl {
 param($Config)
 if([string]::IsNullOrWhiteSpace($Config.Url)){
  throw ("No endpoint URL configured for profile $($Config.Profile). Set $($script:BowerbirdLlmDefaults[$Config.Profile+'UrlEnv']) (or LLM_URL) in Config\bowerbird.env.")
 }
}
function Get-BowerbirdLlmToken {
 [CmdletBinding()]param([string]$ForProfile='Auto',[switch]$AllowPrompt)
 $ForProfile=ConvertTo-BowerbirdLlmProfile -Profile $ForProfile
 if($ForProfile -eq 'Auto'){$ForProfile=(Get-BowerbirdLlmConfig).Profile}
 if($ForProfile -eq 'Fairlead'){
  $routerToken=Get-BowerbirdLlmEnvToken -ForProfile Fairlead;if($routerToken){return $routerToken}
  throw 'Fairlead holds the provider credentials; set FAIRLEAD_TOKEN only if your router asks for a token.'
 }
 $spec=$script:BowerbirdLlmVaultItems[$ForProfile]
 $envTarget=@($script:BowerbirdLlmTokenEnv[$ForProfile])[0]
 $existing=Get-BowerbirdLlmEnvToken -ForProfile $ForProfile;if($existing){return $existing}
 if(-not [string]::IsNullOrWhiteSpace($env:LLM_TOKEN)){return $env:LLM_TOKEN.Trim()}
 # Vault item name: an override from EnvKeys (in order), else the canonical item and then its former names.
 $candidates=@()
 foreach($k in $spec.EnvKeys){$v=[Environment]::GetEnvironmentVariable($k);if(-not [string]::IsNullOrWhiteSpace($v)){$candidates=@($v.Trim());break}}
 if($candidates.Count -eq 0){$candidates=@($spec.Name)+@($spec.Legacy)}
 if(Get-Command Import-BowerbirdLazaretteSession -ErrorAction SilentlyContinue){$null=Import-BowerbirdLazaretteSession -Quiet}
 if(Get-Command Get-BowerbirdLazaretteSecretByName -ErrorAction SilentlyContinue){
  foreach($lazaretteItem in $candidates){
   try{$got=Get-BowerbirdLazaretteSecretByName -ServiceName $lazaretteItem;if(-not [string]::IsNullOrWhiteSpace($got)){$plain=[string]$got.Trim();Set-Item -Path "Env:$envTarget" -Value $plain;return $plain}}catch{Write-Verbose $_.Exception.Message}
  }
 }
 if($AllowPrompt -and [Environment]::UserInteractive){
  $secure=Read-Host 'Token' -AsSecureString
  if($null -eq $secure){throw 'No token provided.'}
  $bstr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try{$plain=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr);if($plain){Set-Item -Path "Env:$envTarget" -Value $plain.Trim();return $plain.Trim()}}
  finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)}
 }
 throw "No LLM token for profile $ForProfile. Configure Lazarette or $envTarget."
}
function Get-BowerbirdLlmAuthToken {
 # The sanitized token for a resolved configuration, or $null when none is needed. Remote endpoints need one
 # (Get-BowerbirdLlmToken). A loopback endpoint such as the local phoenix-lai server has its API key off by
 # default: a profile or LLM_TOKEN value is used when set, the vault is not opened, and no header is sent without one.
 param([Parameter(Mandatory)]$Config)
 if($Config.Profile -eq 'Fairlead'){
  # The router holds the provider credentials. A token is sent only when one is set, to loopback or not.
  $routerToken=Get-BowerbirdLlmEnvToken -ForProfile Fairlead
  if(-not $routerToken){return $null}
  return (($routerToken -replace '^(?i)Bearer\s+','') -replace '[\r\n]','').Trim()
 }
 if(Test-BowerbirdLoopbackUrl -Url ([string]$Config.Url)){
  $token=Get-BowerbirdLlmEnvToken -ForProfile $Config.Profile
  if(-not $token -and -not [string]::IsNullOrWhiteSpace($env:LLM_TOKEN)){$token=$env:LLM_TOKEN}
  if(-not $token){return $null}
 }else{$token=Get-BowerbirdLlmToken -ForProfile $Config.Profile}
 $token=([string]$token).Trim().Trim("'").Trim('"')
 if($token -match '^(?i)Bearer\s+(.+)$'){$token=$Matches[1].Trim()}
 $token=($token -replace '[\r\n]','').Trim()
 if(-not $token){
  if(Test-BowerbirdLoopbackUrl -Url ([string]$Config.Url)){return $null}
  throw 'LLM token empty after sanitization'
 }
 return $token
}
function Invoke-BowerbirdChat {
 [CmdletBinding()]param([Parameter(Mandatory)][object[]]$Messages,[string]$Profile='Auto',[string]$Model,[int]$MaxTokens=1024,[double]$Temperature=0.15,[int]$TimeoutSec=180)
 $cfg=Get-BowerbirdLlmConfig -Profile $Profile
 Assert-BowerbirdLlmUrl -Config $cfg
 if($Model){$cfg.Model=$Model}
 $token=Get-BowerbirdLlmAuthToken -Config $cfg
 $msgList=@()
 foreach($m in $Messages){
  $role=if($m -is [hashtable]){[string]$m['role']}else{[string]$m.role}
  $content=if($m -is [hashtable]){$m['content']}else{$m.content}
  $msgList+=@{role=$role;content=$content}
 }
 $payload=[ordered]@{messages=$msgList;max_tokens=$MaxTokens;model=$cfg.Model;temperature=$Temperature}
 if($cfg.Profile -ne 'Grok' -and $cfg.Url -notmatch 'serving-endpoints'){$payload.stream=$false}
 $bytes=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Depth 12))
 try{[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12}catch{}
 # No Authorization header at all when a local endpoint has no token (never an empty "Bearer ").
 $headers=@{Accept='application/json'};if($token){$headers['Authorization']='Bearer '+$token}
 $resp=Invoke-RestMethod -Uri $cfg.Url -Method Post -Headers $headers -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
 $text=$null
 if($resp.choices -and $resp.choices[0].message.content){$text=[string]$resp.choices[0].message.content}
 elseif($resp.choices -and $resp.choices[0].text){$text=[string]$resp.choices[0].text}
 elseif($resp.candidates -and $resp.candidates[0].content.parts){$text=($resp.candidates[0].content.parts|ForEach-Object {$_.text}) -join ''}
 elseif($resp.content){$text=[string]$resp.content}
 return [pscustomobject]@{Profile=$cfg.Profile;Model=$cfg.Model;Raw=$resp;Text=$text}
}
