#requires -Version 5.1
# A mock OpenAI-compatible provider on loopback for tests: a TcpListener in its own runspace, so no URL ACL or
# admin rights are needed. It serves queued responses (recorded fixtures) and records every request it receives.
#   $mock = Start-MockProvider
#   Push-MockResponse $mock -Body (Get-Content fixture -Raw)            # JSON, HTTP 200
#   Push-MockResponse $mock -Body $sse -ContentType 'text/event-stream'
#   Push-MockResponse $mock -Status 500 -Body 'boom'
#   $mock.Url                      # http://127.0.0.1:<port>/v1/chat/completions
#   $mock.State.Requests           # @{Method;Path;Headers;Body} per request, in order
#   Stop-MockProvider $mock
function Start-MockProvider {
 $state=[hashtable]::Synchronized(@{Requests=(New-Object System.Collections.ArrayList);Responses=(New-Object System.Collections.Queue);Stop=$false;Port=0})
 $listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
 $listener.Start()
 $state.Port=([Net.IPEndPoint]$listener.LocalEndpoint).Port
 $runspace=[runspacefactory]::CreateRunspace();$runspace.Open()
 $runspace.SessionStateProxy.SetVariable('state',$state);$runspace.SessionStateProxy.SetVariable('listener',$listener)
 $ps=[powershell]::Create();$ps.Runspace=$runspace
 $null=$ps.AddScript({
  $latin=[Text.Encoding]::GetEncoding(28591)
  while(-not $state.Stop){
   if(-not $listener.Pending()){Start-Sleep -Milliseconds 15;continue}
   $client=$listener.AcceptTcpClient()
   try{
    $stream=$client.GetStream();$stream.ReadTimeout=5000
    $head=New-Object Text.StringBuilder;$buffer=New-Object byte[] 1
    while($head.Length -lt 65536 -and -not $head.ToString().EndsWith("`r`n`r`n")){if($stream.Read($buffer,0,1) -lt 1){break};[void]$head.Append([char]$buffer[0])}
    $lines=$head.ToString() -split "`r`n"
    $request=$lines[0] -split ' '
    $headers=@{};foreach($line in $lines[1..($lines.Count-1)]){if($line -match '^([^:]+):\s*(.*)$'){$headers[$Matches[1].ToLowerInvariant()]=$Matches[2]}}
    $body=''
    if($headers['content-length']){
     $length=[int]$headers['content-length'];$bytes=New-Object byte[] $length;$got=0
     while($got -lt $length){$n=$stream.Read($bytes,$got,$length-$got);if($n -lt 1){break};$got+=$n}
     $body=[Text.Encoding]::UTF8.GetString($bytes,0,$got)
    }
    [void]$state.Requests.Add(@{Method=$request[0];Path=$request[1];Headers=$headers;Body=$body})
    $reply=if($state.Responses.Count){$state.Responses.Dequeue()}else{@{Status=404;ContentType='text/plain';Body='no response queued'}}
    $payload=[Text.Encoding]::UTF8.GetBytes([string]$reply.Body)
    $out=("HTTP/1.1 {0} Mock`r`nContent-Type: {1}`r`nContent-Length: {2}`r`nConnection: close`r`n`r`n" -f $reply.Status,$reply.ContentType,$payload.Length)
    $headBytes=$latin.GetBytes($out);$stream.Write($headBytes,0,$headBytes.Length);$stream.Write($payload,0,$payload.Length);$stream.Flush()
   }catch{}finally{$client.Close()}
  }
 })
 $async=$ps.BeginInvoke()
 return [pscustomobject]@{State=$state;Url=('http://127.0.0.1:'+$state.Port+'/v1/chat/completions');BaseUrl=('http://127.0.0.1:'+$state.Port);Listener=$listener;PowerShell=$ps;Runspace=$runspace;Async=$async}
}
function Push-MockResponse {
 param([Parameter(Mandatory)]$Mock,[int]$Status=200,[string]$ContentType='application/json',[Parameter(Mandatory)][string]$Body)
 $Mock.State.Responses.Enqueue(@{Status=$Status;ContentType=$ContentType;Body=$Body})
}
function Stop-MockProvider {
 param($Mock)
 if(-not $Mock){return}
 $Mock.State.Stop=$true
 try{$null=$Mock.Async.AsyncWaitHandle.WaitOne(2000)}catch{}
 try{$Mock.Listener.Stop()}catch{}
 try{$Mock.PowerShell.Dispose()}catch{}
 try{$Mock.Runspace.Dispose()}catch{}
}
