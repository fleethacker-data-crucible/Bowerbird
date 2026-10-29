#requires -Version 5.1
<#
 Bowerbird CLI: the Studio API as named commands, for scripts and agents. See docs\CLI.md.
   Start-Bowerbird-Console.bat <noun> <verb> [--key value ...] [--json] [--out file] [--yes] [--dry-run]
   Start-Bowerbird-Console.bat commands [--json]
 Global options: --root <folder> (workspace; default as Studio), --allow-cloud-ai, --local-dev,
 --input <file.json> (body fields as JSON). Commands run in this process through the same dispatcher
 as the browser (Private\BowerbirdApi.ps1); no server or port is opened.
 Exit codes: 0 ok, 1 error, 2 usage (including a destructive command without --yes).
#>
$ErrorActionPreference='Stop'
$script:AppRoot=$PSScriptRoot
$script:Session=$null
$Port=0
$AllowCloudAI=$false
$utf8=New-Object Text.UTF8Encoding $false
try{[Console]::OutputEncoding=$utf8}catch{}
. (Join-Path $AppRoot 'Private\BowerbirdCommands.ps1')

$script:Json=$false;$script:Out='';$yes=$false;$dryRun=$false;$root='';$localDev=$false;$inputFile=''
$script:CommandName=''
function Write-BowerbirdCliOutput([string]$Text){
 if($script:Out){
  $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($script:Out)
  [IO.File]::WriteAllText($full,$Text+[Environment]::NewLine,$utf8)
  if(-not $script:Json){[Console]::Error.WriteLine('Wrote '+$full)}
 }else{[Console]::Out.WriteLine($Text)}
}
function Exit-BowerbirdCli([int]$Code,[string]$Message,$Result){
 if($Code -eq 0){
  if($script:Json){$text=ConvertTo-Json -InputObject ([ordered]@{schema='bowerbird.result/1';command=$script:CommandName;ok=$true;result=$Result}) -Depth 12}
  elseif($Result -is [string]){$text=$Result}
  else{$text=ConvertTo-Json -InputObject $Result -Depth 12}
  Write-BowerbirdCliOutput $text
 }else{
  if($script:Json){Write-BowerbirdCliOutput (ConvertTo-Json -InputObject ([ordered]@{schema='bowerbird.result/1';command=$script:CommandName;ok=$false;error=$Message}) -Depth 4)}
  else{[Console]::Error.WriteLine('bowerbird: '+$Message);if($Code -eq 2){[Console]::Error.WriteLine('Run "commands" for the list of commands and their options.')}}
 }
 exit $Code
}

# Split the arguments into words, global options and command options (raw values; $null = no value).
$words=New-Object Collections.Generic.List[string]
$options=[ordered]@{}
$argv=@($args)
for($i=0;$i -lt $argv.Count;$i++){
 $token=[string]$argv[$i]
 if(-not $token.StartsWith('--')){$words.Add($token);continue}
 $name=$token.Substring(2);$value=$null;$hasValue=$false
 if($name.Contains('=')){$value=$name.Substring($name.IndexOf('=')+1);$name=$name.Substring(0,$name.IndexOf('='));$hasValue=$true}
 if($name -ceq 'json'){$script:Json=$true;continue}
 if($name -ceq 'yes'){$yes=$true;continue}
 if($name -ceq 'dry-run'){$dryRun=$true;continue}
 if($name -ceq 'allow-cloud-ai'){$AllowCloudAI=$true;continue}
 if($name -ceq 'local-dev'){$localDev=$true;continue}
 if(-not $hasValue -and $i+1 -lt $argv.Count -and -not ([string]$argv[$i+1]).StartsWith('--')){$value=[string]$argv[$i+1];$i++;$hasValue=$true}
 if($name -cmatch '^(out|root|input)$'){
  if(-not $hasValue -or -not $value){Exit-BowerbirdCli 2 ('--'+$name+' needs a value')}
  if($name -ceq 'out'){$script:Out=$value}elseif($name -ceq 'root'){$root=$value}else{$inputFile=$value}
  continue
 }
 if($name -cnotmatch '^[a-z][a-z-]*$'){Exit-BowerbirdCli 2 ('Unknown option '+$token)}
 $options[$name]=$value
}

