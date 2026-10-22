#requires -Version 5.1
# User-directed workspace switching for Bowerbird Studio.
# No filesystem writes outside per-workspace user-local application state.
function Get-BowerbirdWorkspaceDataDirectory([string]$Folder){
 $algorithm=[Security.Cryptography.SHA256]::Create()
 try{
  $bytes=[Text.Encoding]::UTF8.GetBytes($Folder.ToUpperInvariant())
  $digest=([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','').Substring(0,32)
 }finally{$algorithm.Dispose()}
 return (Join-Path (Join-Path $script:DataRoot 'workspaces') $digest)
}
function Confirm-BowerbirdWorkspaceDirectory([string]$Folder){
 if([string]::IsNullOrWhiteSpace($Folder)){throw 'Choose a folder before scanning.'}
 if($Folder.Length -gt 2048){throw 'Folder path is too long.'}
 if(-not [IO.Path]::IsPathRooted($Folder)){throw 'Enter the full path to an existing folder.'}
 if(-not (Test-Path -LiteralPath $Folder -PathType Container)){throw 'The folder does not exist or is not accessible.'}
 $resolved=Resolve-Path -LiteralPath $Folder -ErrorAction Stop
 if(@($resolved).Count -ne 1 -or $resolved.Provider.Name -ne 'FileSystem'){throw 'Select a single filesystem directory.'}
 $candidate=[IO.Path]::GetFullPath($resolved.ProviderPath)
 $driveRoot=[IO.Path]::GetPathRoot($candidate)
 if($candidate.Length -gt $driveRoot.Length){$candidate=$candidate.TrimEnd([char]92,[char]47)}
 # Avoid following a directory junction or symlink outside the selected workspace.
 $part=New-Object IO.DirectoryInfo($candidate)
 while($null -ne $part){
  if(($part.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
   throw 'Folder includes a junction or symbolic link. Select a direct folder instead.'
  }
  $part=$part.Parent
 }
 return $candidate
}
function Set-BowerbirdWorkspace {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Folder,[switch]$Initial)
 $selected=Confirm-BowerbirdWorkspaceDirectory $Folder
 if(-not $Initial -and $selected -ieq $script:AllowedRoot){
  return @{ok=$true;changed=$false;root=$script:AllowedRoot;indexExists=(Test-Path -LiteralPath $script:IndexPath)}
 }
 # Stage the new workspace paths and writable state before switching.
 $dir=Get-BowerbirdWorkspaceDataDirectory $selected
 [IO.Directory]::CreateDirectory($dir)|Out-Null
 $newIndex=Join-Path $dir 'studio-index.json'
 $newJournal=Join-Path $dir 'studio-journal.json'
 $newPlan=Join-Path $dir 'studio-plan.json'
 # Never permit an old approved move preview to survive switching folders.
 if($script:PlanPath -and (Test-Path -LiteralPath $script:PlanPath)){
  Remove-Item -LiteralPath $script:PlanPath -Force -ErrorAction Stop
 }
 if(Test-Path -LiteralPath $newPlan){Remove-Item -LiteralPath $newPlan -Force -ErrorAction Stop}
 $script:AllowedRoot=$selected
 $script:WorkspaceDataDir=$dir
 $script:IndexPath=$newIndex
 $script:JournalPath=$newJournal
 $script:PlanPath=$newPlan
 Write-BowerbirdDiagnostic -Event 'WORKSPACE_SWITCH' -Message 'A workspace was selected.'
 return @{ok=$true;changed=$true;root=$selected;indexExists=(Test-Path -LiteralPath $newIndex)}
}
function Show-BowerbirdFolderDialog {
 # On Windows this executes only when the user clicks Browse Folder. It uses
 # the standard built-in .NET Framework dialog, never a third-party executable.
 if([Threading.Thread]::CurrentThread.GetApartmentState() -ne [Threading.ApartmentState]::STA){
  throw 'Windows folder selection needs an STA launcher. Use Start-Bowerbird.bat or enter the full path.'
 }
 try{Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop}
 catch{throw 'Native folder selection is unavailable. Enter the full folder path in the GUI instead.'}
 $owner=New-Object Windows.Forms.Form
 $dialog=New-Object Windows.Forms.FolderBrowserDialog
 try{
  $owner.Text='Bowerbird - Select folder'
  $owner.TopMost=$true
  $owner.ShowInTaskbar=$false
  $owner.StartPosition=[Windows.Forms.FormStartPosition]::CenterScreen
  $owner.Size=New-Object Drawing.Size(1,1)
  $owner.Opacity=0
  $owner.Show()
  $dialog.Description='Choose the folder Bowerbird should scan.'
  $dialog.ShowNewFolderButton=$false
  if(Test-Path -LiteralPath $script:AllowedRoot -PathType Container){$dialog.SelectedPath=$script:AllowedRoot}
  $choice=$dialog.ShowDialog($owner)
  if($choice -ne [Windows.Forms.DialogResult]::OK){return $null}
  return [string]$dialog.SelectedPath
 }finally{$dialog.Dispose();$owner.Close();$owner.Dispose()}
}
