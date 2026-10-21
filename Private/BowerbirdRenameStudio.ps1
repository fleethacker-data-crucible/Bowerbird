#requires -Version 5.1
# Smart screenshot rename proposals. Vision is expressly opt-in and never runs during ordinary indexing.
function New-BowerbirdSmartRenamePlan {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$Folder,
  [switch]$Recurse,[switch]$UseVision,
  [ValidateRange(0,100)][int]$MaxVision=10,
  [ValidateRange(1,10000)][int]$MaxImages=500
 )
 $extensions=@('.png','.jpg','.jpeg','.gif','.bmp','.webp','.tif','.tiff')
 $args=@{LiteralPath=$Folder;File=$true;ErrorAction='SilentlyContinue'}
 if($Recurse){$args.Recurse=$true}
 $reserved=@{}
 $ops=New-Object Collections.Generic.List[object]
 $skipped=New-Object Collections.Generic.List[object]
 $visionCount=0
 foreach($file in (Get-ChildItem @args | Where-Object {$extensions -contains $_.Extension.ToLowerInvariant()} | Select-Object -First $MaxImages)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Test-BowerbirdReparseAncestor $file.FullName)){
   $skipped.Add(@{Source=$file.FullName;Reason='Reparse point in source path'});continue
  }
  try{
   $meta=Get-BowerbirdImageMetadata -File $file
   $analysis=Invoke-BowerbirdPass1 -File $file -Metadata $meta
   if($UseVision -and $visionCount -lt $MaxVision -and $analysis.NeedsVision){
    $analysis=Invoke-BowerbirdPass2 -File $file -Pass1Result $analysis
    $visionCount++
   }
   $candidate=New-BowerbirdFileName -Analysis $analysis -File $file -ExistingNames @($reserved.Keys)
   $to=[string]$candidate.FullProposed
   if($to -ieq $file.FullName){$skipped.Add(@{Source=$file.FullName;Reason='Name already appropriate'});continue}
   if($reserved.ContainsKey($to.ToLowerInvariant()) -or (Test-Path -LiteralPath $to)){
    $skipped.Add(@{Source=$file.FullName;Reason='Target name already taken'});continue
   }
   $reserved[$to.ToLowerInvariant()]=$true
   $ops.Add([pscustomobject]@{
    Source=$file.FullName;Destination=$to;SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    Size=$file.Length;Status='Proposed';Confidence=$analysis.Confidence
    Reason="Smart rename: $($analysis.Source) / $($analysis.Reasoning)"
   })
  }catch{$skipped.Add(@{Source=$file.FullName;Reason=$_.Exception.Message})}
 }
 return [pscustomobject]@{
  SchemaVersion=2;Id=[guid]::NewGuid().ToString('N');Mode='Rename'
  CreatedUtc=[DateTime]::UtcNow.ToString('o')
  VisionRequests=$visionCount;Operations=@($ops.ToArray());Skipped=@($skipped.ToArray())
 }
}