#requires -Version 5.1
<#
 Semaphore data source export (Private\BowerbirdSemaphoreExport.ps1, docs\SEMAPHORE-EXPORT.md). Synthetic
 files in a temporary workspace; no network and no Semaphore needed. The checks mirror what Semaphore's JSON
 reader needs: one list of flat records, nothing nested, no nulls.
 Run: powershell.exe -NoProfile -File .\Tests\SemaphoreExport.ps1
#>
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$cli=Join-Path $repo 'Start-BowerbirdCli.ps1'
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdExportTest_'+[guid]::NewGuid().ToString('N'))
$space=Join-Path $work 'space'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function Invoke-CliJson([string[]]$Arguments){
 $ErrorActionPreference='Continue'
 $output=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $cli @Arguments --json --root $space --local-dev 2>$null
 $text=(@($output) -join [Environment]::NewLine)
 return @{code=$LASTEXITCODE;text=$text;data=($text|ConvertFrom-Json)}
}
function Get-DocSpec{
 $doc=[IO.File]::ReadAllText((Join-Path $repo 'docs\SEMAPHORE-EXPORT.md'))
 $match=[regex]::Match($doc,'(?s)```json semaphore-export\s*(.*?)```')
 Assert $match.Success 'docs\SEMAPHORE-EXPORT.md has the machine-readable block'
 return ($match.Groups[1].Value|ConvertFrom-Json)
}
function Test-ExportShape($Export,[string]$Kind,$Spec){
 # Top level: exactly the documented fields; exactly one list of objects, named records.
 $top=@($Export.PSObject.Properties|ForEach-Object {$_.Name})
 Assert ((@($Spec.top)|Sort-Object) -join ',' -ceq (($top|Sort-Object) -join ',')) ('top-level fields match the document: '+($top -join ','))
 Assert ($Export.schema -ceq 'bowerbird.export/1' -and $Export.kind -ceq $Kind) 'schema and kind'
 $lists=@($top|Where-Object {$Export.$_ -is [array] -and @($Export.$_).Count -gt 0 -and @($Export.$_|Where-Object {$_ -isnot [pscustomobject]}).Count -eq 0})
 Assert ($lists.Count -eq 1 -and $lists[0] -ceq 'records') 'records is the only list of objects, so Semaphore reads it unambiguously'
 Assert ($Export.count -eq @($Export.records).Count -and $Export.count -ge 1) 'count matches the records'
 $fields=$Spec.kinds.$Kind
 $names=@($fields.PSObject.Properties|ForEach-Object {$_.Name})
 foreach($record in @($Export.records)){
  $have=@($record.PSObject.Properties|ForEach-Object {$_.Name})
  Assert (($have -join ',') -ceq ($names -join ',')) ('record fields and order match the document: '+($have -join ','))
  foreach($name in $names){
   $value=$record.$name
   Assert ($null -ne $value) ('no null in '+$name)
   $type=switch($fields.$name){'string'{$value -is [string]}'number'{$value -is [int] -or $value -is [long] -or $value -is [double]}'boolean'{$value -is [bool]}}
   Assert $type ($name+' is a '+$fields.$name+' (got '+$value.GetType().Name+')')
  }
 }
}
try{
 New-Item -ItemType Directory -Path (Join-Path $space 'sub') -Force|Out-Null
 [IO.File]::WriteAllText((Join-Path $space 'first.txt'),'unique apple bowerbird analysis')
 [IO.File]::WriteAllText((Join-Path $space 'second.txt'),'second file with, a comma and "quotes"')
 [IO.File]::WriteAllText((Join-Path $space 'sub\third.ps1'),'Write-Output test')
 $spec=Get-DocSpec
 Assert ($spec.schema -ceq 'bowerbird.export/1') 'document names the schema'

 # --- paths: relative inside the workspace, file name only outside it ---------------------------------
 . (Join-Path $repo 'Private\BowerbirdSemaphoreExport.ps1')
 $script:AllowedRoot=$space
 Assert ((ConvertTo-BowerbirdExportPath (Join-Path $space 'sub\third.ps1')) -ceq 'sub/third.ps1') 'inside: relative with forward slashes'
 Assert ((ConvertTo-BowerbirdExportPath 'C:\Elsewhere\Private\secret.txt') -ceq 'secret.txt') 'outside: file name only, no absolute path leaks'
 $journal=Join-Path $work 'state\journal.json'
 New-Item -ItemType Directory -Path (Join-Path $work 'state\history') -Force|Out-Null
 $entry={param($s,$d,$st,$at)[ordered]@{Source=$s;Destination=$d;SHA256='ABCDEF';At=$at;Status=$st;Error=''}}
 [IO.File]::WriteAllText($journal,(ConvertTo-Json -Depth 6 ([ordered]@{SchemaVersion=2;Id='run2';CreatedUtc='2026-10-31T10:00:00Z';Entries=@(& $entry (Join-Path $space 'b.txt') (Join-Path $space 'Out\b.txt') 'Applied' '2026-10-31T10:00:01Z')})))
 [IO.File]::WriteAllText((Join-Path $work 'state\history\journal-1.json'),(ConvertTo-Json -Depth 6 ([ordered]@{SchemaVersion=2;Id='run1';CreatedUtc='2026-10-30T10:00:00Z';Entries=@(& $entry (Join-Path $space 'a.txt') 'C:\Elsewhere\a.txt' 'Undone' '2026-10-30T10:00:01Z')})))
 $rows=@(Get-BowerbirdSemaphoreHistoryRecords $journal)
 Assert ($rows.Count -eq 2 -and $rows[0].run_id -ceq 'run1' -and $rows[1].run_id -ceq 'run2') 'history is oldest first'
 Assert ($rows[0].archived -eq $true -and $rows[1].archived -eq $false) 'earlier runs are marked archived'
 Assert ($rows[0].destination -ceq 'a.txt' -and $rows[0].destination_folder -ceq '' -and $rows[1].destination -ceq 'Out/b.txt' -and $rows[1].destination_folder -ceq 'Out') 'history paths are split into name and folder'
 Assert ($rows[1].sha256 -ceq 'abcdef') 'hashes are lower case'
 Pass 'Paths are workspace-relative, nothing absolute leaks, history reads the journal and its archive'

 # --- the CLI, in separate processes ------------------------------------------------------------------
 $run=Invoke-CliJson @('export','semaphore','--kind','index')
 Assert ($run.code -eq 1 -and $run.data.error -match 'index') 'index export without an index fails with exit 1'
 $run=Invoke-CliJson @('export','semaphore','--kind','history')
 Assert ($run.code -eq 1 -and $run.data.error -match 'history') 'history export without a journal fails with exit 1'
 Assert ((Invoke-CliJson @('export','semaphore')).code -eq 2) 'a missing --kind is a usage error (exit 2)'
 $run=Invoke-CliJson @('index','build','--recurse','--include-content')
 Assert ($run.code -eq 0 -and $run.data.result.indexed -eq 3) 'index build'
 $run=Invoke-CliJson @('export','semaphore','--kind','nope')
 Assert ($run.code -eq 1) 'an unknown kind is refused'
 $run=Invoke-CliJson @('export','semaphore','--kind','index')
 Assert ($run.code -eq 0 -and $run.data.ok) 'index export'
 Test-ExportShape $run.data.result 'index' $spec
 $byName=@{};foreach($record in @($run.data.result.records)){$byName[$record.path]=$record}
 Assert ($byName.ContainsKey('first.txt') -and $byName.ContainsKey('sub/third.ps1')) 'paths are relative'
 Assert ($byName['first.txt'].size_bytes -eq 31 -and $byName['first.txt'].text_chars -gt 0 -and $byName['first.txt'].sha256 -cmatch '^[0-9a-f]{64}$') 'size, text length and a lower-case hash'
 Assert ($run.text -notmatch [regex]::Escape($space.Replace('\','\\'))) 'the workspace path does not appear in the export'
 Assert ($run.text -notmatch 'apple bowerbird') 'file text is not exported'
 Pass 'Index export: documented fields and types, flat records, relative paths, no file text'

 $run=Invoke-CliJson @('export','semaphore','--kind','index','--save')
 Assert ($run.code -eq 0 -and $run.data.result.count -eq 3 -and -not $run.data.result.PSObject.Properties['records']) '--save returns a summary, not the records'
 $saved=[string]$run.data.result.savedTo
 Assert ($saved -like '*exports\bowerbird-index.json' -and (Test-Path -LiteralPath $saved)) 'the file is in the state folder, exports\bowerbird-index.json'
 Assert (-not ($saved.StartsWith($space,[StringComparison]::OrdinalIgnoreCase))) 'nothing is written into the workspace'
 $bytes=[IO.File]::ReadAllBytes($saved)
 Assert (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'the file has no BOM'
 Test-ExportShape ([Text.Encoding]::UTF8.GetString($bytes)|ConvertFrom-Json) 'index' $spec
 Assert (@(Get-ChildItem -LiteralPath $space -Recurse -File).Count -eq 3) 'the workspace still holds exactly its three files'
 Pass '--save writes a BOM-free file in the state folder and nothing in the workspace'

 # --- history: two applied runs, the first one undone ------------------------------------------------
 $rules=Join-Path $work 'rules.json'
 [IO.File]::WriteAllText($rules,'[{"Name":"Text","Extension":[".txt"],"Folder":"Text"}]',(New-Object Text.UTF8Encoding $false))
 $run=Invoke-CliJson @('plan','create','--rules',('@'+$rules),'--destination','Organized')
 $run=Invoke-CliJson @('plan','apply','--id',[string]$run.data.result.id,'--yes')
 Assert ($run.code -eq 0) 'first plan applied'
 $run=Invoke-CliJson @('plan','undo','--yes')
 Assert ($run.code -eq 0) 'first plan undone'
 $run=Invoke-CliJson @('index','build','--recurse','--include-content')
 $run=Invoke-CliJson @('plan','create','--rules',('@'+$rules),'--destination','Moved')
 $run=Invoke-CliJson @('plan','apply','--id',[string]$run.data.result.id,'--yes')
 Assert ($run.code -eq 0) 'second plan applied'
 $run=Invoke-CliJson @('export','semaphore','--kind','history')
 Assert ($run.code -eq 0) 'history export'
 Test-ExportShape $run.data.result 'history' $spec
 $records=@($run.data.result.records)
 Assert (@($records|Where-Object {$_.archived}).Count -ge 2 -and @($records|Where-Object {-not $_.archived -and $_.status -eq 'Applied'}).Count -eq 2) 'the first run (archived) and the current run are both there'
 Assert (@($records|Where-Object {$_.archived -and $_.status -eq 'Undone'}).Count -eq 2) 'the undone run says Undone'
 Assert (@($records|Where-Object {$_.destination -ceq 'Moved/Text/first.txt' -or $_.destination -ceq 'Moved/Text/second.txt'}).Count -eq 2) 'destinations are workspace-relative'
 Pass 'History export: two runs (one archived and undone, one current), documented fields and types'
 Write-Host ("PASS: Bowerbird Semaphore export ($script:passed groups)") -ForegroundColor Green
 exit 0   # an earlier CLI call exits 1 on purpose; do not leak it as the script result
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
