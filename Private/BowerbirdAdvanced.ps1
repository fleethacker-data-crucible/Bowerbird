#requires -Version 5.1
<#
 Extended local analysis for Bowerbird Studio. No third-party dependencies.
 This module deliberately does not call any cloud service. Text stored in the index
 remains on disk; index a test/approved workspace only.
#>
function Get-BowerbirdCategory {
 [CmdletBinding()]param([string]$Extension,[string]$Name)
 $ext=([string]$Extension).ToLowerInvariant()
 $categories=@{
  Image=@('.png','.jpg','.jpeg','.gif','.bmp','.webp','.tif','.tiff','.svg')
  Video=@('.mp4','.mov','.avi','.mkv','.webm','.wmv')
  Audio=@('.mp3','.wav','.flac','.aac','.ogg','.m4a')
  Document=@('.pdf','.docx','.doc','.rtf','.txt','.md','.odt')
  Spreadsheet=@('.xlsx','.xls','.csv','.tsv','.ods')
  Presentation=@('.pptx','.ppt','.odp')
  Archive=@('.zip','.7z','.rar','.tar','.gz')
  Code=@('.ps1','.psm1','.psd1','.js','.ts','.tsx','.jsx','.py','.cs','.java','.go','.rs','.sql','.html','.css','.json','.yaml','.yml','.xml','.sh')
 }
 foreach($category in $categories.Keys){if($categories[$category] -contains $ext){return $category}}
 if($Name -match '(?i)(screenshot|screen.?shot|snip|capture)'){return 'Image'}
 return 'Other'
}
function Get-BowerbirdPdfText {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000)
 # Lightweight PDF text best-effort. Doesn't pretend to decode all font encodings.
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length -gt 20971520){return ''}
 $latin=[Text.Encoding]::GetEncoding(28591)
 $raw=$latin.GetString($bytes)
 if(-not $raw.StartsWith('%PDF-')){return ''}
 $content=New-Object Text.StringBuilder
 # Uncompressed text streams and zlib FlateDecode are supported.
 $segments=[regex]::Matches($raw,'(?s)(?<dict><<.{0,3000}?>>)\s*stream\r?\n(?<data>.*?)\r?\n?endstream')
 foreach($segment in $segments){
  if($content.Length -ge $MaxCharacters){break}
  $data=$segment.Groups['data'].Value
  if($segment.Groups['dict'].Value -match '/FlateDecode'){
   try{
    $compressed=$latin.GetBytes($data)
    if($compressed.Length -lt 6){continue}
    $compressedStream=New-Object IO.MemoryStream(,$compressed)
    $compressedStream.Position=2
    $deflate=New-Object IO.Compression.DeflateStream($compressedStream,[IO.Compression.CompressionMode]::Decompress,$false)
    $out=New-Object IO.MemoryStream
    try{
     $buf=New-Object byte[] 8192
     while(($count=$deflate.Read($buf,0,$buf.Length)) -gt 0){
      $out.Write($buf,0,$count)
      if($out.Length -gt 2097152){break}
     }
     $data=$latin.GetString($out.ToArray())
    } finally {$deflate.Dispose();$out.Dispose();$compressedStream.Dispose()}
   }catch{continue}
  }
  foreach($block in [regex]::Matches($data,'(?s)\bBT\b(.*?)\bET\b')){
   foreach($value in [regex]::Matches($block.Groups[1].Value,'\((?<text>(?:\\.|[^\\)])*)\)')){
    $t=$value.Groups['text'].Value
    $t=$t.Replace('\(','(').Replace('\)',')').Replace('\n',' ').Replace('\r',' ').Replace('\t',' ').Replace('\\','\')
    [void]$content.Append($t);[void]$content.Append(' ')
    if($content.Length -ge $MaxCharacters){break}
   }
  }
 }
 $value=$content.ToString()
 return $value.Substring(0,[Math]::Min($MaxCharacters,$value.Length))
}
function Get-BowerbirdExtendedText {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000,[switch]$EnableExternalOcr)
 $ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
 if($ext -eq '.pdf'){return Get-BowerbirdPdfText -Path $Path -MaxCharacters $MaxCharacters}
 if($EnableExternalOcr -and @('.png','.jpg','.jpeg','.bmp','.tif','.tiff') -contains $ext){
  $ocr=Get-Command 'tesseract.exe' -ErrorAction SilentlyContinue
  if($ocr){
   $info=New-Object Diagnostics.ProcessStartInfo
   $info.FileName=$ocr.Source;$info.Arguments=('"'+$Path.Replace('"','')+'" stdout')
   $info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
   $process=[Diagnostics.Process]::Start($info)
   try{
    $result=$process.StandardOutput.ReadToEnd()
    if(-not $process.WaitForExit(15000)){try{$process.Kill()}catch{};throw 'OCR process timed out'}
    return $result.Substring(0,[Math]::Min($MaxCharacters,$result.Length))
   }finally{$process.Dispose()}
  }
 }
 return Get-BowerbirdText -Path $Path -MaxCharacters $MaxCharacters
}
function New-BowerbirdSmartIndex {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$Path,[switch]$Recurse,[switch]$IncludeContent,
  [switch]$EnableExternalOcr,[ValidateRange(1000,500000)][int]$MaxTextCharacters=60000,
  [ValidateRange(1,100000)][int]$MaxFiles=20000
 )
 $folder=(Resolve-Path -LiteralPath $Path).ProviderPath
 if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw 'Root is not a directory'}
 $files=New-Object Collections.Generic.List[object]
 $opts=@{LiteralPath=$folder;File=$true;ErrorAction='SilentlyContinue';Force=$true}
 if($Recurse){$opts.Recurse=$true}
 foreach($file in (Get-ChildItem @opts | Select-Object -First $MaxFiles)){
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){continue}
  # Traversal can reach children of directory junctions; verify every ancestor.
  $part=$file.Directory
  $unsafe=$false
  while($part -and $part.FullName.Length -ge $folder.Length){
   if(($part.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$unsafe=$true;break}
   if($part.FullName -ieq $folder){break}
   $part=$part.Parent
  }
  if($unsafe){continue}
  $text='';$hash='';$visual='';$err=''
  if($IncludeContent){try{$text=Get-BowerbirdExtendedText -Path $file.FullName -MaxCharacters $MaxTextCharacters -EnableExternalOcr:$EnableExternalOcr}catch{$err=$_.Exception.Message}}
  try{$hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256 -ErrorAction Stop).Hash}catch{$err=$_.Exception.Message}
  if(@('.png','.jpg','.jpeg','.bmp','.gif','.tif','.tiff') -contains $file.Extension.ToLowerInvariant()){
   try{$visual=Get-BowerbirdImageHash -Path $file.FullName}catch{$err=$_.Exception.Message}
  }
  $files.Add([pscustomobject]@{
   Path=$file.FullName;Name=$file.Name;Extension=$file.Extension;Category=(Get-BowerbirdCategory $file.Extension $file.Name)
   Size=$file.Length;ModifiedUtc=$file.LastWriteTimeUtc.ToString('o')
   SHA256=$hash;VisualHash=$visual;Text=$text;Error=$err
  })
 }
 return [pscustomobject]@{
  SchemaVersion=2;Root=$folder;IndexedUtc=[DateTime]::UtcNow.ToString('o')
  IncludesContent=[bool]$IncludeContent;IncludesExternalOcr=[bool]$EnableExternalOcr
  Files=@($files.ToArray())
 }
}
function Search-BowerbirdIndex {
 [CmdletBinding()]param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$Query,[ValidateRange(1,500)][int]$Top=50)
 $terms=@([regex]::Matches($Query.ToLowerInvariant(),'[\p{L}\p{N}_]{2,}')|ForEach-Object {$_.Value}|Select-Object -Unique)
 if(-not $terms.Count){return @()}
 $docs=@($Index.Files);$n=[Math]::Max(1,$docs.Count)
 $termSet=@{};foreach($t in $terms){$termSet[$t]=0}
 $vectors=New-Object Collections.Generic.List[object];$lengthSum=0.0
 foreach($doc in $docs){
  $counts=@{};$name=[string]$doc.Name
  $content=($name+' '+[string]$doc.Text).ToLowerInvariant()
  $wordCount=0
  foreach($m in [regex]::Matches($content,'[\p{L}\p{N}_]{2,}')){
   $wordCount++
   $word=$m.Value
   if($termSet.ContainsKey($word)){$counts[$word]=1+[int]$counts[$word]}
  }
  foreach($word in $counts.Keys){$termSet[$word]++}
  $lengthSum+=$wordCount
  $vectors.Add([pscustomobject]@{Doc=$doc;Counts=$counts;Length=$wordCount})
 }
 $avg=[Math]::Max(1.0,$lengthSum/$n)
 $result=New-Object Collections.Generic.List[object]
 foreach($v in $vectors){
  $score=0.0
  foreach($word in $terms){
   $tf=[int]$v.Counts[$word];if($tf -eq 0){continue}
   $df=[int]$termSet[$word]
   $idf=[Math]::Log(1.0+($n-$df+0.5)/($df+0.5))
   $score+=$idf*($tf*2.2)/($tf+1.2*(0.25+0.75*$v.Length/$avg))
   if($v.Doc.Name.ToLowerInvariant().Contains($word)){$score+=1.8}
  }
  if($score -gt 0){
   $snippet=[string]$v.Doc.Text
   if($snippet.Length -gt 200){$snippet=$snippet.Substring(0,200)}
   $result.Add([pscustomobject]@{Path=$v.Doc.Path;Name=$v.Doc.Name;Score=[Math]::Round($score,3);Snippet=$snippet;Category=$v.Doc.Category})
  }
 }
 return @($result.ToArray()|Sort-Object Score -Descending|Select-Object -First $Top)
}
function Find-BowerbirdRelatedFiles {
 [CmdletBinding()]param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$Path,[int]$Top=20)
 $target=@($Index.Files|Where-Object {$_.Path -ieq $Path}|Select-Object -First 1)
 if(-not $target.Count){throw 'Selected file is not in the current index'}
 $stop='the','and','for','with','from','this','that','have','into','html','file','json','code','text'
 function Get-Terms($File){
  $map=@{}
  foreach($m in [regex]::Matches(([string]$File.Name+' '+[string]$File.Text).ToLowerInvariant(),'[\p{L}\p{N}_]{3,}')){
   if($stop -contains $m.Value){continue}
   $map[$m.Value]=1
  }
  return $map
 }
 $a=Get-Terms $target[0]
 $results=foreach($file in $Index.Files){
  if($file.Path -ieq $Path){continue}
  $b=Get-Terms $file
  $intersection=0
  foreach($term in $a.Keys){if($b.ContainsKey($term)){$intersection++}}
  $union=$a.Count+$b.Count-$intersection
  if($intersection -gt 0 -and $union -gt 0){
   [pscustomobject]@{Path=$file.Path;Name=$file.Name;Score=[Math]::Round(($intersection/$union),3);Category=$file.Category}
  }
 }
 return @($results|Sort-Object Score -Descending|Select-Object -First $Top)
}
function Get-BowerbirdInsights {
 [CmdletBinding()]param([Parameter(Mandatory)]$Index)
 $files=@($Index.Files);$bytes=0L
 foreach($f in $files){$bytes+=[long]$f.Size}
 $categories=@($files|Group-Object Category|Sort-Object Count -Descending|ForEach-Object {[pscustomobject]@{name=if($_.Name){$_.Name}else{'Other'};count=$_.Count}})
 $withErrors=@($files|Where-Object {$_.Error}).Count
 $duplicateGroups=@(Find-BowerbirdDuplicates -Index $Index -Mode Exact)
 return [pscustomobject]@{files=$files.Count;bytes=$bytes;categories=$categories;errors=$withErrors;duplicateGroups=$duplicateGroups.Count;contentIndexed=[bool]$Index.IncludesContent;lastIndexed=$Index.IndexedUtc}
}