# Bowerbird - Lazarette bridge (Lazarette was formerly ARC; ARC names are still accepted)
#requires -Version 5.1
#
# Contract (see Lazarette docs/INTEGRATION.md): find a Lazarette root that contains
# lib\Lazarette.ps1 or lib\Arc.ps1, load it, unlock interactively, then read secrets with
# Get-LazaretteSecret (or Get-ArcSecret). A folder with only pm.ps1 is an ARC 3/4 install and
# is still supported as a last resort through its old helpers.

function Get-BowerbirdArcEntryFile {
 param([string]$Root)
 foreach($rel in @('lib\Lazarette.ps1','lib\Arc.ps1','pm.ps1')){
  $p=Join-Path $Root $rel
  if(Test-Path -LiteralPath $p){return $p}
 }
 return $null
}

function Find-BowerbirdArcRoot {
 [CmdletBinding()]param()
 $candidates=New-Object System.Collections.Generic.List[string]
 foreach($e in @($env:LAZARETTE_PATH,$env:LAZARETTE_ROOT,$env:LAZARETTE_HOME,$env:ARC_PATH,$env:ARC_ROOT,$env:ARC_HOME)){if($e){[void]$candidates.Add($e.Trim())}}
 $repo=$null;try{$repo=$PSScriptRoot}catch{}
 if($repo){
  $root=Split-Path $repo -Parent
  $envFile=Join-Path $root 'Config\bowerbird.env'
  if(Test-Path -LiteralPath $envFile){
   $lines=@(Get-Content $envFile)
   foreach($key in @('LAZARETTE_PATH','ARC_PATH')){
    foreach($line in $lines){
     if($line -match ('^\s*'+$key+'\s*=\s*(.+)$')){[void]$candidates.Add($Matches[1].Trim().Trim('"').Trim("'"))}
    }
   }
  }
  $parent=Split-Path $root -Parent
  foreach($name in @('Lazarette','arc')){[void]$candidates.Add((Join-Path $parent $name))}
 }
 if($env:USERPROFILE){foreach($name in @('Lazarette','arc')){[void]$candidates.Add((Join-Path $env:USERPROFILE ('Projects\'+$name)))}}
 if($env:LOCALAPPDATA){foreach($name in @('Lazarette','ARC')){[void]$candidates.Add((Join-Path $env:LOCALAPPDATA $name))}}
 # Prefer a current (ARC 5 / Lazarette) install anywhere in the list over a legacy pm.ps1-only one.
 $legacy=$null
 foreach($c in $candidates){
  if(-not $c){continue};try{$full=[IO.Path]::GetFullPath($c)}catch{continue}
  $entry=Get-BowerbirdArcEntryFile -Root $full
  if(-not $entry){continue}
  if((Split-Path $entry -Leaf) -ne 'pm.ps1'){return $full}
  if(-not $legacy){$legacy=$full}
 }
 return $legacy
}

function Test-BowerbirdArcHelpersAvailable {
 return [bool](Get-Command Get-LazaretteSecret -ErrorAction SilentlyContinue) -or
 [bool](Get-Command Get-ArcSecret -ErrorAction SilentlyContinue) -or
 [bool](Get-Command Get-PmStarkApiKey -ErrorAction SilentlyContinue) -or
 [bool](Get-Command Get-LiveVault -ErrorAction SilentlyContinue)
}

function Import-BowerbirdArcSession {
 [CmdletBinding()]param([string]$ArcRoot,[switch]$Quiet)
 if(Test-BowerbirdArcHelpersAvailable){if(-not $Quiet){Write-Host '[*] Lazarette helpers already available' -ForegroundColor DarkGray};return $true}
 $existing=Get-Module -Name BowerbirdArc -ErrorAction SilentlyContinue
 if($existing){return (Test-BowerbirdArcHelpersAvailable)}
 if(-not $ArcRoot){$ArcRoot=Find-BowerbirdArcRoot}
 if(-not $ArcRoot){if(-not $Quiet){Write-Host '[!] Lazarette (formerly ARC) not found' -ForegroundColor DarkGray};return $false}
 $entry=Get-BowerbirdArcEntryFile -Root $ArcRoot
 if(-not $entry){if(-not $Quiet){Write-Host "[!] No lib\Lazarette.ps1, lib\Arc.ps1 or pm.ps1 in $ArcRoot" -ForegroundColor Yellow};return $false}
 if(-not $Quiet){Write-Host "[*] Loading Lazarette from $ArcRoot" -ForegroundColor Cyan}
 try{
  $bowerArc=New-Module -Name BowerbirdArc -ScriptBlock {
   param([string]$EntryPath)
   $ErrorActionPreference='Continue'
   . $EntryPath
   Export-ModuleMember -Function * -Alias * -ErrorAction SilentlyContinue
  } -ArgumentList $entry
  Import-Module -ModuleInfo $bowerArc -Global -Force -WarningAction SilentlyContinue
 }catch{
  Write-Host "[x] Lazarette load failed: $($_.Exception.Message)" -ForegroundColor Red
  return $false
 }
 return (Test-BowerbirdArcHelpersAvailable)
}

function Unlock-BowerbirdArcIfNeeded {
 # Lazarette unlocks interactively by design; only try when a console user can answer.
 $test=@('Test-LazaretteVaultUnlocked','Test-ArcVaultUnlocked')|Where-Object {Get-Command $_ -ErrorAction SilentlyContinue}|Select-Object -First 1
 if(-not $test){return}
 try{if(& $test){return}}catch{}
 if(-not [Environment]::UserInteractive){return}
 $unlock=@('Unlock-LazaretteVaultInteractive','Unlock-ArcVaultInteractive')|Where-Object {Get-Command $_ -ErrorAction SilentlyContinue}|Select-Object -First 1
 if($unlock){try{$null=& $unlock}catch{}}
}

function Get-BowerbirdArcSecretByName {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ServiceName)
 if(-not (Test-BowerbirdArcHelpersAvailable)){$null=Import-BowerbirdArcSession -Quiet}
 $get=@('Get-LazaretteSecret','Get-ArcSecret')|Where-Object {Get-Command $_ -ErrorAction SilentlyContinue}|Select-Object -First 1
 if($get){
  Unlock-BowerbirdArcIfNeeded
  try{$v=& $get -Service $ServiceName -ErrorAction Stop;if($v){return [string]$v}}catch{}
 }
 # ARC 3/4 (pm.ps1) installs
 if(Get-Command Get-PmStarkApiKey -ErrorAction SilentlyContinue){
  try{$v=Get-PmStarkApiKey -Service $ServiceName -ErrorAction Stop;if($v){return [string]$v}}catch{}
 }
 if(Get-Command Get-LiveVault -ErrorAction SilentlyContinue){
  try{
   $vault=Get-LiveVault
   if($vault){
    $item=$vault|Where-Object {$_.Service -eq $ServiceName -or $_.Name -eq $ServiceName}|Select-Object -First 1
    if($item -and $item.Secret){return [string]$item.Secret}
    if($item -and $item.Password){return [string]$item.Password}
   }
  }catch{}
 }
 return $null
}
