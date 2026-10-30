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
function ConvertFrom-BowerbirdPdfString {
 # A PDF literal string body (without the outer parentheses): \n \r \t \b \f, \( \) \\, \ddd octal, line continuation.
 param([string]$Text)
 $sb=New-Object Text.StringBuilder
 for($i=0;$i -lt $Text.Length;$i++){
  $c=$Text[$i]
  if($c -ne '\' -or $i+1 -ge $Text.Length){[void]$sb.Append($c);continue}
  $i++;$n=$Text[$i]
  switch -CaseSensitive ($n){
   'n'{[void]$sb.Append(' ')} 'r'{[void]$sb.Append(' ')} 't'{[void]$sb.Append(' ')} 'b'{} 'f'{}
   "`r"{if($i+1 -lt $Text.Length -and $Text[$i+1] -eq "`n"){$i++}}
   "`n"{}
   default{
    if($n -match '[0-7]'){
     $digits=[string]$n
     while($digits.Length -lt 3 -and $i+1 -lt $Text.Length -and $Text[$i+1] -match '[0-7]'){$i++;$digits+=$Text[$i]}
     [void]$sb.Append([char]([Convert]::ToInt32($digits,8) -band 0xFF))
    }else{[void]$sb.Append($n)}
   }
  }
 }
 return $sb.ToString()
}
function Get-BowerbirdPdfBlockText {
 # Text-showing operators inside one BT..ET block: (text) Tj, (text) ' and ", <hex> Tj, and [(a) -20 (b)] TJ.
 # In a TJ array a large negative offset is a word gap; a small one is kerning and adds no space.
 param([string]$Block)
 $str='\((?:\\.|[^\\)])*\)'
 $pattern='(?s)(?<arr>\[(?:'+$str+'|<[0-9A-Fa-f\s]*>|[^\]\(<])*\])\s*TJ|(?<lit>'+$str+')\s*(?:Tj|''|")|(?<hex><[0-9A-Fa-f\s]*>)\s*Tj'
 $sb=New-Object Text.StringBuilder
 foreach($op in [regex]::Matches($Block,$pattern)){
  if($op.Groups['arr'].Success){
   foreach($part in [regex]::Matches($op.Groups['arr'].Value,'('+$str+')|<([0-9A-Fa-f\s]*)>|(-?\d+(?:\.\d+)?)')){
    if($part.Groups[1].Success){$s=$part.Groups[1].Value;[void]$sb.Append((ConvertFrom-BowerbirdPdfString $s.Substring(1,$s.Length-2)))}
    elseif($part.Groups[2].Success){[void]$sb.Append((ConvertFrom-BowerbirdPdfHex $part.Groups[2].Value))}
    elseif([double]::Parse($part.Groups[3].Value,[Globalization.CultureInfo]::InvariantCulture) -le -200){[void]$sb.Append(' ')}
   }
  }elseif($op.Groups['lit'].Success){$s=$op.Groups['lit'].Value;[void]$sb.Append((ConvertFrom-BowerbirdPdfString $s.Substring(1,$s.Length-2)))}
  elseif($op.Groups['hex'].Success){[void]$sb.Append((ConvertFrom-BowerbirdPdfHex $op.Groups['hex'].Value.Trim('<','>')))}
  [void]$sb.Append(' ')
 }
 return $sb.ToString()
}
function ConvertFrom-BowerbirdPdfHex {
 # Single-byte hex text only. Two-byte (Identity-H / CID) fonts need the font's map and are not decoded here.
 param([string]$Hex)
 $h=($Hex -replace '\s','')
 if($h.Length -lt 2 -or $h.Length % 2){return ''}
 $sb=New-Object Text.StringBuilder
 for($i=0;$i -lt $h.Length;$i+=2){
  $b=[Convert]::ToInt32($h.Substring($i,2),16)
  if($b -ge 32 -and $b -lt 127){[void]$sb.Append([char]$b)}
 }
 return $sb.ToString()
}
function Get-BowerbirdPdfText {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000)
 # Lightweight PDF text best-effort. Doesn't pretend to decode all font encodings.
 $bytes=[IO.File]::ReadAllBytes($Path)
 if($bytes.Length -gt 20971520){return ''}
 $latin=[Text.Encoding]::GetEncoding(28591)
 $raw=$latin.GetString($bytes)
 if(-not $raw.StartsWith('%PDF-')){return ''}
 if($raw -match '/Encrypt\b'){return ''}   # encrypted streams are not decoded; never index their cipher text
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
   [void]$content.Append((Get-BowerbirdPdfBlockText -Block $block.Groups[1].Value))
   if($content.Length -ge $MaxCharacters){break}
  }
 }
 $value=$content.ToString()
 return $value.Substring(0,[Math]::Min($MaxCharacters,$value.Length))
}
function Get-BowerbirdOcrCommand {
 # An approved tesseract on this PC, or $null. BOWERBIRD_OCR_PATH names the program to run (a .exe, or a
 # .cmd/.bat wrapper); otherwise tesseract.exe on PATH. Nothing is downloaded or installed.
 $configured=[Environment]::GetEnvironmentVariable('BOWERBIRD_OCR_PATH')
 if(-not [string]::IsNullOrWhiteSpace($configured)){
  $configured=$configured.Trim().Trim('"')
  if((Test-Path -LiteralPath $configured -PathType Leaf) -and @('.exe','.cmd','.bat') -contains [IO.Path]::GetExtension($configured).ToLowerInvariant()){return $configured}
  return $null
 }
 $found=Get-Command 'tesseract.exe' -ErrorAction SilentlyContinue
 if($found){return $found.Source}
 return $null
}
function Invoke-BowerbirdOcr {
 # Runs the OCR program on one image and returns its text. Output and errors are read while it runs, so a chatty
 # program cannot fill a pipe and hang it; a program that runs past the time limit is stopped.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000,[int]$TimeoutMilliseconds=15000)
 $program=Get-BowerbirdOcrCommand
 if(-not $program){throw 'No OCR program found. Install tesseract and put it on PATH, or set BOWERBIRD_OCR_PATH.'}
 $info=New-Object Diagnostics.ProcessStartInfo
 $info.FileName=$program;$info.Arguments=('"'+$Path.Replace('"','')+'" stdout')
 $info.UseShellExecute=$false;$info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true;$info.CreateNoWindow=$true
 $process=[Diagnostics.Process]::Start($info)
 try{
  $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
  if(-not $process.WaitForExit($TimeoutMilliseconds)){try{$process.Kill()}catch{};throw 'OCR process timed out'}
  $process.WaitForExit()
  if($process.ExitCode -ne 0){throw ('OCR program failed (exit '+$process.ExitCode+')')}
  $result=[string]$outTask.Result
  return $result.Substring(0,[Math]::Min($MaxCharacters,$result.Length)).Trim()
 }finally{$process.Dispose()}
}
function Get-BowerbirdExtendedText {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000,[switch]$EnableExternalOcr)
 $ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
 if($ext -eq '.pdf'){return Get-BowerbirdPdfText -Path $Path -MaxCharacters $MaxCharacters}
 if($EnableExternalOcr -and @('.png','.jpg','.jpeg','.bmp','.tif','.tiff') -contains $ext){
  if(Get-BowerbirdOcrCommand){return (Invoke-BowerbirdOcr -Path $Path -MaxCharacters $MaxCharacters)}
 }
 return Get-BowerbirdText -Path $Path -MaxCharacters $MaxCharacters
}
function New-BowerbirdSmartIndex {
 [CmdletBinding()]param(
  [Parameter(Mandatory)][string]$Path,[switch]$Recurse,[switch]$IncludeContent,
  [switch]$EnableExternalOcr,[ValidateRange(1000,500000)][int]$MaxTextCharacters=60000,
  [ValidateRange(1,100000)][int]$MaxFiles=20000,
  # A previous index: files whose path, size and modified time are unchanged keep their saved hash and text.
  $Previous
 )
 $folder=(Resolve-Path -LiteralPath $Path).ProviderPath
 if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw 'Root is not a directory'}
 $files=New-Object Collections.Generic.List[object]
 $stats=[ordered]@{Added=0;Changed=0;Unchanged=0;Removed=0}
 $lookup=$null;$previousContent=$false;$previousOcr=$false
 if($Previous -and $Previous.Files){
  $lookup=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
  foreach($old in @($Previous.Files)){if($old.Path){$lookup[[string]$old.Path]=$old}}
  $previousContent=[bool]$Previous.IncludesContent;$previousOcr=[bool]$Previous.IncludesExternalOcr
 }
 $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
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
  $null=$seen.Add($file.FullName)
  $reuse=Get-BowerbirdReusableEntry -Lookup $lookup -File $file -NeedContent ([bool]$IncludeContent) -NeedOcr ([bool]$EnableExternalOcr -and @('.png','.jpg','.jpeg','.bmp','.tif','.tiff') -contains $file.Extension.ToLowerInvariant()) -PreviousContent $previousContent -PreviousOcr $previousOcr
  if($reuse){
   $stats.Unchanged++
   $files.Add([pscustomobject]@{
    Path=$file.FullName;Name=$file.Name;Extension=$file.Extension;Category=(Get-BowerbirdCategory $file.Extension $file.Name)
    Size=$file.Length;ModifiedUtc=$file.LastWriteTimeUtc.ToString('o')
    SHA256=[string]$reuse.SHA256;VisualHash=[string]$reuse.VisualHash;Text=$(if($IncludeContent){[string]$reuse.Text}else{''});Error=''
   })
   continue
  }
  if($lookup -and $lookup.ContainsKey($file.FullName)){$stats.Changed++}else{$stats.Added++}
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
 if($lookup){$prefix=$folder.TrimEnd('\')+'\';foreach($key in $lookup.Keys){if(-not $seen.Contains($key) -and $key.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){$stats.Removed++}}}
 return [pscustomobject]@{
  SchemaVersion=2;Root=$folder;IndexedUtc=[DateTime]::UtcNow.ToString('o')
  IncludesContent=[bool]$IncludeContent;IncludesExternalOcr=[bool]$EnableExternalOcr
  Incremental=[bool]$lookup;Stats=[pscustomobject]$stats
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