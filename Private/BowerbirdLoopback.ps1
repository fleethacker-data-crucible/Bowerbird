#requires -Version 5.1
# Pure PowerShell 5.1 loopback server, based on ARC/Cascade transport.
# No HttpListener URLACL, Add-Type, C# compiler, or admin rights required.
function Start-BowerbirdLoopback {
 [CmdletBinding()]param([ValidateRange(0,65535)][int]$Port=8767,[switch]$FixedPort)
 $attempts=if($FixedPort -or $Port -eq 0){@($Port)}else{@($Port,0)}
 foreach($candidate in $attempts){
  $listener=$null
  try{
   $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,[int]$candidate)
   $listener.Start()
   return [pscustomobject]@{Listener=$listener;Port=([Net.IPEndPoint]$listener.LocalEndpoint).Port;Transport='PowerShellTcp'}
  }catch [Net.Sockets.SocketException]{
   if($listener){try{$listener.Stop()}catch{}}
   if($_.Exception.SocketErrorCode -ne [Net.Sockets.SocketError]::AddressAlreadyInUse -or $candidate -eq $attempts[-1]){
    throw "Cannot bind loopback port $candidate : $($_.Exception.Message)"
   }
  }catch{if($listener){try{$listener.Stop()}catch{}};throw}
 }
 throw 'No available loopback port'
}
function Read-BowerbirdLoopbackContext {
 [CmdletBinding()]param([Parameter(Mandatory)][Net.Sockets.TcpListener]$Listener,[ValidateRange(1,65535)][int]$Port)
 while($true){
  $client=$Listener.AcceptTcpClient()
  try{
   $client.ReceiveTimeout=15000;$client.SendTimeout=180000
   $stream=$client.GetStream()
   $headerBytes=New-Object 'System.Collections.Generic.List[byte]'
   while($true){
    $b=$stream.ReadByte()
    if($b -lt 0){throw 'Client closed before request'}
    $headerBytes.Add([byte]$b)
    $n=$headerBytes.Count
    if($n -gt 16384){throw 'Header exceeds 16 KB'}
    if($n -ge 4 -and $headerBytes[$n-4] -eq 13 -and $headerBytes[$n-3] -eq 10 -and $headerBytes[$n-2] -eq 13 -and $headerBytes[$n-1] -eq 10){break}
   }
   $lines=[Text.Encoding]::ASCII.GetString($headerBytes.ToArray()) -split ([char]13+[char]10)
   if($lines[0] -notmatch '^(GET|HEAD|POST) (/[^\s]*) HTTP/1\.[01]$'){throw 'Unsupported HTTP request'}
   $method=[string]$Matches[1];$target=[string]$Matches[2]
   if($target.Length -gt 4096){throw 'URL too long'}
   $headers=New-Object Collections.Specialized.NameValueCollection
   foreach($line in @($lines|Select-Object -Skip 1)){
    if(-not $line){break}
    $colon=$line.IndexOf(':')
    if($colon -le 0){throw 'Malformed HTTP header'}
    $key=$line.Substring(0,$colon).Trim();$value=$line.Substring($colon+1).Trim()
    if($key -notmatch '^[a-zA-Z0-9-]+$'){throw 'Malformed HTTP header name'}
    if($null -ne $headers[$key]){throw 'Duplicate headers not accepted'}
    $headers.Add($key,$value)
   }
   if([string]$headers['Host'] -notin @("127.0.0.1:$Port","localhost:$Port",'127.0.0.1','localhost')){throw 'Non-loopback Host denied'}
   if($headers['Transfer-Encoding']){throw 'Chunked request bodies unsupported'}
   $length=0L
   if($headers['Content-Length']){
    if(-not [long]::TryParse($headers['Content-Length'],[ref]$length)){throw 'Invalid Content-Length'}
   }elseif($method -eq 'POST'){throw 'POST requires Content-Length'}
   if($length -lt 0 -or $length -gt 1048576){throw 'Request exceeds 1 MB'}
   $payload=New-Object byte[] ([int]$length)
   $offset=0
   if($headers['Expect'] -eq '100-continue' -and $length -gt 0){
    $provisional=[Text.Encoding]::ASCII.GetBytes('HTTP/1.1 100 Continue'+[char]13+[char]10+[char]13+[char]10)
    $stream.Write($provisional,0,$provisional.Length)
   }
   while($offset -lt $payload.Length){
    $received=$stream.Read($payload,$offset,$payload.Length-$offset)
    if($received -le 0){throw 'Incomplete request body'}
    $offset+=$received
   }
   $request=[pscustomobject]@{Url=[uri]("http://127.0.0.1:$Port$target");HttpMethod=$method;Headers=$headers;ContentLength64=$length;ContentEncoding=[Text.Encoding]::UTF8;InputStream=(New-Object IO.MemoryStream(,$payload))}
   $response=[pscustomobject]@{StatusCode=200;ContentType='application/octet-stream';ContentLength64=0L;SendChunked=$false;Headers=(New-Object Collections.Specialized.NameValueCollection);OutputStream=(New-Object IO.MemoryStream);NetworkStream=$stream;Client=$client;Closed=$false}
   $response|Add-Member -MemberType ScriptMethod -Name Close -Force -Value {
    if($this.Closed){return}
    $this.Closed=$true
    try{
     $payload=$this.OutputStream.ToArray()
     $crlf=[string][char]13+[char]10
     $reason=switch([int]$this.StatusCode){200 {'OK'}400 {'Bad Request'}403 {'Forbidden'}404 {'Not Found'}405 {'Method Not Allowed'}413 {'Payload Too Large'}500 {'Internal Server Error'}default {'Error'}}
     $sb=New-Object Text.StringBuilder
     [void]$sb.Append('HTTP/1.1 '+$this.StatusCode+' '+$reason+$crlf)
     [void]$sb.Append('Content-Type: '+$this.ContentType+$crlf)
     [void]$sb.Append('Connection: close'+$crlf)
     if($this.SendChunked){[void]$sb.Append('Transfer-Encoding: chunked'+$crlf)}
     else{[void]$sb.Append('Content-Length: '+$payload.Length+$crlf)}
     foreach($name in @($this.Headers.AllKeys)){
      $value=[string]$this.Headers[$name]
      if($name -match '^[A-Za-z0-9-]+$' -and $value -notmatch '[\r\n]'){[void]$sb.Append($name+': '+$value+$crlf)}
     }
     [void]$sb.Append($crlf)
     $raw=[Text.Encoding]::ASCII.GetBytes($sb.ToString())
     $this.NetworkStream.Write($raw,0,$raw.Length)
     if($this.SendChunked){
      if($payload.Length){
       $lead=[Text.Encoding]::ASCII.GetBytes($payload.Length.ToString('x')+$crlf)
       $this.NetworkStream.Write($lead,0,$lead.Length)
       $this.NetworkStream.Write($payload,0,$payload.Length)
       $tail=[Text.Encoding]::ASCII.GetBytes($crlf+'0'+$crlf+$crlf)
      }else{$tail=[Text.Encoding]::ASCII.GetBytes('0'+$crlf+$crlf)}
      $this.NetworkStream.Write($tail,0,$tail.Length)
     }elseif($payload.Length){$this.NetworkStream.Write($payload,0,$payload.Length)}
     $this.NetworkStream.Flush()
    }finally{try{$this.OutputStream.Dispose()}catch{};try{$this.Client.Close()}catch{}}
   }
   return [pscustomobject]@{Request=$request;Response=$response}
  }catch{
   try{$client.Close()}catch{}
   # Aborted browser preconnects and malformed requests cannot crash server.
   continue
  }
 }
}
