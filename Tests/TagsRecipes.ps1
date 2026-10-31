#requires -Version 5.1
<#
 File tags and cleanup recipes on synthetic files in a disposable folder. Recipes are checked as plans first
 (nothing moves), then applied through the same journal as Organize and undone. Nothing is ever deleted.
 Run: powershell.exe -NoProfile -File .\Tests\TagsRecipes.ps1
#>
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $root 'Private\BowerbirdAdvanced.ps1')
. (Join-Path $root 'Private\BowerbirdActions.ps1')
. (Join-Path $root 'Private\BowerbirdTags.ps1')
. (Join-Path $root 'Private\BowerbirdRecipes.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdTagsRecipes_'+[guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function Expect-Throw([scriptblock]$Block,[string]$Pattern){
 $message='';try{$null=& $Block}catch{$message=$_.Exception.Message}
 return [bool]($message -match $Pattern)
}
try{
 $space=Join-Path $work 'space';New-Item -ItemType Directory -Path $space -Force|Out-Null
 $now=[DateTime]::UtcNow
 function Put([string]$Relative,[string]$Text,[int]$AgeDays=0){
  $path=Join-Path $space $Relative
  New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force|Out-Null
  [IO.File]::WriteAllText($path,$Text)
  [IO.File]::SetLastWriteTimeUtc($path,$now.AddDays(-$AgeDays))
  return $path
 }
 # Synthetic files: three identical copies (oldest first), one unique file, two screenshots, one photo.
 $oldCopy=Put 'x\report.txt' 'same bytes for the duplicate test' 400
 $midCopy=Put 'y\report.txt' 'same bytes for the duplicate test' 200
 $newCopy=Put 'z\other.txt' 'same bytes for the duplicate test' 10
 $unique=Put 'notes.txt' 'only one of me' 5
 $oldShot=Put 'shots\Screenshot 2025-01-03.png' 'pretend png' 500
 $newShot=Put 'shots\Screenshot 2026-10-29.png' 'pretend png newer' 2
 $photo=Put 'photos\holiday.png' 'a photo, not a screenshot' 900
 $invoice1=Put 'inbox\invoice-a.txt' 'invoice text a' 3
 $invoice2=Put 'inbox\invoice-b.txt' 'invoice text b' 3
 $tagsPath=Join-Path $work 'tags\studio-tags.json'
 $indexPath=Join-Path $work 'tags\studio-index.json'

 # --- Tags ---
 Assert ((ConvertTo-BowerbirdTag ' Invoices-2026 ') -ceq 'invoices-2026') 'Tags are trimmed and lowercased'
 foreach($bad in @('Bad Tag!','','-lead','a/b','..',('x'*33))){
  Assert (Expect-Throw {ConvertTo-BowerbirdTag $bad} 'Tags are 1-32') "Rejects tag '$bad'"
 }
 $result=Add-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice1 -Tag 'Finance'
 Assert ((@($result) -join ',') -ceq 'finance') 'Adding a tag returns the file tags'
 $null=Add-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice1 -Tag 'finance'
 $result=Add-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice1 -Tag 'q4'
 Assert ((@($result) -join ',') -ceq 'finance,q4') 'Adding the same tag twice changes nothing; tags stay sorted'
 $upper=$invoice1.ToUpperInvariant()
 $null=Add-BowerbirdTag -TagsPath $tagsPath -FilePath $upper -Tag 'archive-me'
 Assert (@((Read-BowerbirdTags -Path $tagsPath)[$invoice1]) -contains 'archive-me') 'Paths are matched case-insensitively'
 Assert (Expect-Throw {Add-BowerbirdTag -TagsPath $tagsPath -FilePath (Join-Path $space 'missing.txt') -Tag 'x'} 'existing file') 'Only existing files can be tagged'
 $null=Add-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice2 -Tag 'finance'
 Assert (@(Get-BowerbirdTaggedFiles -TagsPath $tagsPath -Tag 'finance').Count -eq 2) 'Tag filter finds both files'
 Assert (@(Get-BowerbirdTaggedFiles -TagsPath $tagsPath).Count -eq 2) 'Listing without a tag returns every tagged file'
 $left=Remove-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice1 -Tag 'q4'
 Assert ((@($left) -join ',') -ceq 'archive-me,finance') 'Remove takes one tag off'
 $null=Remove-BowerbirdTag -TagsPath $tagsPath -FilePath $invoice2 -Tag 'finance'
 Assert (-not ((Read-BowerbirdTags -Path $tagsPath).ContainsKey($invoice2))) 'A file with no tags left is dropped from the store'
 Assert (@(Remove-BowerbirdTag -TagsPath $tagsPath -FilePath $unique -Tag 'nothing').Count -eq 0) 'Removing an unknown tag is a no-op'
 Assert ((Get-Content -LiteralPath $tagsPath -Raw|ConvertFrom-Json).SchemaVersion -eq 1) 'Tags file is versioned JSON'
 Assert (Test-Path -LiteralPath $tagsPath) 'Tags are stored beside the index'
 Assert ((Get-BowerbirdTagsPath $indexPath) -eq (Join-Path (Split-Path -Parent $indexPath) 'studio-tags.json')) 'Tags path follows the index folder'
 Assert ((Get-Content -LiteralPath $invoice1 -Raw) -eq 'invoice text a') 'Tagging never changes the file'
 Pass 'File tags: rules, normalising, case-insensitive paths, filter, remove, versioned store'

 # --- Recipes: catalog and checks ---
 $catalog=Get-BowerbirdRecipeCatalog
 Assert (@($catalog.recipes).Count -eq 3 -and $catalog.schema -ceq 'bowerbird.recipes/1') 'Catalog lists three recipes'
 Assert (Expect-Throw {New-BowerbirdRecipePlan -Name 'delete-everything' -Index ([pscustomobject]@{Files=@()}) -DestinationRoot $space} 'Unknown recipe') 'Unknown recipe is refused'
 Assert (Expect-Throw {New-BowerbirdRecipePlan -Name 'tagged' -Index ([pscustomobject]@{Files=@()}) -DestinationRoot $space -TagsPath $tagsPath} 'needs -Tag') 'Tagged recipe needs a tag'

 # Build the index the way Studio does, through the saved file, so timestamps come back as the app sees them.
 $index=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent
 $null=Save-BowerbirdIndexFile -Path $indexPath -Index $index
 $index=Read-BowerbirdIndexFile -Path $indexPath
 $destination=Join-Path $work 'dest'

 # --- duplicate-copies ---
 $plan=New-BowerbirdRecipePlan -Name 'duplicate-copies' -Index $index -DestinationRoot $destination
 $sources=@($plan.Operations|ForEach-Object {$_.Source})
 Assert ($plan.Recipe -eq 'duplicate-copies' -and $plan.Operations.Count -eq 2) ('Two older copies proposed, the oldest kept: '+$plan.Operations.Count)
 Assert (-not ($sources -contains $oldCopy) -and ($sources -contains $midCopy) -and ($sources -contains $newCopy)) 'The oldest copy is never proposed to move'
 Assert (-not ($sources -contains $unique)) 'A file with no duplicate is not proposed'
 $hash=(Get-FileHash -LiteralPath $oldCopy -Algorithm SHA256).Hash
 $folder=Join-Path $destination ('Duplicates\'+$hash.Substring(0,12))
 Assert (@($plan.Operations|Where-Object {$_.Destination.StartsWith($folder,[StringComparison]::OrdinalIgnoreCase)}).Count -eq 2) 'Copies go to Duplicates\<hash12>'
 Assert ((@($plan.Operations|ForEach-Object {$_.Status}|Select-Object -Unique) -join ',') -ceq 'Proposed') 'Every operation is only proposed'
 Assert (Test-Path -LiteralPath $midCopy) 'Planning moves nothing'
 Pass 'duplicate-copies proposes moves for every copy but the oldest, grouped by hash'

 # Same name in two places: the second is skipped, never overwritten.
 $collideSpace=Join-Path $work 'collide';New-Item -ItemType Directory -Path $collideSpace|Out-Null
 foreach($p in 'a\same.txt','b\same.txt','c\same.txt'){New-Item -ItemType Directory -Path (Split-Path -Parent (Join-Path $collideSpace $p)) -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $collideSpace $p),'collide bytes')}
 [IO.File]::SetLastWriteTimeUtc((Join-Path $collideSpace 'a\same.txt'),$now.AddDays(-30))
 $cIndex=New-BowerbirdSmartIndex -Path $collideSpace -Recurse -IncludeContent
 $cPlan=New-BowerbirdRecipePlan -Name 'duplicate-copies' -Index $cIndex -DestinationRoot (Join-Path $work 'cdest')
 Assert ($cPlan.Operations.Count -eq 1 -and $cPlan.Skipped.Count -eq 1) ('Name clash is skipped, not overwritten: ops='+$cPlan.Operations.Count+' skipped='+$cPlan.Skipped.Count)
 Pass 'duplicate-copies skips a name clash instead of overwriting'

 # --- old-screenshots ---
 $shots=New-BowerbirdRecipePlan -Name 'old-screenshots' -Index $index -DestinationRoot $destination -Days 30 -Now $now
 $shotSources=@($shots.Operations|ForEach-Object {$_.Source})
 Assert ($shots.Operations.Count -eq 1 -and $shotSources[0] -eq $oldShot) ('Only the old screenshot is proposed: '+$shots.Operations.Count)
 Assert ($shots.Operations[0].Destination -eq (Join-Path $destination 'Archive\Screenshots\Screenshot 2025-01-03.png')) 'Screenshots go to Archive\Screenshots'
 Assert (-not ($shotSources -contains $photo) -and -not ($shotSources -contains $newShot)) 'A photo and a recent screenshot are left alone'
 $none=New-BowerbirdRecipePlan -Name 'old-screenshots' -Index $index -DestinationRoot $destination -Days 36500 -Now $now
 Assert ($none.Operations.Count -eq 0) 'A long age window proposes nothing'
 Assert (Expect-Throw {New-BowerbirdRecipePlan -Name 'old-screenshots' -Index $index -DestinationRoot $destination -Days 0} 'Days') 'Zero days is refused'
 Pass 'old-screenshots proposes only old image files named like screenshots'

 # --- tagged ---
 $tagged=New-BowerbirdRecipePlan -Name 'tagged' -Index $index -DestinationRoot $destination -TagsPath $tagsPath -Tag 'Archive-Me'
 Assert ($tagged.Operations.Count -eq 1 -and $tagged.Operations[0].Source -eq $invoice1) 'Tagged recipe proposes the file carrying the tag'
 Assert ($tagged.Operations[0].Destination -eq (Join-Path $destination 'archive-me\invoice-a.txt')) 'Tagged files go to a folder named after the tag'
 Assert (Expect-Throw {New-BowerbirdRecipePlan -Name 'tagged' -Index $index -DestinationRoot $destination -TagsPath $tagsPath -Tag '..\escape'} 'Tags are 1-32') 'A traversal tag is refused before any folder is built'
 Pass 'tagged recipe moves files with the tag into a tag-named folder'

 # --- Apply and undo: the same journal as Organize; nothing is deleted ---
 # Files and bytes under the source and the destination together: a move keeps both, a delete would not.
 function Measure-Tree{ $files=@(Get-ChildItem -LiteralPath $space,(Join-Path $work 'dest') -Recurse -File -ErrorAction SilentlyContinue); return @($files.Count,($files|Measure-Object -Property Length -Sum).Sum) }
 $beforeTree=Measure-Tree
 $journal=Join-Path $work 'journal.json'
 $applied=@(Invoke-BowerbirdPlan -Plan $plan -JournalPath $journal -Apply -Confirm:$false)
 Assert (@($applied|Where-Object {$_.Status -eq 'Applied'}).Count -eq 2) 'Both duplicate copies move'
 Assert (Test-Path -LiteralPath $oldCopy) 'The kept copy is still in place'
 $afterTree=Measure-Tree
 Assert ($afterTree[0] -eq $beforeTree[0] -and $afterTree[1] -eq $beforeTree[1]) 'File count and bytes are unchanged by the move (nothing deleted)'
 $restored=@(Undo-BowerbirdPlan -JournalPath $journal -Confirm:$false)
 Assert ($restored.Count -eq 2 -and (Test-Path -LiteralPath $midCopy) -and (Test-Path -LiteralPath $newCopy)) 'Undo puts the copies back'
 Assert (@(Get-ChildItem -LiteralPath (Join-Path $destination 'Duplicates') -Recurse -File -ErrorAction SilentlyContinue).Count -eq 0) 'Undo leaves no files in the copy folders (empty folders stay, as with Organize)'
 Pass 'Applying a recipe uses the journal, keeps every byte, and undo restores it'

 # --- Plans round-trip through the same plan schema Apply reads ---
 $json=ConvertTo-Json -InputObject $plan -Depth 6|ConvertFrom-Json
 Assert ($json.Operations.Count -eq 2 -and $json.Operations[0].SHA256) 'A recipe plan survives JSON with the fields Apply needs'
 Pass 'Recipe plans use the same schema as Organize plans'
 Write-Host ("PASS: Bowerbird tags and cleanup recipes ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