if($words.Count -eq 0 -or ($words.Count -eq 1 -and $words[0] -ceq 'commands')){
 $script:CommandName='bowerbird commands list'
 if($options.Count){Exit-BowerbirdCli 2 ('commands takes no options: --'+(@($options.Keys) -join ', --'))}
 $catalog=Get-BowerbirdCommandCatalog
 if($script:Json){$script:Json=$false;Exit-BowerbirdCli 0 '' (ConvertTo-Json -InputObject $catalog -Depth 12)}
 $lines=New-Object Collections.Generic.List[string]
 foreach($command in $catalog.commands){
  $marks=@();if($command.destructive){$marks+='needs --yes'};if($command.needs){$marks+=('needs '+$command.needs)};if($command.interactive){$marks+='opens a window'}
  $lines.Add($command.name.PadRight(32)+$command.summary+$(if($marks){' ['+($marks -join '; ')+']'}else{''}))
  foreach($field in $command.inputs){$lines.Add('    --'+$field.flag.PadRight(18)+$field.type.PadRight(8)+$(if($field.required){'required  '}else{'          '})+$field.help)}
 }
 Exit-BowerbirdCli 0 '' ($lines -join [Environment]::NewLine)
}
if($words.Count -ne 2){Exit-BowerbirdCli 2 'Expected a command: <noun> <verb> (or "commands")'}
$script:CommandName='bowerbird '+$words[0]+' '+$words[1]
$command=Get-BowerbirdCommand $script:CommandName
if(-not $command){$name=$script:CommandName;$script:CommandName='';Exit-BowerbirdCli 2 ('Unknown command: '+$name)}

# Type each option against the command's inputs.
$arguments=@{}
if($inputFile){
 try{$fromFile=Get-Content -LiteralPath $inputFile -Raw -Encoding UTF8|ConvertFrom-Json}catch{Exit-BowerbirdCli 2 ('--input is not a readable JSON file: '+$_.Exception.Message)}
 foreach($property in @($fromFile.PSObject.Properties)){$arguments[$property.Name]=$property.Value}
}
foreach($name in @($options.Keys)){
 $field=$command.inputs|Where-Object {$_.flag -ceq $name}|Select-Object -First 1
 if(-not $field){Exit-BowerbirdCli 2 ($command.name+' has no option --'+$name)}
 $raw=$options[$name]
 switch($field.type){
  'bool' {
   if($null -eq $raw){$arguments[$name]=$true}
   elseif($raw -match '^(true|yes|1)$'){$arguments[$name]=$true}
   elseif($raw -match '^(false|no|0)$'){$arguments[$name]=$false}
   else{Exit-BowerbirdCli 2 ('--'+$name+' takes true or false')}
  }
  'int' {
   $number=0
   if($null -eq $raw -or -not [int]::TryParse($raw,[ref]$number)){Exit-BowerbirdCli 2 ('--'+$name+' needs a whole number')}
   $arguments[$name]=$number
  }
  'json' {
   if($null -eq $raw){Exit-BowerbirdCli 2 ('--'+$name+' needs JSON, or @file.json')}
   try{
    $text=if($raw.StartsWith('@')){Get-Content -LiteralPath $raw.Substring(1) -Raw -Encoding UTF8}else{$raw}
    $arguments[$name]=ConvertFrom-Json $text
   }catch{Exit-BowerbirdCli 2 ('--'+$name+' is not valid JSON: '+$_.Exception.Message)}
  }
  default {
   if($null -eq $raw){Exit-BowerbirdCli 2 ('--'+$name+' needs a value')}
   $arguments[$name]=$raw
  }
 }
}
foreach($field in $command.inputs){
 if($field.required -and -not ($arguments.ContainsKey($field.flag) -or $arguments.ContainsKey($field.key))){Exit-BowerbirdCli 2 ($command.name+' needs --'+$field.flag)}
}
if($dryRun){Exit-BowerbirdCli 0 '' (Invoke-BowerbirdCommand -Name $command.name -Arguments $arguments -DryRun)}
if($command.destructive -and -not $yes){Exit-BowerbirdCli 2 ($command.name+' changes files or saved state; pass --yes to run it (or --dry-run to see the request)')}

