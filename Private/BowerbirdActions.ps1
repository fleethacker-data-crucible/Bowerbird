#requires -Version 5.1
# Transactional, non-destructive file-move plans with recoverable per-operation journals.
function Write-BowerbirdJournal {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Journal)
 $folder=Split-Path -Parent $Path
 if($folder -and -not (Test-Path -LiteralPath $folder)){New-Item -ItemType Directory -Path $folder -Force|Out-Null}
 $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $json=ConvertTo-Json -InputObject $Journal -Depth 12
 [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding $false))
 try{
  if(Test-Path -LiteralPath $Path){
   $backup=$Path+'.previous'
   [IO.File]::Replace($temp,$Path,$backup)
  }else{[IO.File]::Move($temp,$Path)}
 }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force}}
}
function Test-BowerbirdReparseAncestor {
 [CmdletBinding()]param([string]$Path)
 $directory=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path))
 while($directory){
  if(Test-Path -LiteralPath $directory){
   $item=Get-Item -LiteralPath $directory -Force -ErrorAction Stop
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){return $true}
  }
  $next=[IO.Path]::GetDirectoryName($directory)
  if(-not $next -or $next -eq $directory){break}
  $directory=$next
 }
 return $false
}
function New-BowerbirdPlan {
 [CmdletBinding()]param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$RulesPath,[Parameter(Mandatory)][string]$DestinationRoot)
 $rules=@(Get-Content -LiteralPath $RulesPath -Raw | ConvertFrom-Json)
 $root=[IO.Path]::GetFullPath($DestinationRoot)
 $prefix=$root.TrimEnd([char]'\',[char]'/')+[IO.Path]::DirectorySeparatorChar
 $operations=New-Object Collections.Generic.List[object]
 $skipped=New-Object Collections.Generic.List[object]
 $reserved=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 foreach($file in $Index.Files){
  foreach($rule in $rules){
   $matches=$true
   if($null -ne $rule.Extension -and @($rule.Extension).Count -gt 0 -and $file.Extension -notin @($rule.Extension)){$matches=$false}
   if($rule.NamePattern -and $file.Name -notmatch [string]$rule.NamePattern){$matches=$false}
   if($rule.Contains -and ($file.Name+' '+$file.Text).IndexOf([string]$rule.Contains,[StringComparison]::OrdinalIgnoreCase) -lt 0){$matches=$false}
   if($null -ne $rule.MinBytes -and [long]$file.Size -lt [long]$rule.MinBytes){$matches=$false}
   if($null -ne $rule.MaxBytes -and [long]$file.Size -gt [long]$rule.MaxBytes){$matches=$false}
   if(-not $matches){continue}
   $sub=[string]$rule.Folder
   if([string]::IsNullOrWhiteSpace($sub) -or [IO.Path]::IsPathRooted($sub) -or $sub -match '(^|[\\/])\.\.([\\/]|$)' -or $sub -match '[:*?"<>|]'){throw "Unsafe rule folder: $sub"}
   $destination=[IO.Path]::GetFullPath((Join-Path (Join-Path $root $sub) $file.Name))
   if(-not $destination.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Destination escapes approved root'}
   if($destination -ieq $file.Path){break}
   if((Test-Path -LiteralPath $destination) -or -not $reserved.Add($destination)){
    $skipped.Add([pscustomobject]@{Source=$file.Path;Reason="Destination already exists or was reserved: $destination"})
    break
   }
   $operations.Add([pscustomobject]@{Source=$file.Path;Destination=$destination;Reason="Rule: $($rule.Name)";Status='Proposed';SHA256=$file.SHA256;Size=$file.Size})
   break
  }
 }
 return [pscustomobject]@{SchemaVersion=2;Id=[guid]::NewGuid().ToString('N');DestinationRoot=$root;CreatedUtc=[DateTime]::UtcNow.ToString('o');Operations=@($operations.ToArray());Skipped=@($skipped.ToArray())}
}
function Invoke-BowerbirdPlan {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
 param([Parameter(Mandatory)]$Plan,[Parameter(Mandatory)][string]$JournalPath,[switch]$Apply)
 if(-not $Apply){
  return @($Plan.Operations|ForEach-Object {[pscustomobject]@{Source=$_.Source;Destination=$_.Destination;Status='Preview';Error=''}})
 }
 if((Test-Path -LiteralPath $JournalPath) -and (Test-Path -LiteralPath $JournalPath -PathType Leaf)){
  # Preserve history under a unique path rather than silently losing undo data.
  $history=Join-Path (Split-Path -Parent $JournalPath) 'history'
  if(-not (Test-Path -LiteralPath $history)){New-Item -ItemType Directory -Path $history -Force|Out-Null}
  $archive=Join-Path $history ('journal-'+[guid]::NewGuid().ToString('N')+'.json')
  Copy-Item -LiteralPath $JournalPath -Destination $archive -ErrorAction Stop
 }
 $entries=New-Object Collections.Generic.List[object]
 foreach($op in $Plan.Operations){
  $entries.Add([pscustomobject]@{
   Source=[string]$op.Source;Destination=[string]$op.Destination
   SHA256=[string]$op.SHA256;At='';Status='NotStarted';Error=''
  })
 }
 $journal=[pscustomobject]@{SchemaVersion=2;Id=if($Plan.Id){$Plan.Id}else{[guid]::NewGuid().ToString('N')};CreatedUtc=[DateTime]::UtcNow.ToString('o');Entries=@($entries.ToArray())}
 Write-BowerbirdJournal -Path $JournalPath -Journal $journal
 for($i=0;$i -lt $journal.Entries.Count;$i++){
  $entry=$journal.Entries[$i]
  if(-not $PSCmdlet.ShouldProcess($entry.Source,"Move to $($entry.Destination)")){
   $entry.Status='Skipped';Write-BowerbirdJournal -Path $JournalPath -Journal $journal;continue
  }
  try{
   if(-not (Test-Path -LiteralPath $entry.Source -PathType Leaf)){throw 'Source no longer exists'}
   if(Test-Path -LiteralPath $entry.Destination){throw 'Destination already exists'}
   if(Test-BowerbirdReparseAncestor -Path $entry.Destination){throw 'Destination contains a reparse point'}
   if(Test-BowerbirdReparseAncestor -Path $entry.Source){throw 'Source contains a reparse point'}
   if($entry.SHA256 -and (Get-FileHash -LiteralPath $entry.Source -Algorithm SHA256 -ErrorAction Stop).Hash -cne $entry.SHA256){throw 'Source changed since index'}
   $entry.Status='Prepared';$entry.At=[DateTime]::UtcNow.ToString('o')
   Write-BowerbirdJournal -Path $JournalPath -Journal $journal
   $parent=Split-Path -Parent $entry.Destination
   if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
   if(Test-Path -LiteralPath $entry.Destination){throw 'Destination appeared before move'}
   Move-Item -LiteralPath $entry.Source -Destination $entry.Destination -ErrorAction Stop
   $entry.Status='Applied'
  }catch{$entry.Status='Failed';$entry.Error=$_.Exception.Message}
  Write-BowerbirdJournal -Path $JournalPath -Journal $journal
 }
 return @($journal.Entries)
}
function Undo-BowerbirdPlan {
 [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
 param([Parameter(Mandatory)][string]$JournalPath)
 $raw=Get-Content -LiteralPath $JournalPath -Raw|ConvertFrom-Json
 $entries=if($null -ne $raw.Entries){@($raw.Entries)}else{@($raw)}
 $restored=New-Object Collections.Generic.List[object]
 for($i=$entries.Count-1;$i -ge 0;$i--){
  $entry=$entries[$i]
  if($entry.Status -notin @('Applied','Prepared')){continue}
  $source=[string]$entry.Source;$dest=[string]$entry.Destination
  try{
   if(-not (Test-Path -LiteralPath $dest -PathType Leaf)){throw 'Destination missing; cannot restore'}
   if(Test-Path -LiteralPath $source){throw 'Original path occupied; refusing overwrite'}
   if((Test-BowerbirdReparseAncestor $source) -or (Test-BowerbirdReparseAncestor $dest)){throw 'Reparse-point ancestor detected'}
   if($entry.SHA256 -and (Get-FileHash -LiteralPath $dest -Algorithm SHA256 -ErrorAction Stop).Hash -cne $entry.SHA256){throw 'Destination modified; refusing unsafe undo'}
   if($PSCmdlet.ShouldProcess($dest,"Restore to $source")){
    $parent=Split-Path -Parent $source;if(-not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
    Move-Item -LiteralPath $dest -Destination $source -ErrorAction Stop
    $entry.Status='Undone';$entry.Error=''
    $restored.Add([pscustomobject]@{Restored=$source})
   }
  }catch{$entry.Error=$_.Exception.Message;Write-Warning "Undo skipped $dest : $($_.Exception.Message)"}
  if($null -ne $raw.Entries){$raw.Entries=$entries;Write-BowerbirdJournal -Path $JournalPath -Journal $raw}
 }
 return @($restored.ToArray())
}