#requires -Version 5.1
# Index storage: Windows DPAPI encryption (current user) and incremental re-indexing.
# The index holds extracted document text, so it is encrypted at rest by default. DPAPI keeps the key in the
# user's Windows profile: no key file, no password, nothing to install. A file written by one Windows user
# cannot be read by another user or on another PC; rebuild the index there.
# BOWERBIRD_INDEX_ENCRYPTION=off keeps the old plaintext JSON (for example to inspect it by hand).
$script:BowerbirdIndexMagic=[Text.Encoding]::ASCII.GetBytes('BBIDX1')
$script:BowerbirdIndexEntropy=[Text.Encoding]::UTF8.GetBytes('Bowerbird.Index.v1')
function Test-BowerbirdIndexEncryptionEnabled {
 $value=[Environment]::GetEnvironmentVariable('BOWERBIRD_INDEX_ENCRYPTION')
 if([string]::IsNullOrWhiteSpace($value)){return $true}
 return ($value.Trim() -notmatch '^(?i)(off|0|false|no|plaintext)$')
}
function Protect-BowerbirdBytes {
 [CmdletBinding()]param([Parameter(Mandatory)][byte[]]$Bytes)
 Add-Type -AssemblyName System.Security
 $sealed=[Security.Cryptography.ProtectedData]::Protect($Bytes,$script:BowerbirdIndexEntropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)
 return ,[byte[]]($script:BowerbirdIndexMagic+$sealed)
}
function Unprotect-BowerbirdBytes {
 [CmdletBinding()]param([Parameter(Mandatory)][byte[]]$Bytes)
 Add-Type -AssemblyName System.Security
 $magic=$script:BowerbirdIndexMagic.Length
 $sealed=New-Object byte[] ($Bytes.Length-$magic)
 [Array]::Copy($Bytes,$magic,$sealed,0,$sealed.Length)
 try{return ,[Security.Cryptography.ProtectedData]::Unprotect($sealed,$script:BowerbirdIndexEntropy,[Security.Cryptography.DataProtectionScope]::CurrentUser)}
 catch{throw 'The saved index cannot be decrypted by this Windows user (it is damaged, or was written by another user or PC). Build the index again.'}
}
function Test-BowerbirdEncryptedBytes([byte[]]$Bytes){
 $magic=$script:BowerbirdIndexMagic
 if($null -eq $Bytes -or $Bytes.Length -le $magic.Length){return $false}
 for($i=0;$i -lt $magic.Length;$i++){if($Bytes[$i] -ne $magic[$i]){return $false}}
 return $true
}
function Test-BowerbirdIndexEncrypted {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
 if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
 $head=New-Object byte[] ($script:BowerbirdIndexMagic.Length+1)
 $stream=[IO.File]::OpenRead($Path)
 try{$read=$stream.Read($head,0,$head.Length)}finally{$stream.Dispose()}
 return (Test-BowerbirdEncryptedBytes ([byte[]]$head[0..([Math]::Max(0,$read-1))]))
}
function Save-BowerbirdIndexFile {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Index)
 $parent=Split-Path -Parent $Path
 if($parent -and -not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
 $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Index -Depth 12 -Compress))
 $encrypted=Test-BowerbirdIndexEncryptionEnabled
 if($encrypted){$bytes=Protect-BowerbirdBytes -Bytes $bytes}
 $tmp=$Path+'.tmp'
 [IO.File]::WriteAllBytes($tmp,$bytes)
 Move-Item -LiteralPath $tmp -Destination $Path -Force
 return [pscustomobject]@{Path=$Path;Encrypted=$encrypted}
}
function Read-BowerbirdIndexFile {
 # Reads an encrypted index, or a plaintext one written before encryption existed (or with it switched off).
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
 $bytes=[IO.File]::ReadAllBytes($Path)
 if(Test-BowerbirdEncryptedBytes $bytes){$bytes=Unprotect-BowerbirdBytes -Bytes $bytes}
 $text=[Text.Encoding]::UTF8.GetString($bytes)
 if($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF){$text=$text.Substring(1)}
 return ($text|ConvertFrom-Json)
}
function Convert-BowerbirdIndexFile {
 # Encrypts an existing plaintext index in place (or the reverse with -Plaintext). Returns whether it changed.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[switch]$Plaintext)
 if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return $false}
 $isEncrypted=Test-BowerbirdIndexEncrypted -Path $Path
 if($Plaintext -eq $isEncrypted){
  $index=Read-BowerbirdIndexFile -Path $Path
  $previous=$env:BOWERBIRD_INDEX_ENCRYPTION
  try{$env:BOWERBIRD_INDEX_ENCRYPTION=if($Plaintext){'off'}else{'on'};$null=Save-BowerbirdIndexFile -Path $Path -Index $index}
  finally{$env:BOWERBIRD_INDEX_ENCRYPTION=$previous}
  return $true
 }
 return $false
}
function ConvertTo-BowerbirdTicks($Value){
 # Index timestamps are ISO-8601 text; ConvertFrom-Json may hand back a [DateTime] instead.
 if($null -eq $Value -or "$Value" -eq ''){return -1L}
 if($Value -is [DateTime]){return $Value.ToUniversalTime().Ticks}
 $parsed=[DateTime]::MinValue
 if([DateTime]::TryParse([string]$Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$parsed)){return $parsed.ToUniversalTime().Ticks}
 return -1L
}
function Get-BowerbirdReusableEntry {
 # The previous index entry for a file when nothing about it changed: same path, size and modified time,
 # and it already carries what this run asks for (text, OCR text). Otherwise $null and the file is read again.
 [CmdletBinding()]param($Lookup,[Parameter(Mandatory)][IO.FileInfo]$File,[bool]$NeedContent,[bool]$NeedOcr,[bool]$PreviousContent,[bool]$PreviousOcr)
 if($null -eq $Lookup -or -not $Lookup.ContainsKey($File.FullName)){return $null}
 $old=$Lookup[$File.FullName]
 if([long]$old.Size -ne $File.Length){return $null}
 if((ConvertTo-BowerbirdTicks $old.ModifiedUtc) -ne $File.LastWriteTimeUtc.Ticks){return $null}
 if($old.Error){return $null}
 if($NeedContent -and -not $PreviousContent){return $null}
 if($NeedOcr -and -not $PreviousOcr){return $null}
 return $old
}
