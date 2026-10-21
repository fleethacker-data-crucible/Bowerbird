#requires -Version 5.1
<#
 Integration check for Bowerbird Studio's actual HTTP APIs.
 Creates a disposable workspace and starts/stops a localhost server.
 Run: powershell.exe -NoProfile -File .\Tests\StudioIntegration.ps1
#>
[CmdletBinding()]param([ValidateSet('Auto','HttpListener','Tcp')][string]$Transport='Tcp')
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
 [IO.File]::WriteAllBytes((Join-Path $work 'Screenshot_2026-10-21_123456.png'),[Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAwAAAAMCAIAAADZF8uwAAAAFUlEQVR4nGP8z0AYMBGhZlQR3RUBAM/gARe7TQcrAAAAAElFTkSuQmCC'))
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
 $token=[uri]::UnescapeDataString(($uri.Query.TrimStart('?') -split '=')[1])
 $base="http://127.0.0.1:$port/api/"
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
 if(Test-Path $stdout){Write-Host (Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue)}
 exit 1
}finally{
 if($process -and -not $process.HasExited){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue}
 Start-Sleep -Milliseconds 150
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}