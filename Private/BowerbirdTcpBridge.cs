// Bowerbird loopback HTTP fallback. Runtime: .NET Framework, compiled by Windows PowerShell Add-Type.
// Binds 127.0.0.1 only; no URLACL, administrator rights, third-party server, or public interface.
using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Collections.Generic;
namespace Bowerbird.Transport {
 public sealed class Request {
  public Uri Url {get;set;}
  public string HttpMethod {get;set;}
  public Dictionary<string,string> Headers {get;set;}
  public long ContentLength64 {get;set;}
  public Encoding ContentEncoding {get;set;}
  public Stream InputStream {get;set;}
 }
 public sealed class Response {
  private readonly TcpClient client;
  private readonly NetworkStream stream;
  private readonly MemoryStream buffer = new MemoryStream();
  private readonly ResponseStream output;
  private bool started=false, closed=false;
  public int StatusCode {get;set;}
  public string ContentType {get;set;}
  public Dictionary<string,string> Headers {get;private set;}
  public bool SendChunked {get;set;}
  public long ContentLength64 {get;set;}
  public Stream OutputStream {get{return output;}}
  public Response(TcpClient connection){
   client=connection; stream=connection.GetStream(); StatusCode=200;
   ContentType="application/octet-stream";Headers=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   ContentLength64=-1;output=new ResponseStream(this);
  }
  private string Reason(int code){
   if(code==200)return "OK";if(code==400)return "Bad Request";
   if(code==403)return "Forbidden";if(code==404)return "Not Found";
   if(code==413)return "Payload Too Large";return "Error";
  }
  private void StartHeaders(long contentLength){
   if(started)return;started=true;
   StringBuilder sb=new StringBuilder();
   sb.Append("HTTP/1.1 ").Append(StatusCode).Append(" ").Append(Reason(StatusCode)).Append("\r\n");
   sb.Append("Content-Type: ").Append(ContentType).Append("\r\n");
   sb.Append("Connection: close\r\n");
   if(SendChunked)sb.Append("Transfer-Encoding: chunked\r\n");
   else sb.Append("Content-Length: ").Append(contentLength).Append("\r\n");
   foreach(var pair in Headers){
    if(pair.Key.IndexOf('\r')>=0||pair.Key.IndexOf('\n')>=0||pair.Value.IndexOf('\r')>=0||pair.Value.IndexOf('\n')>=0)
      throw new InvalidOperationException("Invalid header");
    sb.Append(pair.Key).Append(": ").Append(pair.Value).Append("\r\n");
   }
   sb.Append("\r\n");
   byte[] bytes=Encoding.ASCII.GetBytes(sb.ToString());
   stream.Write(bytes,0,bytes.Length);
  }
  internal void WriteBody(byte[] bytes,int offset,int count){
   if(closed)throw new ObjectDisposedException("response");
   if(SendChunked){
    StartHeaders(-1);
    byte[] prefix=Encoding.ASCII.GetBytes(count.ToString("x")+"\r\n");
    stream.Write(prefix,0,prefix.Length);
    stream.Write(bytes,offset,count);
    byte[] end=Encoding.ASCII.GetBytes("\r\n");stream.Write(end,0,end.Length);
   }else if(ContentLength64>=0){
    StartHeaders(ContentLength64);
    stream.Write(bytes,offset,count);
   }else buffer.Write(bytes,offset,count);
  }
  internal void FlushBody(){if(started)stream.Flush();}
  public void Close(){
   if(closed)return;
   try{
    if(!started){StartHeaders(SendChunked?-1:buffer.Length);if(buffer.Length>0){
      byte[] contents=buffer.ToArray();
      if(SendChunked)WriteBody(contents,0,contents.Length);
      else stream.Write(contents,0,contents.Length);
    }}
    if(SendChunked){byte[] final=Encoding.ASCII.GetBytes("0\r\n\r\n");stream.Write(final,0,final.Length);}
    stream.Flush();
   }finally{closed=true;buffer.Dispose();stream.Dispose();client.Close();}
  }
  private sealed class ResponseStream : Stream {
   readonly Response parent;
   public ResponseStream(Response r){parent=r;}
   public override bool CanRead{get{return false;}}
   public override bool CanSeek{get{return false;}}
   public override bool CanWrite{get{return true;}}
   public override long Length{get{throw new NotSupportedException();}}
   public override long Position{get{throw new NotSupportedException();}set{throw new NotSupportedException();}}
   public override int Read(byte[] a,int o,int c){throw new NotSupportedException();}
   public override long Seek(long v,SeekOrigin s){throw new NotSupportedException();}
   public override void SetLength(long v){throw new NotSupportedException();}
   public override void Write(byte[] data,int offset,int count){parent.WriteBody(data,offset,count);}
   public override void Flush(){parent.FlushBody();}
  }
 }
 public sealed class Context {
  public Request Request {get;set;}
  public Response Response {get;set;}
 }
 public sealed class Server {
  readonly TcpListener listener;
  readonly int port;
  public bool IsListening{get;private set;}
  public Server(int port){
   this.port=port;
   listener=new TcpListener(IPAddress.Loopback,port);
  }
  public void Start(){listener.Start();IsListening=true;}
  public void Stop(){IsListening=false;listener.Stop();}
  public void Close(){Stop();}
  private static string ReadHeaders(NetworkStream stream) {
   var bytes=new List<byte>();
   while(bytes.Count<16384){
    int value=stream.ReadByte();
    if(value<0)throw new EndOfStreamException();
    bytes.Add((byte)value);
    int n=bytes.Count;
    if(n>=4&&bytes[n-4]==13&&bytes[n-3]==10&&bytes[n-2]==13&&bytes[n-1]==10){
      return Encoding.ASCII.GetString(bytes.ToArray());
    }
   }
   throw new InvalidDataException("Header too large");
  }
  private Context Parse(TcpClient client) {
   NetworkStream stream=client.GetStream();
   stream.ReadTimeout=10000;stream.WriteTimeout=180000;
   string header=ReadHeaders(stream);
   string[] lines=header.Split(new string[]{"\r\n"},StringSplitOptions.None);
   string[] requestLine=lines[0].Split(' ');
   if(requestLine.Length<3||!requestLine[1].StartsWith("/"))throw new InvalidDataException("Unsupported request line");
   var fields=new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
   for(int i=1;i<lines.Length;i++){
    if(string.IsNullOrEmpty(lines[i]))break;
    int colon=lines[i].IndexOf(':');
    if(colon>0)fields[lines[i].Substring(0,colon).Trim()]=lines[i].Substring(colon+1).Trim();
   }
   long length=0;
   if(fields.ContainsKey("Content-Length")&&!long.TryParse(fields["Content-Length"],out length))throw new InvalidDataException("Bad content length");
   if(length<0||length>1048576)throw new InvalidDataException("Request too large");
   byte[] body=new byte[(int)length];
   int read=0;
   while(read<body.Length){
    int amount=stream.Read(body,read,body.Length-read);
    if(amount<=0)throw new EndOfStreamException();
    read+=amount;
   }
   return new Context {
    Request=new Request{Url=new Uri("http://127.0.0.1:"+port+requestLine[1]),HttpMethod=requestLine[0],Headers=fields,ContentLength64=length,ContentEncoding=Encoding.UTF8,InputStream=new MemoryStream(body,false)},
    Response=new Response(client)
   };
  }
  public Context GetContext(){
   if(!IsListening)throw new InvalidOperationException("Server not listening");
   while(true){
    TcpClient client=listener.AcceptTcpClient();
    try{return Parse(client);}
    catch{client.Close();}
   }
  }
 }
}