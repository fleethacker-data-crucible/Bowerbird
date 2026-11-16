#requires -Version 5.1
# Spoken progress through Fairlead's /v1/audio/speech (TalkForge behind the router).
# The browser keeps its local voice and uses it when this call does not return audio.
# The spoken line is not logged. The key is the same Fairlead key as chat, sent only to the loopback address.
function Invoke-BowerbirdSpeech {
 [CmdletBinding()]param([AllowEmptyString()][string]$Text,[int]$TimeoutSec=15)
 $spoken=($Text -replace '[\r\n]',' ').Trim()
 if([string]::IsNullOrWhiteSpace($spoken) -or $spoken.Length -gt 200){throw 'Speech text must be 1 to 200 characters.'}
 $cfg=Get-BowerbirdLlmConfig
 Assert-BowerbirdLlmUrl -Config $cfg
 $u=[Uri]$cfg.Url
 if($u.UserInfo){throw 'The Fairlead address must not contain a user name or password.'}
 $url=$u.GetLeftPart([UriPartial]::Authority)+'/v1/audio/speech'
 $headers=Get-BowerbirdLlmHeaders -Config $cfg
 $payload=[ordered]@{model=$cfg.Model;input=$spoken;response_format='wav'}
 $body=[Text.Encoding]::UTF8.GetBytes(($payload|ConvertTo-Json -Compress))
 $req=[Net.HttpWebRequest]::Create($url)
 $req.Method='POST'
 $req.ContentType='application/json; charset=utf-8'
 $req.Accept='audio/wav,audio/*'
 $req.Timeout=$TimeoutSec*1000
 $req.ReadWriteTimeout=$TimeoutSec*1000
 $req.Proxy=$null
 $req.AllowAutoRedirect=$false
 $req.ContentLength=$body.Length
 $req.Headers[[Net.HttpRequestHeader]::Authorization]=[string]$headers['Authorization']
 $req.Headers['X-Fairlead-Label']=[string]$headers['X-Fairlead-Label']
 $req.Headers['X-Fairlead-Privacy']=[string]$headers['X-Fairlead-Privacy']
 $headers=$null
 $resp=$null
 try{
  $up=$req.GetRequestStream()
  try{$up.Write($body,0,$body.Length)}finally{$up.Dispose()}
  try{$resp=$req.GetResponse()}catch{
   $ex=$_.Exception
   while($null -ne $ex -and -not ($ex -is [Net.WebException])){$ex=$ex.InnerException}
   if($ex -and $ex.Response){$resp=$ex.Response}else{throw 'Fairlead did not return audio.'}
  }
  $status=[int]$resp.StatusCode
  $type=[string]$resp.ContentType
  if($status -ne 200 -or $type -notmatch '(?i)\Aaudio/'){throw 'Fairlead did not return audio.'}
  $ms=New-Object IO.MemoryStream
  $src=$resp.GetResponseStream()
  try{
   $buf=New-Object byte[] 16384
   while(($n=$src.Read($buf,0,$buf.Length)) -gt 0){
    $ms.Write($buf,0,$n)
    if($ms.Length -gt 2097152){throw 'Fairlead did not return audio.'}
   }
  }finally{$src.Dispose()}
  if($ms.Length -eq 0){throw 'Fairlead did not return audio.'}
  return [pscustomobject]@{Bytes=$ms.ToArray();ContentType=$type}
 }finally{
  if($null -ne $resp){try{$resp.Close()}catch{}}
 }
}
