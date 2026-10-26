#requires -Version 5.1
# No external modules. Execute in a disposable workspace:
# powershell -NoProfile -File .\Tests\Smoke.ps1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $root 'Private\BowerbirdActions.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdTest_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'input';$dest=Join-Path $temp 'output'
New-Item -ItemType Directory -Path $source,$dest -Force|Out-Null
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
try{
 Set-Content -LiteralPath (Join-Path $source 'first.txt') -Value 'Hello bowerbird search test' -Encoding UTF8
 Copy-Item -LiteralPath (Join-Path $source 'first.txt') -Destination (Join-Path $source 'copy.txt')
 Set-Content -LiteralPath (Join-Path $source 'empty.txt') -Value '' -NoNewline
 $index=New-BowerbirdIndex -Path $source -Recurse
 Assert ($index.Files.Count -eq 3) 'Index file count'
 Assert ((Get-BowerbirdText (Join-Path $source 'empty.txt')) -eq '') 'Empty text extraction'
 $hits=@(Search-BowerbirdIndex -Index $index -Query 'bowerbird')
 Assert ($hits.Count -eq 2) 'Search matches'
 $dups=@(Find-BowerbirdDuplicates -Index $index)
 Assert ($dups.Count -eq 1) 'Exact duplicates'
 $rulesPath=Join-Path $temp 'rules.json'
 '[{"Name":"Text","Extension":[".txt"],"Folder":"Text"}]'|Set-Content -LiteralPath $rulesPath
 $plan=New-BowerbirdPlan -Index $index -RulesPath $rulesPath -DestinationRoot $dest
 Assert ($plan.Operations.Count -eq 3) 'Plan count'
 $journal=Join-Path $temp 'journal.json'
 $applied=@(Invoke-BowerbirdPlan -Plan $plan -JournalPath $journal -Apply -Confirm:$false)
 Assert (@($applied|Where-Object {$_.Status -eq 'Applied'}).Count -eq 3) 'Applied statuses'
 Assert ((Get-ChildItem (Join-Path $dest 'Text') -File).Count -eq 3) 'Moved files'
 $restored=@(Undo-BowerbirdPlan -JournalPath $journal -Confirm:$false)
 Assert ($restored.Count -eq 3) 'Undo count'
 Assert ((Get-ChildItem $source -File).Count -eq 3) 'Restored files'
 Write-Host 'PASS: Bowerbird intelligence, duplicate, search, plan, apply and undo smoke test' -ForegroundColor Green
 # Lazarette item names: Bowerbird's current override first, then its former names, then Halyard's names.
 . (Join-Path $root 'Private\LazaretteBridge.ps1')
 . (Join-Path $root 'Private\BowerbirdLlm.ps1')
 $spec=$script:BowerbirdLlmVaultItems.AiEndpoint
 $keys=@($spec.EnvKeys)
 $itemVars=@('LLM_TOKEN','LLM_URL','BOWERBIRD_AI_ENDPOINT_URL','BOWERBIRD_GROK_URL','DATABRICKS_TOKEN')+@($script:BowerbirdLlmTokenEnv.AiEndpoint)+$keys
 $savedVars=@{};foreach($n in $itemVars){$savedVars[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
 try{
  function Import-BowerbirdLazaretteSession {param([switch]$Quiet);return $true}
  function Get-BowerbirdLazaretteSecretByName {param([string]$ServiceName);return ('secret-for-'+$ServiceName)}
  $cases=@(
   @{Set=@{};Want=$spec.Name},
   @{Set=@{$keys[6]='c-llm'};Want='c-llm'},
   @{Set=@{$keys[5]='c-gen';$keys[4]='h-llm'};Want='h-llm'},
   @{Set=@{$keys[3]='h-gen';$keys[2]='b-arc'};Want='b-arc'},
   @{Set=@{$keys[2]='b-arc';$keys[1]='b-old'};Want='b-old'},
   @{Set=@{$keys[1]='b-old';$keys[0]='b-laz'};Want='b-laz'}
  )
  foreach($case in $cases){
   foreach($n in $keys){[Environment]::SetEnvironmentVariable($n,$null)}
   foreach($k in $case.Set.Keys){[Environment]::SetEnvironmentVariable($k,$case.Set[$k])}
   foreach($p in @('AiEndpoint')+@($script:BowerbirdLlmProfileAliases.Keys)){
    $got=Get-BowerbirdLlmToken -ForProfile $p
    Assert ($got -eq ('secret-for-'+$case.Want)) ("Lazarette item order ($p): expected $($case.Want), got $got")
    foreach($n in @($script:BowerbirdLlmTokenEnv.AiEndpoint)){[Environment]::SetEnvironmentVariable($n,$null)}
   }
  }
  foreach($n in $keys){[Environment]::SetEnvironmentVariable($n,$null)}
  # A vault that only holds the former item name still works.
  function Get-BowerbirdLazaretteSecretByName {param([string]$ServiceName);if(@($spec.Legacy) -contains $ServiceName){return 'old-item-secret'};return $null}
  Assert ((Get-BowerbirdLlmToken -ForProfile AiEndpoint) -eq 'old-item-secret') 'Former vault item name still read'
  foreach($n in @($script:BowerbirdLlmTokenEnv.AiEndpoint)){[Environment]::SetEnvironmentVariable($n,$null)}
  # Token variables: current name preferred, former name still read.
  [Environment]::SetEnvironmentVariable(@($script:BowerbirdLlmTokenEnv.AiEndpoint)[1],'old-token')
  Assert ((Get-BowerbirdLlmToken -ForProfile AiEndpoint) -eq 'old-token') 'Former token variable still read'
  $env:AI_ENDPOINT_TOKEN='new-token'
  Assert ((Get-BowerbirdLlmToken -ForProfile AiEndpoint) -eq 'new-token') 'Current token variable preferred'
  # Profiles and endpoint configuration.
  Assert ((ConvertTo-BowerbirdLlmProfile -Profile @($script:BowerbirdLlmProfileAliases.Keys)[0]) -eq 'AiEndpoint') 'Deprecated profile name maps to AiEndpoint'
  $threw=$false;try{$null=ConvertTo-BowerbirdLlmProfile -Profile 'Nope'}catch{$threw=$true}
  Assert $threw 'Unknown profile rejected'
  $cfg=Get-BowerbirdLlmConfig -Profile Auto
  Assert ($cfg.Profile -eq 'AiEndpoint' -and $cfg.Url -eq '') 'No endpoint URL built in'
  $msg='';try{$null=Invoke-BowerbirdChat -Messages @(@{role='user';content='x'})}catch{$msg=$_.Exception.Message}
  Assert ($msg -match 'BOWERBIRD_AI_ENDPOINT_URL') 'Missing endpoint URL explained'
  $env:BOWERBIRD_GROK_URL='https://databricks.example.org/serving-endpoints/x/invocations/'
  Assert ((Get-BowerbirdLlmConfig -Profile Grok).Url -eq 'https://databricks.example.org/serving-endpoints/x/invocations') 'Grok URL read from configuration'
  Write-Host 'PASS: Lazarette item names, token variables, profile names and endpoint configuration' -ForegroundColor Green
 }finally{foreach($n in $itemVars){[Environment]::SetEnvironmentVariable($n,$savedVars[$n])}}
}catch{Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
