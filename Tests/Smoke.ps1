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
 # Lazarette item names: BOWERBIRD_LAZARETTE_ITEM_* first, then BOWERBIRD_ARC_ITEM_*, then Halyard's names.
 . (Join-Path $root 'Private\LazaretteBridge.ps1')
 . (Join-Path $root 'Private\BowerbirdLlm.ps1')
 $itemVars=@('GENAI_TOKEN','LLM_TOKEN','BOWERBIRD_LAZARETTE_ITEM_GenAi','BOWERBIRD_ARC_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_GenAi','HALYARD_LAZARETTE_ITEM_Llm','CASCADE_ARC_ITEM_GenAi','CASCADE_ARC_ITEM_Llm')
 $savedVars=@{};foreach($n in $itemVars){$savedVars[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
 try{
  function Import-BowerbirdLazaretteSession {param([switch]$Quiet);return $true}
  function Get-BowerbirdLazaretteSecretByName {param([string]$ServiceName);return ('secret-for-'+$ServiceName)}
  $cases=@(
   @{Set=@{};Want='genapi'},
   @{Set=@{CASCADE_ARC_ITEM_Llm='c-llm'};Want='c-llm'},
   @{Set=@{CASCADE_ARC_ITEM_GenAi='c-gen';HALYARD_LAZARETTE_ITEM_Llm='h-llm'};Want='h-llm'},
   @{Set=@{HALYARD_LAZARETTE_ITEM_GenAi='h-gen';BOWERBIRD_ARC_ITEM_GenAi='b-arc'};Want='b-arc'},
   @{Set=@{BOWERBIRD_ARC_ITEM_GenAi='b-arc';BOWERBIRD_LAZARETTE_ITEM_GenAi='b-laz'};Want='b-laz'}
  )
  foreach($case in $cases){
   foreach($n in $itemVars){[Environment]::SetEnvironmentVariable($n,$null)}
   foreach($k in $case.Set.Keys){[Environment]::SetEnvironmentVariable($k,$case.Set[$k])}
   $got=Get-BowerbirdLlmToken -ForProfile GenAi
   Assert ($got -eq ('secret-for-'+$case.Want)) ("Lazarette item order: expected $($case.Want), got $got")
  }
  Write-Host 'PASS: Lazarette item names (BOWERBIRD_LAZARETTE_ITEM_*, BOWERBIRD_ARC_ITEM_*, HALYARD_LAZARETTE_ITEM_*, CASCADE_ARC_ITEM_*)' -ForegroundColor Green
 }finally{foreach($n in $itemVars){[Environment]::SetEnvironmentVariable($n,$savedVars[$n])}}
}catch{Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
