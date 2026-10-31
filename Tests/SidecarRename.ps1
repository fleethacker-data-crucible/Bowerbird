#requires -Version 5.1
<#
 Rename from SnapShackle OCR sidecars (Private\BowerbirdSidecarRename.ps1). Synthetic files only, in a
 temporary folder; no OCR engine, no network, no real captures.
 Run: powershell.exe -NoProfile -File .\Tests\SidecarRename.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$cli=Join-Path $repo 'Start-BowerbirdCli.ps1'
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdSidecarTest_'+[guid]::NewGuid().ToString('N'))
$space=Join-Path $work 'space'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function Invoke-CliJson([string[]]$Arguments){
 $ErrorActionPreference='Continue'
 $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments --json --root $space --local-dev 2>$null
 $text=(@($output) -join [Environment]::NewLine)
 return @{code=$LASTEXITCODE;text=$text;data=($text|ConvertFrom-Json)}
}
$utf8=New-Object Text.UTF8Encoding $false
$pngBytes=[byte[]](0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,0,0,0,0)   # a PNG signature is enough: nothing decodes the image
function New-Capture([string]$Name,$Sidecar,[switch]$Bom){
 $png=Join-Path $space $Name
 [IO.File]::WriteAllBytes($png,($pngBytes+[Text.Encoding]::ASCII.GetBytes($Name)))
 if($null -ne $Sidecar){
  $enc=if($Bom){New-Object Text.UTF8Encoding $true}else{$utf8}
  [IO.File]::WriteAllText($png+'.meta.json',(ConvertTo-Json -InputObject $Sidecar -Compress),$enc)
 }
 return $png
}
try{
 New-Item -ItemType Directory -Path $space -Force|Out-Null
 . (Join-Path $repo 'Private\BowerbirdActions.ps1')
 . (Join-Path $repo 'Private\BowerbirdSidecarRename.ps1')

 # --- the slug rules --------------------------------------------------------------------------------
 Assert ((ConvertTo-BowerbirdSidecarSlug "Quarterly Revenue Report`r`nQ3 summary") -ceq 'quarterly-revenue-report') 'first title-like line becomes the slug'
 Assert ((ConvertTo-BowerbirdSidecarSlug "ok`nSettings - Network Adapters") -ceq 'settings-network-adapters') 'short lines are skipped'
 Assert ((ConvertTo-BowerbirdSidecarSlug "Password: hunter2`nbilling@example.com`nBuild Pipeline Overview") -ceq 'build-pipeline-overview') 'secret and e-mail lines are skipped'
 Assert ((ConvertTo-BowerbirdSidecarSlug "C:\Users\Someone\file.txt`nhttps://example.test/page") -ceq '') 'paths and URLs never become names'
 Assert ((ConvertTo-BowerbirdSidecarSlug "Token ghp1234567890abcdef") -ceq '') 'a line that names a token is dropped'
 Assert ((ConvertTo-BowerbirdSidecarSlug "Meeting notes a1b2c3d4e5f6g7h8 for Friday") -ceq 'meeting-notes-for-friday') 'id-like words are dropped'
 Assert ((ConvertTo-BowerbirdSidecarSlug 'one two three four five six seven eight nine ten').Split('-').Count -eq 6) 'at most six words'
 Assert ((ConvertTo-BowerbirdSidecarSlug ('abcdefghij '*20)).Length -le 48) 'at most 48 characters'
 Assert ((ConvertTo-BowerbirdSidecarSlug '') -ceq '' -and (ConvertTo-BowerbirdSidecarSlug '12 34 56') -ceq '') 'no text, no name'
 Pass 'Slug rules: title line, six words, 48 characters, secrets and ids left out'

 # --- the plan ---------------------------------------------------------------------------------------
 $good=New-Capture 'SnapShackle-20261031-141502-123-1a2b3c4d.png' @{schema='snapshackle.capture/1';tags=@('work');note='';ocr="Quarterly Revenue Report`r`nQ3 summary"}
 $legacy=New-Capture 'CutterMk-20260101-090000-001-0a0b0c0d.png' @{tags=@();note='';ocr='Network Adapters Settings'}   # no schema field: version 1
 $bom=New-Capture 'Lasso-20260102-090000-002-ffeeddcc.png' @{schema='snapshackle.capture/1';tags=@();note='';ocr='Build Pipeline Overview'} -Bom
 $secret=New-Capture 'SnapShackle-20261031-141503-124-aaaaaaaa.png' @{schema='snapshackle.capture/1';tags=@();note='';ocr='Password: hunter2'}
 $empty=New-Capture 'SnapShackle-20261031-141504-125-bbbbbbbb.png' @{schema='snapshackle.capture/1';tags=@();note='';ocr=''}
 $future=New-Capture 'SnapShackle-20261031-141505-126-cccccccc.png' @{schema='snapshackle.capture/2';tags=@();note='';ocr='Future Format Screen'}
 $none=New-Capture 'SnapShackle-20261031-141506-127-dddddddd.png' $null
 $named=New-Capture 'holiday-photo.png' @{schema='snapshackle.capture/1';tags=@();note='';ocr='Holiday Photo Gallery'}
 $before=@{}
 foreach($file in Get-ChildItem -LiteralPath $space -File){$before[$file.Name]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}
 $plan=New-BowerbirdSidecarRenamePlan -Folder $space
 Assert ($plan.Mode -eq 'SidecarRename' -and $plan.SchemaVersion -eq 2) 'plan header'
 Assert (@($plan.Operations).Count -eq 6) ('three captures, two operations each (got '+@($plan.Operations).Count+')')
 $ops=@{};foreach($op in $plan.Operations){$ops[[IO.Path]::GetFileName($op.Source)]=$op}
 $newGood='SnapShackle-quarterly-revenue-report-20261031-141502-123-1a2b3c4d.png'
 Assert ($ops[(Split-Path $good -Leaf)].Destination -ceq (Join-Path $space $newGood)) 'PNG destination keeps the prefix, stamp and suffix'
 Assert ($ops[(Split-Path $good -Leaf)+'.meta.json'].Destination -ceq (Join-Path $space ($newGood+'.meta.json'))) 'sidecar destination is the new PNG name plus .meta.json'
 Assert ($ops[(Split-Path $good -Leaf)].Kind -eq 'Capture' -and $ops[(Split-Path $good -Leaf)+'.meta.json'].Kind -eq 'Sidecar') 'operations say which is which'
 Assert ($plan.Operations[0].Kind -eq 'Capture' -and $plan.Operations[1].Kind -eq 'Sidecar') 'the PNG comes before its sidecar'
 Assert ($ops['CutterMk-20260101-090000-001-0a0b0c0d.png'].Destination -clike '*SnapShackle-network-adapters-settings-20260101-090000-001-0a0b0c0d.png') 'a legacy prefix and a sidecar without schema are read as version 1'
 Assert ($ops['Lasso-20260102-090000-002-ffeeddcc.png'].Destination -clike '*SnapShackle-build-pipeline-overview-*') 'a sidecar with a byte-order mark is read'
 $reasons=@{};foreach($skip in $plan.Skipped){$reasons[[IO.Path]::GetFileName($skip.Source)]=$skip.Reason}
 Assert ($reasons['SnapShackle-20261031-141503-124-aaaaaaaa.png'] -like 'No usable text*') 'a secret-only OCR is skipped'
 Assert ($reasons['SnapShackle-20261031-141504-125-bbbbbbbb.png'] -like 'No usable text*') 'empty OCR is skipped'
 Assert ($reasons['SnapShackle-20261031-141505-126-cccccccc.png'] -like 'Unknown sidecar schema*') 'an unknown schema major is skipped'
 Assert ($reasons['SnapShackle-20261031-141506-127-dddddddd.png'] -eq 'No sidecar') 'no sidecar, no rename'
 Assert ($reasons['holiday-photo.png'] -like 'Name is not an automatic*') 'a name a person chose is left alone'
 foreach($file in Get-ChildItem -LiteralPath $space -File){Assert ($before[$file.Name] -ceq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) ('the preview changed nothing: '+$file.Name)}
 Assert (@(Get-ChildItem -LiteralPath $space -File).Count -eq $before.Count) 'the preview added and removed no files'
 Pass 'Plan: three captures proposed as PNG plus sidecar; five skipped with a reason; nothing touched'

 # --- apply through the journal, then undo -----------------------------------------------------------
 $journal=Join-Path $work 'journal.json'
 $results=@(Invoke-BowerbirdPlan -Plan $plan -JournalPath $journal -Apply -Confirm:$false)
 Assert (@($results|Where-Object {$_.Status -eq 'Applied'}).Count -eq 6) 'all six operations applied'
 Assert ((Test-Path -LiteralPath (Join-Path $space $newGood)) -and (Test-Path -LiteralPath (Join-Path $space ($newGood+'.meta.json')))) 'both files moved together'
 Assert (-not (Test-Path -LiteralPath $good) -and -not (Test-Path -LiteralPath ($good+'.meta.json'))) 'the old names are gone'
 Assert ((Get-FileHash -LiteralPath (Join-Path $space ($newGood+'.meta.json')) -Algorithm SHA256).Hash -ceq $before[(Split-Path $good -Leaf)+'.meta.json']) 'the sidecar content is byte-identical'
 Assert (Test-Path -LiteralPath $secret) 'a skipped capture stays where it was'
 $restored=@(Undo-BowerbirdPlan -JournalPath $journal -Confirm:$false)
 Assert ($restored.Count -eq 6) 'undo restores all six'
 foreach($file in Get-ChildItem -LiteralPath $space -File){Assert ($before[$file.Name] -ceq (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash) ('undo restored '+$file.Name)}
 Assert (@(Get-ChildItem -LiteralPath $space -File).Count -eq $before.Count) 'undo left no extra files'
 Pass 'Apply moves each PNG with its sidecar through the journal; undo puts every byte back'

 # --- a name already taken is never overwritten ------------------------------------------------------
 [IO.File]::WriteAllBytes((Join-Path $space $newGood),[byte[]](1,2,3))
 $again=New-BowerbirdSidecarRenamePlan -Folder $space
 $took=@($again.Skipped|Where-Object {$_.Source -eq $good})
 Assert ($took.Count -eq 1 -and $took[0].Reason -eq 'Target name already taken') 'a taken target name is skipped'
 Remove-Item -LiteralPath (Join-Path $space $newGood)
 Pass 'A target name that already exists is skipped, never overwritten'

 # --- the same thing through the CLI, in separate processes ------------------------------------------
 $run=Invoke-CliJson @('sidecar','preview')
 Assert ($run.code -eq 0 -and $run.data.ok -and $run.data.result.captures -eq 3 -and $run.data.result.count -eq 6) 'sidecar preview over the CLI'
 Assert (@($run.data.result.skipped).Count -eq 5) 'the CLI result lists the skipped files'
 $planId=[string]$run.data.result.id
 $run=Invoke-CliJson @('plan','apply','--id',$planId)
 Assert ($run.code -eq 2) 'plan apply without --yes exits 2'
 $run=Invoke-CliJson @('plan','apply','--id',$planId,'--yes')
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $space ($newGood+'.meta.json')))) 'plan apply --yes moves the pair in a later process'
 $run=Invoke-CliJson @('plan','undo','--yes')
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath $good) -and (Test-Path -LiteralPath ($good+'.meta.json'))) 'plan undo --yes restores the pair'
 $run=Invoke-CliJson @('sidecar','preview','--path','..\Windows')
 Assert ($run.code -eq 1) 'a path outside the workspace is refused'
 Pass 'CLI: sidecar preview, plan apply (needs --yes) and plan undo across separate processes'
 Write-Host ("PASS: Bowerbird sidecar rename ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
