#requires -Version 5.1
<#
 PDF text extraction on synthetic PDFs built here (uncompressed and FlateDecode streams, kerned TJ arrays,
 escapes, hex strings, encrypted and non-PDF files), and OCR through a stand-in program set with
 BOWERBIRD_OCR_PATH (a .cmd that prints text, fails, or hangs). No real tesseract or real-world PDF is used.
 Run: powershell.exe -NoProfile -File .\Tests\PdfOcr.ps1
#>
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $root 'Private\BowerbirdAdvanced.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdPdfOcr_'+[guid]::NewGuid().ToString('N'))
$latin=[Text.Encoding]::GetEncoding(28591)
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
function New-TestPdf([string]$Path,[string]$Content,[switch]$Flate,[string]$ExtraDictionary='',[string]$Header='%PDF-1.4'){
 # One page, one content stream. The content is the page's operators, e.g. "BT /F1 12 Tf (Hello) Tj ET".
 $body=$latin.GetBytes($Content)
 if($Flate){
  $ms=New-Object IO.MemoryStream
  $ms.WriteByte(0x78);$ms.WriteByte(0x9C)   # zlib header; the reader skips it
  $deflate=New-Object IO.Compression.DeflateStream($ms,[IO.Compression.CompressionMode]::Compress,$true)
  $deflate.Write($body,0,$body.Length);$deflate.Dispose()
  $body=$ms.ToArray();$ms.Dispose()
  $dictionary="<< /Filter /FlateDecode /Length $($body.Length) >>"
 }else{$dictionary="<< /Length $($body.Length) >>"}
 $pre=$latin.GetBytes("$Header`n1 0 obj`n$dictionary`nstream`n")
 $post=$latin.GetBytes("`nendstream`nendobj`ntrailer`n<< /Root 1 0 R $ExtraDictionary >>`n%%EOF`n")
 [IO.File]::WriteAllBytes($Path,[byte[]]($pre+$body+$post))
}
$savedOcr=$env:BOWERBIRD_OCR_PATH
try{
 New-Item -ItemType Directory -Path $work -Force|Out-Null

 # --- PDF text ---
 $plain=Join-Path $work 'plain.pdf'
 New-TestPdf $plain 'BT /F1 12 Tf 72 700 Td (Quarterly budget review) Tj 0 -14 Td (Prepared by finance) Tj ET'
 $text=Get-BowerbirdPdfText -Path $plain
 Assert ($text -match 'Quarterly budget review' -and $text -match 'Prepared by finance') ("Uncompressed Tj text: '$text'")
 $flate=Join-Path $work 'flate.pdf'
 New-TestPdf $flate 'BT /F1 12 Tf 72 700 Td (Compressed stream text zebra4411) Tj ET' -Flate
 Assert ((Get-BowerbirdPdfText -Path $flate) -match 'Compressed stream text zebra4411') 'FlateDecode stream text'
 $kerned=Join-Path $work 'kerned.pdf'
 New-TestPdf $kerned 'BT /F1 12 Tf [(Pa)-20(y)-15(ment) -480 (due) -500 (Fri)10(day)] TJ ET'
 $text=Get-BowerbirdPdfText -Path $kerned
 Assert ($text -match 'Payment due Friday') ("TJ arrays: kerning joins letters, large gaps become spaces: '$text'")
 $escapes=Join-Path $work 'escapes.pdf'
 New-TestPdf $escapes 'BT (Cost \(approx\) is 5\\6 \251 2026\nline two) Tj ET'
 $text=Get-BowerbirdPdfText -Path $escapes
 Assert ($text -match 'Cost \(approx\) is 5\\6 ' -and $text.Contains([string][char]0xA9) -and $text -match 'line two') ("Escapes and octal codes: '$text'")
 $hex=Join-Path $work 'hex.pdf'
 New-TestPdf $hex 'BT <48656C6C6F20686578> Tj [<576F726C64>] TJ ET'
 $text=Get-BowerbirdPdfText -Path $hex
 Assert ($text -match 'Hello hex' -and $text -match 'World') ("Single-byte hex strings: '$text'")
 $notText=Join-Path $work 'drawing.pdf'
 New-TestPdf $notText '0 0 m 100 100 l S (not shown outside BT) '
 Assert ((Get-BowerbirdPdfText -Path $notText) -eq '') 'Strings outside text blocks are ignored'
 $locked=Join-Path $work 'locked.pdf'
 New-TestPdf $locked 'BT (secret cipher text) Tj ET' -ExtraDictionary '/Encrypt 9 0 R'
 Assert ((Get-BowerbirdPdfText -Path $locked) -eq '') 'An encrypted PDF yields no text rather than cipher text'
 $fake=Join-Path $work 'fake.pdf';[IO.File]::WriteAllText($fake,'this is not a pdf')
 Assert ((Get-BowerbirdPdfText -Path $fake) -eq '') 'A file that is not a PDF yields no text'
 $long=Join-Path $work 'long.pdf'
 New-TestPdf $long ('BT '+((1..400|ForEach-Object {"(word$_) Tj "}) -join '')+'ET')
 Assert ((Get-BowerbirdPdfText -Path $long -MaxCharacters 500).Length -le 500) 'MaxCharacters caps the text'
 $multi=Join-Path $work 'multi.pdf'
 $a=$latin.GetBytes("%PDF-1.4`n1 0 obj`n<< /Length 30 >>`nstream`nBT (First page alpha) Tj ET`nendstream`nendobj`n2 0 obj`n<< /Length 30 >>`nstream`nBT (Second page beta) Tj ET`nendstream`nendobj`n%%EOF`n")
 [IO.File]::WriteAllBytes($multi,$a)
 $text=Get-BowerbirdPdfText -Path $multi
 Assert ($text -match 'First page alpha' -and $text -match 'Second page beta') 'Several content streams are read in order'
 # Through the index and search.
 $space=Join-Path $work 'space';New-Item -ItemType Directory -Path $space|Out-Null
 Copy-Item $flate (Join-Path $space 'report.pdf');Copy-Item $kerned (Join-Path $space 'invoice.pdf')
 $index=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent
 $hits=@(Search-BowerbirdIndex -Index $index -Query 'zebra4411')
 Assert ($hits.Count -eq 1 -and $hits[0].Name -eq 'report.pdf') 'A PDF is found by its text in the index'
 Assert (@(Search-BowerbirdIndex -Index $index -Query 'Friday').Count -eq 1) 'Kerned PDF text is searchable'
 Pass 'PDF text: Tj, TJ kerning, escapes, hex, Flate, multiple streams, encrypted and fake files, search'

 # --- OCR ---
 Add-Type -AssemblyName System.Drawing
 $scan=Join-Path $work 'scan.png'
 $bitmap=New-Object Drawing.Bitmap(16,16);try{$bitmap.SetPixel(3,3,[Drawing.Color]::Black);$bitmap.Save($scan,[Drawing.Imaging.ImageFormat]::Png)}finally{$bitmap.Dispose()}
 $env:BOWERBIRD_OCR_PATH=(Join-Path $work 'does-not-exist.cmd')
 Assert ($null -eq (Get-BowerbirdOcrCommand)) 'A BOWERBIRD_OCR_PATH that does not exist means no OCR'
 $msg='';try{$null=Invoke-BowerbirdOcr -Path $scan}catch{$msg=$_.Exception.Message}
 Assert ($msg -match 'No OCR program') 'Running OCR with no program explains what to do'
 $notProgram=Join-Path $work 'notes.txt';[IO.File]::WriteAllText($notProgram,'x');$env:BOWERBIRD_OCR_PATH=$notProgram
 Assert ($null -eq (Get-BowerbirdOcrCommand)) 'Only .exe, .cmd and .bat programs are accepted'
 $ok=Join-Path $work 'ocr-ok.cmd'
 [IO.File]::WriteAllText($ok,"@echo off`r`necho Invoice 4521 total due from %~n1`r`n")
 $env:BOWERBIRD_OCR_PATH=$ok
 Assert ((Get-BowerbirdOcrCommand) -eq $ok) 'BOWERBIRD_OCR_PATH selects the program'
 $text=Invoke-BowerbirdOcr -Path $scan
 Assert ($text -ceq 'Invoice 4521 total due from scan') ("OCR text comes back trimmed: '$text'")
 Assert ((Invoke-BowerbirdOcr -Path $scan -MaxCharacters 7) -ceq 'Invoice') 'OCR text is capped'
 $fail=Join-Path $work 'ocr-fail.cmd';[IO.File]::WriteAllText($fail,"@echo off`r`necho trouble 1>&2`r`nexit /b 3`r`n")
 $env:BOWERBIRD_OCR_PATH=$fail
 $msg='';try{$null=Invoke-BowerbirdOcr -Path $scan}catch{$msg=$_.Exception.Message}
 Assert ($msg -match 'exit 3') 'A failing OCR program is reported with its exit code'
 $hang=Join-Path $work 'ocr-hang.cmd';[IO.File]::WriteAllText($hang,"@echo off`r`nping -n 30 127.0.0.1 >nul`r`n")
 $env:BOWERBIRD_OCR_PATH=$hang
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $msg='';try{$null=Invoke-BowerbirdOcr -Path $scan -TimeoutMilliseconds 1200}catch{$msg=$_.Exception.Message}
 Assert ($msg -match 'timed out' -and $watch.Elapsed.TotalSeconds -lt 15) ('A hung OCR program is stopped at the limit ('+[int]$watch.Elapsed.TotalSeconds+'s)')
 # Through the index: only when asked, and only for images.
 $env:BOWERBIRD_OCR_PATH=$ok
 $ocrSpace=Join-Path $work 'ocr-space';New-Item -ItemType Directory -Path $ocrSpace|Out-Null
 Copy-Item $scan (Join-Path $ocrSpace 'receipt.png');[IO.File]::WriteAllText((Join-Path $ocrSpace 'note.txt'),'plain note')
 $without=New-BowerbirdSmartIndex -Path $ocrSpace -Recurse -IncludeContent
 Assert (@(Search-BowerbirdIndex -Index $without -Query '4521').Count -eq 0) 'No OCR text unless OCR is requested'
 $with=New-BowerbirdSmartIndex -Path $ocrSpace -Recurse -IncludeContent -EnableExternalOcr -Previous $without
 Assert ($with.Stats.Changed -eq 1 -and $with.Stats.Unchanged -eq 1) 'Turning OCR on re-reads only the image (incremental)'
 $hits=@(Search-BowerbirdIndex -Index $with -Query '4521')
 Assert ($hits.Count -eq 1 -and $hits[0].Name -eq 'receipt.png' -and $with.IncludesExternalOcr) 'OCR text from an image is searchable'
 $env:BOWERBIRD_OCR_PATH=$fail
 $broken=New-BowerbirdSmartIndex -Path $ocrSpace -Recurse -IncludeContent -EnableExternalOcr
 Assert ((@($broken.Files|Where-Object {$_.Name -eq 'receipt.png'})[0].Error) -match 'exit 3' -and @($broken.Files).Count -eq 2) 'An OCR failure is recorded on that file and indexing continues'
 Pass 'OCR through a stand-in program: text, cap, exit code, timeout, index and search'
 Write-Host ("PASS: Bowerbird PDF and OCR ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 $env:BOWERBIRD_OCR_PATH=$savedOcr
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
