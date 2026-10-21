# Basic image metadata for Pass 1 (no external tools required)
#requires -Version 5.1
function Get-BowerbirdImageMetadata {
 [CmdletBinding()]param([Parameter(Mandatory)][System.IO.FileInfo]$File)
 $result=[ordered]@{FullName=$File.FullName;Name=$File.Name;Extension=$File.Extension.ToLowerInvariant();Length=$File.Length;CreationTime=$File.CreationTime;LastWriteTime=$File.LastWriteTime;Width=$null;Height=$null;DateTaken=$null;CameraModel=$null;IsImage=$false}
 $imageExts=@('.png','.jpg','.jpeg','.gif','.bmp','.webp','.tif','.tiff')
 if($imageExts -notcontains $result.Extension){return [pscustomobject]$result}
 $result.IsImage=$true
 try{
  Add-Type -AssemblyName System.Drawing -ErrorAction SilentlyContinue
  $img=[System.Drawing.Image]::FromFile($File.FullName)
  try{
   $result.Width=$img.Width;$result.Height=$img.Height
   foreach($prop in $img.PropertyItems){
    if($prop.Id -eq 0x9003 -or $prop.Id -eq 0x0132){
     $raw=[System.Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0)
     if($raw -match '^(\d{4}):(\d{2}):(\d{2})\s+(\d{2}):(\d{2}):(\d{2})'){
      try{$result.DateTaken=Get-Date -Year $Matches[1] -Month $Matches[2] -Day $Matches[3] -Hour $Matches[4] -Minute $Matches[5] -Second $Matches[6]}catch{}
     }
    }
    if($prop.Id -eq 0x0110){$result.CameraModel=[System.Text.Encoding]::ASCII.GetString($prop.Value).Trim([char]0)}
   }
  }finally{$img.Dispose()}
 }catch{Write-Verbose "System.Drawing metadata failed for $($File.Name): $($_.Exception.Message)"}
 if(-not $result.DateTaken){
  try{
   $shell=New-Object -ComObject Shell.Application
   $folder=$shell.NameSpace($File.DirectoryName);$item=$folder.ParseName($File.Name);$dt=$folder.GetDetailsOf($item,12)
   if($dt -and $dt -match '\d'){$parsed=$null;if([datetime]::TryParse($dt,[ref]$parsed)){$result.DateTaken=$parsed}}
  }catch{}
 }
 return [pscustomobject]$result
}
