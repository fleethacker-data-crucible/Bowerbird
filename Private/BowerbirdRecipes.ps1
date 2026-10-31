#requires -Version 5.1
# Cleanup recipes: each one proposes a plan of moves from the saved index and never deletes anything.
# A recipe's plan goes through the same preview, APPLY confirmation, journal and undo as Organize.
# Duplicate copies move to <destination>\Duplicates\<first 12 hex of SHA-256>\ so each group stays together; the
# oldest copy stays where it is.

$script:BowerbirdRecipes=[ordered]@{
 'duplicate-copies'=@{Summary='Keep the oldest copy of each exact duplicate in place; move the other copies to Duplicates\<hash>'}
 'old-screenshots'=@{Summary='Move screenshots not modified for more than -Days days to Archive\Screenshots'}
 'tagged'=@{Summary='Move the files carrying -Tag into a folder named after the tag'}
}

function Get-BowerbirdRecipeCatalog {
 return [ordered]@{schema='bowerbird.recipes/1';recipes=@($script:BowerbirdRecipes.Keys|ForEach-Object {[pscustomobject]@{name=$_;summary=$script:BowerbirdRecipes[$_].Summary}})}
}

function Add-BowerbirdRecipeOperation {
 # One proposed move, checked like New-BowerbirdPlan: the folder must be a plain relative folder and the
 # destination must stay under the approved root. A name already taken (or reserved this run) is skipped, not overwritten.
 param($Operations,$Skipped,$Reserved,[string]$Root,[string]$Prefix,$Entry,[string]$Folder,[string]$Reason)
 if([string]::IsNullOrWhiteSpace($Folder) -or [IO.Path]::IsPathRooted($Folder) -or $Folder -match '(^|[\\/])\.\.([\\/]|$)' -or $Folder -match '[:*?"<>|]'){throw "Unsafe recipe folder: $Folder"}
 $destination=[IO.Path]::GetFullPath((Join-Path (Join-Path $Root $Folder) $Entry.Name))
 if(-not $destination.StartsWith($Prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escapes approved root'}
 if($destination -ieq $Entry.Path){return}
 if((Test-Path -LiteralPath $destination) -or -not $Reserved.Add($destination)){
  $Skipped.Add([pscustomobject]@{Source=$Entry.Path;Reason="Destination already exists or was reserved: $destination"})
  return
 }
 $Operations.Add([pscustomobject]@{Source=$Entry.Path;Destination=$destination;Reason=$Reason;Status='Proposed';SHA256=$Entry.SHA256;Size=$Entry.Size})
}

function New-BowerbirdRecipePlan {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$Name,
  [Parameter(Mandatory)]$Index,
  [Parameter(Mandatory)][string]$DestinationRoot,
  [string]$TagsPath,
  [string]$Tag,
  [ValidateRange(1,36500)][int]$Days=365,
  [datetime]$Now=[DateTime]::UtcNow
 )
 if(-not $script:BowerbirdRecipes.Contains($Name)){throw "Unknown recipe '$Name'. Use one of: $(@($script:BowerbirdRecipes.Keys) -join ', ')."}
 $root=[IO.Path]::GetFullPath($DestinationRoot)
 $prefix=$root.TrimEnd([char]'\',[char]'/')+[IO.Path]::DirectorySeparatorChar
 $operations=New-Object Collections.Generic.List[object]
 $skipped=New-Object Collections.Generic.List[object]
 $reserved=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 $files=@($Index.Files)
 switch($Name){
  'duplicate-copies' {
   $byPath=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
   foreach($f in $files){$byPath[[string]$f.Path]=$f}
   foreach($group in @(Find-BowerbirdDuplicates -Index $Index -Mode Exact)){
    # Oldest first; ties keep path order so the choice is repeatable.
    $members=@($group.Files|ForEach-Object {$byPath[[string]$_]}|Where-Object {$_}|Sort-Object @{Expression={ConvertTo-BowerbirdTicks $_.ModifiedUtc}},@{Expression={$_.Path}})
    if($members.Count -lt 2){continue}
    $hash=[string]$group.Key
    $folder='Duplicates\'+$hash.Substring(0,[Math]::Min(12,$hash.Length))
    foreach($copy in @($members|Select-Object -Skip 1)){
     Add-BowerbirdRecipeOperation -Operations $operations -Skipped $skipped -Reserved $reserved -Root $root -Prefix $prefix -Entry $copy -Folder $folder -Reason 'Recipe duplicate-copies: an older identical copy is kept'
    }
   }
  }
  'old-screenshots' {
   $cutoff=$Now.ToUniversalTime().AddDays(-$Days).Ticks
   $imageTypes=@('.png','.jpg','.jpeg','.bmp','.gif','.tif','.tiff')
   foreach($f in $files){
    $isShot=$imageTypes -contains ([string]$f.Extension).ToLowerInvariant() -and ([string]$f.Name -match '(?i)(screenshot|screen.?shot|snip|capture)')
    if($isShot -and (ConvertTo-BowerbirdTicks $f.ModifiedUtc) -ge 0 -and (ConvertTo-BowerbirdTicks $f.ModifiedUtc) -lt $cutoff){
     Add-BowerbirdRecipeOperation -Operations $operations -Skipped $skipped -Reserved $reserved -Root $root -Prefix $prefix -Entry $f -Folder 'Archive\Screenshots' -Reason "Recipe old-screenshots: not modified for more than $Days days"
    }
   }
  }
  'tagged' {
   if(-not $Tag){throw 'The tagged recipe needs -Tag'}
   $wanted=ConvertTo-BowerbirdTag $Tag
   if(-not $TagsPath){throw 'The tagged recipe needs the tags file'}
   $tagged=New-Object 'System.Collections.Generic.Dictionary[string,bool]' ([StringComparer]::OrdinalIgnoreCase)
   foreach($hit in @(Get-BowerbirdTaggedFiles -TagsPath $TagsPath -Tag $wanted)){$tagged[$hit.Path]=$true}
   foreach($f in $files){
    if($tagged.ContainsKey([string]$f.Path)){
     Add-BowerbirdRecipeOperation -Operations $operations -Skipped $skipped -Reserved $reserved -Root $root -Prefix $prefix -Entry $f -Folder $wanted -Reason "Recipe tagged: tag $wanted"
    }
   }
  }
 }
 return [pscustomobject]@{SchemaVersion=2;Id=[guid]::NewGuid().ToString('N');Recipe=$Name;DestinationRoot=$root;CreatedUtc=[DateTime]::UtcNow.ToString('o');Operations=@($operations.ToArray());Skipped=@($skipped.ToArray())}
}
