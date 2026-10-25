# Bowerbird GenAI / Grok multimodal client
#requires -Version 5.1
$script:BowerbirdLlmDefaults=@{
 GrokUrl='https://advana-jupiter.cloud.databricks.mil/serving-endpoints/databricks-grok-4-6/invocations'
 GrokModel='system.ai.grok-4-6'
 GenAiUrl='https://api.genai.mil/v1/chat/completions'
 GenAiModel='gemini-3.8-flash'
}
function Get-BowerbirdLlmConfig {
 [CmdletBinding()]param([ValidateSet('Auto','Grok','GenAi')][string]$Profile='Auto')
 $url=$env:LLM_URL;$model=$env:LLM_MODEL;$resolved=$Profile
 if($Profile -eq 'Auto'){
  if($url -match 'databricks\.mil|serving-endpoints'){$resolved='Grok'}
  elseif($url -match 'genai\.mil'){$resolved='GenAi'}
  elseif(-not [string]::IsNullOrWhiteSpace($env:DATABRICKS_TOKEN) -and [string]::IsNullOrWhiteSpace($env:GENAI_TOKEN)){$resolved='Grok'}
  else{$resolved='GenAi'}
 }
 if([string]::IsNullOrWhiteSpace($url)){$url=if($resolved -eq 'GenAi'){$script:BowerbirdLlmDefaults.GenAiUrl}else{$script:BowerbirdLlmDefaults.GrokUrl}}
 if([string]::IsNullOrWhiteSpace($model)){$model=if($resolved -eq 'GenAi'){$script:BowerbirdLlmDefaults.GenAiModel}else{$script:BowerbirdLlmDefaults.GrokModel}}
 return [pscustomobject]@{Profile=$resolved;Url=$url.TrimEnd('/');Model=$model}
}
function Get-BowerbirdLlmToken {
 [CmdletBinding()]param([ValidateSet('Auto','Grok','GenAi')][string]$ForProfile='Auto',[switch]$AllowPrompt)
 if($ForProfile -eq 'Auto'){$ForProfile=(Get-BowerbirdLlmConfig).Profile}
 if($ForProfile -eq 'GenAi'){$envTarget='GENAI_TOKEN';$defaultItem='genapi';$itemKeys=@('BOWERBIRD_LAZARETTE_ITEM_GenAi','BOWERBIRD_ARC_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_Llm','CASCADE_ARC_ITEM_GenAi','CASCADE_ARC_ITEM_Llm')}
 else{$envTarget='DATABRICKS_TOKEN';$defaultItem='advana-api';$itemKeys=@('BOWERBIRD_LAZARETTE_ITEM_Grok','BOWERBIRD_ARC_ITEM_Grok','HALYARD_LAZARETTE_ITEM_Grok','CASCADE_ARC_ITEM_Grok')}
 $existing=[Environment]::GetEnvironmentVariable($envTarget);if(-not [string]::IsNullOrWhiteSpace($existing)){return $existing.Trim()}
 if(-not [string]::IsNullOrWhiteSpace($env:LLM_TOKEN)){return $env:LLM_TOKEN.Trim()}
 # Vault item name: Bowerbird's own name first (then its former BOWERBIRD_ARC_ITEM_* name), then
 # Halyard's shared HALYARD_LAZARETTE_ITEM_* (then its former CASCADE_ARC_ITEM_*), else the canonical item.
 $lazaretteItem=$null
 foreach($k in $itemKeys){$v=[Environment]::GetEnvironmentVariable($k);if(-not [string]::IsNullOrWhiteSpace($v)){$lazaretteItem=$v.Trim();break}}
 if(-not $lazaretteItem){$lazaretteItem=$defaultItem}
 if(Get-Command Import-BowerbirdLazaretteSession -ErrorAction SilentlyContinue){$null=Import-BowerbirdLazaretteSession -Quiet}
 if(Get-Command Get-BowerbirdLazaretteSecretByName -ErrorAction SilentlyContinue){
  try{$got=Get-BowerbirdLazaretteSecretByName -ServiceName $lazaretteItem;if(-not [string]::IsNullOrWhiteSpace($got)){$plain=[string]$got.Trim();Set-Item -Path "Env:$envTarget" -Value $plain;return $plain}}catch{Write-Verbose $_.Exception.Message}
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
 [CmdletBinding()]param([Parameter(Mandatory)][object[]]$Messages,[ValidateSet('Auto','Grok','GenAi')][string]$Profile='Auto',[string]$Model,[int]$MaxTokens=1024,[double]$Temperature=0.15,[int]$TimeoutSec=180)
 $cfg=Get-BowerbirdLlmConfig -Profile $Profile
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
