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
 $debugRules=@(Get-Content -LiteralPath $rulesPath -Raw|ConvertFrom-Json)
 Write-Host ('RULES DEBUG: '+(ConvertTo-Json -InputObject $debugRules -Depth 5 -Compress))
 Write-Host ('INDEX DEBUG: '+((@($index.Files)|ForEach-Object {$_.Name+':'+$_.Extension}) -join ', '))
 foreach($debugRule in $debugRules){
  Write-Host ("RULE TEST: Name=$($debugRule.Name) Ext=$($debugRule.Extension -join ',') Min=$($debugRule.MinBytes) Max=$($debugRule.MaxBytes)")
 }
 foreach($df in $index.Files){
  $dr=$debugRules[0]
  Write-Host ("CHECK: file=$($df.Name) ext=$($df.Extension) ext-mismatch=$($null -ne $dr.Extension -and @($dr.Extension).Count -gt 0 -and $df.Extension -notin @($dr.Extension)) pattern=$([bool]$dr.NamePattern) contains=$([bool]$dr.Contains) minexists=$($null -ne $dr.MinBytes) maxexists=$($null -ne $dr.MaxBytes)")
 }
 $plan=New-BowerbirdPlan -Index $index -RulesPath $rulesPath -DestinationRoot $dest
 Write-Host ('PLAN DEBUG: '+($plan|ConvertTo-Json -Depth 6 -Compress))
 Assert ($plan.Operations.Count -eq 3) 'Plan count'
 $journal=Join-Path $temp 'journal.json'
 $applied=@(Invoke-BowerbirdPlan -Plan $plan -JournalPath $journal -Apply -Confirm:$false)
 Assert (@($applied|Where-Object {$_.Status -eq 'Applied'}).Count -eq 3) 'Applied statuses'
 Assert ((Get-ChildItem (Join-Path $dest 'Text') -File).Count -eq 3) 'Moved files'
 $restored=@(Undo-BowerbirdPlan -JournalPath $journal -Confirm:$false)
 Assert ($restored.Count -eq 3) 'Undo count'
 Assert ((Get-ChildItem $source -File).Count -eq 3) 'Restored files'
 Write-Host 'PASS: Bowerbird intelligence, duplicate, search, plan, apply and undo smoke test' -ForegroundColor Green
}catch{Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red;exit 1}
finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
