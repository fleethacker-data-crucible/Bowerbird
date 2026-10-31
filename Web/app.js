'use strict';
let storedToken=null;
try{storedToken=sessionStorage.getItem('bowerbird-token')}catch(_){/* Managed browsers may disable session storage. */}
const launchToken=new URLSearchParams(location.search).get('token');
const state={path:'.',token:launchToken||storedToken,status:null,plan:null,renamePlan:null,selectedFile:null,previewUrl:null};
if(state.token){
 try{sessionStorage.setItem('bowerbird-token',state.token);if(location.search)history.replaceState({},'',location.pathname)}catch(_){/* Keep the token in the URL when storage is unavailable. */}
}
if(window.BowerbirdDiagnostics)window.BowerbirdDiagnostics.setToken(state.token);
const $=id=>document.getElementById(id);
function record(event,target){
 if(!state.token||event==='CLICK'||event==='READY')return;
 const value=String(target||'unknown').replace(/[^a-zA-Z0-9_.:-]/g,'_').slice(0,80)||'unknown';
 fetch('/api/client-event',{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':state.token},body:JSON.stringify({event,target:value}),cache:'no-store'}).catch(()=>{});
}
window.addEventListener('error',e=>{record('CLIENT_ERROR','script_'+(e.filename||'browser').split('/').pop());const n=$('notice');if(n){n.textContent='A browser script error occurred. Open Diagnostics to review the local report.';n.className='error'}});
window.addEventListener('unhandledrejection',()=>{record('CLIENT_ERROR','unhandled_promise');const n=$('notice');if(n){n.textContent='A browser request failed. Open Diagnostics for details.';n.className='error'}});
document.addEventListener('click',e=>{const target=e.target&&e.target.closest?e.target.closest('button'):null;if(target){record('CLICK',target.id||target.dataset.view||'button')}},true);
function engine(name){if(window.BowerbirdShell)window.BowerbirdShell.setEngine(name);else $('connection').textContent=name}
function glyph(name){return window.BowerbirdIcons?window.BowerbirdIcons.icon(name,16):null}
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=String(text);return n}
function clear(n){n.replaceChildren()}
function notify(message,error=false){const n=$('notice');n.textContent=message;n.className=error?'error':''}
async function api(route,body={}){
 if(!state.token)throw Error('Missing session token. Launch the browser from the PowerShell Studio process.');
 const response=await fetch('/api/'+route,{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':state.token},body:JSON.stringify(body),cache:'no-store'});
 let data;try{data=await response.json()}catch{throw Error('Server returned an invalid response')}
 if(!response.ok){if(route!=='client-event')record('API_ERROR',route);throw Error((data.error||'Request failed')+(data.requestId?' [Request '+data.requestId+']':''))}
 return data
}
const spoken=window.BowerbirdVoice?window.BowerbirdVoice.create({synth:window.speechSynthesis,Utterance:window.SpeechSynthesisUtterance,lang:document.documentElement.lang||navigator.language||'en-US',isEnabled:()=>!!$('voice-toggle')&&$('voice-toggle').checked,onStatus:t=>{$('voice-status').textContent=t}}):null;
async function run(action,done){const job=spoken?spoken.begin():null;try{notify('Working…');const result=await action();notify(done||'Done');if(job)job.end(true,done||'Done');return result}catch(err){notify(err.message,true);if(job)job.end(false);return null}}
function initSpokenProgress(){
 const box=$('voice-toggle');if(!spoken){$('voice-status').textContent='Spoken progress is unavailable. Progress stays on screen.';box.disabled=true;return}
 let saved=false;try{saved=localStorage.getItem('bowerbird-voice')==='on'}catch(_){/* Storage may be disabled; the switch just starts off. */}
 box.checked=saved;spoken.refreshStatus();
 if(window.speechSynthesis&&window.speechSynthesis.addEventListener)window.speechSynthesis.addEventListener('voiceschanged',()=>spoken.refreshStatus());
 box.addEventListener('change',()=>{try{localStorage.setItem('bowerbird-voice',box.checked?'on':'off')}catch(_){/* Not remembered; still works for this page. */}if(box.checked)spoken.announceEnabled();else{spoken.stop();spoken.refreshStatus()}});
}
initSpokenProgress();
function size(bytes){if(bytes===null||bytes===undefined)return '—';if(bytes<1024)return bytes+' B';if(bytes<1048576)return (bytes/1024).toFixed(1)+' KB';return (bytes/1048576).toFixed(1)+' MB'}
function show(view){document.querySelectorAll('.nav').forEach(b=>{const on=b.dataset.view===view;b.classList.toggle('active',on);if(on)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current')});document.querySelectorAll('.view').forEach(s=>s.classList.toggle('active',s.id==='view-'+view));$('page-title').textContent=({files:'File Explorer',search:'Intelligent Search',insights:'Insights & Agents',duplicates:'Duplicate Detection',organize:'File Organization',rename:'Smart Rename',code:'Code Insights',assistant:'AI Assistant',diagnostics:'Diagnostics & Feedback'})[view];if(window.BowerbirdDiagnostics)window.BowerbirdDiagnostics.page(view);if(view==='diagnostics')return window.BowerbirdDiagnostics?.activate();if(view==='files')return loadFiles();if(view==='insights')return loadInsights()}
document.querySelectorAll('.nav').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));
async function loadStatus(){const s=await run(()=>api('status'));if(!s)return;state.status=s;engine('running');if(s.version)$('app-version').textContent='Bowerbird Studio '+s.version;$('workspace').textContent=s.root;$('workspace-current').textContent=s.root;$('workspace-path').value=s.root;$('index-state').textContent=s.indexExists?'Index available':'Not indexed';$('welcome').hidden=!!s.indexExists;$('ai-state').textContent=s.cloudAI?'Enabled':'Offline';$('ai-hint').textContent=s.cloudAI?'Streaming connection to configured provider':'Offline assistance · use -AllowCloudAI for approved provider';if(s.indexExists)loadInsights()}
function resetForWorkspaceSwitch(){
 state.path='.';
 state.plan=null;state.renamePlan=null;state.selectedFile=null;
 $('apply').disabled=true;$('rename-apply').disabled=true;$('related').disabled=true;
 $('cwd').textContent='.';$('file-count').textContent='—';$('index-state').textContent='Not indexed';$('welcome').hidden=false;$('size-state').textContent='—';
 $('preview-name').textContent='Select a file';$('preview-text').textContent='No file selected';
 if(state.previewUrl){URL.revokeObjectURL(state.previewUrl);state.previewUrl=null}
 clear($('media-preview'));clear($('file-table'));
 const placeholders={
  'search-results':'Build an index, then search this folder.',
  'duplicate-results':'No duplicate scan for this folder yet.',
  'plan-results':'No proposed moves. Generate a plan for the selected folder.',
  'rename-results':'No rename proposals for this folder yet.',
  'related-results':'','code-results':'Run an analysis for this folder.',
  'agent-results':'Run an agent after indexing this folder.',
  'category-results':'Build an index to view folder insights.'
 };
 for(const [id,label] of Object.entries(placeholders))$(id).textContent=label;
 for(const id of ['insight-files','insight-size','insight-dupes','insight-errors'])$(id).textContent='—';
}
let workspaceRequestRunning=false;
async function switchWorkspace(pathOrNull){
 if(workspaceRequestRunning)return;
 const buttons=[$('browse-folder'),$('change-folder')];
 workspaceRequestRunning=true;
 buttons.forEach(b=>b.disabled=true);
 const nativePicker=pathOrNull===null;
 try{
  notify(nativePicker?'Opening Windows folder picker…':'Changing scan folder…');
  const result=await api(nativePicker?'workspace/browse':'workspace/select',nativePicker?{}:{path:pathOrNull});
  if(result.cancelled){notify('Folder selection cancelled. No changes made.');return}
  if(!result.changed){
   $('workspace-path').value=result.root;
   notify('This folder is already selected.');return
  }
  resetForWorkspaceSwitch();
  await loadStatus();
  // Selecting a folder only changes the workspace; scanning is still explicit.
  await show('files');
  notify('Scan folder changed. Click Build Index when you are ready to scan this folder.');
 }catch(err){
  notify(err.message,true);
  // Keep the user-entered path so it can be corrected without typing it twice.
 }finally{
  buttons.forEach(b=>b.disabled=false);
  workspaceRequestRunning=false;
 }
}
$('workspace-form').addEventListener('submit',e=>{
 e.preventDefault();
 const path=$('workspace-path').value.trim();
 if(!path){notify('Select or enter an existing folder path.',true);return}
 switchWorkspace(path);
});
$('browse-folder').addEventListener('click',()=>switchWorkspace(null));
async function loadFiles(){
 const data=await run(()=>api('files',{path:state.path}));if(!data)return;
 $('cwd').textContent=data.path;$('file-count').textContent=data.items.length;const tbody=$('file-table');clear(tbody);
 for(const item of data.items){
  const tr=el('tr');tr.tabIndex=0;const td=el('td','name-cell');const icon=glyph(item.directory?'folder':'file');if(icon)td.append(icon);td.append(el('span','',item.name));if(item.directory)td.classList.add('folder');tr.append(td,el('td','',item.directory?'Folder':item.extension||'File'),el('td','num',size(item.size)),el('td','',new Date(item.modified).toLocaleString()));
  const open=()=>{if(window.BowerbirdDiagnostics)window.BowerbirdDiagnostics.event('FILE_SELECTED',{target:item.directory?'open-folder':'preview-file'});return item.directory?openFolder(item.path):preview(item.path)};
  tr.addEventListener('click',open);tr.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();open()}});tbody.append(tr)
 }
 if(!data.items.length){const tr=el('tr');const td=el('td','','Folder is empty');td.colSpan=4;tr.append(td);tbody.append(tr)}
}
function openFolder(path){state.path=path;loadFiles()}
$('up').addEventListener('click',()=>{state.path=state.path==='.'?'.':(state.path.split('/').slice(0,-1).join('/')||'.');loadFiles()});
async function preview(path){
 state.selectedFile=path;$('related').disabled=false;$('preview-name').textContent=path;clear($('related-results'));
 if(state.previewUrl){URL.revokeObjectURL(state.previewUrl);state.previewUrl=null}
 clear($('media-preview'));$('preview-text').textContent='';
 const ext=(path.split('.').pop()||'').toLowerCase();
 if(['png','jpg','jpeg','gif','webp','bmp','pdf'].includes(ext)){
  try{
   const resp=await fetch('/api/media',{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':state.token},body:JSON.stringify({path})});
   if(!resp.ok){const data=await resp.json();throw Error(data.error||'Preview failed')}
   state.previewUrl=URL.createObjectURL(await resp.blob());
   let visual;
   if(ext==='pdf'){
    visual=el('iframe','pdf-frame');visual.title='PDF preview';visual.setAttribute('sandbox','allow-scripts allow-same-origin');
   }else{visual=el('img','image-preview');visual.alt='Local preview: '+path}
   visual.src=state.previewUrl;$('media-preview').append(visual);
   notify('Preview loaded locally')
  }catch(err){$('preview-text').textContent=err.message;notify(err.message,true)}
 }else{
  const data=await run(()=>api('preview',{path}));$('preview-text').textContent=data?data.text:'Binary preview not available for this file'
 }
}
$('refresh').addEventListener('click',async()=>{await loadStatus();await loadFiles()});
$('index').addEventListener('click',async()=>{const contents=$('content-index').checked;if(contents&&!confirm('Extract and store document content in a plaintext local JSON index? Only continue for approved workspace content.'))return;const data=await run(()=>api('index',{path:state.path,recurse:$('recurse').checked,includeContent:contents,ocr:$('ocr-index').checked}),'Index built');if(data){if(state.status)state.status.indexExists=true;$('welcome').hidden=true;$('index-state').textContent=data.indexed+' files indexed';notify('Indexed '+data.indexed+' files.');loadInsights()}})
async function loadInsights(){if(!state.status||!state.status.indexExists)return;try{const d=await api('insights');$('insight-files').textContent=d.files;$('insight-size').textContent=size(d.bytes);$('insight-dupes').textContent=d.duplicateGroups;$('insight-errors').textContent=d.errors;$('size-state').textContent=size(d.bytes);const target=$('category-results');clear(target);for(const c of d.categories){const row=el('div','category-card');row.append(el('strong','',c.count),el('span','',c.name));target.append(row)}if(!d.categories.length)target.textContent='No files indexed.'}catch(err){notify(err.message,true)}}
function addResult(parent,title,subtitle,detail){const row=el('div','result');row.append(el('strong','',title));if(subtitle)row.append(el('small','',subtitle));if(detail)row.append(el('p','muted',detail));parent.append(row)}
$('search-form').addEventListener('submit',async e=>{e.preventDefault();const data=await run(()=>api('search',{query:$('search-query').value}),'Search complete');if(!data)return;const target=$('search-results');clear(target);for(const item of data.items)addResult(target,item.name,item.path+' · score '+item.score,item.snippet);if(!data.items.length)target.textContent='No matches found.'})
async function duplicates(visual){const data=await run(()=>api('duplicates',{visual}),'Duplicate scan complete');if(!data)return;const target=$('duplicate-results');clear(target);for(const group of data.groups)addResult(target,group.kind+' group · '+group.files.length+' files',group.key,group.files.join('  •  '));if(!data.groups.length)target.textContent='No duplicate groups detected.'}
$('related').addEventListener('click',async()=>{if(!state.selectedFile)return;const data=await run(()=>api('related',{path:state.selectedFile}),'Related file analysis complete');if(!data)return;const target=$('related-results');clear(target);for(const item of data.items)addResult(target,item.name,item.path,'Similarity score '+item.score);if(!data.items.length)target.textContent='No lexical relationships found.'});
document.querySelectorAll('.agent-btn').forEach(button=>button.addEventListener('click',async()=>{
 const data=await run(()=>api('agents',{agent:button.dataset.agent}),'Agent report ready');if(!data)return;const target=$('agent-results');clear(target);target.append(el('h3','',button.textContent+' · '+data.suggestions.length+' observations'));
 for(const item of data.suggestions)addResult(target,item.title,item.kind,item.detail);
 if(!data.suggestions.length)target.append(el('p','muted','Nothing requiring attention.'));
}));
$('exact').addEventListener('click',()=>duplicates(false));$('visual').addEventListener('click',()=>duplicates(true));
$('plan').addEventListener('click',async()=>{
 let rules;try{rules=JSON.parse($('rules').value);if(!Array.isArray(rules))throw Error('Rules must be a JSON array')}catch(e){notify('Invalid rules: '+e.message,true);return}
 const data=await run(()=>api('plan',{destination:$('destination').value,rules}),'Plan generated. Review every proposed move.');if(!data)return;
 state.plan=data;$('apply').disabled=!data.count;$('rename-apply').disabled=true;state.renamePlan=null;const target=$('plan-results');clear(target);target.append(el('h3','',data.count+' proposed moves'));
 for(const op of data.operations)addResult(target,op.source,'→ '+op.destination,op.reason);
 if(data.skipped&&data.skipped.length){target.append(el('h3','',data.skipped.length+' skipped for safety'));for(const op of data.skipped)addResult(target,op.source,'Skipped',op.reason)}
});
$('rules').addEventListener('input',()=>{$('apply').disabled=true;state.plan=null});$('destination').addEventListener('input',()=>{$('apply').disabled=true;state.plan=null});
$('apply').addEventListener('click',async()=>{
 if(!state.plan||!state.plan.count)return;
 if(!confirm('Move '+state.plan.count+' files? Review the preview carefully. This changes files on disk.'))return;
 const phrase=prompt('Type APPLY to authorize the proposed moves:');if(phrase!=='APPLY')return;
 const data=await run(()=>api('apply',{confirm:phrase,id:state.plan.id}),'Apply completed. Inspect results before further changes.');if(!data)return;
 $('apply').disabled=true;state.plan=null;const target=$('plan-results');clear(target);
 for(const r of data.results)addResult(target,r.Status,r.Source+' → '+r.Destination,r.Error||'');
});
$('undo').addEventListener('click',async()=>{
 if(!confirm('Attempt to restore files from the last journal? Existing destinations will not be overwritten.'))return;
 const phrase=prompt('Type UNDO to confirm:');if(phrase!=='UNDO')return;
 const data=await run(()=>api('undo',{confirm:phrase}),'Undo attempted. Review restored files.');if(data)notify('Undo returned '+(data.restored||[]).length+' restored entries.')
});

$('rename-plan').addEventListener('click',async()=>{
 const useVision=$('rename-vision').checked;
 if(useVision){
  if(!state.status||!state.status.cloudAI){notify('Vision requires -AllowCloudAI and an approved AI provider.',true);return}
  if(!confirm('This will send eligible image content to your configured AI service, up to the limit selected. Proceed only with approved images.'))return
 }
 const maxVision=Math.max(0,Math.min(25,Number($('rename-limit').value)||0));
 const data=await run(()=>api('rename-preview',{path:state.path,recurse:$('rename-recurse').checked,useVision,maxVision,consent:useVision?'VISION_UPLOAD':''}),'Rename proposals ready');
 if(!data)return;
 state.renamePlan=data;state.plan=null;$('apply').disabled=true;$('rename-apply').disabled=!data.count;
 const target=$('rename-results');clear(target);
 target.append(el('h3','',data.count+' rename proposals · '+data.vision+' vision calls'));
 for(const item of data.operations){
  addResult(target,item.source,'→ '+item.destination,'Confidence '+Math.round((item.confidence||0)*100)+'% · '+item.reason)
 }
 if(data.skipped&&data.skipped.length){
  target.append(el('h3','',data.skipped.length+' skipped'));
  for(const item of data.skipped)addResult(target,item.source,'Skipped',item.reason)
 }
 if(!data.count)target.append(el('p','muted','No eligible files found, or filenames are already appropriate.'))
});
$('rename-vision').addEventListener('change',()=>{state.renamePlan=null;$('rename-apply').disabled=true});
$('rename-limit').addEventListener('change',()=>{state.renamePlan=null;$('rename-apply').disabled=true});
$('rename-apply').addEventListener('click',async()=>{
 const plan=state.renamePlan;if(!plan||!plan.count)return;
 if(!confirm('Rename '+plan.count+' files exactly as previewed?'))return;
 if(prompt('Type APPLY to authorize these renames:')!=='APPLY')return;
 const result=await run(()=>api('apply',{confirm:'APPLY',id:plan.id}),'Renames applied. Undo Last Apply in Organize can restore them.');
 if(!result)return;
 state.renamePlan=null;$('rename-apply').disabled=true;
 const target=$('rename-results');clear(target);
 for(const entry of result.results)addResult(target,entry.Source,entry.Status,entry.Error||entry.Destination);
});

$('analyze-code').addEventListener('click',async()=>{
 const data=await run(()=>api('code',{path:'.',recurse:true}),'Source analysis complete');if(!data)return;
 const target=$('code-results');clear(target);const totals={};for(const item of data.items){const t=totals[item.language]||(totals[item.language]={files:0,code:0,lines:0});t.files++;t.code+=item.code;t.lines+=item.lines}
 for(const [language,t] of Object.entries(totals).sort((a,b)=>b[1].code-a[1].code))addResult(target,language,t.files+' files',t.code+' code lines / '+t.lines+' total lines');
 target.append(el('h3','',data.items.length+' source files'));
 for(const item of data.items)addResult(target,item.path,item.language,item.code+' code · '+item.comments+' comments · '+item.blank+' blank')
});
function bubble(text,kind){const n=el('div','bubble '+kind,text);$('messages').append(n);$('messages').scrollTop=$('messages').scrollHeight;return n}
$('chat-form').addEventListener('submit',async e=>{
 e.preventDefault();const prompt=$('chat-prompt').value.trim();if(!prompt)return;
 bubble(prompt,'user');$('chat-prompt').value='';const pending=bubble('Thinking…','bot');
 try{
  if(!state.status||!state.status.cloudAI){
   const requested=/duplicat|cleanup|copy|redundan/i.test(prompt)?'cleanup':/risk|privacy|error|problem/i.test(prompt)?'audit':'triage';
   const data=await api('agents',{agent:requested});
   pending.textContent='Local '+requested+' report (no cloud calls):\n'+(data.suggestions.length?data.suggestions.slice(0,18).map(x=>'• '+x.title+': '+x.detail).join('\n'):'No issues found.')+'\n\nFor generative analysis, relaunch with -AllowCloudAI and your approved AI credentials.';
   notify('Local agent response ready');return
  }
  await streamAi({prompt,includeIndex:$('chat-index').checked},text=>{pending.textContent=text});
  notify('Streaming response complete');
 }catch(err){pending.textContent='Request failed: '+err.message;notify(err.message,true)}
});
async function streamAi(payload,onText){
 const response=await fetch('/api/stream',{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':state.token},body:JSON.stringify(payload)});
 if(!response.ok){let reason='Request rejected';try{reason=(await response.json()).error||reason}catch{}throw Error(reason)}
 if(!response.body||!response.body.getReader){const d=await api('ai',payload);onText(d.text||'');return}
 const reader=response.body.getReader();const decoder=new TextDecoder();
 let buffer='',combined='',ended=false;
 function parse(block){
  const event=(block.match(/^event: (.*)$/m)||[])[1]||'message';
  const data=(block.match(/^data: (.*)$/m)||[])[1];if(!data)return;
  let value;try{value=JSON.parse(data)}catch{return}
  if(event==='delta'){combined+=value.text||'';onText(combined)}
  if(event==='failure')throw Error(value.error||'AI provider failed');
  if(event==='done')ended=true
 }
 try{
  while(true){const {done,value}=await reader.read();if(done)break;buffer=(buffer+decoder.decode(value,{stream:true})).replace(/\r/g,'');
   let split;while((split=buffer.indexOf('\n\n'))!==-1){const block=buffer.slice(0,split).replace(/\r/g,'');buffer=buffer.slice(split+2);parse(block)}
  }
  if(buffer.trim())parse(buffer);
  if(!ended)throw Error('AI stream terminated before completion')
 }finally{reader.releaseLock()}
}

$('diagnostics').addEventListener('click',()=>show('diagnostics'));
function showSessionEnded(detail){
 const panel=$('session-ended');
 if(detail)$('session-ended-detail').textContent=detail;
 panel.hidden=false;
 engine('stopped');
 document.querySelector('.shell').setAttribute('aria-hidden','true');
}
if(window.BowerbirdLifecycle){
 // The tab owns the server: heartbeats keep it alive, closing the tab lets it stop itself.
 window.BowerbirdLifecycle.start(state.token);
 window.BowerbirdLifecycle.onServerGone=()=>engine('disconnected');
}
$('end-session').addEventListener('click',async()=>{
 if(!window.BowerbirdLifecycle)return;
 if(!window.confirm('End this Bowerbird session? The local server stops; run Start-Bowerbird.bat to start again.'))return;
 const button=$('end-session');
 button.disabled=true;
 try{
  await window.BowerbirdLifecycle.endSession();
  showSessionEnded('The local server has stopped. You can close this tab.');
 }catch(err){notify(err.message,true);button.disabled=false}
});
loadStatus().then(()=>{record('READY','browser_ui');return loadFiles()}).catch(err=>notify('Initialization failed: '+err.message,true));
// Welcome panel (shown until the folder is indexed): its buttons run the existing toolbar actions.
$('welcome-index').addEventListener('click',()=>$('index').click());$('welcome-browse').addEventListener('click',()=>$('browse-folder').click());
