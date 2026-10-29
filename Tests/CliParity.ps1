#requires -Version 5.1
<#
 CLI/API parity for Bowerbird (docs\CLI.md): every UI route has a command, every command route is in
 the dispatcher, and the CLI keeps its output contract. Runs the CLI in a disposable workspace.
 Run: powershell.exe -NoProfile -File .\Tests\CliParity.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$cli=Join-Path $repo 'Start-BowerbirdCli.ps1'
$launcher=Join-Path $repo 'Start-Bowerbird-Console.bat'
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdCliTest_'+[guid]::NewGuid().ToString('N'))
$space=Join-Path $work 'space'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function Invoke-Cli([string[]]$Arguments){
 # The CLI writes usage text to stderr; under Stop, PowerShell 5.1 would throw on it.
 $ErrorActionPreference='Continue'
 $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments 2>$null
 return @{code=$LASTEXITCODE;text=(@($output) -join [Environment]::NewLine)}
}
function Invoke-CliJson([string[]]$Arguments){
 $run=Invoke-Cli ($Arguments+@('--json','--root',$space,'--local-dev'))
 $run.data=$run.text|ConvertFrom-Json
 return $run
}
try{
 New-Item -ItemType Directory -Path $space -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $space 'first.txt'),'unique apple bowerbird analysis')
 Copy-Item (Join-Path $space 'first.txt') (Join-Path $space 'second.txt')
 [IO.File]::WriteAllText((Join-Path $space 'third.ps1'),'Write-Output test')

 # Static checks: the registry against the UI and the dispatcher.
 . (Join-Path $repo 'Private\BowerbirdCommands.ps1')
 $registry=@(Get-BowerbirdCommandRegistry)
 $routes=@($registry|ForEach-Object {$_.route})
 $uiRoutes=New-Object Collections.Generic.HashSet[string]
 foreach($file in Get-ChildItem (Join-Path $repo 'Web') -Filter '*.js'){
  $source=[IO.File]::ReadAllText($file.FullName)
  foreach($pattern in @("(?:api|call)\(\s*'([a-z][a-z/-]*)'","'/api/([a-z][a-z/-]*)'","'(workspace/[a-z]+)'")){
   foreach($match in [regex]::Matches($source,$pattern)){$null=$uiRoutes.Add('/api/'+$match.Groups[1].Value)}
  }
 }
 # Served by the request loop itself, not the dispatcher: tab presence, End session, binary media, SSE.
 $serverOnly=@('/api/heartbeat','/api/session/stop','/api/media','/api/stream')
 Assert ($uiRoutes.Count -ge 20) ('UI routes found: '+$uiRoutes.Count)
 foreach($route in $uiRoutes){
  if($serverOnly -contains $route){continue}
  Assert ($routes -contains $route) ('UI route has a command: '+$route)
 }
 Pass ('Every UI route has a command ('+($uiRoutes.Count-$serverOnly.Count)+' routes; '+$serverOnly.Count+' server-only routes exempt)')
 $api=[IO.File]::ReadAllText((Join-Path $repo 'Private\BowerbirdApi.ps1'))
 $dispatch=$api.Substring($api.IndexOf('function Invoke-Api'))
 $dispatched=@([regex]::Matches($dispatch,"(?m)^  '(/api/[a-z/-]+)' \{")|ForEach-Object {$_.Groups[1].Value})
 foreach($route in $routes){Assert ($dispatched -contains $route) ('Command route is in the dispatcher: '+$route)}
 foreach($route in $dispatched){Assert ($routes -contains $route) ('Dispatcher route has a command: '+$route)}
 Pass ('Every command route is in the dispatcher and back ('+$dispatched.Count+' routes)')
 foreach($command in $registry){Assert ($command.name -cmatch '^bowerbird [a-z-]+ [a-z-]+$') ('Command name form: '+$command.name)}
 Assert (@($registry|ForEach-Object {$_.name}|Select-Object -Unique).Count -eq $registry.Count) 'Command names are unique'
 Pass ('Command names match "bowerbird <noun> <verb>" ('+$registry.Count+' commands)')

 # commands --json is self-describing.
 $run=Invoke-Cli @('commands','--json')
 Assert ($run.code -eq 0) 'commands --json exits 0'
 $catalog=$run.text|ConvertFrom-Json
 Assert ($catalog.schema -eq 'bowerbird.commands/1') 'commands --json schema'
 Assert (@($catalog.commands).Count -eq $registry.Count) 'commands --json lists every command'
 $first=@($catalog.commands)[0]
 foreach($field in @('name','route','summary','inputs','destructive','needs')){Assert ($null -ne $first.PSObject.Properties[$field]) ('Command entry has '+$field)}
 $plain=Invoke-Cli @('commands')
 Assert ($plain.code -eq 0 -and $plain.text -match 'bowerbird plan apply') 'commands prints a readable list'
 Pass 'commands --json has the bowerbird.commands/1 schema'

 # Destructive commands refuse without --yes (exit 2), and --dry-run runs nothing.
 $fill=@{path=$space;id='0';status='open'}
 foreach($command in @($registry|Where-Object {$_.destructive})){
  $words=@($command.name.Split(' ')[1..2])
  foreach($field in @($command.inputs|Where-Object {$_.required})){$words+=@(('--'+$field.flag),[string]$fill[$field.key])}
  $run=Invoke-CliJson $words
  Assert ($run.code -eq 2) ('Refused without --yes (exit 2): '+$command.name+' got '+$run.code)
  Assert (-not $run.data.ok -and $run.data.error -match '--yes') ('Refusal says why: '+$command.name)
  $dry=Invoke-CliJson ($words+@('--dry-run'))
  Assert ($dry.code -eq 0 -and $dry.data.result.dryRun -and $dry.data.result.route -eq $command.route) ('--dry-run shows the request: '+$command.name)
 }
 Pass ('Destructive commands refuse without --yes: '+(@($registry|Where-Object {$_.destructive}|ForEach-Object {$_.name}) -join ', '))

 # Result envelope, usage errors and runtime errors.
 $run=Invoke-CliJson @('status','show')
 Assert ($run.code -eq 0 -and $run.data.schema -eq 'bowerbird.result/1' -and $run.data.ok -and $run.data.command -eq 'bowerbird status show') 'status show --json envelope'
 Assert ($run.data.result.root -eq $space -and $run.data.result.transport -eq 'cli' -and -not $run.data.result.cloudAI) 'status show reports the workspace, cli transport and cloud AI off'
 Assert ((Invoke-CliJson @('status','nope')).code -eq 2) 'Unknown command exits 2'
 Assert ((Invoke-CliJson @('index','search')).code -eq 2) 'Missing required option exits 2'
 Assert ((Invoke-CliJson @('status','show','--bogus','1')).code -eq 2) 'Unknown option exits 2'
 $run=Invoke-CliJson @('index','search','--query','apple')
 Assert ($run.code -eq 1 -and -not $run.data.ok -and $run.data.error -match 'index') 'A command that needs an index fails with exit 1 and ok=false'
 $run=Invoke-CliJson @('files','list','--path','..\Windows')
 Assert ($run.code -eq 1) 'Traversal outside the workspace is refused'
 $run=Invoke-CliJson @('ai','ask','--prompt','hello')
 Assert ($run.code -eq 1 -and $run.data.error -match 'Cloud AI disabled') 'AI stays off without --allow-cloud-ai'
 Pass 'Result envelope bowerbird.result/1 and exit codes 0 / 1 / 2'

 # --out writes UTF-8 without a BOM.
 $outFile=Join-Path $work 'status.json'
 $run=Invoke-Cli @('status','show','--json','--root',$space,'--local-dev','--out',$outFile)
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath $outFile)) '--out wrote the file'
 $bytes=[IO.File]::ReadAllBytes($outFile)
 Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) '--out file has no BOM'
 Assert ((([Text.Encoding]::UTF8.GetString($bytes))|ConvertFrom-Json).schema -eq 'bowerbird.result/1') '--out file holds the envelope'
 Pass '--out writes UTF-8 without a BOM'

 # The same dispatcher as the browser, end to end across separate processes.
 $run=Invoke-CliJson @('index','build','--recurse','--include-content')
 Assert ($run.code -eq 0 -and $run.data.result.indexed -ge 3) 'index build'
 $run=Invoke-CliJson @('index','search','--query','bowerbird')
 Assert ($run.code -eq 0 -and @($run.data.result.items).Count -ge 2) 'index search after index build'
 $run=Invoke-CliJson @('index','duplicates')
 Assert ($run.code -eq 0 -and @($run.data.result.groups).Count -ge 1) 'index duplicates'
 $rulesFile=Join-Path $work 'rules.json'
 [IO.File]::WriteAllText($rulesFile,'[{"Name":"Text","Extension":[".txt"],"Folder":"Text"}]',(New-Object Text.UTF8Encoding $false))
 $run=Invoke-CliJson @('plan','create','--rules',('@'+$rulesFile),'--destination','Organized')
 Assert ($run.code -eq 0 -and $run.data.result.count -ge 2) 'plan create from a rules file'
 $planId=[string]$run.data.result.id
 $run=Invoke-CliJson @('plan','apply','--id','not-the-plan','--yes')
 Assert ($run.code -eq 1) 'plan apply refuses a stale plan id'
 $run=Invoke-CliJson @('plan','apply','--id',$planId,'--yes')
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $space 'Organized\Text\first.txt'))) 'plan apply --yes moves the files in a later process'
 $run=Invoke-CliJson @('plan','undo','--yes')
 Assert ($run.code -eq 0 -and (Test-Path -LiteralPath (Join-Path $space 'first.txt'))) 'plan undo --yes moves them back'
 Pass 'index build, search, plan create, apply and undo through the CLI'

 # The console launcher routes "<noun> <verb>" to the CLI and passes the exit code through.
 $null=& cmd.exe /d /c ('"'+$launcher+'" status nope --json') 2>$null
 Assert ($LASTEXITCODE -eq 2) ('Console launcher passes the CLI exit code (got '+$LASTEXITCODE+')')
 $text=(& cmd.exe /d /c ('"'+$launcher+'" commands --json') 2>$null) -join [Environment]::NewLine
 Assert ($LASTEXITCODE -eq 0 -and ($text|ConvertFrom-Json).schema -eq 'bowerbird.commands/1') 'Console launcher runs commands --json'
 Pass 'Start-Bowerbird-Console.bat routes commands to the CLI'
 Write-Host ("PASS: Bowerbird CLI/API parity ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
