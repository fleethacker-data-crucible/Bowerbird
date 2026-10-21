#requires -Version 5.1
function New-BowerbirdPlan {
 [CmdletBinding()] param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$RulesPath,[Parameter(Mandatory)][string]$DestinationRoot)
 $rules=@(Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json)
 $root=[IO.Path]::GetFullPath($DestinationRoot);$operations=New-Object Collections.Generic.List[object];$reserved=@{}
 foreach($file in $Index.Files){
  foreach($rule in $rules){
   $match=$true
   if($rule.Extension -and $file.Extension -notin @($rule.Extension)){$match=$false}
   if($rule.NamePattern -and $file.Name -notmatch $rule.NamePattern){$match=$false}
   if($rule.Contains -and ($file.Name+' '+$file.Text).IndexOf([string]$rule.Contains,[StringComparison]::OrdinalIgnoreCase) -lt 0){$match=$false}
   if(-not $match){continue}
   $sub=[string]$rule.Folder
   if([IO.Path]::IsPathRooted($sub) -or $sub -match '(^|[\\/])\.\.([\\/]|$)' -or $sub -match '[:*?"<>|]'){throw "Unsafe rule folder: $sub"}
   $destination=[IO.Path]::GetFullPath((Join-Path (Join-Path $root $sub) $file.Name))
   if(-not $destination.StartsWith(($root.TrimEnd([char]'\',[char]'/')+[IO.Path]::DirectorySeparatorChar),[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escapes approved root'}
   if($destination -ieq $file.Path){break}
   $key=$destination.ToLowerInvariant()
   if((Test-Path -LiteralPath $destination) -or $reserved.ContainsKey($key)){break}
   $reserved[$key]=$true
   $operations.Add([pscustomobject]@{Source=$file.Path;Destination=$destination;Reason="Rule: $($rule.Name)";Status='Proposed';SHA256=$file.SHA256});break
  }
 }
 return [pscustomobject]@{SchemaVersion=1;DestinationRoot=$root;CreatedUtc=[DateTime]::UtcNow.ToString('o');Operations=@($operations.ToArray())}
}
function Invoke-BowerbirdPlan {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')] param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$JournalPath,[switch]$Apply)
 $records=New-Object Collections.Generic.List[object]
 $journalDir=Split-Path -Parent $JournalPath;if($journalDir -and -not (Test-Path $journalDir)){New-Item -ItemType Directory -Path $journalDir -Force|Out-Null}
 foreach($op in $Plan.Operations){
  $entry=[ordered]@{At=[DateTime]::UtcNow.ToString('o');Source=$op.Source;Destination=$op.Destination;Status='Preview';Error=''}
  if($Apply -and $PSCmdlet.ShouldProcess($op.Source,"Move to $($op.Destination)")){
   try{
    if(-not (Test-Path -LiteralPath $op.Source -PathType Leaf)){throw 'Source missing'}
    if(Test-Path -LiteralPath $op.Destination){throw 'Destination exists'}
    if($op.SHA256 -and (Get-FileHash -LiteralPath $op.Source -Algorithm SHA256).Hash -ne $op.SHA256){throw 'Source changed since index'}
    $entry.Status='Pending';$records.Add([pscustomobject]$entry)
    [IO.File]::WriteAllText($JournalPath,(@($records.ToArray())|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding $false))
    $destDir=Split-Path -Parent $op.Destination;if(-not (Test-Path $destDir)){New-Item -ItemType Directory -Path $destDir -Force|Out-Null}
    Move-Item -LiteralPath $op.Source -Destination $op.Destination -ErrorAction Stop
    $entry.Status='Applied'
   }catch{$entry.Status='Failed';$entry.Error=$_.Exception.Message}
  }
  if($entry.Status -ne 'Pending'){$records.Add([pscustomobject]$entry)}
  [IO.File]::WriteAllText($JournalPath,(@($records.ToArray())|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding $false))
 }
 return @($records.ToArray())
}
function Undo-BowerbirdPlan {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')] param([Parameter(Mandatory)][string]$JournalPath)
 $entries=@(Get-Content -LiteralPath $JournalPath -Raw | ConvertFrom-Json)
 [array]::Reverse($entries)
 foreach($entry in $entries){
  if($entry.Status -ne 'Applied'){continue}
  if((Test-Path -LiteralPath $entry.Destination -PathType Leaf) -and -not (Test-Path -LiteralPath $entry.Source)){
   if($PSCmdlet.ShouldProcess($entry.Destination,"Restore to $($entry.Source)")){Move-Item -LiteralPath $entry.Destination -Destination $entry.Source -ErrorAction Stop;[pscustomobject]@{Restored=$entry.Source}}
  }else{Write-Warning "Cannot safely restore $($entry.Destination): source occupied or destination missing"}
 }
}
