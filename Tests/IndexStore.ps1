#requires -Version 5.1
<#
 Encrypted index storage (Windows DPAPI) and incremental re-indexing, on synthetic files in a disposable folder.
 Run: powershell.exe -NoProfile -File .\Tests\IndexStore.ps1
#>
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdIntelligence.ps1')
. (Join-Path $root 'Private\BowerbirdAdvanced.ps1')
$work=Join-Path ([IO.Path]::GetTempPath()) ('BowerbirdIndexStore_'+[guid]::NewGuid().ToString('N'))
$space=Join-Path $work 'space'
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('ASSERT FAILED: '+$Message)}}
$script:passed=0
function Pass([string]$Message){$script:passed++;Write-Host ('PASS: '+$Message) -ForegroundColor Green}
$savedEnv=$env:BOWERBIRD_INDEX_ENCRYPTION
try{
 New-Item -ItemType Directory -Path $space -Force|Out-Null
 $env:BOWERBIRD_INDEX_ENCRYPTION=$null
 [IO.File]::WriteAllText((Join-Path $space 'alpha.txt'),'quarterly budget zebra-marker-9931')
 [IO.File]::WriteAllText((Join-Path $space 'beta.txt'),'meeting notes for the team')
 [IO.File]::WriteAllText((Join-Path $space 'gamma.md'),'# plan')

 # --- Encryption at rest ---
 Assert (Test-BowerbirdIndexEncryptionEnabled) 'Encryption is on by default'
 $index=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent
 $file=Join-Path $work 'data\index.bin'
 $saved=Save-BowerbirdIndexFile -Path $file -Index $index
 Assert ($saved.Encrypted) 'Save reports encrypted'
 $bytes=[IO.File]::ReadAllBytes($file)
 Assert ([Text.Encoding]::ASCII.GetString($bytes,0,6) -ceq 'BBIDX1') 'Encrypted file starts with the BBIDX1 header'
 Assert ($bytes.Length -gt 100) 'Encrypted file has a payload'
 Assert ([Text.Encoding]::GetEncoding(28591).GetString($bytes) -notmatch 'zebra-marker-9931') 'Extracted text is not readable in the saved file'
 Assert ([Text.Encoding]::GetEncoding(28591).GetString($bytes) -notmatch 'alpha\.txt') 'File names are not readable in the saved file'
 Assert (Test-BowerbirdIndexEncrypted -Path $file) 'Test-BowerbirdIndexEncrypted sees it'
 $back=Read-BowerbirdIndexFile -Path $file
 Assert (@($back.Files).Count -eq 3 -and (@($back.Files|Where-Object {$_.Text -match 'zebra-marker-9931'}).Count -eq 1)) 'Round trip keeps files and text'
 Assert (@(Search-BowerbirdIndex -Index $back -Query 'zebra-marker-9931').Count -ge 0) 'Search runs on a decrypted index'
 Assert (@(Search-BowerbirdIndex -Index $back -Query 'budget').Count -eq 1) 'Search finds text from a decrypted index'
 Assert (-not (Test-Path -LiteralPath ($file+'.tmp'))) 'No temp file left behind'
 Pass 'Index is DPAPI-encrypted at rest and reads back intact'

 # --- Plaintext compatibility and the off switch ---
 $env:BOWERBIRD_INDEX_ENCRYPTION='off'
 Assert (-not (Test-BowerbirdIndexEncryptionEnabled)) 'BOWERBIRD_INDEX_ENCRYPTION=off turns it off'
 $plain=Join-Path $work 'data\index.json'
 $savedPlain=Save-BowerbirdIndexFile -Path $plain -Index $index
 Assert (-not $savedPlain.Encrypted -and -not (Test-BowerbirdIndexEncrypted -Path $plain)) 'Off writes plaintext JSON'
 Assert ([IO.File]::ReadAllText($plain) -match 'zebra-marker-9931') 'Plaintext file holds the text (as before)'
 Assert (@((Read-BowerbirdIndexFile -Path $plain).Files).Count -eq 3) 'Plaintext index still reads'
 $env:BOWERBIRD_INDEX_ENCRYPTION=$null
 Assert (Convert-BowerbirdIndexFile -Path $plain) 'Convert encrypts a plaintext index'
 Assert ((Test-BowerbirdIndexEncrypted -Path $plain) -and (@((Read-BowerbirdIndexFile -Path $plain).Files).Count -eq 3)) 'Converted index is encrypted and intact'
 Assert (-not (Convert-BowerbirdIndexFile -Path $plain)) 'Convert is a no-op when already encrypted'
 Assert (Convert-BowerbirdIndexFile -Path $plain -Plaintext) 'Convert -Plaintext decrypts'
 Assert (-not (Test-BowerbirdIndexEncrypted -Path $plain) -and $env:BOWERBIRD_INDEX_ENCRYPTION -eq $null) 'Back to plaintext, setting restored'
 [IO.File]::WriteAllBytes((Join-Path $work 'bom.json'),([byte[]](0xEF,0xBB,0xBF)+[Text.Encoding]::UTF8.GetBytes('{"Files":[]}')))
 Assert ($null -ne (Read-BowerbirdIndexFile -Path (Join-Path $work 'bom.json'))) 'A plaintext index with a BOM reads'
 Pass 'Plaintext indexes still read; off switch and conversion work'

 # --- Damaged or foreign encrypted files fail clearly ---
 $damaged=Join-Path $work 'damaged.bin'
 [IO.File]::WriteAllBytes($damaged,([Text.Encoding]::ASCII.GetBytes('BBIDX1')+[byte[]](1..64)))
 $message='';try{$null=Read-BowerbirdIndexFile -Path $damaged}catch{$message=$_.Exception.Message}
 Assert ($message -match 'cannot be decrypted' -and $message -match 'Build the index again') 'Damaged encrypted file explains itself'
 Pass 'A damaged or foreign encrypted index fails with a clear message'

 # --- Incremental indexing ---
 $first=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent
 Assert ($first.Stats.Added -eq 3 -and $first.Stats.Unchanged -eq 0 -and -not $first.Incremental) 'Full build counts every file as added'
 $null=Save-BowerbirdIndexFile -Path $file -Index $first
 $previous=Read-BowerbirdIndexFile -Path $file   # through JSON: timestamps must still compare equal
 $again=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent -Previous $previous
 Assert ($again.Incremental -and $again.Stats.Unchanged -eq 3 -and $again.Stats.Added -eq 0 -and $again.Stats.Changed -eq 0 -and $again.Stats.Removed -eq 0) 'Nothing changed: all three reused'
 Assert (@($again.Files|Where-Object {$_.Text -match 'zebra-marker-9931'}).Count -eq 1) 'Reused entries keep their text'
 # Reuse really skips hashing: a sentinel hash survives only when the saved entry is reused.
 $sentinel=@($previous.Files|Where-Object {$_.Name -eq 'alpha.txt'})[0];$sentinel.SHA256='SENTINEL'
 $reused=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent -Previous $previous
 Assert (@($reused.Files|Where-Object {$_.SHA256 -eq 'SENTINEL'}).Count -eq 1) 'Unchanged file keeps its saved hash (not read again)'
 # Change, add, remove.
 [IO.File]::WriteAllText((Join-Path $space 'alpha.txt'),'quarterly budget revised with more words')
 [IO.File]::WriteAllText((Join-Path $space 'delta.txt'),'new file')
 Remove-Item -LiteralPath (Join-Path $space 'gamma.md')
 $delta=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent -Previous $previous
 Assert ($delta.Stats.Changed -eq 1 -and $delta.Stats.Added -eq 1 -and $delta.Stats.Removed -eq 1 -and $delta.Stats.Unchanged -eq 1) ('Change/add/remove counted: '+($delta.Stats|ConvertTo-Json -Compress))
 Assert (@($delta.Files).Count -eq 3 -and -not (@($delta.Files|Where-Object {$_.Name -eq 'gamma.md'}).Count)) 'Removed file is gone from the index'
 $changed=@($delta.Files|Where-Object {$_.Name -eq 'alpha.txt'})[0]
 Assert ($changed.SHA256 -ne 'SENTINEL' -and $changed.SHA256.Length -eq 64 -and $changed.Text -match 'revised') 'Changed file is read again'
 # Same size, new modified time: still detected.
 [IO.File]::WriteAllText((Join-Path $space 'beta.txt'),'meeting notes for the TEAM')
 [IO.File]::SetLastWriteTimeUtc((Join-Path $space 'beta.txt'),[DateTime]::UtcNow.AddMinutes(5))
 $touch=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent -Previous $delta
 Assert ($touch.Stats.Changed -eq 1) 'A new modified time marks a file changed'
 # Asking for more than the previous run had forces a re-read.
 $metaOnly=New-BowerbirdSmartIndex -Path $space -Recurse -Previous $touch
 Assert ($metaOnly.Stats.Unchanged -eq 3 -and @($metaOnly.Files|Where-Object {$_.Text}).Count -eq 0) 'Dropping content reuses hashes and clears text'
 $upgraded=New-BowerbirdSmartIndex -Path $space -Recurse -IncludeContent -Previous $metaOnly
 Assert ($upgraded.Stats.Changed -eq 3 -and @($upgraded.Files|Where-Object {$_.Text}).Count -eq 3) 'Adding content reads every file again'
 # Entries outside the new root do not leak in, and are not counted as removed.
 $subdir=Join-Path $space 'sub';New-Item -ItemType Directory -Path $subdir|Out-Null
 [IO.File]::WriteAllText((Join-Path $subdir 'inner.txt'),'inner')
 $sub=New-BowerbirdSmartIndex -Path $subdir -Recurse -IncludeContent -Previous $upgraded
 Assert (@($sub.Files).Count -eq 1 -and $sub.Stats.Removed -eq 0 -and $sub.Stats.Added -eq 1) 'Indexing a subfolder starts from that folder'
 Pass 'Incremental index: reuses unchanged files; detects changed, added and removed'
 Write-Host ("PASS: Bowerbird index store ($script:passed groups)") -ForegroundColor Green
}catch{
 Write-Host ('FAIL: '+$_.Exception.Message) -ForegroundColor Red
 exit 1
}finally{
 $env:BOWERBIRD_INDEX_ENCRYPTION=$savedEnv
 Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
