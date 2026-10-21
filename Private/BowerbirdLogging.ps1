# Bowerbird console and persistent diagnostics
#requires -Version 5.1
$script:BowerbirdLogRoot=$null
$script:BowerbirdTranscriptPath=$null
function Initialize-BowerbirdLogging {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Root)
 $script:BowerbirdLogRoot=$Root
 $logDir=Join-Path $Root 'Logs'
 if(-not (Test-Path -LiteralPath $logDir)){New-Item -ItemType Directory -Path $logDir -Force|Out-Null}
 $script:BowerbirdMainLog=Join-Path $logDir 'bowerbird.log'
 try{$stamp=Get-Date -Format 'yyyyMMdd_HHmmss';$tx=Join-Path $logDir "bowerbird-transcript_$stamp.txt";Start-Transcript -Path $tx -Append -ErrorAction SilentlyContinue|Out-Null;$script:BowerbirdTranscriptPath=$tx}catch{}
}
function Write-BowerbirdLog {
 [CmdletBinding()]param([ValidateSet('INFO','WARN','ERROR','DEBUG','CRASH')][string]$Level='INFO',[Parameter(Mandatory)][string]$Message,[string]$Root,[System.Management.Automation.ErrorRecord]$ErrorRecord)
 if(-not $Root){$Root=$script:BowerbirdLogRoot}
 $ts=Get-Date -Format 'yyyy-MM-dd HH:mm:ss';$line="[$ts] [$Level] $Message"
 switch($Level){
  'ERROR'{Write-Host $line -ForegroundColor Red}
  'CRASH'{Write-Host $line -ForegroundColor Magenta}
  'WARN'{Write-Host $line -ForegroundColor Yellow}
  'DEBUG'{Write-Verbose $line}
  default{Write-Host $line -ForegroundColor Gray}
 }
 if($Root){
  $logDir=Join-Path $Root 'Logs'
  if(-not (Test-Path -LiteralPath $logDir)){try{New-Item -ItemType Directory -Path $logDir -Force|Out-Null}catch{}}
  $logFile=Join-Path $logDir 'bowerbird.log'
  try{Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
  if($ErrorRecord){
   $detail=@("  Exception: $($ErrorRecord.Exception.GetType().FullName)","  Message  : $($ErrorRecord.Exception.Message)","  Script   : $($ErrorRecord.InvocationInfo.ScriptName)","  Line     : $($ErrorRecord.InvocationInfo.ScriptLineNumber)","  Code     : $($ErrorRecord.InvocationInfo.Line)","  Position : $($ErrorRecord.InvocationInfo.PositionMessage)","  Stack    :")
   if($ErrorRecord.ScriptStackTrace){$detail+=($ErrorRecord.ScriptStackTrace -split "`n"|ForEach-Object {"    $_"})}
   try{Add-Content -LiteralPath $logFile -Value ($detail -join "`r`n") -Encoding UTF8 -ErrorAction SilentlyContinue}catch{}
  }
 }
}
function Write-BowerbirdCrashLog {
 [CmdletBinding()]param([Parameter(Mandatory)][System.Management.Automation.ErrorRecord]$ErrorRecord,[string]$Root,[string]$Context='unhandled')
 if(-not $Root){$Root=$script:BowerbirdLogRoot}
 if(-not $Root){$Root=if($PSScriptRoot){$PSScriptRoot}else{(Get-Location).Path}}
 $logDir=Join-Path $Root 'Logs'
 try{if(-not (Test-Path -LiteralPath $logDir)){New-Item -ItemType Directory -Path $logDir -Force|Out-Null}}catch{$logDir=$Root}
 $stamp=Get-Date -Format 'yyyyMMdd_HHmmss'
 $crashPath=Join-Path $logDir "bowerbird-CRASH_$stamp.txt"
 $body=@"
BOWERBIRD CRASH REPORT
Time: $(Get-Date -Format 'o')
Context: $Context
PowerShell: $($PSVersionTable.PSVersion)
OS: $([Environment]::OSVersion.VersionString)
Exception: $($ErrorRecord.Exception)
Script: $($ErrorRecord.InvocationInfo.ScriptName)
Line: $($ErrorRecord.InvocationInfo.ScriptLineNumber)
Stack: $($ErrorRecord.ScriptStackTrace)
Full error: $($ErrorRecord|Format-List * -Force|Out-String)
"@
 try{[IO.File]::WriteAllText($crashPath,$body,(New-Object Text.UTF8Encoding $false))}catch{$crashPath=$null}
 Write-BowerbirdLog -Level CRASH -Message "Crash written to $crashPath :: $($ErrorRecord.Exception.Message)" -Root $Root -ErrorRecord $ErrorRecord
 return $crashPath
}
function Stop-BowerbirdLogging {
 if($script:BowerbirdTranscriptPath){try{Stop-Transcript -ErrorAction SilentlyContinue|Out-Null}catch{};$script:BowerbirdTranscriptPath=$null}
}
