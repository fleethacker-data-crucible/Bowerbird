#requires -Version 5.1
# Rename SnapShackle captures from the OCR text in their .meta.json sidecars.
# Contract: SnapShackle docs\CAPTURE-FORMAT.md (schema snapshackle.capture/1). Propose-only: this builds a
# plan (the same shape the move plan uses) and never touches a file. Applying goes through the existing
# plan apply and journal, so it can be undone, and nothing is ever deleted.
# A capture is two files that belong together, so each rename is two plan operations: the PNG, then its
# sidecar (NAME.png.meta.json -> NEWNAME.png.meta.json). The sidecar content is never edited.

# Auto-generated capture names only: <prefix>-<yyyyMMdd>-<HHmmss>-<fff>-<8 hex>.png. A name a person chose
# (or one this feature already wrote) does not match, so it is left alone.
$script:BowerbirdCaptureNamePattern='^(?:SnapShackle|CutterMk|Lasso|SnipHero)-(?<stamp>\d{8}-\d{6}-\d{3}-[0-9a-f]{8})\.png$'
# OCR text from a screen can hold secrets. A line that mentions one of these never becomes a file name.
$script:BowerbirdSidecarSensitivePattern='(?i)pass(word|wd|phrase)|secret|token|api[ _-]?key|private[ _-]?key|bearer|credential|ssn|social security|credit card|card number|cvv|iban'

function ConvertTo-BowerbirdSidecarSlug {
 # First title-like line of the OCR text -> lowercase words joined by hyphens, or '' when nothing is safe to use.
 [CmdletBinding()]param([string]$Ocr,[ValidateRange(8,80)][int]$MaxChars=48,[ValidateRange(1,10)][int]$MaxWords=6)
 if([string]::IsNullOrWhiteSpace($Ocr)){return ''}
 foreach($rawLine in ($Ocr -split '\r?\n')){
  $line=$rawLine.Trim()
  if($line.Length -lt 4){continue}
  if($line -match $script:BowerbirdSidecarSensitivePattern){continue}
  if($line -match '[@\/:]|\d{6,}'){continue}   # e-mail, paths, URLs, long numbers
  $words=New-Object Collections.Generic.List[string]
  foreach($match in [regex]::Matches($line,'[A-Za-z][A-Za-z0-9]*')){
   $word=$match.Value.ToLowerInvariant()
   if($word.Length -ge 20){continue}
   if($word.Length -ge 8 -and $word -match '\d'){continue}   # looks like an id or key
   $words.Add($word)
  }
  $letters=($words -join '').Length
  if($letters -lt 5){continue}
  $slug=''
  foreach($word in ($words|Select-Object -First $MaxWords)){
   $next=if($slug){$slug+'-'+$word}else{$word}
   if($next.Length -gt $MaxChars){break}
   $slug=$next
  }
  if($slug.Length -ge 4){return $slug}
 }
 return ''
}

function Read-BowerbirdCaptureSidecar {
 # Returns @{Ok;Reason;Ocr;Tags;Note}. A missing sidecar reads as empty, as the contract says.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$PngPath)
 $sidecar=$PngPath+'.meta.json'
 if(-not (Test-Path -LiteralPath $sidecar -PathType Leaf)){return @{Ok=$false;Reason='No sidecar';Path=$sidecar;Ocr=''}}
 try{$json=[IO.File]::ReadAllText($sidecar)|ConvertFrom-Json}catch{return @{Ok=$false;Reason='Sidecar is not valid JSON';Path=$sidecar;Ocr=''}}
 if($null -eq $json -or $json -isnot [pscustomobject]){return @{Ok=$false;Reason='Sidecar is not a JSON object';Path=$sidecar;Ocr=''}}
 $schema=if($json.PSObject.Properties['schema']){[string]$json.schema}else{'snapshackle.capture/1'}
 if($schema -cnotmatch '^snapshackle\.capture/1$'){return @{Ok=$false;Reason="Unknown sidecar schema: $schema";Path=$sidecar;Ocr=''}}
 $ocr=if($json.PSObject.Properties['ocr'] -and $json.ocr -is [string]){[string]$json.ocr}else{''}
 return @{Ok=$true;Reason='';Path=$sidecar;Ocr=$ocr}
}

function New-BowerbirdSidecarRenamePlan {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$Folder,[switch]$Recurse,
  [ValidateRange(1,10000)][int]$MaxImages=500
 )
 $opts=@{LiteralPath=$Folder;File=$true;Filter='*.png';ErrorAction='SilentlyContinue'}
 if($Recurse){$opts.Recurse=$true}
 $reserved=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
 $ops=New-Object Collections.Generic.List[object]
 $skipped=New-Object Collections.Generic.List[object]
 foreach($file in (Get-ChildItem @opts|Sort-Object FullName|Select-Object -First $MaxImages)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or (Test-BowerbirdReparseAncestor $file.FullName)){
   $skipped.Add(@{Source=$file.FullName;Reason='Reparse point in source path'});continue
  }
  $nameMatch=[regex]::Match($file.Name,$script:BowerbirdCaptureNamePattern,'IgnoreCase')
  if(-not $nameMatch.Success){$skipped.Add(@{Source=$file.FullName;Reason='Name is not an automatic capture name'});continue}
  $sidecar=Read-BowerbirdCaptureSidecar -PngPath $file.FullName
  if(-not $sidecar.Ok){$skipped.Add(@{Source=$file.FullName;Reason=$sidecar.Reason});continue}
  $slug=ConvertTo-BowerbirdSidecarSlug -Ocr $sidecar.Ocr
  if(-not $slug){$skipped.Add(@{Source=$file.FullName;Reason='No usable text in the OCR (empty, too short or sensitive)'});continue}
  # Keep the SnapShackle- prefix so the capture stays listed in SnapShackle's library, and keep the
  # time stamp and random suffix so names sort the same way and never collide.
  $newName='SnapShackle-'+$slug+'-'+$nameMatch.Groups['stamp'].Value.ToLowerInvariant()+'.png'
  $newPng=Join-Path $file.DirectoryName $newName
  $newSidecar=$newPng+'.meta.json'
  if((Test-Path -LiteralPath $newPng) -or (Test-Path -LiteralPath $newSidecar) -or -not $reserved.Add($newPng)){
   $skipped.Add(@{Source=$file.FullName;Reason='Target name already taken'});continue
  }
  $null=$reserved.Add($newSidecar)
  $reason="Sidecar OCR text: $slug"
  $ops.Add([pscustomobject]@{
   Source=$file.FullName;Destination=$newPng;SHA256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
   Size=$file.Length;Status='Proposed';Confidence=0.6;Kind='Capture';Reason=$reason
  })
  $sidecarItem=Get-Item -LiteralPath $sidecar.Path
  $ops.Add([pscustomobject]@{
   Source=$sidecarItem.FullName;Destination=$newSidecar;SHA256=(Get-FileHash -LiteralPath $sidecarItem.FullName -Algorithm SHA256).Hash
   Size=$sidecarItem.Length;Status='Proposed';Confidence=0.6;Kind='Sidecar';Reason='Moves with its capture'
  })
 }
 return [pscustomobject]@{
  SchemaVersion=2;Id=[guid]::NewGuid().ToString('N');Mode='SidecarRename'
  CreatedUtc=[DateTime]::UtcNow.ToString('o');VisionRequests=0
  Operations=@($ops.ToArray());Skipped=@($skipped.ToArray())
 }
}
