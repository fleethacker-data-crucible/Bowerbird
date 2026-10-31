#requires -Version 5.1
[CmdletBinding()]param(
 [ValidateSet('Index','Search','Duplicates','VisualDuplicates','CodeStats','Plan','Apply','Undo')][string]$Action='Index',
 [string]$Path='.',[string]$IndexPath,[string]$Query,[string]$RulesPath,[string]$DestinationRoot,[string]$PlanPath,[string]$JournalPath,[switch]$Recurse,[switch]$ConfirmApply
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $PSScriptRoot 'Private\BowerbirdActions.ps1')
if(-not $IndexPath){$IndexPath=Join-Path $PSScriptRoot 'Data\index.json'}
if(-not $PlanPath){$PlanPath=Join-Path $PSScriptRoot 'Data\plan.json'}
if(-not $JournalPath){$JournalPath=Join-Path $PSScriptRoot 'Data\journal.json'}
switch($Action){
 'Index' {New-BowerbirdIndex -Path $Path -OutputPath $IndexPath -Recurse:$Recurse | Select-Object Root,IndexedUtc,@{N='FileCount';E={$_.Files.Count}}}
 'CodeStats' {Get-BowerbirdCodeStats -Path $Path -Recurse:$Recurse}
 'Undo' {Undo-BowerbirdPlan -JournalPath $JournalPath -Confirm:$false}
 'Apply' {if(-not $ConfirmApply){throw 'Apply requires -ConfirmApply'};$plan=Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json;Invoke-BowerbirdPlan -Plan $plan -JournalPath $JournalPath -Apply -Confirm:$false}
 default {
  $index=Read-BowerbirdIndexFile -Path $IndexPath
  switch($Action){
   'Search' {Search-BowerbirdIndex -Index $index -Query $Query}
   'Duplicates' {Find-BowerbirdDuplicates -Index $index}
   'VisualDuplicates' {Find-BowerbirdDuplicates -Index $index -Mode Visual}
   'Plan' {if(-not $RulesPath -or -not $DestinationRoot){throw 'Plan requires -RulesPath and -DestinationRoot'};$plan=New-BowerbirdPlan -Index $index -RulesPath $RulesPath -DestinationRoot $DestinationRoot;$parent=Split-Path -Parent $PlanPath;if(-not (Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$plan|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $PlanPath -Encoding UTF8;$plan}
  }
 }
}