# Main orchestration - two-pass image organizer
#requires -Version 5.1
function Invoke-BowerbirdOrganize {
 [CmdletBinding(SupportsShouldProcess=$true)]param(
  [Parameter(Mandatory)][string]$Path,
  [ValidateSet('Auto','Grok','GenAi')][string]$Profile='Auto',
  [double]$Pass1Threshold=0.65,[int]$MaxVision=25,[switch]$Apply,[switch]$Recurse,[string]$Root
 )
 if(-not $Root){$Root=$PSScriptRoot;if(-not $Root){$Root=Get-Location}}
 if((Split-Path $Root -Leaf) -eq 'Public'){$Root=Split-Path $Root -Parent}
 if(-not (Test-Path -LiteralPath $Path)){throw "Path not found: $Path"}
 $target=Get-Item -LiteralPath $Path
 if(-not $target.PSIsContainer){throw "Path must be a folder: $Path"}
 $imageExts=@('.png','.jpg','.jpeg','.gif','.bmp','.webp','.tif','.tiff')
 $gciParams=@{LiteralPath=$target.FullName;File=$true;ErrorAction='SilentlyContinue'}
 if($Recurse){$gciParams.Recurse=$true}
 $files=Get-ChildItem @gciParams|Where-Object {$imageExts -contains $_.Extension.ToLowerInvariant()}
 $total=@($files).Count
 Write-BowerbirdLog -Level INFO -Message "Found $total image(s) under $($target.FullName)" -Root $Root
 if($total -eq 0){Write-Host 'No images found.' -ForegroundColor Yellow;return}
 $stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$auditPath=Join-Path $Root "Logs\bowerbird-audit_$stamp.json"
 $proposals=@();$visionUsed=0;$existingNames=@($files|ForEach-Object {$_.Name.ToLowerInvariant()});$i=0
 foreach($f in $files){
  $i++;Write-Progress -Activity 'Bowerbird' -Status $f.Name -PercentComplete ([int](100*$i/$total))
  $meta=Get-BowerbirdImageMetadata -File $f
  $pass1=Invoke-BowerbirdPass1 -File $f -Metadata $meta
  $analysis=$pass1
  if($pass1.NeedsVision -and $visionUsed -lt $MaxVision){
   Write-Host ("  [{0}/{1}] Vision → {2}" -f $i,$total,$f.Name) -ForegroundColor Cyan
   $analysis=Invoke-BowerbirdPass2 -File $f -Pass1Result $pass1 -Profile $Profile;$visionUsed++
  }else{Write-Host ("  [{0}/{1}] Pass1 → {2} (conf={3:N2})" -f $i,$total,$f.Name,$pass1.Confidence) -ForegroundColor DarkGray}
  $proposal=New-BowerbirdFileName -Analysis $analysis -File $f -ExistingNames $existingNames
  $proposals+=$proposal;$existingNames+=$proposal.ProposedName.ToLowerInvariant()
  if($Apply){$null=Rename-BowerbirdFile -File $f -Proposal $proposal -AuditLogPath $auditPath}
  else{$null=Rename-BowerbirdFile -File $f -Proposal $proposal -AuditLogPath $auditPath -WhatIf}
 }
 Write-Progress -Activity 'Bowerbird' -Completed
 Write-Host '';Write-Host '=== Bowerbird Preview ===' -ForegroundColor Cyan
 $proposals|Select-Object OriginalName,ProposedName,@{N='Conf';E={'{0:N2}' -f $_.Confidence}},Source|Format-Table -AutoSize
 Write-Host ("Vision calls used: {0} / {1}" -f $visionUsed,$MaxVision) -ForegroundColor DarkGray
 Write-Host ("Audit log: {0}" -f $auditPath) -ForegroundColor DarkGray
 if(-not $Apply){Write-Host 'Dry-run only. Re-run with -Apply to perform renames.' -ForegroundColor Yellow}
 else{Write-Host 'Renames applied. Use Undo-BowerbirdRename to reverse.' -ForegroundColor Green}
 return [pscustomobject]@{Proposals=$proposals;AuditLog=$auditPath;VisionUsed=$visionUsed;Applied=[bool]$Apply}
}
