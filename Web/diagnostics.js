/* Bowerbird Diagnostics & Feedback — browser-native, no dependencies, no uploads.
   Session recording is opt-in and memory-only. Errors are retained in memory.
   Only explicit Save Issue sends operator-entered report fields to localhost.
*/
(function(){
 'use strict';
 const $=id=>document.getElementById(id);
 const recorder={
  active:false,id:'',started:null,events:[],countErrors:0,issues:[],offlineIssues:[],
  lastAction:'',lastRequestId:'',token:'',serverEvents:[],requestStats:[],
  activated:false,latestBundle:null
 };
 const LIMIT=500;
 const now=()=>new Date().toISOString();
 const short=()=>Date.now().toString(36);
 const safeIdentifier=value=>String(value||'unknown').replace(/[^a-zA-Z0-9_.:-]/g,'_').slice(0,64);
 function safeMessage(value){
  let v=String(value||'').slice(0,600);
  v=v.replace(/(authorization|bearer|password|secret|api[_-]?key|token|credential)\s*[:=]\s*[^\s,;&]+/gi,'$1=[REDACTED]');
  v=v.replace(/https?:\/\/\S+/gi,'[URL REDACTED]');
  v=v.replace(/(?:[a-z]:\\|\\\\)[^\s"'<>|]+/gi,'[PATH REDACTED]');
  v=v.replace(/[A-Za-z0-9_-]{48,}/g,'[LONG VALUE REDACTED]');
  return v.replace(/[\r\n\t]+/g,' ').slice(0,260);
 }
 function isError(type){return /ERROR|FAILURE|REJECTED|HTTP_4|HTTP_5/.test(type)}
 function emit(type,detail={},force=false){
  if(!recorder.active&&!force)return;
  const entry={time:now(),type:safeIdentifier(type)};
  if(detail.target)entry.target=safeIdentifier(detail.target);
  if(detail.route)entry.route=safeIdentifier(detail.route);
  if(detail.status!==undefined)entry.status=Number(detail.status)||0;
  if(detail.elapsedMs!==undefined)entry.elapsedMs=Math.max(0,Math.round(Number(detail.elapsedMs)||0));
  if(detail.requestId&&/^[a-f0-9]{12}$/.test(detail.requestId))entry.requestId=detail.requestId;
  if(detail.message)entry.message=safeMessage(detail.message);
  recorder.events.push(entry);
  if(recorder.events.length>LIMIT)recorder.events.splice(0,recorder.events.length-LIMIT);
  if(isError(entry.type))recorder.countErrors++;
  updateCounters();
  if(document.getElementById('view-diagnostics')?.classList.contains('active'))renderTimeline();
 }
 function setToken(token){recorder.token=token||''}
 async function call(route,body={}){
  if(!recorder.token)throw Error('Missing local session. Relaunch Bowerbird from Start-Bowerbird.bat.');
  const response=await fetch('/api/'+route,{
   method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':recorder.token},
   body:JSON.stringify(body),cache:'no-store'
  });
  const data=await response.json();
  if(!response.ok)throw Error(safeMessage(data.error||'Request failed')+
   (data.requestId?' [Request '+data.requestId+']':''));
  return data;
 }
 // Intercept response status, duration and request ID; never inspect bodies or headers containing secrets.
 const nativeFetch=window.fetch.bind(window);
 window.fetch=function(resource,options){
  let pathname='';
  try{pathname=new URL(typeof resource==='string'?resource:resource.url,location.href).pathname}catch{}
  // Heartbeats run every 5 s; recording them would bury the user's own actions.
  const monitored=pathname.startsWith('/api/')&&pathname!=='/api/client-event'&&pathname!=='/api/heartbeat';
  const started=monitored?Date.now():0;
  return nativeFetch(resource,options).then(response=>{
   if(monitored){
    const status=response.status;
    const requestId=response.headers.get('X-Bowerbird-Request-ID')||'';
    if(!response.ok&&/^[a-f0-9]{12}$/.test(requestId))recorder.lastRequestId=requestId;
    if(!response.ok||recorder.active)emit(
     response.ok?'API_OK':'API_ERROR',
     {route:pathname.replace('/api/',''),status,elapsedMs:Date.now()-started,requestId},
     !response.ok
    );
   }
   return response;
  }).catch(error=>{
   if(monitored)emit('NETWORK_ERROR',{route:pathname.replace('/api/',''),message:error.name||'Network failure',elapsedMs:Date.now()-started},true);
   throw error;
  });
 };
 window.addEventListener('error',event=>{
  emit('BROWSER_ERROR',{target:'javascript',message:(event.error&&event.error.name?event.error.name+': ':'')+(event.message||'Script error')},true);
 });
 window.addEventListener('unhandledrejection',event=>{
  const reason=event.reason;
  emit('UNHANDLED_REJECTION',{target:'javascript',message:reason&&reason.message?reason.name+': '+reason.message:String(reason||'Unhandled promise')},true);
 });
 document.addEventListener('click',event=>{
  const button=event.target&&event.target.closest?event.target.closest('button'):null;
  if(!button)return;
  const target=safeIdentifier(button.id||button.dataset.view||button.dataset.agent||'button');
  const isDiagnostic=!!button.closest('#view-diagnostics');
  if(!isDiagnostic){recorder.lastAction=target;const hint=$('diag-last-action');if(hint)hint.textContent='Last action: '+target}
  emit('BUTTON_CLICK',{target});
 },true);
 document.addEventListener('change',event=>{
  if(!recorder.active)return;
  const element=event.target;
  if(!element||!element.id||element.closest('#view-diagnostics'))return;
  if(element.matches('input[type=checkbox],select'))emit('CONTROL_CHANGED',{target:element.id});
 },true);
 const options={
  'all':()=>true,
  'errors':e=>isError(e.type),
  'actions':e=>e.type==='BUTTON_CLICK'||e.type==='CONTROL_CHANGED'||e.type==='PAGE_CHANGED'||e.type==='FILE_SELECTED',
  'api':e=>e.type.startsWith('API_')||e.type==='NETWORK_ERROR'
 };
 function updateCounters(){
  if(!$('diag-stat-events'))return;
  $('diag-stat-events').textContent=recorder.events.length;
  $('diag-stat-errors').textContent=recorder.countErrors;
  $('diag-stat-issues').textContent=recorder.issues.length;
  $('diag-stat-recording').textContent=recorder.active?'On':'Off';
  $('diag-record-state').textContent=recorder.active?'● Recording':'Not recording';
  $('diag-record-state').classList.toggle('active',recorder.active);
  $('diag-record-start').disabled=recorder.active;
  $('diag-record-stop').disabled=!recorder.active;
  $('diag-last-action').textContent='Last action: '+(recorder.lastAction||'none');
 }
 function empty(container,message){
  container.replaceChildren();
  const item=document.createElement('p');item.className='muted';item.textContent=message;container.append(item);
 }
 function renderEntries(container,events,label){
  container.replaceChildren();
  if(!events.length){empty(container,label);return}
  for(const e of events.slice(-160).reverse()){
   const div=document.createElement('div');div.className='diag-row';
   if(isError(e.type)||e.level==='ERROR')div.classList.add('diag-row-error');
   const main=document.createElement('div');main.className='diag-row-main';
   const name=document.createElement('strong');name.textContent=e.type||e.event||'EVENT';
   const meta=document.createElement('small');meta.textContent=
    [e.time?new Date(e.time).toLocaleTimeString():'',e.route||e.target||'',e.status?'HTTP '+e.status:'',e.elapsedMs!==undefined?e.elapsedMs+'ms':''].filter(Boolean).join('  ·  ');
   main.append(name,meta);div.append(main);
   if(e.message){const msg=document.createElement('div');msg.className='diag-row-detail';msg.textContent=e.message;div.append(msg)}
   if(e.requestId){const id=document.createElement('code');id.className='diag-request';id.textContent='Request '+e.requestId;div.append(id)}
   container.append(div);
  }
 }
 function renderTimeline(){
  const filter=$('diag-event-filter').value;
  renderEntries($('diag-timeline'),recorder.events.filter((options[filter]||options.all)),
   'No events to display. Start recording and reproduce the problem.');
 }
 function renderServerEvents(){
  const filter=$('diag-server-filter').value;
  let list=recorder.serverEvents.map(x=>({
   time:x.time,type:x.event,route:x.route,requestId:x.requestId,message:x.message,
   level:x.level,status:(/\bHTTP\s+(\d+)/.exec(x.message||'')||[])[1]||undefined
  }));
  if(filter==='errors')list=list.filter(x=>x.level==='ERROR'||x.level==='WARN');
  if(filter==='requests')list=list.filter(x=>x.type==='REQUEST'||x.type==='HTTP_ERROR');
  renderEntries($('diag-server-events'),list,'No matching backend events were found.');
 }
 async function refreshLogs(){
  const data=await call('diagnostics',{});
  recorder.serverEvents=Array.isArray(data.events)?data.events:[];
  renderServerEvents();
  return data;
 }
 async function refreshHealth(){
  const result=await call('diagnostics/health',{});
  const target=$('diag-health');target.replaceChildren();
  for(const check of result.checks||[]){
   const row=document.createElement('div');row.className='diag-check';
   const icon=document.createElement('span');icon.className='diag-check-icon';icon.textContent=check.ok?'✓':'—';
   const label=document.createElement('div');const title=document.createElement('strong');title.textContent=check.name;
   const detail=document.createElement('small');detail.textContent=check.detail||'';
   label.append(title,detail);row.append(icon,label);target.append(row);
  }
  return result;
 }
 async function refreshIssues(){
  const data=await call('feedback/list',{});
  recorder.issues=[...(Array.isArray(data.issues)?data.issues:[]),...recorder.offlineIssues];
  updateCounters();renderIssues();
  return recorder.issues;
 }
 function renderIssues(){
  const target=$('diag-issues');target.replaceChildren();
  if(!recorder.issues.length){empty(target,'No issues saved. Describe a problem on the left and click Save.');return}
  for(const issue of recorder.issues){
   const card=document.createElement('div');card.className='diag-issue-card';
   const row=document.createElement('div');row.className='diag-issue-head';
   const title=document.createElement('strong');title.textContent=issue.title;
   const status=document.createElement('span');status.className='diag-issue-status';status.textContent=issue.status||'open';
   row.append(title,status);card.append(row);
   const meta=document.createElement('small');meta.textContent=
    [issue.feature,issue.kind,issue.severity,new Date(issue.createdUtc).toLocaleDateString()].join(' · ');
   card.append(meta);
   const id=document.createElement('code');id.className='diag-request';id.textContent='ID '+issue.id.slice(0,12);card.append(id);
   const buttons=document.createElement('div');buttons.className='diag-issue-actions';
   const view=document.createElement('button');view.type='button';view.className='ghost';view.textContent='View Details';
   view.addEventListener('click',()=>{
    const existing=card.querySelector('.diag-issue-description');
    if(existing){existing.remove();view.textContent='View Details';return}
    const detail=document.createElement('div');detail.className='diag-issue-description';
    for(const [label,content] of [['Observed',issue.actual],['Expected',issue.expected],['Steps',issue.steps]]){
     if(!content)continue;
     const p=document.createElement('p');const b=document.createElement('strong');b.textContent=label+': ';
     p.append(b,document.createTextNode(content));detail.append(p);
    }
    card.append(detail);view.textContent='Hide Details';
   });
   const resolve=document.createElement('button');resolve.type='button';resolve.className='ghost';
   resolve.textContent=issue.status==='download-only'?'Downloaded Only':issue.status==='resolved'?'Reopen':'Mark Resolved';
   if(issue.status==='download-only')resolve.disabled=true;
   resolve.addEventListener('click',async()=>{
    resolve.disabled=true;
    try{await call('feedback/status',{id:issue.id,status:issue.status==='resolved'?'open':'resolved'});
     await refreshIssues();showFeedback('Issue status saved locally.')}
    catch(err){resolve.disabled=false;showFeedback(err.message,true)}
   });
   buttons.append(view,resolve);card.append(buttons);target.append(card);
  }
 }
 function showFeedback(msg,fail=false){
  const target=$('diag-issue-result');if(!target)return;
  target.textContent=msg;target.className=fail?'diag-message-error':'diag-message-success';
 }
 function featureFor(target){
  if(/folder|browse|workspace/.test(target))return 'folder-picker';
  if(/index/.test(target))return 'index';
  if(/rename/.test(target))return 'rename';
  if(/duplicate|exact|visual/.test(target))return 'duplicates';
  if(/apply|plan|undo|rules/.test(target))return 'organize';
  if(/search/.test(target))return 'search';
  if(/assistant|chat/.test(target))return 'assistant';
  if(/code/.test(target))return 'code';
  if(/diagnostic|diag/.test(target))return 'diagnostics';
  return 'other';
 }
 function prefillIssueFromLastAction(){
  const target=recorder.lastAction||'unknown';
  $('diag-issue-kind').value='not-working';
  $('diag-issue-feature').value=featureFor(target);
  $('diag-issue-title').value=target==='unknown'?'Feature is not working':'The '+target+' control is not working';
  $('diag-issue-actual').value='I selected '+target+', but it did not behave as expected.';
  $('diag-issue-expected').value='';
  $('diag-issue-steps').value='';
  $('diag-issue-last').checked=true;
  $('diag-issue-title').focus();
  showFeedback('The report is prefilled. Add details, then click Save Local Issue Report.');
 }
 function start(){
  recorder.id='s-'+short();recorder.started=now();recorder.events=[];recorder.countErrors=0;
  recorder.active=true;emit('SESSION_START',{target:'diagnostics'},true);
  updateCounters();renderTimeline();
 }
 function stop(){emit('SESSION_STOP',{target:'diagnostics'},true);recorder.active=false;updateCounters()}
 function clearSession(){
  if(recorder.active)stop();
  recorder.events=[];recorder.countErrors=0;recorder.lastAction='';recorder.lastRequestId='';recorder.id='';recorder.started=null;
  updateCounters();renderTimeline();
 }
 function download(name,body,contentType){
  const blob=new Blob([body],{type:contentType||'application/json'});
  const url=URL.createObjectURL(blob);const anchor=document.createElement('a');
  anchor.href=url;anchor.download=name;anchor.style.display='none';document.body.append(anchor);anchor.click();
  anchor.remove();setTimeout(()=>URL.revokeObjectURL(url),12000);
 }
 function sessionData(){
  return {schemaVersion:1,sessionId:recorder.id||'',started:recorder.started,exportedUtc:now(),
   privacyNotice:'No typed values, prompts, document contents, or credentials captured automatically.',
   events:recorder.events};
 }
 async function buildSupport(includeNotes){
  let server;let fallback=false;
  try{server=await call('diagnostics/support',{includeNotes})}
  catch(_){
   fallback=true;
   server={
    schemaVersion:2,generatedUtc:now(),environment:{product:'Bowerbird Studio',version:'2.3'},
    privacyNotice:'Browser-only emergency bundle. The backend could not be reached.',
    serverEvents:recorder.serverEvents,issues:[],offline:true
   };
  }
  const unsaved=recorder.offlineIssues.map(issue=>includeNotes?issue:{
   id:issue.id,createdUtc:issue.createdUtc,status:issue.status,
   kind:issue.kind,severity:issue.severity,feature:issue.feature,lastAction:issue.lastAction,
   requestId:issue.requestId
  });
  const payload={
   ...server,offlineIssues:unsaved,clientSession:sessionData(),
   lastKnownRequestId:recorder.lastRequestId||'',
   exportDisclaimer:'Review this file before sharing. Manually entered notes may include sensitive information.'
  };
  recorder.latestBundle=payload;
  const json=JSON.stringify(payload,null,2);
  $('diag-support-preview').textContent=json.slice(0,13000)+(json.length>13000?'\n\n[PREVIEW TRUNCATED — download includes the remainder]':'');
  if(fallback)showFeedback('Backend is offline: the package contains browser events, cached sanitized server logs and unsaved issue metadata only.',true);
  return json;
 }
 async function copy(text){
  if(navigator.clipboard&&navigator.clipboard.writeText){await navigator.clipboard.writeText(text);return true}
  const area=document.createElement('textarea');area.value=text;area.style.position='fixed';area.style.left='-9999px';
  document.body.append(area);area.focus();area.select();
  try{return document.execCommand('copy')}finally{area.remove()}
 }
 async function refreshAll(){
  const results=await Promise.allSettled([refreshLogs(),refreshIssues(),refreshHealth()]);
  const errors=results.filter(x=>x.status==='rejected');
  if(errors.length)showFeedback('Some checks failed: '+errors.map(x=>safeMessage(x.reason.message)).join('; '),true);
  else showFeedback('Diagnostics refreshed. Nothing was sent outside this computer.');
  updateCounters();renderTimeline();
 }
 let installed=false;
 function setup(){
  if(installed)return;installed=true;
  $('diag-record-start').addEventListener('click',start);
  $('diag-record-stop').addEventListener('click',stop);
  $('diag-record-clear').addEventListener('click',()=>{clearSession();showFeedback('Local session recording cleared. Saved reports and server log remain.')});
  $('diag-record-export').addEventListener('click',()=>{download('bowerbird-session-'+(recorder.id||short())+'.json',JSON.stringify(sessionData(),null,2));showFeedback('Session downloaded locally.')});
  $('diag-mark-not-working').addEventListener('click',prefillIssueFromLastAction);
  $('diag-event-filter').addEventListener('change',renderTimeline);
  $('diag-server-filter').addEventListener('change',renderServerEvents);
  $('diag-refresh-all').addEventListener('click',refreshAll);
  $('diag-server-refresh').addEventListener('click',async()=>{try{await refreshLogs();showFeedback('Server log refreshed.')}catch(err){showFeedback(err.message,true)}});
  $('diag-issues-refresh').addEventListener('click',async()=>{try{await refreshIssues();showFeedback('Issue list refreshed.')}catch(err){showFeedback(err.message,true)}});
  $('diag-health-refresh').addEventListener('click',async()=>{try{await refreshHealth();showFeedback('Local checks completed.')}catch(err){showFeedback(err.message,true)}});
  $('diag-issue-reset').addEventListener('click',()=>{$('diag-issue-form').reset();showFeedback('Report form cleared.')});
  $('diag-issue-form').addEventListener('submit',async event=>{
   event.preventDefault();const save=$('diag-issue-save');save.disabled=true;
   const payload={
    kind:$('diag-issue-kind').value,severity:$('diag-issue-severity').value,
    feature:$('diag-issue-feature').value,title:$('diag-issue-title').value,
    actual:$('diag-issue-actual').value,expected:$('diag-issue-expected').value,
    steps:$('diag-issue-steps').value,
    lastAction:$('diag-issue-last').checked?recorder.lastAction:'',
    requestId:$('diag-issue-last').checked?recorder.lastRequestId:''
   };
   try{
    const issue=await call('feedback/create',payload);
    await refreshIssues();
    showFeedback('Saved locally · Issue '+issue.id.slice(0,12)+'. Export a support bundle to share a report.');
    $('diag-issue-form').reset();
   }catch(err){
    // Preserve the operator's explicit report even if the local engine crashes.
    const issue={
     schemaVersion:1,id:'offline-'+short(),createdUtc:now(),
     status:'download-only',...payload
    };
    recorder.offlineIssues.unshift(issue);
    recorder.issues.unshift(issue);updateCounters();renderIssues();
    try{
     const emergency={...issue,recordedSession:sessionData(),
      notice:'Backend save failed; keep this file locally. Nothing was uploaded.'};
     download('bowerbird-emergency-issue-'+short()+'.json',JSON.stringify(emergency,null,2));
     showFeedback('The local backend could not save this report: '+safeMessage(err.message)+'. An emergency JSON download was requested; check Downloads and review before sharing.',true);
    }catch(downloadError){
     showFeedback('The backend is unavailable and automatic downloading failed. Select and copy your report text before closing the browser.',true);
    }
   }finally{save.disabled=false}
  });
  $('diag-support-export').addEventListener('click',async()=>{
   const includeNotes=$('diag-export-notes').checked;
   if(includeNotes&&!window.confirm('Include the notes you typed in reports? Review the package before sharing.'))return;
   try{
    const json=await buildSupport(includeNotes);
    download('bowerbird-support-'+new Date().toISOString().slice(0,10)+'.json',json);
    showFeedback(recorder.latestBundle&&recorder.latestBundle.offline?'Partial browser-only support bundle download requested: backend was unreachable. Review the file before sharing.':'Support bundle download requested locally. Nothing was uploaded.');
   }catch(err){showFeedback(err.message,true)}
  });
  $('diag-support-copy').addEventListener('click',async()=>{
   try{
    const server=await call('diagnostics/support',{includeNotes:false});
    const summary=[
     'BOWERBIRD DIAGNOSTIC SUMMARY',
     'Version: '+server.environment.version,
     'PowerShell: '+server.environment.powershell,
     'Backend: '+server.environment.transport,
     'Server events: '+server.counts.serverEvents,
     'Warnings/errors: '+server.counts.warningsAndErrors,
     'Saved issue reports: '+server.counts.issues,
     'Session events: '+recorder.events.length,
     'Last API request ID: '+(recorder.lastRequestId||'none'),
     'No free-text issue notes or workspace paths included.'
    ].join('\n');
    if(!await copy(summary))throw Error('Browser clipboard unavailable');
    showFeedback('Safe troubleshooting summary copied.');
   }catch(err){showFeedback('Copy failed: '+err.message,true)}
  });
  updateCounters();renderTimeline();
 }
 function activate(){
  setup();if(!recorder.activated){recorder.activated=true;refreshAll()}else{renderTimeline();renderServerEvents();updateCounters()}
 }
 window.BowerbirdDiagnostics={
  setToken,activate,
  event:(type,detail)=>{if(type==='FILE_SELECTED'&&detail&&detail.target){recorder.lastAction=safeIdentifier(detail.target);updateCounters()}emit(type,detail,isError(type))},
  page:view=>emit('PAGE_CHANGED',{target:view}),
  lastRequestId:()=>recorder.lastRequestId,
  sessionState:()=>({active:recorder.active,eventCount:recorder.events.length,errors:recorder.countErrors})
 };
})();