#requires -Version 5.1
# Where Bowerbird keeps its state and logs. Studio (Start-BowerbirdStudio.ps1) and the CLI
# (Start-BowerbirdCli.ps1) both ask here, so they always agree.
#
# Default: %LOCALAPPDATA%\Bowerbird\State and \Logs (or ...\Bowerbird\LocalDev\... with -LocalDev).
# Override, for a demo or a test run that must not touch the real folders:
#   Studio  -DataDir <folder>           CLI  --data-dir <folder>           either  BOWERBIRD_DATA_DIR=<folder>
# The option wins over the environment variable, which wins over -LocalDev. With an override, state goes to
# <folder>\State and logs (runtime files, feedback issues) to <folder>\Logs, and nothing is written under
# %LOCALAPPDATA%. A relative folder is taken from the current directory. See docs\DEMO-WALKTHROUGH.md.
function Resolve-BowerbirdDataLocations {
 [CmdletBinding()]param([string]$DataDir='',[switch]$LocalDev)
 if([string]::IsNullOrWhiteSpace($DataDir)){$DataDir=[string]$env:BOWERBIRD_DATA_DIR}
 if(-not [string]::IsNullOrWhiteSpace($DataDir)){
  $full=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DataDir.Trim().Trim('"'))
  if($full.Length -gt 200){throw 'The data directory path is too long.'}
  if($full.TrimEnd([char]92,[char]47) -ieq [IO.Path]::GetPathRoot($full).TrimEnd([char]92,[char]47)){throw 'The data directory cannot be a drive root.'}
  return [pscustomobject]@{State=(Join-Path $full 'State');Logs=(Join-Path $full 'Logs');Override=$true;Base=$full}
 }
 $localData=[Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
 if(-not $localData){$localData=[IO.Path]::GetTempPath()}
 $leaf=if($LocalDev){'Bowerbird\LocalDev'}else{'Bowerbird'}
 return [pscustomobject]@{State=(Join-Path $localData ($leaf+'\State'));Logs=(Join-Path $localData ($leaf+'\Logs'));Override=$false;Base=(Join-Path $localData $leaf)}
}
