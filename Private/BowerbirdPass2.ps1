# Pass 2 - Deep analysis via vision LLM
#requires -Version 5.1
function Get-BowerbirdImageBase64 {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][System.IO.FileInfo]$File,[int]$MaxBytes=4194304)
 if($File.Length -gt $MaxBytes){
  $sizeMb=[math]::Round(($File.Length/1MB),1)
  Write-Warning ("Image {0} is large ({1} MB) - skipping vision for size" -f $File.Name,$sizeMb)
  return $null
 }
 try{$bytes=[System.IO.File]::ReadAllBytes($File.FullName);return [Convert]::ToBase64String($bytes)}
 catch{Write-Warning ("Failed to read {0} for base64 conversion: {1}" -f $File.Name,$_.Exception.Message);return $null}
}
function Get-BowerbirdMimeType {
 param([string]$Extension)
 switch($Extension.ToLowerInvariant()){
  '.png'{return 'image/png'}
  '.jpg'{return 'image/jpeg'}
  '.jpeg'{return 'image/jpeg'}
  '.gif'{return 'image/gif'}
  '.webp'{return 'image/webp'}
  '.bmp'{return 'image/bmp'}
  default{return 'image/png'}
 }
}
function Invoke-BowerbirdPass2 {
 [CmdletBinding()]param([Parameter(Mandatory=$true)][System.IO.FileInfo]$File,[pscustomobject]$Pass1Result)
 $meta=$Pass1Result.Metadata;$b64=Get-BowerbirdImageBase64 -File $File
 if(-not $b64){
  return [pscustomobject]@{Confidence=$Pass1Result.Confidence;SuggestedName=$Pass1Result.SuggestedName;Reasoning=$Pass1Result.Reasoning+'; vision skipped (size or read failure)';Source='pass1-only';VisionText=$null;NeedsVision=$false}
 }
 $mime=Get-BowerbirdMimeType -Extension $File.Extension;$dataUrl='data:'+$mime+';base64,'+$b64
 $systemPrompt=@'
You are a precise file-naming assistant for screenshots and photos.
Respond with ONLY a single line of JSON (no markdown, no explanation):
{"short_description":"3-8 word human description","category":"Screenshot|Photo|Diagram|UI|Document|Other","key_text":"any important visible text or app name","suggested_slug":"lowercase-kebab-case-slug-max-6-words"}
Rules:
- short_description focuses on the main subject or purpose of the image.
- For screenshots prefer app/window name + action if clear (e.g. "Outlook inbox triage", "PowerShell error dialog").
- suggested_slug must be filesystem-safe, no spaces, no special chars except hyphen.
- Do not invent information that is not visible.
'@
 $userText='Analyze this image and return the JSON. Original filename: '+$File.Name
 if($Pass1Result.DatePart){$userText+='  Possible date: '+$Pass1Result.DatePart}
 $userContent=@(@{type='text';text=$userText},@{type='image_url';image_url=@{url=$dataUrl}})
 $messages=@(@{role='system';content=$systemPrompt},@{role='user';content=$userContent})
 try{$resp=Invoke-BowerbirdChat -Messages $messages -MaxTokens 400 -Temperature 0.1;$raw=$resp.Text}
 catch{
  Write-Warning ("Vision call failed for {0}: {1}" -f $File.Name,$_.Exception.Message)
  return [pscustomobject]@{Confidence=$Pass1Result.Confidence;SuggestedName=$Pass1Result.SuggestedName;Reasoning=$Pass1Result.Reasoning+'; vision error: '+$_.Exception.Message;Source='pass1-fallback';VisionText=$null;NeedsVision=$false}
 }
 $jsonText=$raw;if($raw -match '(?s)\{.*\}'){$jsonText=$Matches[0]}
 $parsed=$null;try{$parsed=$jsonText|ConvertFrom-Json -ErrorAction Stop}catch{Write-Verbose ("Could not parse vision JSON: {0}" -f $raw)}
 $slug=$null;$desc=$null
 if($parsed){$slug=$parsed.suggested_slug;$desc=$parsed.short_description;if(-not $slug -and $desc){$slug=($desc -replace '[^a-zA-Z0-9\s-]','' -replace '\s+','-').ToLowerInvariant()}}
 $datePart=$Pass1Result.DatePart;if(-not $datePart -and $meta -and $meta.DateTaken){$datePart=$meta.DateTaken.ToString('yyyy-MM-dd')}
 $suggested=$null
 if($slug){$parts=@();if($datePart){$parts+=$datePart};$parts+=$slug;$suggested=($parts -join '_')+$File.Extension.ToLowerInvariant()}
 $reasonText='Vision: '+[string]$desc
 return [pscustomobject]@{Confidence=0.88;SuggestedName=$suggested;Reasoning=$reasonText;Source='vision';VisionText=$raw;Parsed=$parsed;NeedsVision=$false;DatePart=$datePart;DescPart=$slug}
}
