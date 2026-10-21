#requires -Version 5.1
# Local-first indexing, OpenXML extraction, duplicate detection and lexical retrieval.
function Get-BowerbirdText {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[int]$MaxCharacters=120000)
 $ext=[IO.Path]::GetExtension($Path).ToLowerInvariant()
 if(@('.txt','.md','.csv','.json','.xml','.log','.ps1','.psm1','.psd1','.js','.ts','.css','.html','.htm','.py','.yml','.yaml','.ini','.config') -contains $ext){
   $reader=New-Object IO.StreamReader($Path,$true); try { $buffer=New-Object char[] $MaxCharacters; $n=$reader.Read($buffer,0,$MaxCharacters); if($n -eq 0){return ''}; return (-join $buffer[0..($n-1)]) } finally {$reader.Dispose()}
 }
 if(@('.docx','.xlsx','.pptx') -notcontains $ext){return ''}
 Add-Type -AssemblyName System.IO.Compression
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 $zip=[IO.Compression.ZipFile]::OpenRead($Path)
 try {
  $parts= @($zip.Entries | Where-Object {
   ($ext -eq '.docx' -and $_.FullName -match '^word/(document|header\d*|footer\d*)\.xml$') -or
   ($ext -eq '.pptx' -and $_.FullName -match '^ppt/slides/slide\d+\.xml$') -or
   ($ext -eq '.xlsx' -and $_.FullName -match '^xl/(sharedStrings|worksheets/sheet\d+)\.xml$')
  })
  $sb=New-Object Text.StringBuilder
  foreach($part in $parts){
   $stream=$part.Open(); try {
    $reader=New-Object IO.StreamReader($stream)
    try {$xml=New-Object Xml.XmlDocument; $xml.XmlResolver=$null; $xml.LoadXml($reader.ReadToEnd()); $nodes=$xml.SelectNodes('//*[local-name()="t" or local-name()="v"]'); foreach($node in $nodes){[void]$sb.Append($node.InnerText);[void]$sb.Append(' '); if($sb.Length -ge $MaxCharacters){break}}} finally {$reader.Dispose()}
   } finally {$stream.Dispose()}
   if($sb.Length -ge $MaxCharacters){break}
  }
  $result=$sb.ToString(); return $result.Substring(0,[Math]::Min($MaxCharacters,$result.Length))
 } finally {$zip.Dispose()}
}
function Get-BowerbirdImageHash {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Path)
 Add-Type -AssemblyName System.Drawing
 $image=[Drawing.Image]::FromFile($Path)
 $bitmap=New-Object Drawing.Bitmap(9,8)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 try {
  $graphics.DrawImage($image,0,0,9,8)
  $bits=New-Object Text.StringBuilder
  for($y=0;$y -lt 8;$y++){for($x=0;$x -lt 8;$x++){
   $a=$bitmap.GetPixel($x,$y);$b=$bitmap.GetPixel(($x+1),$y)
   $la=299*$a.R+587*$a.G+114*$a.B;$lb=299*$b.R+587*$b.G+114*$b.B
   [void]$bits.Append($(if($la -gt $lb){'1'}else{'0'}))
  }}
  $s=$bits.ToString();$hex=New-Object Text.StringBuilder
  for($i=0;$i -lt 64;$i+=4){[void]$hex.Append(([Convert]::ToInt32($s.Substring($i,4),2)).ToString('x'))}
  return $hex.ToString()
 } finally {$graphics.Dispose();$bitmap.Dispose();$image.Dispose()}
}
function Get-BowerbirdHashDistance {
 param([string]$A,[string]$B)
 if($A.Length -ne 16 -or $B.Length -ne 16){throw 'Expected 64-bit hexadecimal dHash values'}
 $distance=0
 for($i=0;$i -lt 16;$i++){ $v=[Convert]::ToInt32($A.Substring($i,1),16) -bxor [Convert]::ToInt32($B.Substring($i,1),16);while($v -ne 0){$distance+=($v -band 1);$v=$v -shr 1} }
 return $distance
}
function New-BowerbirdIndex {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[string]$OutputPath,[switch]$Recurse,[int]$MaxTextCharacters=120000)
 $folder=(Resolve-Path -LiteralPath $Path).ProviderPath
 if(-not (Test-Path -LiteralPath $folder -PathType Container)){throw 'Index root must be a directory'}
 $args=@{LiteralPath=$folder;File=$true;ErrorAction='SilentlyContinue'};if($Recurse){$args.Recurse=$true}
 $items=New-Object Collections.Generic.List[object]
 foreach($file in (Get-ChildItem @args)){
  if($OutputPath -and $file.FullName -eq [IO.Path]::GetFullPath($OutputPath)){continue}
  $text='';$sha='';$visual='';$errorText=''
  try{$text=Get-BowerbirdText -Path $file.FullName -MaxCharacters $MaxTextCharacters}catch{$errorText=$_.Exception.Message}
  try{$sha=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash}catch{$errorText=$_.Exception.Message}
  if(@('.png','.jpg','.jpeg','.bmp','.gif','.tif','.tiff') -contains $file.Extension.ToLowerInvariant()){
   try{$visual=Get-BowerbirdImageHash -Path $file.FullName}catch{$errorText=$_.Exception.Message}
  }
  $items.Add([pscustomobject]@{Path=$file.FullName;Name=$file.Name;Extension=$file.Extension;Size=$file.Length;ModifiedUtc=$file.LastWriteTimeUtc.ToString('o');SHA256=$sha;VisualHash=$visual;Text=$text;Error=$errorText})
 }
 $result=[pscustomobject]@{SchemaVersion=1;Root=$folder;IndexedUtc=[DateTime]::UtcNow.ToString('o');Files=@($items.ToArray())}
 if($OutputPath){$parent=Split-Path -Parent $OutputPath;if($parent -and -not (Test-Path $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null};$tmp="$OutputPath.tmp";[IO.File]::WriteAllText($tmp,($result|ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false));Move-Item -LiteralPath $tmp -Destination $OutputPath -Force}
 return $result
}
function Find-BowerbirdDuplicates {
 [CmdletBinding()] param([Parameter(Mandatory)]$Index,[ValidateSet('Exact','Visual')][string]$Mode='Exact',[ValidateRange(0,64)][int]$MaxDistance=6)
 $files=@($Index.Files)
 if($Mode -eq 'Exact'){return @($files | Where-Object {$_.SHA256} | Group-Object SHA256 | Where-Object {$_.Count -gt 1} | ForEach-Object {[pscustomobject]@{Kind='Exact';Key=$_.Name;Files=@($_.Group | ForEach-Object {$_.Path})}})}
 # Connected components; transitive similarity groups. No automatic deletion.
 $images=@($files | Where-Object {$_.VisualHash});$seen=@{};$groups=New-Object Collections.Generic.List[object]
 for($i=0;$i -lt $images.Count;$i++){
  if($seen.ContainsKey($i)){continue};$queue=New-Object Collections.Queue;$queue.Enqueue($i);$seen[$i]=$true;$component=New-Object Collections.Generic.List[string]
  while($queue.Count){$k=[int]$queue.Dequeue();$component.Add($images[$k].Path);for($j=0;$j -lt $images.Count;$j++){if(-not $seen.ContainsKey($j) -and (Get-BowerbirdHashDistance $images[$k].VisualHash $images[$j].VisualHash) -le $MaxDistance){$seen[$j]=$true;$queue.Enqueue($j)}}}
  if($component.Count -gt 1){$groups.Add([pscustomobject]@{Kind='Visual';Key=$images[$i].VisualHash;Files=@($component.ToArray())})}
 }
 return @($groups.ToArray())
}
function Search-BowerbirdIndex {
 [CmdletBinding()] param([Parameter(Mandatory)]$Index,[Parameter(Mandatory)][string]$Query,[int]$Top=25)
 $tokens=@([regex]::Matches($Query.ToLowerInvariant(),'[\p{L}\p{N}_]{2,}')|ForEach-Object {$_.Value}|Select-Object -Unique)
 $docs=@($Index.Files);$n=[Math]::Max(1,$docs.Count);$average=[Math]::Max(1,(($docs|ForEach-Object {($_.Name+' '+$_.Text).Length}|Measure-Object -Average).Average))
 $results=foreach($doc in $docs){
  $content=($doc.Name+' '+$doc.Text).ToLowerInvariant();$words=@([regex]::Matches($content,'[\p{L}\p{N}_]{2,}')|ForEach-Object {$_.Value});$score=0.0
  foreach($term in $tokens){$tf=@($words|Where-Object {$_ -eq $term}).Count;if($tf -eq 0){continue};$df=@($docs|Where-Object {($_.Name+' '+$_.Text).ToLowerInvariant() -match ('(?<![\p{L}\p{N}_])'+[regex]::Escape($term)+'(?![\p{L}\p{N}_])')}).Count
   $idf=[Math]::Log(1+($n-$df+0.5)/($df+0.5));$score+=$idf*($tf*2.2)/($tf+1.2*(0.25+0.75*$words.Count/$average));if($doc.Name.ToLowerInvariant().Contains($term)){$score+=2}
  }
  if($score -gt 0){[pscustomobject]@{Path=$doc.Path;Name=$doc.Name;Score=[Math]::Round($score,3);Snippet=$doc.Text.Substring(0,[Math]::Min(180,$doc.Text.Length))}}
 }
 return @($results|Sort-Object Score -Descending|Select-Object -First $Top)
}
function Get-BowerbirdCodeStats {
 [CmdletBinding()] param([Parameter(Mandatory)][string]$Path,[switch]$Recurse)
 $extensions=@{'.ps1'='PowerShell';'.psm1'='PowerShell';'.js'='JavaScript';'.ts'='TypeScript';'.py'='Python';'.cs'='C#';'.html'='HTML';'.css'='CSS';'.json'='JSON';'.sql'='SQL'}
 $args=@{LiteralPath=$Path;File=$true};if($Recurse){$args.Recurse=$true}
 foreach($f in (Get-ChildItem @args | Where-Object {$extensions.ContainsKey($_.Extension.ToLowerInvariant())})){
  $lines=@(Get-Content -LiteralPath $f.FullName);$blank=@($lines|Where-Object {-not $_.Trim()}).Count;$comments=@($lines|Where-Object {$_.TrimStart() -match '^(#|//|/\*|\*|<!--|--)'}).Count
  [pscustomobject]@{Path=$f.FullName;Language=$extensions[$f.Extension.ToLowerInvariant()];Lines=$lines.Count;Blank=$blank;Comments=$comments;Code=$lines.Count-$blank-$comments}
 }
}
