# Pass 1 - Fast filename + metadata analysis (no network)
#requires -Version 5.1
function Invoke-BowerbirdPass1 {
 [CmdletBinding()]param([Parameter(Mandatory)][System.IO.FileInfo]$File,[pscustomobject]$Metadata)
 if(-not $Metadata){$Metadata=Get-BowerbirdImageMetadata -File $File}
 $name=[IO.Path]::GetFileNameWithoutExtension($File.Name);$ext=$File.Extension.ToLowerInvariant()
 $confidence=0.0;$suggested=$null;$reasoning=@();$datePart=$null;$descPart=$null
 if($name -match '(?i)(?:screenshot|screen\s*shot|capture|desktop)[_\s-]*(\d{4})[-_]?(\d{2})[-_]?(\d{2})[_\s-T]?(\d{2})[-_]?(\d{2})[-_]?(\d{2})?'){
  $datePart='{0}-{1}-{2}' -f $Matches[1],$Matches[2],$Matches[3]
  $timePart=if($Matches[6]){'{0}{1}{2}' -f $Matches[4],$Matches[5],$Matches[6]}else{'{0}{1}' -f $Matches[4],$Matches[5]}
  $descPart='Screenshot';$confidence=0.55;$reasoning+='Matched common screenshot filename pattern'
 }elseif($name -match '(?i)^(?:IMG|DSC|DSCN|PICT|Photo)[_-]?(\d+)$'){
  $descPart='Photo';$confidence=0.25;$reasoning+='Generic camera filename (IMG_/DSC_ style)'
 }elseif($name -match '(\d{4})[-_](\d{2})[-_](\d{2})'){
  $datePart='{0}-{1}-{2}' -f $Matches[1],$Matches[2],$Matches[3]
  $confidence=0.40;$reasoning+='Found ISO-like date in filename'
 }
 if($Metadata.DateTaken){
  $datePart=$Metadata.DateTaken.ToString('yyyy-MM-dd');$confidence=[Math]::Max($confidence,0.50);$reasoning+='Using DateTaken from metadata'
 }elseif($Metadata.CreationTime -and $Metadata.CreationTime.Year -gt 2005){
  if(-not $datePart){$datePart=$Metadata.CreationTime.ToString('yyyy-MM-dd');$confidence=[Math]::Max($confidence,0.30);$reasoning+='Fell back to file CreationTime'}
 }
 if($Metadata.Width -and $Metadata.Height){
  $reasoning+=("Dimensions {0}x{1}" -f $Metadata.Width,$Metadata.Height)
  if($Metadata.Width -ge 1920 -or $Metadata.Height -ge 1080){
   if(-not $descPart){$descPart='Screenshot'};$confidence=[Math]::Min(0.70,$confidence+0.10)
  }
 }
 if($Metadata.CameraModel){
  $reasoning+="Camera: $($Metadata.CameraModel)"
  if(-not $descPart){$descPart='Photo'};$confidence=[Math]::Min(0.75,$confidence+0.15)
 }
 if($datePart -or $descPart){
  $parts=@();if($datePart){$parts+=$datePart};if($descPart){$parts+=$descPart}
  if($name -match '(\d{4,})'){$parts+=$Matches[1]}
  $suggested=($parts -join '_')+$ext
 }
 if($confidence -gt 0.70){$confidence=0.70}
 return [pscustomobject]@{Confidence=[double]$confidence;SuggestedName=$suggested;Reasoning=($reasoning -join '; ');Source='filename+metadata';DatePart=$datePart;DescPart=$descPart;Metadata=$Metadata;NeedsVision=($confidence -lt 0.65)}
}
