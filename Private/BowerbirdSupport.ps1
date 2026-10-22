#requires -Version 5.1
# Bowerbird Diagnostics & Feedback — local-only support records.
# No network transmission. No content scanning. All issue text is operator-entered.
function Get-BowerbirdSafeDiagnosticText {
 [CmdletBinding()]param([AllowEmptyString()][string]$Value,[int]$Limit=400)
 $value=[string]$Value
 $value=$value -replace '(?i)(authorization|bearer|password|passwd|secret|api[_-]?key|token|credential)\s*[:=]\s*[^ \t,;&"''<>]+','$1=[REDACTED]'
 $value=$value -replace '(?i)https?://\S+','[URL REDACTED]'
 $value=$value -replace '(?i)(?:[A-Z]:\\|\\\\)[^\r\n\t"''<>|]+','[PATH REDACTED]'
 $value=$value -replace '(?i)session=[a-z0-9_\-]{8,}','session=[REDACTED]'
 $value=$value -replace '(?i)[a-z0-9_\-]{48,}','[LONG VALUE REDACTED]'
 $value=$value -replace '[\r\n\t]+',' '
 if($Limit -gt 0 -and $value.Length -gt $Limit){$value=$value.Substring(0,$Limit)+'…'}
 return $value
}
function Get-BowerbirdIssuesDirectory {
 $directory=Join-Path $script:LogDir 'Issues'
 [IO.Directory]::CreateDirectory($directory)|Out-Null
 return $directory
}
function Get-BowerbirdIssueFile([string]$Id){
 if($Id -notmatch '^[a-f0-9]{32}$'){throw 'Invalid issue identifier'}
 return (Join-Path (Get-BowerbirdIssuesDirectory) ($Id+'.json'))
}
function Save-BowerbirdIssueFile([string]$Path,$Issue){
 $directory=Split-Path -Parent $Path
 if(-not (Test-Path -LiteralPath $directory)){throw 'Issue storage directory missing'}
 $temporary=Join-Path $directory ([guid]::NewGuid().ToString('N')+'.tmp')
 try{
  $json=ConvertTo-Json -InputObject $Issue -Depth 7
  [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding $false))
  if(Test-Path -LiteralPath $Path){
   # Each edit overwrites only its own local feedback file; never workspace files.
   [IO.File]::Copy($temporary,$Path,$true)
   Remove-Item -LiteralPath $temporary -Force
  }else{[IO.File]::Move($temporary,$Path)}
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
function Test-BowerbirdIssueEnum([string]$Value,[string[]]$Options,[string]$Field){
 if($Options -notcontains $Value){throw "Invalid $Field"}
 return $Value
}
function ConvertTo-BowerbirdIssueField([string]$Value,[int]$Max,[string]$Field){
 if($Value.Length -gt $Max){throw "$Field exceeds $Max characters"}
 return $Value.Trim()
}
function New-BowerbirdFeedbackIssue($Body){
 $kind=Test-BowerbirdIssueEnum ([string]$Body.kind) @('error','not-working','wrong-result','performance','suggestion','other') 'issue type'
 $severity=Test-BowerbirdIssueEnum ([string]$Body.severity) @('low','medium','high','blocking') 'severity'
 $feature=Test-BowerbirdIssueEnum ([string]$Body.feature) @('explorer','folder-picker','index','search','duplicates','organize','rename','code','agents','assistant','integrations','diagnostics','startup','other') 'feature'
 $title=ConvertTo-BowerbirdIssueField ([string]$Body.title) 160 'Title'
 $actual=ConvertTo-BowerbirdIssueField ([string]$Body.actual) 2500 'Observed behavior'
 $expected=ConvertTo-BowerbirdIssueField ([string]$Body.expected) 1500 'Expected behavior'
 $steps=ConvertTo-BowerbirdIssueField ([string]$Body.steps) 2000 'Reproduction steps'
 if([string]::IsNullOrWhiteSpace($title)){throw 'Issue title is required'}
 if([string]::IsNullOrWhiteSpace($actual)){throw 'Describe what happened or which feature did not work'}
 $lastAction=([string]$Body.lastAction) -replace '[^a-zA-Z0-9_.:-]','_'
 if($lastAction.Length -gt 64){$lastAction=$lastAction.Substring(0,64)}
 $requestId=[string]$Body.requestId
 if($requestId -notmatch '^[a-f0-9]{12}$'){$requestId=''}
 $issue=[pscustomobject]@{
  schemaVersion=1;id=[guid]::NewGuid().ToString('N');createdUtc=[DateTime]::UtcNow.ToString('o')
  updatedUtc=[DateTime]::UtcNow.ToString('o');status='open'
  kind=$kind;severity=$severity;feature=$feature;title=$title
  actual=$actual;expected=$expected;steps=$steps
  lastAction=$lastAction;requestId=$requestId
 }
 $path=Get-BowerbirdIssueFile $issue.id
 Save-BowerbirdIssueFile -Path $path -Issue $issue
 Write-BowerbirdDiagnostic -Event 'ISSUE_CREATED' -Message ($kind+' '+$severity+' '+$feature+' id='+$issue.id)
 return $issue
}
function Get-BowerbirdFeedbackIssues([int]$MaxItems=100){
 $directory=Get-BowerbirdIssuesDirectory
 $results=New-Object 'System.Collections.Generic.List[object]'
 $files=@(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -ErrorAction SilentlyContinue|
  Sort-Object LastWriteTimeUtc -Descending|Select-Object -First ([Math]::Max(1,[Math]::Min($MaxItems,200))))
 foreach($file in $files){
  if($file.BaseName -notmatch '^[a-f0-9]{32}$'){continue}
  try{
   if($file.Length -gt 32768){continue}
   $entry=Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop|ConvertFrom-Json
   if($entry.id -eq $file.BaseName){$results.Add($entry)}
  }catch{continue}
 }
 return @($results.ToArray())
}
function Set-BowerbirdFeedbackStatus($Body){
 $id=[string]$Body.id
 $status=Test-BowerbirdIssueEnum ([string]$Body.status) @('open','resolved') 'issue status'
 $file=Get-BowerbirdIssueFile $id
 if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw 'Issue does not exist'}
 $entry=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
 if([string]$entry.id -cne $id){throw 'Stored issue identifier mismatch'}
 $entry.status=$status
 $entry.updatedUtc=[DateTime]::UtcNow.ToString('o')
 Save-BowerbirdIssueFile -Path $file -Issue $entry
 Write-BowerbirdDiagnostic -Event 'ISSUE_UPDATED' -Message ('status='+$status+' id='+$id)
 return @{ok=$true;id=$id;status=$status}
}
function Get-BowerbirdRecentDiagnostics([int]$Limit=200){
 $limit=[Math]::Max(1,[Math]::Min(400,$Limit))
 $lines=if(Test-Path -LiteralPath $script:LogFile){@(Get-Content -LiteralPath $script:LogFile -Tail $limit -ErrorAction SilentlyContinue)}else{@()}
 $items=New-Object 'System.Collections.Generic.List[object]'
 foreach($line in $lines){
  try{
   $e=$line|ConvertFrom-Json
   $event=[string]$e.event
   $route=[string]$e.route
   if($event -notmatch '^[a-zA-Z0-9_.:-]{1,60}$'){$event='UNCLASSIFIED'}
   if($route -notmatch '^/[a-zA-Z0-9_./:-]*$'){$route='[ROUTE REDACTED]'}
   $items.Add([pscustomobject]@{
    time=[string]$e.time;level=[string]$e.level
    event=$event;route=$route
    requestId=if([string]$e.requestId -match '^[a-f0-9]{12}$'){[string]$e.requestId}else{''}
    message=(Get-BowerbirdSafeDiagnosticText -Value ([string]$e.message))
   })
  }catch{continue}
 }
 return @($items.ToArray())
}
function Get-BowerbirdSupportSnapshot {
 [CmdletBinding()]param([switch]$IncludeNotes)
 $issues=@(Get-BowerbirdFeedbackIssues -MaxItems 100)
 if(-not $IncludeNotes){
  $issues=@($issues|ForEach-Object {
   [pscustomobject]@{id=$_.id;createdUtc=$_.createdUtc;status=$_.status;kind=$_.kind
    severity=$_.severity;feature=$_.feature;lastAction=$_.lastAction;requestId=$_.requestId}
  })
 }
 $events=@(Get-BowerbirdRecentDiagnostics -Limit 200)
 $severitySummary=@($events|Where-Object {$_.level -in @('ERROR','WARN')})
 return [pscustomobject]@{
  schemaVersion=2;generatedUtc=[DateTime]::UtcNow.ToString('o')
  privacyNotice='No credentials, tokens, file contents, or workspace paths are intentionally included. Review before sharing.'
  includeManualNotes=[bool]$IncludeNotes
  environment=[pscustomobject]@{
   product='Bowerbird Studio';version='2.3';powershell=$PSVersionTable.PSVersion.ToString()
   transport=$script:Session.GetType().Name;port=$script:CurrentPort
   osFamily='Windows';cloudEnabled=[bool]$script:CloudEnabled
   indexExists=(Test-Path -LiteralPath $script:IndexPath)
  }
  counts=[pscustomobject]@{serverEvents=$events.Count;warningsAndErrors=$severitySummary.Count;issues=$issues.Count}
  serverEvents=$events;issues=$issues
 }
}
