// Static browser contract tests; Node is CI-only, never required on Nautilus.
'use strict';
const fs=require('fs');
const path=require('path');
const assert=require('assert');
const html=fs.readFileSync(path.join(__dirname,'..','Web','index.html'),'utf8');
const js=fs.readFileSync(path.join(__dirname,'..','Web','app.js'),'utf8');
const css=fs.readFileSync(path.join(__dirname,'..','Web','style.css'),'utf8');
const diagnosticsJs=fs.readFileSync(path.join(__dirname,'..','Web','diagnostics.js'),'utf8');
new (require('vm').Script)(js,{filename:'Web/app.js'});
new (require('vm').Script)(diagnosticsJs,{filename:'Web/diagnostics.js'});
const ids=[...html.matchAll(/\bid="([^"]+)"/g)].map(x=>x[1]);
const known=new Set(ids);
assert.equal(ids.length,known.size,'DOM ids must be unique');
const required=[...new Set([...(js+'\n'+diagnosticsJs).matchAll(/\$\('([^']+)'\)/g)].map(x=>x[1]))];
for(const id of required)assert(known.has(id),'Missing HTML id: '+id);
for(const [,view] of html.matchAll(/data-view="([^"]+)"/g))assert(known.has('view-'+view),'Navigation target missing: '+view);
assert(!/\.innerHTML\s*=/.test(js+'\n'+diagnosticsJs),'Do not insert untrusted file contents via innerHTML');
assert(/@media/.test(css),'Responsive stylesheet expected');
assert(/\/api\/stream/.test(js),'Streaming chat route expected');
assert(html.includes('<script src="/diagnostics.js" defer></script>'),'Diagnostics script must be loaded');
for(const id of ['view-diagnostics','diag-record-start','diag-record-stop','diag-issue-save','diag-support-export','diag-server-events','diag-issues'])assert(known.has(id),'Required diagnostics UI missing: '+id);
assert(/feedback\/create/.test(diagnosticsJs),'Issue reporting endpoint missing');
console.log('PASS: Bowerbird browser UI contract ('+known.size+' ids, '+required.length+' bound selectors)');
// Lifecycle: the tab owns the server. Exercise Web/lifecycle.js against a fake browser.
const lifecycleJs=fs.readFileSync(path.join(__dirname,'..','Web','lifecycle.js'),'utf8');
assert(html.indexOf('<script src="/lifecycle.js" defer></script>')!==-1&&html.indexOf('/lifecycle.js')<html.indexOf('/app.js'),'lifecycle.js must load before app.js');
assert(known.has('end-session')&&/<nav[^]*id="end-session"[^]*<\/nav>/.test(html),'End session control must be in the main navigation');
{
 const fetches=[],beacons=[],listeners={},docListeners={},intervals=[];
 const fakeWindow={
  fetch:(url,options)=>{fetches.push({url,options});return Promise.resolve({ok:true,status:200,json:()=>Promise.resolve({ok:true,stopping:true})})},
  navigator:{sendBeacon:(url,blob)=>{beacons.push({url,blob});return true}},
  Blob:class{constructor(parts,opts){this.text=parts.join('');this.type=opts&&opts.type}},
  crypto:{getRandomValues:a=>{for(let i=0;i<a.length;i++)a[i]=i;return a}},
  setInterval:(fn,ms)=>{intervals.push({fn,ms});return intervals.length},
  clearInterval:id=>{intervals[id-1]=null},
  addEventListener:(name,fn)=>{listeners[name]=fn},
  removeEventListener:name=>{delete listeners[name]},
  document:{visibilityState:'visible',addEventListener:(name,fn)=>{docListeners[name]=fn},removeEventListener:name=>{delete docListeners[name]}}
 };
 const context=require('vm').createContext({window:fakeWindow,globalThis:fakeWindow,Uint8Array,Array,JSON,Promise,String,Error,Date,Math});
 new (require('vm').Script)(lifecycleJs,{filename:'Web/lifecycle.js'}).runInContext(context);
 const life=fakeWindow.BowerbirdLifecycle;
 assert(life&&typeof life.start==='function','BowerbirdLifecycle API');
 life.start('TOKEN123');
 assert.equal(fetches.length,1,'Heartbeat sent immediately on start');
 const first=fetches[0];
 assert.equal(first.url,'/api/heartbeat');
 assert.equal(first.options.method,'POST');
 assert.equal(first.options.headers['X-Bowerbird-Token'],'TOKEN123','Heartbeat uses the session header');
 const beat=JSON.parse(first.options.body);
 assert.equal(beat.leaving,false);
 assert(/^[0-9a-f]{24}$/.test(beat.tab),'Each page has its own tab id');
 assert(!('session' in beat),'A normal heartbeat never puts the token in the body');
 assert.equal(intervals.length,1);assert.equal(intervals[0].ms,5000,'Heartbeat every 5 s');
 intervals[0].fn();
 assert.equal(fetches.length,2,'Interval sends a heartbeat');
 assert(typeof listeners.pagehide==='function','pagehide listener installed');
 listeners.pagehide();
 assert.equal(beacons.length,1,'pagehide sends a beacon');
 assert.equal(beacons[0].url,'/api/heartbeat','Beacon goes to the heartbeat route, never a query string');
 const leaving=JSON.parse(beacons[0].blob.text);
 assert.equal(leaving.leaving,true);assert.equal(leaving.session,'TOKEN123','Beacon carries the token in the body');assert.equal(leaving.tab,beat.tab);
 assert.equal(beacons[0].blob.type,'application/json');
 listeners.pageshow();
 assert.equal(JSON.parse(fetches[fetches.length-1].options.body).leaving,false,'pageshow (back/forward cache) sends a fresh heartbeat');
 fakeWindow.navigator.sendBeacon=()=>false;
 listeners.pagehide();
 const fallback=fetches[fetches.length-1];
 assert(JSON.parse(fallback.options.body).leaving&&fallback.options.keepalive,'Falls back to a keepalive fetch when the beacon is refused');
 life.endSession().then(()=>{
  const stop=fetches[fetches.length-1];
  assert.equal(stop.url,'/api/session/stop');
  assert.equal(stop.options.headers['X-Bowerbird-Intent'],'end-session');
  assert.equal(intervals[0],null,'Heartbeats stop after End session');
  assert(!listeners.pagehide,'No leaving beacon after End session');
  console.log('PASS: Bowerbird lifecycle heartbeat, leaving beacon and End session');
 }).catch(err=>{console.error(err);process.exitCode=1});
}
