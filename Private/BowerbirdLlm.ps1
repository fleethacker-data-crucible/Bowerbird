# Bowerbird AI endpoint / Grok multimodal client
#requires -Version 5.1
# Endpoint URLs are configuration, not code: set BOWERBIRD_AI_ENDPOINT_URL / BOWERBIRD_GROK_URL
# (or LLM_URL for any profile) in Config\bowerbird.env.
$script:BowerbirdLlmDefaults=@{
 GrokUrlEnv='BOWERBIRD_GROK_URL'
 GrokModel='system.ai.grok-4-6'
 AiEndpointUrlEnv='BOWERBIRD_AI_ENDPOINT_URL'
 AiEndpointModel='gemini-3.8-flash'
}
# Profiles are Auto | AiEndpoint | Grok. The former AI-endpoint profile name is a legacy alias (deprecated).
$script:BowerbirdLlmProfileAliases=@{'GenAi'='AiEndpoint'}   # legacy alias
# Token variables per profile, current name first; the second AiEndpoint entry is a legacy alias (deprecated).
$script:BowerbirdLlmTokenEnv=@{AiEndpoint=@('AI_ENDPOINT_TOKEN','GENAI_TOKEN');Grok=@('DATABRICKS_TOKEN')}   # legacy alias
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
 foreach($known in @('Auto','AiEndpoint','Grok')){if($p -eq $known){return $known}}
 throw "Unknown LLM profile '$Profile'. Use Auto, AiEndpoint or Grok."
}
function Get-BowerbirdLlmEnvToken {
 param([string]$ForProfile)
 foreach($n in @($script:BowerbirdLlmTokenEnv[$ForProfile])){
  $v=[Environment]::GetEnvironmentVariable($n);if(-not [string]::IsNullOrWhiteSpace($v)){return $v.Trim()}
 }
 return $null
}
function Get-BowerbirdLlmConfig {
 [CmdletBinding()]param([string]$Profile='Auto')
 $Profile=ConvertTo-BowerbirdLlmProfile -Profile $Profile
 $url=$env:LLM_URL;$model=$env:LLM_MODEL;$resolved=$Profile
 if($Profile -eq 'Auto'){
  if($url -match 'serving-endpoints'){$resolved='Grok'}
  elseif((Get-BowerbirdLlmEnvToken -ForProfile Grok) -and -not (Get-BowerbirdLlmEnvToken -ForProfile AiEndpoint)){$resolved='Grok'}
  else{$resolved='AiEndpoint'}
 }
 if([string]::IsNullOrWhiteSpace($url)){$url=[Environment]::GetEnvironmentVariable($script:BowerbirdLlmDefaults[$resolved+'UrlEnv'])}
 if([string]::IsNullOrWhiteSpace($model)){$model=$script:BowerbirdLlmDefaults[$resolved+'Model']}
 if($null -eq $url){$url=''}
 return [pscustomobject]@{Profile=$resolved;Url=$url.Trim().TrimEnd('/');Model=$model}
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
function Invoke-BowerbirdChat {
 [CmdletBinding()]param([Parameter(Mandatory)][object[]]$Messages,[string]$Profile='Auto',[string]$Model,[int]$MaxTokens=1024,[double]$Temperature=0.15,[int]$TimeoutSec=180)
 $cfg=Get-BowerbirdLlmConfig -Profile $Profile
 Assert-BowerbirdLlmUrl -Config $cfg
 if($Model){$cfg.Model=$Model}
 $token=Get-BowerbirdLlmToken -ForProfile $cfg.Profile
 $token=$token.Trim().Trim("'").Trim('"')
 if($token -match '^(?i)Bearer\s+(.+)$'){$token=$Matches[1].Trim()}
 $token=($token -replace '[\r\n]','').Trim()
 if(-not $token){throw 'LLM token empty after sanitization'}
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
 $resp=Invoke-RestMethod -Uri $cfg.Url -Method Post -Headers @{Authorization=('Bearer '+$token);Accept='application/json'} -Body $bytes -ContentType 'application/json; charset=utf-8' -TimeoutSec $TimeoutSec
 $text=$null
 if($resp.choices -and $resp.choices[0].message.content){$text=[string]$resp.choices[0].message.content}
 elseif($resp.choices -and $resp.choices[0].text){$text=[string]$resp.choices[0].text}
 elseif($resp.candidates -and $resp.candidates[0].content.parts){$text=($resp.candidates[0].content.parts|ForEach-Object {$_.text}) -join ''}
 elseif($resp.content){$text=[string]$resp.content}
 return [pscustomobject]@{Profile=$cfg.Profile;Model=$cfg.Model;Raw=$resp;Text=$text}
}
