<#
.SYNOPSIS
  Bowerbird MVP – intelligent image / screenshot renamer (PowerShell + ARC + GenAi/Grok vision)
.DESCRIPTION
  Two-pass organizer: filename and metadata first, optional vision LLM second.
  Default is dry-run. Use -Apply to rename.
#>
#requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true)]
param(
 [Parameter(Position=0)][string]$Path,
 [ValidateSet('Auto','Grok','GenAi')][string]$Profile='Auto',
 [double]$Pass1Threshold=0.65,[int]$MaxVision=25,[switch]$Apply,[switch]$Recurse,[switch]$Undo,[string]$AuditLogPath
)
$Root=$PSScriptRoot;if(-not $Root){$Root=Get-Location}
$Error.Clear();$Global:ErrorActionPreference='Stop'
function Write-CrashReport {
 param($Exception)
 $timestamp=Get-Date -Format 'yyyyMMdd_HHmmss';$dir=Join-Path $Root 'Logs'
 if(-not (Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
 $crashLog=Join-Path $dir "bowerbird-CRASH_$timestamp.txt"
 $report=@"
BOWERBIRD CRASH REPORT - $(Get-Date)
Exception Type: $($Exception.GetType().FullName)
Message: $($Exception.Message)
Script Line: $($Exception.InvocationInfo.ScriptLineNumber)
Script Name: $($Exception.InvocationInfo.ScriptName)
Stack Trace:
$($Exception.ScriptStackTrace)
Full Error:
$($Exception|Format-List -Force|Out-String)
"@
 $report|Out-File -FilePath $crashLog -Encoding UTF8 -Force
 Write-Host "`n[x] Bowerbird crashed! Report: $crashLog" -ForegroundColor Red
}
try{
 $envFile=Join-Path $Root 'Config\bowerbird.env'
 if(Test-Path $envFile){
  Get-Content $envFile|ForEach-Object{
   $line=$_.Trim()
   if($line -match '^\s*#' -or $line -eq ''){return}
   if($line -match '^\s*([^=]+)=(.*)$'){
    $k=$Matches[1].Trim();$v=$Matches[2].Trim().Trim('"').Trim("'")
    if($k){Set-Item -Path "Env:$k" -Value $v -Force}
   }
  }
  Write-Host 'Loaded Config\bowerbird.env' -ForegroundColor DarkGray
 }
 if($env:BOWERBIRD_LLM_PROFILE -and $Profile -eq 'Auto'){$Profile=$env:BOWERBIRD_LLM_PROFILE}
 $scripts=@(
  'Private\ArcBridge.ps1','Private\BowerbirdLogging.ps1','Private\BowerbirdLlm.ps1',
  'Private\Get-ImageMetadata.ps1','Private\BowerbirdPass1.ps1','Private\BowerbirdPass2.ps1',
  'Private\BowerbirdNamer.ps1','Private\BowerbirdRenamer.ps1','Public\Invoke-BowerbirdOrganize.ps1'
 )
 foreach($script in $scripts){
  $fullPath=Join-Path $Root $script
  if(Test-Path $fullPath){. $fullPath}else{throw "Missing required script: $script"}
 }
 try{$null=Import-BowerbirdArcSession -Quiet}catch{}
 Write-Host '';Write-Host '=== Bowerbird MVP ===' -ForegroundColor Cyan
 Write-Host 'Intelligent screenshot & image renamer (PowerShell + ARC + vision)' -ForegroundColor DarkGray
 if($Undo){
  if(-not $AuditLogPath){
   $latest=Get-ChildItem (Join-Path $Root 'Logs') -Filter 'bowerbird-audit_*.json' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
   if($latest){$AuditLogPath=$latest.FullName}
  }
  if(-not $AuditLogPath){Write-Host 'No audit log found. Supply -AuditLogPath.' -ForegroundColor Yellow;return}
  Undo-BowerbirdRename -AuditLogPath $AuditLogPath;return
 }
 if(-not $Path){
  Write-Host 'Usage:' -ForegroundColor Yellow
  Write-Host '.\Start-BowerbirdMVP.ps1 -Path "D:\Screenshots"'
  Write-Host '.\Start-BowerbirdMVP.ps1 -Path "D:\Screenshots" -Apply'
  Write-Host '.\Start-BowerbirdMVP.ps1 -Undo';return
 }
 $result=Invoke-BowerbirdOrganize -Path $Path -Profile $Profile -Pass1Threshold $Pass1Threshold -MaxVision $MaxVision -Apply:$Apply -Recurse:$Recurse -Root $Root -WhatIf:(-not $Apply)
 Write-BowerbirdLog -Level INFO -Message "Run complete. Applied=$($result.Applied) Vision=$($result.VisionUsed)" -Root $Root
}catch{Write-CrashReport -Exception $_}
finally{$ErrorActionPreference='Continue'}
