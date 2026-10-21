#requires -Version 5.1
<#
 Integration check for Bowerbird Studio's actual HTTP APIs.
 Creates a disposable workspace and starts/stops a localhost server.
 Run: powershell.exe -NoProfile -File .\Tests\StudioIntegration.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdStudioTest_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -Force|Out-Null
$stdout=Join-Path $work 'stdout.txt';$stderr=Join-Path $work 'stderr.txt'
$server=Join-Path $repo 'Start-BowerbirdStudio.ps1'
$port=Get-Random -Minimum 22000 -Maximum 45000
$process=$null
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
try{
 [IO.File]::WriteAllText((Join-Path $work 'first.txt'),'unique apple bowerbird analysis')
 Copy-Item (Join-Path $work 'first.txt') (Join-Path $work 'second.txt')
 [IO.File]::WriteAllText((Join-Path $work 'third.ps1'),'Write-Output test')
 $arguments="-NoProfile -NonInteractive -File ""$server"" -Root ""$work"" -Port $port -NoBrowser"
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
 $token=[uri]::UnescapeDataString(($uri.Query.TrimStart('?') -split '=')[1])
 $base="http://127.0.0.1:$port/api/"
 $headers=@{'X-Bowerbird-Token'=$token}
 function Call([string]$route,$value){
  $body=ConvertTo-Json -InputObject $value -Depth 10 -Compress
  return Invoke-RestMethod -Method Post -Uri ($base+$route) -Headers $headers -ContentType 'application/json' -Body $body -TimeoutSec 30
 }
 $status=Call 'status' @{}
 Assert $status.ok 'Status endpoint'
 Assert (-not $status.cloudAI) 'Cloud AI must be off by default'
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
 $rules=@(@{Name='Text';Extension=@('.txt');Folder='Text'})
 $plan=Call 'plan' @{destination='Organized';rules=$rules}
 Assert ($plan.count -ge 2) 'Organization preview'
 $apply=Call 'apply' @{confirm='APPLY'}
 Assert ((Test-Path (Join-Path $work 'Organized\Text\first.txt'))) 'Apply move'
 $undo=Call 'undo' @{confirm='UNDO'}
 Assert ((Test-Path (Join-Path $work 'first.txt'))) 'Undo move'
 # A blocked traversal must return HTTP 400; no file contents should leave the workspace.
 $blocked=$false
 try{$null=Call 'files' @{path='..\Windows'}}catch{$blocked=$true}
 Assert $blocked 'Traversal must be blocked'
 # The streaming endpoint should be unavailable unless explicitly allowed.
 $blocked=$false
 try{$null=Call 'stream' @{prompt='hello'}}catch{$blocked=$true}
 Assert $blocked 'Cloud requests should be disabled'
 Write-Host 'PASS: Bowerbird Studio localhost integration (browse, index, search, duplicates, agents, plan, apply, undo, isolation)' -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 if(Test-Path $stderr){Write-Host (Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue)}
 exit 1
}finally{
 if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Start-Sleep -Milliseconds 150
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}