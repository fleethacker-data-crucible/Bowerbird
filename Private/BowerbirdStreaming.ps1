#requires -Version 5.1
# Optional SSE bridge to Fairlead's OpenAI-compatible chat address.
function Write-BowerbirdSse {
 [CmdletBinding()]param([Parameter(Mandatory)]$Response,[Parameter(Mandatory)][string]$Event,[Parameter(Mandatory)]$Value)
 $json=ConvertTo-Json -InputObject $Value -Depth 8 -Compress
 $line="event: $Event"+[char]10+"data: $json"+[char]10+[char]10
 $data=[Text.Encoding]::UTF8.GetBytes($line)
 $Response.OutputStream.Write($data,0,$data.Length)
 $Response.OutputStream.Flush()
}
function Invoke-BowerbirdStreamingChat {
 [CmdletBinding()]param(
  [Parameter(Mandatory)]$Response,
  [Parameter(Mandatory)][object[]]$Messages,
  [ValidateRange(32,8192)][int]$MaxTokens=1400,
  [ValidateRange(5,300)][int]$TimeoutSeconds=120
 )
 $cfg=Get-BowerbirdLlmConfig
 Assert-BowerbirdLlmUrl -Config $cfg
 $headers=Get-BowerbirdLlmHeaders -Config $cfg
 $payload=[ordered]@{model=$cfg.Model;messages=$Messages;max_tokens=$MaxTokens;temperature=0.2;stream=$true}
 $bytes=[Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $payload -Depth 12))
 $request=[Net.HttpWebRequest][Net.WebRequest]::Create($cfg.Url)
 $request.Method='POST';$request.ContentType='application/json; charset=utf-8'
 $request.Accept='text/event-stream,application/json'
 $request.Timeout=$TimeoutSeconds*1000;$request.ReadWriteTimeout=$TimeoutSeconds*1000
 foreach($name in $headers.Keys){$request.Headers[$name]=[string]$headers[$name]}
 $request.ContentLength=$bytes.Length
 $remote=$null;$responseReader=$null
 try{
  $body=$request.GetRequestStream()
  try{$body.Write($bytes,0,$bytes.Length)}finally{$body.Dispose()}
  $remote=[Net.HttpWebResponse]$request.GetResponse()
  if($remote.StatusCode -ne [Net.HttpStatusCode]::OK){throw "Provider HTTP $([int]$remote.StatusCode)"}
  $responseReader=New-Object IO.StreamReader($remote.GetResponseStream())
  $received=0
  Write-BowerbirdSse -Response $Response -Event 'start' -Value @{model=$cfg.Model}
  $type=([string]$remote.ContentType).ToLowerInvariant()
  if($type -notlike '*text/event-stream*'){
   $parsed=$responseReader.ReadToEnd()|ConvertFrom-Json
   $value=''
   if($parsed.choices){$value=[string]$parsed.choices[0].message.content}
   elseif($parsed.candidates){$value=(@($parsed.candidates[0].content.parts)|ForEach-Object {$_.text}) -join ''}
   if($value){Write-BowerbirdSse -Response $Response -Event 'delta' -Value @{text=$value};$received=$value.Length}
  }else{
   while($null -ne ($line=$responseReader.ReadLine())){
    if($line -notmatch '^data:\s*(.+)$'){continue}
    $data=$Matches[1]
    if($data -eq '[DONE]'){break}
    try{
     $parsed=$data|ConvertFrom-Json
     $chunk=''
     if($parsed.choices){
      $choice=$parsed.choices[0]
      if($choice.delta -and $choice.delta.content){$chunk=[string]$choice.delta.content}
      elseif($choice.text){$chunk=[string]$choice.text}
     }elseif($parsed.candidates){
      if($parsed.candidates[0].content.parts){$chunk=(@($parsed.candidates[0].content.parts)|ForEach-Object {$_.text}) -join ''}
     }
     if($chunk){
      $received+=$chunk.Length
      if($received -gt 300000){throw 'Response exceeded safety limit'}
      Write-BowerbirdSse -Response $Response -Event 'delta' -Value @{text=$chunk}
     }
    }catch{
     if($_.Exception.Message -eq 'Response exceeded safety limit'){throw}
    }
   }
  }
  Write-BowerbirdSse -Response $Response -Event 'done' -Value @{characters=$received;model=$cfg.Model}
 }catch{
  try{Write-BowerbirdSse -Response $Response -Event 'failure' -Value @{error=$_.Exception.Message}}catch{}
 }finally{
  if($responseReader){$responseReader.Dispose()}
  if($remote){$remote.Dispose()}
 }
}