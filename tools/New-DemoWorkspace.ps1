#requires -Version 5.1
<#
.SYNOPSIS
  Creates a small workspace of synthetic files for a Bowerbird demo (docs\DEMO-WALKTHROUGH.md).
.DESCRIPTION
  Everything here is invented: made-up reports, notes, a little code, one pair of exact duplicates and three
  small generated screenshots with typical screenshot names. Nothing is copied from the real machine and
  nothing is written outside -Path. It refuses a folder that already holds files, so it can never mix demo
  files into real ones.
.EXAMPLE
  powershell.exe -NoProfile -File .\tools\New-DemoWorkspace.ps1 -Path "$env:TEMP\bowerbird-demo\files"
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
$full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
if((Test-Path -LiteralPath $full) -and @(Get-ChildItem -LiteralPath $full -Force).Count -gt 0){throw "Refusing to use a folder that already has files: $full"}
$utf8=New-Object Text.UTF8Encoding $false
function Write-DemoText([string]$Relative,[string]$Text){
 $target=Join-Path $full $Relative
 [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
 [IO.File]::WriteAllText($target,$Text,$utf8)
}
Write-DemoText 'Reports\q3-revenue-summary.txt' "Quarterly revenue summary (invented figures)`r`nNorth region: 1.2 million. South region: 0.9 million.`r`nThe harbor project is on schedule."
Write-DemoText 'Reports\q3-revenue-summary-copy.txt' "Quarterly revenue summary (invented figures)`r`nNorth region: 1.2 million. South region: 0.9 million.`r`nThe harbor project is on schedule."
Write-DemoText 'Notes\meeting-notes.md' "# Harbor project meeting`r`n- Order the new bollards`r`n- Review the berth schedule with the pilot team`r`n"
Write-DemoText 'Notes\ideas.txt' "Ideas for the open day: guided tour of the signal station, a knot-tying table, a model lighthouse."
Write-DemoText 'Code\build.ps1' "# Invented build script`r`nWrite-Output 'building the demo'`r`n# TODO: add tests`r`n"
Write-DemoText 'Code\helper.js' "// Invented helper`r`nfunction add(a, b) { return a + b; }`r`nmodule.exports = { add };`r`n"
Write-DemoText 'Data\berths.csv' "berth,length_m,status`r`nA1,40,free`r`nA2,55,taken`r`nB1,30,free`r`n"
Add-Type -AssemblyName System.Drawing
$shots=@(
 @{Name='Screenshot_2026-10-28_141502.png';Color=[Drawing.Color]::SteelBlue}
 @{Name='Screenshot_2026-10-30_153044.png';Color=[Drawing.Color]::SeaGreen}
 @{Name='Screenshot_2026-10-31_090112.png';Color=[Drawing.Color]::Goldenrod}
)
foreach($shot in $shots){
 $target=Join-Path $full ('Screenshots\'+$shot.Name)
 [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
 $bitmap=New-Object Drawing.Bitmap 1920,1080
 try{
  $graphics=[Drawing.Graphics]::FromImage($bitmap)
  try{$graphics.Clear($shot.Color);$graphics.FillRectangle([Drawing.Brushes]::White,100,100,800,400)}finally{$graphics.Dispose()}
  $bitmap.Save($target,[Drawing.Imaging.ImageFormat]::Png)
 }finally{$bitmap.Dispose()}
}
$count=@(Get-ChildItem -LiteralPath $full -Recurse -File).Count
Write-Host "Created $count synthetic files in $full"
