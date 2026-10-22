#requires -Version 5.1
<#
 Integration check for Bowerbird Studio's actual HTTP APIs.
 Creates a disposable workspace and starts/stops a localhost server.
 Run: powershell.exe -NoProfile -File .\Tests\StudioIntegration.ps1
#>
[CmdletBinding()]param([ValidateSet('Auto','HttpListener','Tcp','CompiledTcp')][string]$Transport='Tcp',[switch]$SimulateCollision)
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdStudioTest_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force|Out-Null
$stdout=Join-Path $work 'stdout.txt';$stderr=Join-Path $work 'stderr.txt'
$server=Join-Path $repo 'Start-BowerbirdStudio.ps1'
$port=Get-Random -Minimum 22000 -Maximum 45000
$process=$null
$blocker=$null
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
try{
 [IO.File]::WriteAllText((Join-Path $work 'first.txt'),'unique apple bowerbird analysis')
 Copy-Item (Join-Path $work 'first.txt') (Join-Path $work 'second.txt')
 [IO.File]::WriteAllText((Join-Path $work 'third.ps1'),'Write-Output test')
 [IO.File]::WriteAllBytes((Join-Path $work 'Screenshot_2026-10-21_123456.png'),[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAFUlEQVR4nGP8z0AYMBGhZlQR3RUBAM/gARe7TQcrAAAAAElFTkSuQmCC'))
 if($SimulateCollision){
  if($Transport -notin @('Auto','Tcp')){throw 'Port collision test requires pure PowerShell transport'}
  $blocker=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $blocker.Start()
  $port=([Net.IPEndPoint]$blocker.LocalEndpoint).Port
 }
 $arguments="-NoProfile -NonInteractive -File ""$server"" -Root ""$work"" -Port $port -NoBrowser -Transport $Transport"
 $process=Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $session=$null
 for($attempt=0;$attempt -lt 60;$attempt++){
  Start-Sleep -Milliseconds 300
  if(Test-Path $stdout){
   $line=Get-Content -LiteralPath $stdout | Where-Object {$_ -like 'Session URL:*'} | Select-Object -First 1
   if($line){$session=([string]$line).Substring(13).Trim();break}
  }
  if($process.HasExited){throw ('Studio exited early: '+(Get-Content $stderr -Raw -ErrorAction SilentlyContinue))}
 }
 Assert (-not [string]::IsNullOrWhiteSpace($session)) 'Server startup URL'
 $uri=[uri]$session
 if($SimulateCollision){Assert ($uri.Port -ne $port) 'Port collision must select a different localhost port'}
 $port=$uri.Port
 $token=[uri]::UnescapeDataString(($uri.Query.TrimStart('?') -split '=')[1])
 $site="http://127.0.0.1:$port/"
 $base=$site+'api/'
 # Unlike prior versions, validate the browser page and assets, not API only.
 foreach($asset in @(@{path='';type='text/html';needle='BOWERBIRD'},@{path='app.js';type='javascript';needle='async function api'},@{path='style.css';type='text/css';needle='.shell'})){
  $response=Invoke-WebRequest -Uri ($site+$asset.path) -UseBasicParsing -TimeoutSec 20
  Assert ($response.StatusCode -eq 200) ('Browser asset HTTP 200: '+$asset.path)
  Assert ($response.Headers['Content-Type'] -match $asset.type) ('Browser asset Content-Type: '+$asset.path)
  Assert ($response.Content -match [regex]::Escape($asset.needle)) ('Browser asset contains expected content: '+$asset.path)
 }
 $headers=@{'X-Bowerbird-Token'=$token}
 function Call([string]$route,$value){
  $body=ConvertTo-Json -InputObject $value -Depth 10 -Compress
  try{return Invoke-RestMethod -Method Post -Uri ($base+$route) -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30}
  catch{
   $details=''
   try{$reader=New-Object IO.StreamReader($_.Exception.Response.GetResponseStream());$details=$reader.ReadToEnd();$reader.Dispose()}catch{}
   throw "Route /api/$route failed: $($_.Exception.Message) $details"
  }
 }
 $status=Call 'status' @{}
 Assert $status.ok 'Status endpoint'
 Assert ($status.port -eq $port) 'Returned port matches listener'
 Assert (-not $status.cloudAI) 'Cloud AI must be off by default'
 # Error and non-functionality reporting must work without any external account.
 $checks=Call 'diagnostics/health' @{}
 Assert $checks.ok 'Local diagnostics health route'
 Assert (@($checks.checks).Count -ge 4) 'Health returns independent checks'
 $diag=Call 'diagnostics' @{}
 Assert $diag.ok 'Redacted server log route'
 $missing="NONFUNCTIONAL_NOTE_DO_NOT_AUTO_EXPORT_5021"
 $feedback=Call 'feedback/create' @{
  kind='not-working';severity='high';feature='folder-picker'
  title='Folder selector did not respond';actual=$missing
  expected='Windows folder selection dialog should open';steps='Click Browse Folder'
  lastAction='browse-folder';requestId=''
 }
 Assert ($feedback.id -match '^[a-f0-9]{32}
 Assert ($files.items.Count -ge 3) 'File explorer'
 $index=Call 'index' @{path='.';recurse=$true;includeContent=$true;ocr=$false}
 Assert ($index.indexed -ge 3) 'Smart indexing'
 $search=Call 'search' @{query='bowerbird'}
 Assert ($search.items.Count -ge 2) 'Lexical search'
 $dups=Call 'duplicates' @{visual=$false}
 Assert ($dups.groups.Count -ge 1) 'Exact duplicate groups'
 $insights=Call 'insights' @{}
 Assert ($insights.files -ge 3) 'Insights'
 $agents=Call 'agents' @{agent='triage'}
 Assert ($agents.suggestions.Count -ge 1) 'Local agents'
 $related=Call 'related' @{path='first.txt'}
 Assert ($related.items.Count -ge 1) 'Related file discovery'
 $rename=Call 'rename-preview' @{path='.';recurse=$true;useVision=$false;maxVision=0}
 Assert ($rename.count -ge 1) 'Smart screenshot rename proposal'
 $mediaResult=Invoke-WebRequest -Method Post -Uri ($base+'media') -Headers $headers -UseBasicParsing -ContentType 'application/json' -Body (@{path='Screenshot_2026-10-21_123456.png'}|ConvertTo-Json) -TimeoutSec 15
 Assert ($mediaResult.Headers['Content-Type'] -match 'image/png') 'Local image preview'
 $rules=@(@{Name='Text';Extension=@('.txt');Folder='Text'})
 $plan=Call 'plan' @{destination='Organized';rules=$rules}
 Assert ($plan.count -ge 2) 'Organization preview'
 $apply=Call 'apply' @{confirm='APPLY';id=$plan.id}
 Assert ((Test-Path (Join-Path $work 'Organized\Text\first.txt'))) 'Apply move'
 $undo=Call 'undo' @{confirm='UNDO'}
 Assert ((Test-Path (Join-Path $work 'first.txt'))) 'Undo move'
 # Switching folders must isolate indexes and discard all pending move proposals.
 $planBeforeSwitch=Call 'plan' @{destination='Organized';rules=$rules}
 Assert ($planBeforeSwitch.count -ge 2) 'Pending plan exists before folder switch'
 $other=Join-Path $work 'AnotherScanFolder'
 [IO.Directory]::CreateDirectory($other)|Out-Null
 [IO.File]::WriteAllText((Join-Path $other 'OtherFolderOnly.txt'),'A separate workspace for GUI folder selection')
 $change=Call 'workspace/select' @{path=$other}
 Assert ($change.changed -and $change.root -ieq $other) 'Folder selector changes workspace'
 Assert (-not $change.indexExists) 'New folder must not reuse previous index'
 $now=Call 'status' @{}
 Assert ($now.root -ieq $other -and -not $now.indexExists) 'Status reports newly selected scan root'
 $contents=Call 'files' @{path='.'}
 Assert ($contents.items.Count -eq 1 -and $contents.items[0].name -eq 'OtherFolderOnly.txt') 'Explorer uses selected folder'
 $blocked=$false
 try{$null=Call 'search' @{query='bowerbird'}}catch{$blocked=$true}
 Assert $blocked 'Search must not reuse previous scan index'
 $blocked=$false
 try{$null=Call 'apply' @{confirm='APPLY';id=$planBeforeSwitch.id}}catch{$blocked=$true}
 Assert $blocked 'Cannot apply a previous folder plan'
 $otherIndex=Call 'index' @{path='.';recurse=$true;includeContent=$true}
 Assert ($otherIndex.indexed -eq 1) 'Re-index scans only new folder'
 $otherSearch=Call 'search' @{query='separate'}
 Assert ($otherSearch.items.Count -eq 1) 'New folder search uses new index'
 $blocked=$false
 try{$null=Call 'workspace/select' @{path='.'}}catch{$blocked=$true}
 Assert $blocked 'Relative folder selection is prohibited'
 $blocked=$false
 try{$null=Call 'workspace/select' @{path=(Join-Path $work 'DefinitelyMissingFolder')}}catch{$blocked=$true}
 Assert $blocked 'Unavailable folder selection is prohibited'
 $stillHere=Call 'status' @{}
 Assert ($stillHere.root -ieq $other) 'Invalid selection must not change workspace'
 $return=Call 'workspace/select' @{path=$work}
 Assert ($return.root -ieq $work -and $return.indexExists) 'Switching back restores original index without mixing workspaces'
 $blocked=$false
 try{$null=Call 'apply' @{confirm='APPLY';id=$planBeforeSwitch.id}}catch{$blocked=$true}
 Assert $blocked 'Returning to original folder does not revive old move plan'
 $firstAgain=Call 'files' @{path='.'}
 Assert (@($firstAgain.items|Where-Object {$_.name -eq 'first.txt'}).Count -eq 1) 'Original explorer state returns'
 Write-Host 'PASS: Folder switching isolates indexes, invalidates move plans and rejects invalid paths' -ForegroundColor Green
 # A blocked traversal must return HTTP 400; no file contents should leave the workspace.
 $blocked=$false
 try{$null=Call 'files' @{path='..\Windows'}}catch{$blocked=$true}
 Assert $blocked 'Traversal must be blocked'
 # The streaming endpoint should be unavailable unless explicitly allowed.
 $blocked=$false
 try{$null=Call 'stream' @{prompt='hello'}}catch{$blocked=$true}
 Assert $blocked 'Cloud requests should be disabled'
 Write-Host "PASS: Bowerbird Studio browser+API integration ($Transport, collision=$SimulateCollision, port=$port)" -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 if(Test-Path $stderr){Write-Host (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}
 if(Test-Path $stdout){Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
 exit 1
}finally{
 if($blocker){$blocker.Stop()}
 if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Start-Sleep -Milliseconds 150
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}) 'Issue has a generated local identifier'
 Assert ($feedback.status -eq 'open') 'Issue is open by default'
 $issues=Call 'feedback/list' @{}
 Assert (@($issues.issues|Where-Object {$_.id -eq $feedback.id}).Count -eq 1) 'Saved issue appears in local list'
 $summary=Call 'diagnostics/support' @{includeNotes=$false}
 $withoutNotes=$summary|ConvertTo-Json -Depth 15 -Compress
 Assert ($withoutNotes -notmatch $missing) 'Default support bundle omits manually entered issue notes'
 Assert ($withoutNotes -notmatch [regex]::Escape($work)) 'Default support bundle must omit root workspace path'
 Assert ($summary.environment.product -eq 'Bowerbird Studio') 'Support bundle has product and local runtime metadata'
 $withNotes=Call 'diagnostics/support' @{includeNotes=$true}
 Assert (($withNotes|ConvertTo-Json -Depth 15) -match $missing) 'Explicit export includes manually entered issue notes'
 $changedIssue=Call 'feedback/status' @{id=$feedback.id;status='resolved'}
 Assert ($changedIssue.status -eq 'resolved') 'Issue can be marked resolved'
 $issuesAgain=Call 'feedback/list' @{}
 Assert (@($issuesAgain.issues|Where-Object {$_.id -eq $feedback.id -and $_.status -eq 'resolved'}).Count -eq 1) 'Resolved status persists locally'
 $reopen=Call 'feedback/status' @{id=$feedback.id;status='open'}
 Assert ($reopen.status -eq 'open') 'Issue can be reopened'
 $blocked=$false
 try{$null=Call 'feedback/create' @{kind='invalid';severity='high';feature='explorer';title='fail';actual='no'}}catch{$blocked=$true}
 Assert $blocked 'Invalid report categories are rejected'
 $blocked=$false
 try{$null=Call 'feedback/status' @{id='../outside';status='resolved'}}catch{$blocked=$true}
 Assert $blocked 'Issue IDs cannot traverse directories'
 Write-Host 'PASS: Local feedback reports, issue lifecycle, health checks and default-redacted support export' -ForegroundColor Green
 $files=Call 'files' @{path='.'}
 Assert ($files.items.Count -ge 3) 'File explorer'
 $index=Call 'index' @{path='.';recurse=$true;includeContent=$true;ocr=$false}
 Assert ($index.indexed -ge 3) 'Smart indexing'
 $search=Call 'search' @{query='bowerbird'}
 Assert ($search.items.Count -ge 2) 'Lexical search'
 $dups=Call 'duplicates' @{visual=$false}
 Assert ($dups.groups.Count -ge 1) 'Exact duplicate groups'
 $insights=Call 'insights' @{}
 Assert ($insights.files -ge 3) 'Insights'
 $agents=Call 'agents' @{agent='triage'}
 Assert ($agents.suggestions.Count -ge 1) 'Local agents'
 $related=Call 'related' @{path='first.txt'}
 Assert ($related.items.Count -ge 1) 'Related file discovery'
 $rename=Call 'rename-preview' @{path='.';recurse=$true;useVision=$false;maxVision=0}
 Assert ($rename.count -ge 1) 'Smart screenshot rename proposal'
 $mediaResult=Invoke-WebRequest -Method Post -Uri ($base+'media') -Headers $headers -UseBasicParsing -ContentType 'application/json' -Body (@{path='Screenshot_2026-10-21_123456.png'}|ConvertTo-Json) -TimeoutSec 15
 Assert ($mediaResult.Headers['Content-Type'] -match 'image/png') 'Local image preview'
 $rules=@(@{Name='Text';Extension=@('.txt');Folder='Text'})
 $plan=Call 'plan' @{destination='Organized';rules=$rules}
 Assert ($plan.count -ge 2) 'Organization preview'
 $apply=Call 'apply' @{confirm='APPLY';id=$plan.id}
 Assert ((Test-Path (Join-Path $work 'Organized\Text\first.txt'))) 'Apply move'
 $undo=Call 'undo' @{confirm='UNDO'}
 Assert ((Test-Path (Join-Path $work 'first.txt'))) 'Undo move'
 # Switching folders must isolate indexes and discard all pending move proposals.
 $planBeforeSwitch=Call 'plan' @{destination='Organized';rules=$rules}
 Assert ($planBeforeSwitch.count -ge 2) 'Pending plan exists before folder switch'
 $other=Join-Path $work 'AnotherScanFolder'
 [IO.Directory]::CreateDirectory($other)|Out-Null
 [IO.File]::WriteAllText((Join-Path $other 'OtherFolderOnly.txt'),'A separate workspace for GUI folder selection')
 $change=Call 'workspace/select' @{path=$other}
 Assert ($change.changed -and $change.root -ieq $other) 'Folder selector changes workspace'
 Assert (-not $change.indexExists) 'New folder must not reuse previous index'
 $now=Call 'status' @{}
 Assert ($now.root -ieq $other -and -not $now.indexExists) 'Status reports newly selected scan root'
 $contents=Call 'files' @{path='.'}
 Assert ($contents.items.Count -eq 1 -and $contents.items[0].name -eq 'OtherFolderOnly.txt') 'Explorer uses selected folder'
 $blocked=$false
 try{$null=Call 'search' @{query='bowerbird'}}catch{$blocked=$true}
 Assert $blocked 'Search must not reuse previous scan index'
 $blocked=$false
 try{$null=Call 'apply' @{confirm='APPLY';id=$planBeforeSwitch.id}}catch{$blocked=$true}
 Assert $blocked 'Cannot apply a previous folder plan'
 $otherIndex=Call 'index' @{path='.';recurse=$true;includeContent=$true}
 Assert ($otherIndex.indexed -eq 1) 'Re-index scans only new folder'
 $otherSearch=Call 'search' @{query='separate'}
 Assert ($otherSearch.items.Count -eq 1) 'New folder search uses new index'
 $blocked=$false
 try{$null=Call 'workspace/select' @{path='.'}}catch{$blocked=$true}
 Assert $blocked 'Relative folder selection is prohibited'
 $blocked=$false
 try{$null=Call 'workspace/select' @{path=(Join-Path $work 'DefinitelyMissingFolder')}}catch{$blocked=$true}
 Assert $blocked 'Unavailable folder selection is prohibited'
 $stillHere=Call 'status' @{}
 Assert ($stillHere.root -ieq $other) 'Invalid selection must not change workspace'
 $return=Call 'workspace/select' @{path=$work}
 Assert ($return.root -ieq $work -and $return.indexExists) 'Switching back restores original index without mixing workspaces'
 $blocked=$false
 try{$null=Call 'apply' @{confirm='APPLY';id=$planBeforeSwitch.id}}catch{$blocked=$true}
 Assert $blocked 'Returning to original folder does not revive old move plan'
 $firstAgain=Call 'files' @{path='.'}
 Assert (@($firstAgain.items|Where-Object {$_.name -eq 'first.txt'}).Count -eq 1) 'Original explorer state returns'
 Write-Host 'PASS: Folder switching isolates indexes, invalidates move plans and rejects invalid paths' -ForegroundColor Green
 # A blocked traversal must return HTTP 400; no file contents should leave the workspace.
 $blocked=$false
 try{$null=Call 'files' @{path='..\Windows'}}catch{$blocked=$true}
 Assert $blocked 'Traversal must be blocked'
 # The streaming endpoint should be unavailable unless explicitly allowed.
 $blocked=$false
 try{$null=Call 'stream' @{prompt='hello'}}catch{$blocked=$true}
 Assert $blocked 'Cloud requests should be disabled'
 Write-Host "PASS: Bowerbird Studio browser+API integration ($Transport, collision=$SimulateCollision, port=$port)" -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 if(Test-Path $stderr){Write-Host (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}
 if(Test-Path $stdout){Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
 exit 1
}finally{
 if($blocker){$blocker.Stop()}
 if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Start-Sleep -Milliseconds 150
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}