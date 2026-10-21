# Final name sanitization and uniqueness
#requires -Version 5.1
function New-BowerbirdFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$Analysis,
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [string[]]$ExistingNames = @()
    )
    $ext = $File.Extension.ToLowerInvariant()
    $candidate = $Analysis.SuggestedName
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $stamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
        $candidate = "Unnamed_$stamp$ext"
    }
    $base = [IO.Path]::GetFileNameWithoutExtension($candidate)
    $base = $base -replace '[<>:"/\\|?*\x00-\x1F]', ''
    $base = $base -replace '\s+', '_'
    $base = $base.Trim(' ._')
    if ([string]::IsNullOrWhiteSpace($base)) { $base = 'Unnamed' }
    $reserved = @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9','LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')
    if ($reserved -contains $base.ToUpperInvariant()) { $base = "File_$base" }
    if ($base.Length -gt 120) { $base = $base.Substring(0, 120).TrimEnd('_-') }
    $final = "$base$ext"; $dir = $File.DirectoryName; $counter = 1
    while ($ExistingNames -contains $final.ToLowerInvariant() -or (Test-Path -LiteralPath (Join-Path $dir $final))) {
        $final = "{0}_{1:D2}{2}" -f $base, $counter, $ext
        $counter++
        if ($counter -gt 999) { break }
    }
    return [pscustomobject]@{
        OriginalName=$File.Name; ProposedName=$final; FullProposed=(Join-Path $dir $final)
        Confidence=$Analysis.Confidence; Source=$Analysis.Source; Reasoning=$Analysis.Reasoning
    }
}
