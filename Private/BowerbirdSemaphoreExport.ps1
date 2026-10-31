#requires -Version 5.1
# Export the index and the move history as flat JSON records that Semaphore reads as a data source
# (Data > Add data > a JSON file with one list of flat records). Format: docs\SEMAPHORE-EXPORT.md.
# Read-only: it never touches the user's files. File text is not exported, only metadata.
# Uses the caller's $script:AllowedRoot.
$script:BowerbirdExportSchema='bowerbird.export/1'

function ConvertTo-BowerbirdExportPath([string]$Full){
 # Workspace-relative with forward slashes. A path outside the workspace keeps only its file name.
 if([string]::IsNullOrEmpty($Full)){return ''}
 try{
  $root=$script:AllowedRoot.TrimEnd([char]92,[char]47)+[IO.Path]::DirectorySeparatorChar
  $full=[IO.Path]::GetFullPath($Full)
  if($full.StartsWith($root,[StringComparison]::OrdinalIgnoreCase)){return $full.Substring($root.Length).Replace([string][char]92,'/')}
  return [IO.Path]::GetFileName($full)
 }catch{return ''}
}
function Split-BowerbirdExportPath([string]$Relative){
 $slash=$Relative.LastIndexOf('/')
 if($slash -lt 0){return @{name=$Relative;folder=''}}
 return @{name=$Relative.Substring($slash+1);folder=$Relative.Substring(0,$slash)}
}
function Get-BowerbirdSemaphoreIndexRecords($Index){
 $records=New-Object Collections.Generic.List[object]
 foreach($file in @($Index.Files)){
  $path=ConvertTo-BowerbirdExportPath ([string]$file.Path)
  $parts=Split-BowerbirdExportPath $path
  $category=if($file.PSObject.Properties['Category']){[string]$file.Category}else{''}
  $text=[string]$file.Text
  $records.Add([ordered]@{
   path=$path;name=[string]$file.Name;folder=$parts.folder;extension=([string]$file.Extension).ToLowerInvariant();category=$category
   size_bytes=[long]$file.Size;modified_utc=[string]$file.ModifiedUtc;sha256=([string]$file.SHA256).ToLowerInvariant()
   text_chars=$text.Length;error=[string]$file.Error
  })
 }
 return @($records.ToArray())
}
function Get-BowerbirdSemaphoreHistoryRecords([string]$JournalPath){
 # The current journal, plus the earlier runs Invoke-BowerbirdPlan copied to history\ before each new run.
 $files=New-Object Collections.Generic.List[object]
 $historyDir=Join-Path (Split-Path -Parent $JournalPath) 'history'
 if(Test-Path -LiteralPath $historyDir -PathType Container){
  foreach($item in (Get-ChildItem -LiteralPath $historyDir -Filter 'journal-*.json' -File -ErrorAction SilentlyContinue)){$files.Add(@{Path=$item.FullName;Archived=$true})}
 }
 if(Test-Path -LiteralPath $JournalPath -PathType Leaf){$files.Add(@{Path=$JournalPath;Archived=$false})}
 $records=New-Object Collections.Generic.List[object]
 $seen=New-Object 'System.Collections.Generic.HashSet[string]'
 foreach($item in $files){
  try{$raw=[IO.File]::ReadAllText($item.Path)|ConvertFrom-Json}catch{continue}
  if($null -eq $raw){continue}
  $entries=if($null -ne $raw.PSObject.Properties['Entries']){@($raw.Entries)}else{@($raw)}
  $runId=if($null -ne $raw.PSObject.Properties['Id']){[string]$raw.Id}else{''}
  $created=if($null -ne $raw.PSObject.Properties['CreatedUtc']){[string]$raw.CreatedUtc}else{''}
  foreach($entry in $entries){
   if($null -eq $entry -or $null -eq $entry.PSObject.Properties['Source']){continue}
   $source=ConvertTo-BowerbirdExportPath ([string]$entry.Source)
   $destination=ConvertTo-BowerbirdExportPath ([string]$entry.Destination)
   $key=($runId,$source,$destination,[string]$entry.Status,[string]$entry.At) -join '|'
   if(-not $seen.Add($key)){continue}
   $from=Split-BowerbirdExportPath $source;$to=Split-BowerbirdExportPath $destination
   $records.Add([ordered]@{
    run_id=$runId;created_utc=$created;moved_utc=[string]$entry.At;status=[string]$entry.Status
    source=$source;destination=$destination;source_name=$from.name;destination_name=$to.name
    source_folder=$from.folder;destination_folder=$to.folder
    sha256=([string]$entry.SHA256).ToLowerInvariant();error=[string]$entry.Error;archived=[bool]$item.Archived
   })
  }
 }
 return @($records.ToArray()|Sort-Object @{Expression={$_.created_utc}},@{Expression={$_.moved_utc}})
}
function New-BowerbirdSemaphoreExport {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Kind,[string]$IndexPath,[string]$JournalPath)
 switch($Kind){
  'index' {
   if(-not (Test-Path -LiteralPath $IndexPath)){throw 'Build an index first'}
   $records=@(Get-BowerbirdSemaphoreIndexRecords ([IO.File]::ReadAllText($IndexPath)|ConvertFrom-Json))
   if($records.Count -eq 0){throw 'The index has no files to export'}
  }
  'history' {
   $records=@(Get-BowerbirdSemaphoreHistoryRecords $JournalPath)
   if($records.Count -eq 0){throw 'No move history yet'}
  }
  default {throw 'kind must be index or history'}
 }
 # Semaphore reads one list of flat records under "records"; every other field is a plain value, so no
 # second list can make the file ambiguous.
 return [ordered]@{
  schema=$script:BowerbirdExportSchema;kind=$Kind;exportedAt=[DateTime]::UtcNow.ToString('o')
  workspace=(Split-Path -Leaf $script:AllowedRoot.TrimEnd([char]92,[char]47));count=$records.Count;records=$records
 }
}
