# Safe rename + audit journal (supports undo)
#requires -Version 5.1
function Write-BowerbirdAuditEntry {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$LogPath,[Parameter(Mandatory)][pscustomobject]$Entry)
 $dir=Split-Path $LogPath -Parent
 if(-not (Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
 $list=@()
 if(Test-Path -LiteralPath $LogPath){
  try{$existing=Get-Content -LiteralPath $LogPath -Raw -ErrorAction Stop|ConvertFrom-Json;if($existing -is [array]){$list=@($existing)}elseif($existing){$list=@($existing)}}catch{}
 }
 $list+=$Entry
 $json=$list|ConvertTo-Json -Depth 6
 $utf8NoBom=New-Object System.Text.UTF8Encoding $false
 [IO.File]::WriteAllText($LogPath,$json,$utf8NoBom)
}
function Rename-BowerbirdFile {
 [CmdletBinding(SupportsShouldProcess=$true)]param([Parameter(Mandatory)][System.IO.FileInfo]$File,[Parameter(Mandatory)][pscustomobject]$Proposal,[string]$AuditLogPath,[switch]$Force)
 $oldFull=$File.FullName;$newFull=$Proposal.FullProposed;$newName=$Proposal.ProposedName
 if($oldFull -eq $newFull){return [pscustomobject]@{Success=$true;Skipped=$true;Message='Name unchanged'}}
 if((Test-Path -LiteralPath $newFull) -and -not $Force){return [pscustomobject]@{Success=$false;Message="Target already exists: $newName"}}
 $entry=[pscustomobject]@{Timestamp=(Get-Date).ToString('o');OriginalPath=$oldFull;NewPath=$newFull;OriginalName=$File.Name;NewName=$newName;Confidence=$Proposal.Confidence;Source=$Proposal.Source;Reasoning=$Proposal.Reasoning;Applied=$false}
 if($PSCmdlet.ShouldProcess($oldFull,"Rename to $newName")){
  try{Rename-Item -LiteralPath $oldFull -NewName $newName -ErrorAction Stop;$entry.Applied=$true;if($AuditLogPath){Write-BowerbirdAuditEntry -LogPath $AuditLogPath -Entry $entry};return [pscustomobject]@{Success=$true;Skipped=$false;Message="Renamed → $newName";Entry=$entry}}
  catch{$entry.Error=$_.Exception.Message;if($AuditLogPath){Write-BowerbirdAuditEntry -LogPath $AuditLogPath -Entry $entry};return [pscustomobject]@{Success=$false;Message=$_.Exception.Message;Entry=$entry}}
 }else{
  if($AuditLogPath){$entry.Applied=$false;$entry.DryRun=$true;Write-BowerbirdAuditEntry -LogPath $AuditLogPath -Entry $entry}
  return [pscustomobject]@{Success=$true;Skipped=$false;DryRun=$true;Message="Would rename → $newName";Entry=$entry}
 }
}
function Undo-BowerbirdRename {
 [CmdletBinding(SupportsShouldProcess=$true)]param([Parameter(Mandatory)][string]$AuditLogPath,[switch]$LastRunOnly)
 if(-not (Test-Path -LiteralPath $AuditLogPath)){Write-Warning "No audit log at $AuditLogPath";return}
 $entries=Get-Content -LiteralPath $AuditLogPath -Raw|ConvertFrom-Json
 if(-not $entries){return}
 $entries=@($entries)|Where-Object {$_.Applied -eq $true}
 if($LastRunOnly -and $entries.Count -gt 0){
  $lastTs=($entries|Sort-Object Timestamp -Descending|Select-Object -First 1).Timestamp
  $entries=$entries|Where-Object {$_.Timestamp -like "$($lastTs.Substring(0,16))*"}
 }
 $undone=0
 foreach($e in ($entries|Sort-Object Timestamp -Descending)){
  if(-not (Test-Path -LiteralPath $e.NewPath)){continue}
  if(Test-Path -LiteralPath $e.OriginalPath){Write-Warning "Original path already exists, skip: $($e.OriginalName)";continue}
  if($PSCmdlet.ShouldProcess($e.NewPath,"Restore to $($e.OriginalName)")){
   try{Rename-Item -LiteralPath $e.NewPath -NewName $e.OriginalName -ErrorAction Stop;$undone++;Write-Host "Restored: $($e.NewName) → $($e.OriginalName)" -ForegroundColor Green}
   catch{Write-Warning "Undo failed for $($e.NewName): $($_.Exception.Message)"}
  }
 }
 Write-Host "Undo complete. Restored $undone file(s)." -ForegroundColor Cyan
}
