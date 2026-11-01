# Bowerbird - Lazarette bridge
#requires -Version 5.1
#
# Contract (Lazarette docs/INTEGRATION.md): find the Lazarette folder, dot-source lib\Lazarette.ps1, unlock
# interactively, then read secrets with Get-LazaretteSecret. Discovery order, first match wins:
#   $env:LAZARETTE_PATH, a Lazarette folder next to the Bowerbird folder, $env:USERPROFILE\Projects\Lazarette.
# The folder must contain lib\Lazarette.ps1.

function Find-BowerbirdLazaretteRoot {
 [CmdletBinding()]param()
 $candidates=New-Object System.Collections.Generic.List[string]
 if($env:LAZARETTE_PATH){[void]$candidates.Add($env:LAZARETTE_PATH.Trim())}
 $repo=$null;try{$repo=$PSScriptRoot}catch{}
 if($repo){[void]$candidates.Add((Join-Path (Split-Path (Split-Path $repo -Parent) -Parent) 'Lazarette'))}
 if($env:USERPROFILE){[void]$candidates.Add((Join-Path $env:USERPROFILE 'Projects\Lazarette'))}
 foreach($c in $candidates){
  if(-not $c){continue}
  try{$full=[IO.Path]::GetFullPath($c)}catch{continue}
  if(Test-Path -LiteralPath (Join-Path $full 'lib\Lazarette.ps1')){return $full}
 }
 return $null
}

function Test-BowerbirdLazaretteHelpersAvailable {
 return [bool](Get-Command Get-LazaretteSecret -ErrorAction SilentlyContinue)
}

function Import-BowerbirdLazaretteSession {
 [CmdletBinding()]param([string]$LazaretteRoot,[switch]$Quiet)
 if(Test-BowerbirdLazaretteHelpersAvailable){if(-not $Quiet){Write-Host '[*] Lazarette helpers already available' -ForegroundColor DarkGray};return $true}
 $existing=Get-Module -Name BowerbirdLazarette -ErrorAction SilentlyContinue
 if($existing){return (Test-BowerbirdLazaretteHelpersAvailable)}
 if(-not $LazaretteRoot){$LazaretteRoot=Find-BowerbirdLazaretteRoot}
 if(-not $LazaretteRoot){if(-not $Quiet){Write-Host '[!] Lazarette not found (set LAZARETTE_PATH, or keep a Lazarette folder next to Bowerbird)' -ForegroundColor DarkGray};return $false}
 $entry=Join-Path $LazaretteRoot 'lib\Lazarette.ps1'
 if(-not (Test-Path -LiteralPath $entry)){if(-not $Quiet){Write-Host "[!] No lib\Lazarette.ps1 in $LazaretteRoot" -ForegroundColor Yellow};return $false}
 if(-not $Quiet){Write-Host "[*] Loading Lazarette from $LazaretteRoot" -ForegroundColor Cyan}
 try{
  $bowerLazarette=New-Module -Name BowerbirdLazarette -ScriptBlock {
   param([string]$EntryPath)
   $ErrorActionPreference='Continue'
   . $EntryPath
   Export-ModuleMember -Function * -Alias * -ErrorAction SilentlyContinue
  } -ArgumentList $entry
  Import-Module -ModuleInfo $bowerLazarette -Global -Force -WarningAction SilentlyContinue
 }catch{
  Write-Host "[x] Lazarette load failed: $($_.Exception.Message)" -ForegroundColor Red
  return $false
 }
 return (Test-BowerbirdLazaretteHelpersAvailable)
}

function Unlock-BowerbirdLazaretteIfNeeded {
 # Lazarette unlocks interactively by design; only try when a console user can answer.
 if(-not (Get-Command Test-LazaretteVaultUnlocked -ErrorAction SilentlyContinue)){return}
 try{if(Test-LazaretteVaultUnlocked){return}}catch{}
 if(-not [Environment]::UserInteractive){return}
 if(Get-Command Unlock-LazaretteVaultInteractive -ErrorAction SilentlyContinue){try{$null=Unlock-LazaretteVaultInteractive}catch{}}
}

function Get-BowerbirdLazaretteSecretByName {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ServiceName)
 if(-not (Test-BowerbirdLazaretteHelpersAvailable)){$null=Import-BowerbirdLazaretteSession -Quiet}
 if(Get-Command Get-LazaretteSecret -ErrorAction SilentlyContinue){
  Unlock-BowerbirdLazaretteIfNeeded
  try{$v=Get-LazaretteSecret -Service $ServiceName -ErrorAction Stop;if($v){return [string]$v}}catch{}
 }
 return $null
}
