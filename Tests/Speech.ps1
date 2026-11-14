#requires -Version 5.1
# Fairlead /v1/audio/speech for spoken progress. A fake loopback server; no real Fairlead and no real key.
# Run: powershell -NoProfile -File .\Tests\Speech.ps1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'Private\BowerbirdLlm.ps1')
. (Join-Path $root 'Private\BowerbirdSpeech.ps1')
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw "ASSERTION FAILED: $Message"}}
$savedReader=$script:BowerbirdCredentialReader
$names=@('BOWERBIRD_FAIRLEAD_URL','BOWERBIRD_FAIRLEAD_MODEL','BOWERBIRD_FAIRLEAD_PRIVACY')
$saved=@{}
foreach($n in $names){$saved[$n]=[Environment]::GetEnvironmentVariable($n);[Environment]::SetEnvironmentVariable($n,$null)}
$script:BowerbirdCredentialReader={param([string]$Target) return 'fl-speechkey'}
if($script:BowerbirdFairleadPrepare){$script:BowerbirdFairleadPrepare={param($Config)}}
$job=$null
try{
 $threw=$false
 try{Invoke-BowerbirdSpeech -Text ''}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Speech text must be 1 to 200 characters.') 'empty speech text is refused'
 $threw=$false
 try{Invoke-BowerbirdSpeech -Text ('x'*201)}catch{$threw=$true}
 Assert $threw 'speech text over 200 characters is refused'
 $env:BOWERBIRD_FAIRLEAD_URL='https://ai.example.org/v1/chat/completions'
 $threw=$false
 try{Invoke-BowerbirdSpeech -Text 'Still working.'}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -match 'BOWERBIRD_FAIRLEAD_URL' -and $msg -notmatch 'Still working') 'a non-loopback speech address is refused and the line is not repeated'
 $env:BOWERBIRD_FAIRLEAD_URL='http://user:secret@127.0.0.1:8776/v1/chat/completions'
 $threw=$false
 try{Invoke-BowerbirdSpeech -Text 'Still working.'}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'The Fairlead address must not contain a user name or password.' -and $msg -notmatch 'secret') 'a user name in the speech address is refused and not repeated'
 foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$null)}

 $probe=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
 $probe.Start();$port=$probe.LocalEndpoint.Port;$probe.Stop()
 $cap=Join-Path ([IO.Path]::GetTempPath()) ('bowerbird-speech-' + [guid]::NewGuid().ToString('N') + '.txt')
 $ready=$cap+'.ready'
 $job=Start-Job -ArgumentList $port,$cap,$ready -ScriptBlock {
  param($port,$cap,$ready)
  $l=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,$port);$l.Start()
  [IO.File]::WriteAllText($ready,'ok')
  try{
   foreach($code in @('500','200')){
    $c=$l.AcceptTcpClient();$s=$c.GetStream();$s.ReadTimeout=5000
    $buf=New-Object byte[] 65536;$ms=New-Object IO.MemoryStream;$need=-1
    while($true){
     $r=$s.Read($buf,0,$buf.Length);if($r -le 0){break};$ms.Write($buf,0,$r)
     $t=[Text.Encoding]::UTF8.GetString($ms.ToArray());$i=$t.IndexOf("`r`n`r`n")
     if($i -ge 0){
      if($need -lt 0){$m=[regex]::Match($t,'(?i)content-length:\s*(\d+)');$need=$i+4+[int]$m.Groups[1].Value}
      if($ms.Length -ge $need){break}
     }
    }
    $req=[Text.Encoding]::UTF8.GetString($ms.ToArray())
    [IO.File]::AppendAllText($cap,$req+"`n=====`n")
    if($code -eq '500'){$payload=[Text.Encoding]::UTF8.GetBytes('no')}
    else{$payload=[Text.Encoding]::ASCII.GetBytes('RIFF')}
    $ctype=if($code -eq '200'){'audio/wav'}else{'text/plain'}
    $head="HTTP/1.1 $code X`r`nContent-Type: $ctype`r`nContent-Length: $($payload.Length)`r`nConnection: close`r`n`r`n"
    $hb=[Text.Encoding]::ASCII.GetBytes($head)
    $s.Write($hb,0,$hb.Length);$s.Write($payload,0,$payload.Length);$s.Flush();$c.Close()
   }
  }finally{$l.Stop()}
 }
 $waited=0;while(-not (Test-Path -LiteralPath $ready) -and $waited -lt 100){Start-Sleep -Milliseconds 100;$waited++}
 Assert (Test-Path -LiteralPath $ready) 'Fake speech server started'
 $env:BOWERBIRD_FAIRLEAD_URL="http://127.0.0.1:$port/v1/chat/completions"
 $threw=$false
 try{Invoke-BowerbirdSpeech -Text 'Still working.'}catch{$threw=$true;$msg=$_.Exception.Message}
 Assert ($threw -and $msg -eq 'Fairlead did not return audio.' -and $msg -notmatch 'Still working') 'a non-audio answer is refused without repeating the line'
 $audio=Invoke-BowerbirdSpeech -Text 'Still working.'
 Assert ($audio.ContentType -eq 'audio/wav' -and [Text.Encoding]::ASCII.GetString($audio.Bytes) -eq 'RIFF') 'a wav answer is returned as bytes'
 $null=Wait-Job -Job $job -Timeout 10
 $seen=[IO.File]::ReadAllText($cap)
 Assert ($seen -match 'POST /v1/audio/speech ') 'speech goes to /v1/audio/speech on the Fairlead origin'
 Assert (([regex]::Matches($seen,'(?im)^authorization:\s*Bearer fl-speechkey\s*$')).Count -eq 2) 'both speech calls send the Fairlead key'
 Assert (([regex]::Matches($seen,'(?im)^x-fairlead-label:\s*Bowerbird\s*$')).Count -eq 2) 'both speech calls send the label'
 Assert (([regex]::Matches($seen,'(?im)^x-fairlead-privacy:\s*local\s*$')).Count -eq 2) 'speech stays on the local privacy setting'
 Assert (([regex]::Matches($seen,'"input":"Still working\."')).Count -eq 2) 'the spoken line is the request input'
 Write-Host 'PASS: Fairlead speech, with the local voice left for a miss' -ForegroundColor Green
}catch{
 Write-Host "FAIL: $($_.Exception.Message)" -ForegroundColor Red
 exit 1
}finally{
 $script:BowerbirdCredentialReader=$savedReader
 foreach($n in $names){[Environment]::SetEnvironmentVariable($n,$saved[$n])}
 if($job){Stop-Job -Job $job -ErrorAction SilentlyContinue;Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
 if($cap){Remove-Item -LiteralPath $cap,$ready -Force -ErrorAction SilentlyContinue}
}
