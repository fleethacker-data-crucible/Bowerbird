'use strict';
// The browser tab owns the local server. Every 5 s this page tells Bowerbird Studio it is still
// open; on pagehide it sends a "leaving" beacon. The server stops itself 20 s after the last
// heartbeat from every open tab, or 5 s after a leaving signal that no new heartbeat follows,
// so a reload (leave, then a fresh heartbeat from the new page) does not stop it.
(function(root){
 const INTERVAL_MS=5000;
 function newTabId(){
  try{const bytes=new Uint8Array(12);root.crypto.getRandomValues(bytes);return Array.from(bytes,b=>b.toString(16).padStart(2,'0')).join('')}
  catch(_){return 'tab'+Date.now().toString(36)+Math.random().toString(36).slice(2,10)}
 }
 const tab=newTabId();
 let token='';
 let timer=null;
 let failures=0;
 let ended=false;
 function hidden(){try{return root.document.visibilityState==='hidden'}catch(_){return false}}
 function body(leaving,withToken){
  const value={tab,leaving:!!leaving,hidden:hidden()};
  if(withToken)value.session=token;
  return JSON.stringify(value);
 }
 function send(leaving){
  if(!token||ended)return Promise.resolve(null);
  let request;
  try{
   request=root.fetch('/api/heartbeat',{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':token},body:body(leaving,false),cache:'no-store',keepalive:true});
  }catch(_){return Promise.resolve(null)}
  return Promise.resolve(request).then(response=>{failures=0;return response},()=>{
   failures++;
   if(failures===2&&typeof api.onServerGone==='function'){try{api.onServerGone()}catch(_){}}
   return null;
  });
 }
 function onHide(){
  if(!token||ended)return;
  // sendBeacon is what browsers deliver during unload; it cannot set headers, so the session
  // token travels in the JSON body, which the server accepts on /api/heartbeat only.
  let sent=false;
  try{
   if(root.navigator&&typeof root.navigator.sendBeacon==='function'){
    sent=root.navigator.sendBeacon('/api/heartbeat',new root.Blob([body(true,true)],{type:'application/json'}));
   }
  }catch(_){sent=false}
  if(!sent)send(true);
 }
 function onShow(){send(false)}
 function onVisibility(){send(false)}
 function start(sessionToken){
  if(!sessionToken||timer!==null)return stop;
  token=String(sessionToken);
  send(false);
  timer=root.setInterval(()=>send(false),INTERVAL_MS);
  root.addEventListener('pagehide',onHide);
  root.addEventListener('pageshow',onShow);
  if(root.document&&root.document.addEventListener)root.document.addEventListener('visibilitychange',onVisibility);
  return stop;
 }
 function stop(){
  if(timer!==null){root.clearInterval(timer);timer=null}
  root.removeEventListener('pagehide',onHide);
  root.removeEventListener('pageshow',onShow);
  if(root.document&&root.document.removeEventListener)root.document.removeEventListener('visibilitychange',onVisibility);
 }
 async function endSession(){
  if(!token)throw Error('Missing session token. Relaunch Bowerbird from Start-Bowerbird.bat.');
  const response=await root.fetch('/api/session/stop',{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':token,'X-Bowerbird-Intent':'end-session'},body:'{}',cache:'no-store'});
  let data={};try{data=await response.json()}catch(_){}
  if(!response.ok)throw Error(data.error||'The server did not end the session');
  ended=true;
  stop();
  return data;
 }
 const api={start,stop,endSession,tab,intervalMs:INTERVAL_MS,onServerGone:null};
 root.BowerbirdLifecycle=api;
})(typeof window!=='undefined'?window:globalThis);
