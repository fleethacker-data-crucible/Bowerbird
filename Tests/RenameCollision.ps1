#requires -Version 5.1
<#
 Two screenshots from the same day used to get the same proposed name, and the second was skipped as
 "Target name already taken". They now get numbered names (_01, _02), in both the smart rename plan and
 Invoke-BowerbirdOrganize's bare-name list. Synthetic generated images in a temporary folder; no network.
 Run: powershell.exe -NoProfile -File .\Tests\RenameCollision.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdRenameCollision_'+[guid]::NewGuid().ToString('N'))
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
function New-Shot([string]$Folder,[string]$Name,$Color){
 Add-Type -AssemblyName System.Drawing
 $bitmap=New-Object Drawing.Bitmap 1920,1080
 try{
  $graphics=[Drawing.Graphics]::FromImage($bitmap)
  try{$graphics.Clear($Color)}finally{$graphics.Dispose()}
  $bitmap.Save((Join-Path $Folder $Name),[Drawing.Imaging.ImageFormat]::Png)
 }finally{$bitmap.Dispose()}
}
try{
 Add-Type -AssemblyName System.Drawing
 New-Item -ItemType Directory -Path $work -Force|Out-Null
 foreach($module in @('Get-ImageMetadata','BowerbirdPass1','BowerbirdNamer','BowerbirdActions','BowerbirdRenameStudio')){. (Join-Path $repo ('Private\'+$module+'.ps1'))}
 New-Shot $work 'Screenshot_2026-10-30_141502.png' ([Drawing.Color]::SteelBlue)
 New-Shot $work 'Screenshot_2026-10-30_153044.png' ([Drawing.Color]::SeaGreen)
 New-Shot $work 'Screenshot_2026-10-30_180000.png' ([Drawing.Color]::Goldenrod)

 # Smart plan: three same-day screenshots -> three distinct proposals, none skipped.
 $plan=New-BowerbirdSmartRenamePlan -Folder $work
 Assert (@($plan.Operations).Count -eq 3) ('all three are proposed, none skipped (got '+@($plan.Operations).Count+', skipped '+@($plan.Skipped).Count+')')
 $names=@($plan.Operations|ForEach-Object {Split-Path -Leaf $_.Destination})
 Assert (@($names|Select-Object -Unique).Count -eq 3) ('the proposed names are distinct: '+($names -join ', '))
 Assert (@($names|Where-Object {$_ -like '*_01.png'}).Count -eq 1 -and @($names|Where-Object {$_ -like '*_02.png'}).Count -eq 1) 'the second and third get _01 and _02'
 Write-Host 'PASS: Same-day screenshots get distinct numbered names in the smart rename plan' -ForegroundColor Green

 # A target that already exists on disk is still stepped over.
 $first=Split-Path -Leaf (@($plan.Operations)[0].Destination)
 [IO.File]::WriteAllBytes((Join-Path $work $first),[byte[]](1,2,3))
 $again=New-BowerbirdSmartRenamePlan -Folder $work
 $taken=@($again.Operations|ForEach-Object {Split-Path -Leaf $_.Destination})
 Assert ($taken -notcontains $first -and @($taken|Select-Object -Unique).Count -eq $taken.Count) 'a name already on disk is never proposed'
 Write-Host 'PASS: A name that already exists on disk is not proposed' -ForegroundColor Green

 # The bare-name list used by Invoke-BowerbirdOrganize.
 $file=Get-Item -LiteralPath (Join-Path $work 'Screenshot_2026-10-30_141502.png')
 $analysis=[pscustomobject]@{SuggestedName='2026-10-30_Screenshot.png';Confidence=0.6;Source='test';Reasoning='test'}
 $one=New-BowerbirdFileName -Analysis $analysis -File $file -ExistingNames @('2026-10-30_screenshot.png')
 Assert ($one.ProposedName -ceq '2026-10-30_Screenshot_01.png') 'a bare lower-case name in the list is stepped over'
 Write-Host 'PASS: Bare-name collisions still get numbered' -ForegroundColor Green
 Write-Host 'PASS: Bowerbird rename collisions (3 groups)' -ForegroundColor Green
 exit 0
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
