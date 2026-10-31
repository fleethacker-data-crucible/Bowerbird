#requires -Version 5.1
# File tags: short labels kept beside the workspace index (studio-tags.json). A tag never changes a file.
# Tags are keyed by full path, compared case-insensitively. A tag follows its path: a file that is moved by a
# plan keeps no tags at its new location (the README says so). Tags are for finding and for the cleanup recipes.

function Get-BowerbirdTagsPath {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$IndexPath)
 return (Join-Path (Split-Path -Parent $IndexPath) 'studio-tags.json')
}

function ConvertTo-BowerbirdTag {
 # Lowercase letters, digits and hyphens; 1-32 characters; must start with a letter or digit.
 [CmdletBinding()]param([Parameter(Mandatory)][AllowEmptyString()][string]$Tag)
 $normal=([string]$Tag).Trim().ToLowerInvariant()
 if($normal -notmatch '^[a-z0-9][a-z0-9-]{0,31}$'){throw 'Tags are 1-32 characters: lowercase letters, digits and hyphens, starting with a letter or digit.'}
 return $normal
}

function Read-BowerbirdTags {
 # Returns a case-insensitive dictionary: full path -> sorted array of tags. Missing file means no tags.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path)
 $map=New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::OrdinalIgnoreCase)
 if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){return ,$map}
 $saved=Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
 foreach($entry in @($saved.Files)){
  if($entry.Path -and @($entry.Tags).Count){$map[[string]$entry.Path]=@($entry.Tags|ForEach-Object {[string]$_}|Sort-Object)}
 }
 return ,$map
}

function Save-BowerbirdTags {
 [CmdletBinding()]param([Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)]$Map)
 $files=@($Map.Keys|Sort-Object|ForEach-Object {[pscustomobject]@{Path=[string]$_;Tags=@($Map[$_])}})
 $document=[pscustomobject]@{SchemaVersion=1;Files=$files}
 $parent=Split-Path -Parent $Path
 if($parent -and -not (Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent -Force|Out-Null}
 $tmp=$Path+'.tmp'
 [IO.File]::WriteAllText($tmp,(ConvertTo-Json -InputObject $document -Depth 6),(New-Object Text.UTF8Encoding $false))
 Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Add-BowerbirdTag {
 # Adds one tag to an existing file and returns the file's tags. Adding the same tag twice changes nothing.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$TagsPath,[Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string]$Tag)
 if(-not (Test-Path -LiteralPath $FilePath -PathType Leaf)){throw 'Only an existing file can be tagged'}
 $normal=ConvertTo-BowerbirdTag $Tag
 $full=[IO.Path]::GetFullPath($FilePath)
 $map=Read-BowerbirdTags -Path $TagsPath
 $current=@();if($map.ContainsKey($full)){$current=@($map[$full])}
 $map[$full]=@(($current+$normal)|Select-Object -Unique|Sort-Object)
 Save-BowerbirdTags -Path $TagsPath -Map $map
 return @($map[$full])
}

function Remove-BowerbirdTag {
 # Removes one tag from a file. A file with no tags left is dropped from the store. Returns the remaining tags.
 [CmdletBinding()]param([Parameter(Mandatory)][string]$TagsPath,[Parameter(Mandatory)][string]$FilePath,[Parameter(Mandatory)][string]$Tag)
 $normal=ConvertTo-BowerbirdTag $Tag
 $full=[IO.Path]::GetFullPath($FilePath)
 $map=Read-BowerbirdTags -Path $TagsPath
 if(-not $map.ContainsKey($full)){return @()}
 $left=@($map[$full]|Where-Object {$_ -ne $normal})
 if($left.Count){$map[$full]=$left}else{$map.Remove($full)|Out-Null}
 Save-BowerbirdTags -Path $TagsPath -Map $map
 return $left
}

function Get-BowerbirdTaggedFiles {
 # Full paths of files carrying the tag (all tagged files when no tag is given).
 [CmdletBinding()]param([Parameter(Mandatory)][string]$TagsPath,[string]$Tag)
 $map=Read-BowerbirdTags -Path $TagsPath
 $wanted=$null;if($Tag){$wanted=ConvertTo-BowerbirdTag $Tag}
 $hits=foreach($key in $map.Keys){
  if(-not $wanted -or @($map[$key]) -contains $wanted){[pscustomobject]@{Path=[string]$key;Tags=@($map[$key])}}
 }
 return @($hits)
}
