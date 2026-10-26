// CI-only, dependency-free Chromium DevTools test of the actual GUI folder selector.
// Does not run on or install anything on an operational workstation.
'use strict';
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const {spawn,execFileSync}=require('node:child_process');
const assert=require('node:assert/strict');
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const [url,selectedFolder,edgeBinary]=process.argv.slice(2);
if(!url||!selectedFolder||!edgeBinary)throw Error('Usage: node GuiFolderSwitch.js <session-url> <folder> <edge-exe>');
if(typeof WebSocket!=='function')throw Error('Node built-in WebSocket is required on the CI runner.');
const profile=fs.mkdtempSync(path.join(os.tmpdir(),'bowerbird-cdp-'));
const deadline=Date.now()+30000;
let edge=null,ws=null,nextId=0;
const pending=new Map();
async function until(fn,label){
 while(Date.now()<deadline){
  try{const result=await fn();if(result)return result}catch(err){if(Date.now()+1000>=deadline)throw err}
  await sleep(180);
 }
 throw Error('Timed out: '+label);
}
function call(method,params){
 const id=++nextId;
 return new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{pending.delete(id);reject(Error('CDP timeout: '+method))},15000);
  pending.set(id,{resolve,reject,timer});
  ws.send(JSON.stringify({id,method,params}));
 });
}
async function evaluate(expression){
 const response=await call('Runtime.evaluate',{expression,awaitPromise:true,returnByValue:true});
 if(response.exceptionDetails)throw Error('Browser exception: '+response.exceptionDetails.text);
 return response.result&&response.result.value;
}
async function main(){
 edge=spawn(edgeBinary,[
  '--headless=new','--disable-gpu','--disable-background-networking','--disable-extensions',
  '--no-first-run','--no-default-browser-check','--remote-debugging-port=0',
  '--remote-allow-origins=*','--user-data-dir='+profile,url
 ],{stdio:'ignore'});
 const debugFile=path.join(profile,'DevToolsActivePort');
 const port=await until(()=>{
  if(!fs.existsSync(debugFile))return null;
  const raw=fs.readFileSync(debugFile,'utf8').split(/\r?\n/)[0].trim();
  return /^\d+$/.test(raw)?Number(raw):null;
 },'Edge DevTools port');
 const pages=await until(async()=>{
  const res=await fetch('http://127.0.0.1:'+port+'/json');
  if(!res.ok)return null;
  const items=await res.json();
  return items.find(x=>x.type==='page'&&x.url.includes('127.0.0.1')&&x.webSocketDebuggerUrl);
 },'Bowerbird browser target');
 ws=new WebSocket(pages.webSocketDebuggerUrl);
 await new Promise((resolve,reject)=>{
  const t=setTimeout(()=>reject(Error('DevTools socket timed out')),7000);
  ws.addEventListener('open',()=>{clearTimeout(t);resolve()},{once:true});
  ws.addEventListener('error',()=>{clearTimeout(t);reject(Error('DevTools WebSocket failed'))},{once:true});
 });
 ws.addEventListener('message',event=>{
  try{
   const message=JSON.parse(String(event.data));
   const current=pending.get(message.id);
   if(!current)return;
   pending.delete(message.id);clearTimeout(current.timer);
   if(message.error)current.reject(Error(JSON.stringify(message.error)));
   else current.resolve(message.result);
  }catch(err){console.error('CDP message failed:',err.message)}
 });
 const initial=await until(()=>evaluate(
  "!!document.getElementById('workspace-path') && document.getElementById('connection').textContent.includes('connected') && document.getElementById('file-table').textContent.includes('BowerbirdGuiProbe.txt')"
 ),'Initial GUI explorer populated');
 assert.equal(initial,true);
 const value=JSON.stringify(selectedFolder);
 const clicked=await evaluate(
  "(()=>{const field=document.getElementById('workspace-path');const button=document.getElementById('change-folder');if(!field||!button)throw Error('Controls missing');field.value="+value+";button.click();return true})()"
 );
 assert.equal(clicked,true);
 const displayed=await until(()=>evaluate(
  "document.getElementById('workspace-current').textContent === "+value+
  " && document.getElementById('file-table').textContent.includes('BrowserSelected.txt')"+
  " && !document.getElementById('file-table').textContent.includes('BowerbirdGuiProbe.txt')"
 ),'GUI selected-folder explorer updated');
 assert.equal(displayed,true);
 const state=await evaluate("({current:document.getElementById('workspace-path').value,scan:document.getElementById('index-state').textContent,folder:document.getElementById('workspace-current').textContent,notice:document.getElementById('notice').textContent})");
 assert.equal(state.folder,selectedFolder);
 assert.equal(state.current,selectedFolder);
 assert.match(state.notice,/Scan folder changed/i);
 assert.match(state.scan,/Not indexed/i);
 console.log('PASS: Edge GUI Use This Folder button switched workspace and refreshed Explorer');
 // Exercise diagnostics navigation, recording, reporting and issue status.
 assert.equal(await evaluate("(()=>{const tab=document.querySelector('[data-view=diagnostics]');if(!tab)throw Error('Diagnostics tab missing');tab.click();return true})()"),true);
 const diagReady=await until(()=>evaluate(
  "document.getElementById('view-diagnostics').classList.contains('active') && document.getElementById('diag-health').textContent.includes('Local backend')"
 ),'Diagnostics tab and local health checks initialized');
 assert.equal(diagReady,true);
 await evaluate("document.getElementById('diag-record-start').click();true");
 await evaluate("document.querySelector('[data-view=files]').click();true");
 await evaluate("document.getElementById('refresh').click();true");
 await until(()=>evaluate("document.getElementById('file-table').textContent.includes('BrowserSelected.txt')"),'Explorer reloaded while recording');
 await evaluate("document.querySelector('[data-view=diagnostics]').click();true");
 const recorded=await until(()=>evaluate(
  "Number(document.getElementById('diag-stat-events').textContent)>2 && document.getElementById('diag-stat-recording').textContent==='On'"
 ),'Diagnostics recorded actions and API outcomes');
 assert.equal(recorded,true);
 const issueTitle='GUI browser test broken-feature report';
 const submitted=await evaluate("(()=>{"+
  "document.getElementById('diag-issue-kind').value='not-working';"+
  "document.getElementById('diag-issue-severity').value='high';"+
  "document.getElementById('diag-issue-feature').value='explorer';"+
  "document.getElementById('diag-issue-title').value="+JSON.stringify(issueTitle)+";"+
  "document.getElementById('diag-issue-actual').value='Refresh did not work in the test scenario.';"+
  "document.getElementById('diag-issue-expected').value='The explorer refreshes.';"+
  "document.getElementById('diag-issue-save').click();return true})()");
 assert.equal(submitted,true);
 const saved=await until(()=>evaluate(
  "document.getElementById('diag-issues').textContent.includes("+JSON.stringify(issueTitle)+") && document.getElementById('diag-issue-result').textContent.includes('Saved locally')"
 ),'Broken feature issue saved locally in the GUI');
 assert.equal(saved,true);
 await evaluate("(()=>{"+
  "const cards=[...document.querySelectorAll('#diag-issues .diag-issue-card')];"+
  "const card=cards.find(c=>c.textContent.includes("+JSON.stringify(issueTitle)+"));"+
  "if(!card)throw Error('Saved report missing');"+
  "const resolved=[...card.querySelectorAll('button')].find(b=>b.textContent==='Mark Resolved');"+
  "if(!resolved)throw Error('Resolve action missing');resolved.click();return true})()");
 const resolved=await until(()=>evaluate(
  "(()=>{const card=[...document.querySelectorAll('#diag-issues .diag-issue-card')].find(c=>c.textContent.includes("+JSON.stringify(issueTitle)+"));return card&&card.querySelector('.diag-issue-status')?.textContent==='resolved'})()"
 ),'Mark Resolved updated saved issue');
 assert.equal(resolved,true);
 await evaluate("document.getElementById('diag-record-stop').click();true");
 assert.equal(await evaluate("document.getElementById('diag-stat-recording').textContent"),'Off');
 console.log('PASS: Edge Diagnostics tab recorded actions, saved a broken-feature report and updated its status');
 // Simulate failure of the local issue endpoint while retaining the already loaded UI.
 // The feedback form must still create a browser-only emergency download.
 await evaluate("(()=>{window.__bowerbirdOriginalFetch=window.fetch;window.fetch=function(url,options){if(String(url).includes('/api/feedback/create'))return Promise.reject(new Error('Simulated local backend outage'));return window.__bowerbirdOriginalFetch(url,options)};return true})()");
 const offlineTitle='Browser emergency error report';
 await evaluate("(()=>{"+
  "document.getElementById('diag-issue-title').value="+JSON.stringify(offlineTitle)+";"+
  "document.getElementById('diag-issue-actual').value='Simulated backend failure during Save';"+
  "document.getElementById('diag-issue-save').click();return true})()");
 const emergency=await until(()=>evaluate(
  "document.getElementById('diag-issues').textContent.includes("+JSON.stringify(offlineTitle)+") && "+
  "document.getElementById('diag-issues').textContent.includes('download-only') && "+
  "document.getElementById('diag-issue-result').textContent.includes('emergency JSON')"
 ),'Offline emergency report created in the browser');
 assert.equal(emergency,true);
 await evaluate("(()=>{window.fetch=window.__bowerbirdOriginalFetch;delete window.__bowerbirdOriginalFetch;return true})()");
 console.log('PASS: Diagnostics captured an emergency issue locally when the feedback backend was unreachable');
}
main().catch(err=>{console.error('FAIL: GUI folder selector: '+err.stack);process.exitCode=1}).finally(()=>{
 if(ws){try{ws.close()}catch{}}
 for(const task of pending.values())clearTimeout(task.timer);
 if(edge&&!edge.killed){
  try{execFileSync('taskkill.exe',['/PID',String(edge.pid),'/T','/F'],{stdio:'ignore'})}
  catch{try{edge.kill()}catch{}}
 }
 try{fs.rmSync(profile,{recursive:true,force:true,maxRetries:5,retryDelay:100})}catch{}
});
