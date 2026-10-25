# Bowerbird - Lazarette bridge (Lazarette was formerly ARC; ARC names are still accepted)
#requires -Version 5.1
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
 foreach($c in $candidates){
  if(-not $c){continue};try{$full=[IO.Path]::GetFullPath($c)}catch{continue}
  if(Test-Path -LiteralPath (Join-Path $full 'pm.ps1')){return $full}
 }
 return $null
}
function Test-BowerbirdArcHelpersAvailable {
 return [bool](Get-Command Get-PmStarkApiKey -ErrorAction SilentlyContinue) -or
 [bool](Get-Command Get-LiveVault -ErrorAction SilentlyContinue) -or
 [bool](Get-Command Ensure-VaultUnlocked -ErrorAction SilentlyContinue)
}
function Import-BowerbirdArcSession {
 [CmdletBinding()]param([string]$ArcRoot,[switch]$Quiet)
 if(Test-BowerbirdArcHelpersAvailable){if(-not $Quiet){Write-Host '[*] Lazarette helpers already available' -ForegroundColor DarkGray};return $true}
 $existing=Get-Module -Name BowerbirdArc -ErrorAction SilentlyContinue
 if($existing){return (Test-BowerbirdArcHelpersAvailable)}
 if(-not $ArcRoot){$ArcRoot=Find-BowerbirdArcRoot}
 if(-not $ArcRoot){if(-not $Quiet){Write-Host '[!] Lazarette (formerly ARC) not found' -ForegroundColor DarkGray};return $false}
 $pm=Join-Path $ArcRoot 'pm.ps1'
 if(-not (Test-Path -LiteralPath $pm)){if(-not $Quiet){Write-Host "[!] pm.ps1 missing: $pm" -ForegroundColor Yellow};return $false}
 if(-not $Quiet){Write-Host "[*] Loading Lazarette from $ArcRoot" -ForegroundColor Cyan}
 try{
  $bowerArc=New-Module -Name BowerbirdArc -ScriptBlock {
   param([string]$PmPath)
   $ErrorActionPreference='Continue'
   . $PmPath
   Export-ModuleMember -Function * -Alias * -ErrorAction SilentlyContinue
  } -ArgumentList $pm
  Import-Module -ModuleInfo $bowerArc -Global -Force -WarningAction SilentlyContinue
 }catch{
  Write-Host "[x] Lazarette module load failed: $($_.Exception.Message)" -ForegroundColor Red
  try{. $pm;if(-not $Quiet){Write-Host '[*] Lazarette fallback: dot-sourced' -ForegroundColor Yellow}}catch{return $false}
 }
 return (Test-BowerbirdArcHelpersAvailable)
}
function Get-BowerbirdArcSecretByName {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$ServiceName)
 if(-not (Test-BowerbirdArcHelpersAvailable)){$null=Import-BowerbirdArcSession -Quiet}
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
