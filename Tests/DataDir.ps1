#requires -Version 5.1
<#
 --data-dir / -DataDir / BOWERBIRD_DATA_DIR: a demo or test run keeps its state and logs in a chosen folder and
 never touches %LOCALAPPDATA%\Bowerbird. Also runs the commands in docs\DEMO-WALKTHROUGH.md against the
 synthetic workspace from tools\New-DemoWorkspace.ps1. Synthetic files only; no network.
 Run: powershell.exe -NoProfile -File .\Tests\DataDir.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$cli=Join-Path $repo 'Start-BowerbirdCli.ps1'
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdDataDirTest_'+[guid]::NewGuid().ToString('N'))
$files=Join-Path $work 'files'
$data=Join-Path $work 'data'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function Invoke-Cli([string[]]$Arguments){
 $ErrorActionPreference='Continue'
 $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments --json 2>$null
 $text=(@($output) -join [Environment]::NewLine)
 return @{code=$LASTEXITCODE;text=$text;data=($text|ConvertFrom-Json)}
}
# What this test could disturb in the real state folders: today's CLI log and the per-workspace state.
function Get-RealStateSnapshot{
 $base=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'Bowerbird'
 if(-not (Test-Path -LiteralPath $base)){return ''}
 return (@(Get-ChildItem -LiteralPath $base -Recurse -File -Force -ErrorAction SilentlyContinue|Where-Object {$_.Name -like 'cli-*.jsonl' -or $_.FullName -like '*\workspaces\*'}|Sort-Object FullName|ForEach-Object {$_.FullName+'|'+$_.Length+'|'+$_.LastWriteTimeUtc.Ticks}) -join "`n")
}
try{
 New-Item -ItemType Directory -Path $work -Force|Out-Null
 . (Join-Path $repo 'Private\BowerbirdDataDir.ps1')

 # --- the rules --------------------------------------------------------------------------------------
 $saved=$env:BOWERBIRD_DATA_DIR
 try{
  $env:BOWERBIRD_DATA_DIR=''
  $default=Resolve-BowerbirdDataLocations
  Assert (-not $default.Override -and $default.State -like '*\Bowerbird\State' -and $default.Logs -like '*\Bowerbird\Logs') 'default: under %LOCALAPPDATA%\Bowerbird'
  $dev=Resolve-BowerbirdDataLocations -LocalDev
  Assert ($dev.State -like '*\Bowerbird\LocalDev\State') '-LocalDev keeps its own folder'
  $one=Resolve-BowerbirdDataLocations -DataDir (Join-Path $work 'one')
  Assert ($one.Override -and $one.State -ceq (Join-Path (Join-Path $work 'one') 'State') -and $one.Logs -ceq (Join-Path (Join-Path $work 'one') 'Logs')) '-DataDir: State and Logs under the folder'
  $env:BOWERBIRD_DATA_DIR=(Join-Path $work 'env')
  Assert ((Resolve-BowerbirdDataLocations).State -ceq (Join-Path (Join-Path $work 'env') 'State')) 'the environment variable is used'
  Assert ((Resolve-BowerbirdDataLocations -DataDir (Join-Path $work 'one')).State -ceq (Join-Path (Join-Path $work 'one') 'State')) 'the option wins over the variable'
  Assert ((Resolve-BowerbirdDataLocations -DataDir (Join-Path $work 'one') -LocalDev).Override) 'an override wins over -LocalDev'
  $env:BOWERBIRD_DATA_DIR=''
  Push-Location $work
  try{Assert ((Resolve-BowerbirdDataLocations -DataDir '.\rel').Base -ceq (Join-Path $work 'rel')) 'a relative folder is taken from the current directory'}finally{Pop-Location}
  $threw=$false;try{$null=Resolve-BowerbirdDataLocations -DataDir ([IO.Path]::GetPathRoot($work))}catch{$threw=$true}
  Assert $threw 'a drive root is refused'
 }finally{$env:BOWERBIRD_DATA_DIR=$saved}
 foreach($entry in @('Start-BowerbirdStudio.ps1','Start-BowerbirdCli.ps1')){
  $source=[IO.File]::ReadAllText((Join-Path $repo $entry))
  Assert ($source -match 'Resolve-BowerbirdDataLocations' -and $source -notmatch 'GetFolderPath\(\[Environment\+SpecialFolder\]::LocalApplicationData\)') ($entry+' asks the shared resolver and has no path of its own')
 }
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'Start-BowerbirdStudio.ps1'),[ref]$tokens,[ref]$errors)
 Assert (@($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -eq 'DataDir'}).Count -eq 1) 'Studio has a -DataDir parameter'
 Pass 'Rules: option, then variable, then -LocalDev, then the default; relative and drive-root cases; Studio and CLI share one resolver'

 # --- the walkthrough, against the synthetic workspace -----------------------------------------------
 $doc=[IO.File]::ReadAllText((Join-Path $repo 'docs\DEMO-WALKTHROUGH.md'))
 foreach($step in @('index build','index search','index duplicates','rename preview','plan apply','plan undo','New-DemoWorkspace.ps1','-DataDir','--data-dir','BOWERBIRD_DATA_DIR')){Assert ($doc.Contains($step)) ('the walkthrough mentions '+$step)}
 $before=Get-RealStateSnapshot
 $null=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\New-DemoWorkspace.ps1') -Path $files
 $demoFiles=@(Get-ChildItem -LiteralPath $files -Recurse -File)
 Assert ($demoFiles.Count -eq 10 -and $doc.Contains('creates 10 synthetic files')) 'the generator makes the 10 files the walkthrough says'
 $refused=$false;try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $repo 'tools\New-DemoWorkspace.ps1') -Path $files 2>$null;$refused=($LASTEXITCODE -ne 0)}catch{$refused=$true}
 Assert $refused 'the generator refuses a folder that already has files'
 $common=@('--root',$files,'--data-dir',$data)
 $run=Invoke-Cli (@('index','build','--recurse','--include-content')+$common)
 Assert ($run.code -eq 0 -and $run.data.result.indexed -eq 10) 'index build indexes the 10 demo files'
 $run=Invoke-Cli (@('index','search','--query','harbor')+$common)
 Assert ($run.code -eq 0 -and @($run.data.result.items).Count -eq 3) 'search for harbor finds the two reports and the notes'
 $run=Invoke-Cli (@('index','duplicates')+$common)
 Assert ($run.code -eq 0 -and @($run.data.result.groups).Count -eq 1 -and @($run.data.result.groups[0].files).Count -eq 2) 'one exact duplicate group of two'
 $run=Invoke-Cli (@('rename','preview','--path','Screenshots')+$common)
 Assert ($run.code -eq 0 -and $run.data.result.count -eq 3) 'rename preview proposes the three screenshots'
 $planId=[string]$run.data.result.id
 $run=Invoke-Cli (@('plan','apply','--id',$planId,'--yes')+$common)
 Assert ($run.code -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $files 'Screenshots\Screenshot_2026-10-28_141502.png'))) 'plan apply --yes renamed them'
 $run=Invoke-Cli (@('plan','undo','--yes')+$common)
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $files 'Screenshots\Screenshot_2026-10-28_141502.png'))) 'plan undo --yes restored them'
 Assert (@(Get-ChildItem -LiteralPath $files -Recurse -File).Count -eq 10) 'all 10 files are still there'
 Pass 'The walkthrough commands run on the synthetic workspace: index, search, duplicates, rename preview, apply, undo'

 # --- state landed in the demo folder and nowhere else ----------------------------------------------
 Assert ((Test-Path -LiteralPath (Join-Path $data 'State\workspaces')) -and @(Get-ChildItem -LiteralPath (Join-Path $data 'State\workspaces') -Recurse -File).Count -ge 3) 'index, plan and journal are under <data>\State\workspaces'
 Assert (@(Get-ChildItem -LiteralPath (Join-Path $data 'Logs') -Filter 'cli-*.jsonl' -File).Count -eq 1) 'the log is under <data>\Logs'
 Assert ($before -ceq (Get-RealStateSnapshot)) 'the real %LOCALAPPDATA%\Bowerbird state was not touched'
 Pass 'State and logs are in the data folder; the real %LOCALAPPDATA%\Bowerbird is unchanged'

 # --- the environment variable, and the option beating it -------------------------------------------
 $envData=Join-Path $work 'envdata'
 $saved=$env:BOWERBIRD_DATA_DIR
 try{
  $env:BOWERBIRD_DATA_DIR=$envData
  $run=Invoke-Cli @('status','show','--root',$files)
  Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $envData 'Logs'))) 'BOWERBIRD_DATA_DIR alone redirects the log'
  $other=Join-Path $work 'optiondata'
  $run=Invoke-Cli @('status','show','--root',$files,'--data-dir',$other)
  Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $other 'Logs')) -and @(Get-ChildItem -LiteralPath (Join-Path $envData 'Logs') -Filter 'cli-*.jsonl').Count -eq 1) '--data-dir wins over the variable'
  $run=Invoke-Cli @('status','show','--root',$files,'--data-dir')
  Assert ($run.code -eq 2) '--data-dir without a value is a usage error'
 }finally{$env:BOWERBIRD_DATA_DIR=$saved}
 Assert ($before -ceq (Get-RealStateSnapshot)) 'still nothing under the real %LOCALAPPDATA%\Bowerbird'
 Pass 'BOWERBIRD_DATA_DIR redirects on its own; --data-dir wins; a missing value exits 2'
 Write-Host ("PASS: Bowerbird data folder override ($script:passed groups)") -ForegroundColor Green
 exit 0
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