# The same user-local state as Studio; never the program folder.
try{
 $localData=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
 if(-not $localData){$localData=[IO.Path]::GetTempPath()}
 $script:DataRoot=Join-Path $localData $(if($localDev){'Bowerbird\LocalDev\State'}else{'Bowerbird\State'})
 $script:LogDir=Join-Path $localData $(if($localDev){'Bowerbird\LocalDev\Logs'}else{'Bowerbird\Logs'})
 [IO.Directory]::CreateDirectory($script:DataRoot)|Out-Null
 [IO.Directory]::CreateDirectory($script:LogDir)|Out-Null
 $script:LogFile=Join-Path $script:LogDir ('cli-'+(Get-Date -Format 'yyyyMMdd')+'.jsonl')
 function Write-BowerbirdDiagnostic {
  [CmdletBinding()]param([string]$Level='INFO',[string]$Event,[string]$Message='',[string]$Route='',[string]$RequestId='')
  try{
   $safe=Get-BowerbirdSafeDiagnosticText -Value ([string]$Message -replace '(?i)https?://[^\s]+','[URL REDACTED]') -Limit 480
   $line=[pscustomobject]@{time=[DateTime]::UtcNow.ToString('o');level=$Level;event=$Event;route=$Route;requestId=$RequestId;message=$safe}|ConvertTo-Json -Compress
   [IO.File]::AppendAllText($script:LogFile,$line+[Environment]::NewLine,[Text.Encoding]::UTF8)
  }catch{}
 }
 foreach($module in @('BowerbirdIntelligence','BowerbirdAdvanced','BowerbirdStreaming','Get-ImageMetadata','BowerbirdPass1','BowerbirdPass2','BowerbirdNamer','BowerbirdRenameStudio','BowerbirdActions','BowerbirdLlm','LazaretteBridge','BowerbirdWorkspace','BowerbirdSupport','BowerbirdApi')){
  . (Join-Path $AppRoot ('Private\'+$module+'.ps1'))
 }
 if([string]::IsNullOrWhiteSpace($root)){
  $candidates=New-Object Collections.Generic.List[string]
  if($env:USERPROFILE){$candidates.Add((Join-Path $env:USERPROFILE 'Pictures'));$candidates.Add((Join-Path $env:USERPROFILE 'Documents'));$candidates.Add($env:USERPROFILE)}
  $candidates.Add((Get-Location).ProviderPath)
  foreach($candidate in $candidates){
   if($candidate -and (Test-Path -LiteralPath $candidate -PathType Container)){$root=$candidate;break}
  }
 }else{$root=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($root)}
 # Open the workspace without Set-BowerbirdWorkspace -Initial, which discards the saved plan:
 # plan apply runs in a later process than the preview that saved it.
 $script:AllowedRoot=Confirm-BowerbirdWorkspaceDirectory $root
 $script:WorkspaceDataDir=Get-BowerbirdWorkspaceDataDirectory $script:AllowedRoot
 [IO.Directory]::CreateDirectory($script:WorkspaceDataDir)|Out-Null
 $script:IndexPath=Join-Path $script:WorkspaceDataDir 'studio-index.json'
 $script:JournalPath=Join-Path $script:WorkspaceDataDir 'studio-journal.json'
 $script:PlanPath=Join-Path $script:WorkspaceDataDir 'studio-plan.json'
 Write-BowerbirdDiagnostic -Event 'CLI' -Message $command.name
 $result=Invoke-BowerbirdCommand -Name $command.name -Arguments $arguments -Yes:$yes
}catch{
 $message=$_.Exception.Message
 try{Write-BowerbirdDiagnostic -Level ERROR -Event 'CLI_ERROR' -Message $message}catch{}
 if(Get-Command Get-BowerbirdSafeDiagnosticText -ErrorAction SilentlyContinue){$message=Get-BowerbirdSafeDiagnosticText -Value $message -Limit 360}
 Exit-BowerbirdCli 1 $message
}
Exit-BowerbirdCli 0 '' $result
