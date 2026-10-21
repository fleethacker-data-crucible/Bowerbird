'use strict';
const state={path:'.',token:new URLSearchParams(location.search).get('token')||sessionStorage.getItem('bowerbird-token'),status:null,plan:null};
if(state.token){sessionStorage.setItem('bowerbird-token',state.token);if(location.search)history.replaceState({},'',location.pathname)}
const $=id=>document.getElementById(id);
function el(tag,cls,text){const n=document.createElement(tag);if(cls)n.className=cls;if(text!==undefined)n.textContent=String(text);return n}
function clear(n){n.replaceChildren()}
function notify(message,error=false){const n=$('notice');n.textContent=message;n.className=error?'error':''}
async function api(route,body={}){
 if(!state.token)throw Error('Missing session token. Launch the browser from the PowerShell Studio process.');
 const response=await fetch('/api/'+route,{method:'POST',headers:{'Content-Type':'application/json','X-Bowerbird-Token':state.token},body:JSON.stringify(body),cache:'no-store'});
 let data;try{data=await response.json()}catch{throw Error('Server returned an invalid response')}
 if(!response.ok)throw Error(data.error||'Request failed');
 return data
}
async function run(action,done){try{notify('Working…');const result=await action();notify(done||'Done');return result}catch(err){notify(err.message,true);return null}}
function size(bytes){if(bytes===null||bytes===undefined)return '—';if(bytes<1024)return bytes+' B';if(bytes<1048576)return (bytes/1024).toFixed(1)+' KB';return (bytes/1048576).toFixed(1)+' MB'}
function show(view){document.querySelectorAll('.nav').forEach(b=>b.classList.toggle('active',b.dataset.view===view));document.querySelectorAll('.view').forEach(s=>s.classList.toggle('active',s.id==='view-'+view));$('page-title').textContent=({files:'File Explorer',search:'Intelligent Search',duplicates:'Duplicate Detection',organize:'File Organization',code:'Code Insights',assistant:'AI Assistant'})[view];if(view==='files')loadFiles()}
document.querySelectorAll('.nav').forEach(b=>b.addEventListener('click',()=>show(b.dataset.view)));
async function loadStatus(){const s=await run(()=>api('status'));if(!s)return;state.status=s;$('connection').textContent='Local server connected';$('workspace').textContent=s.root;$('index-state').textContent=s.indexExists?'Index available':'Not indexed';$('ai-state').textContent=s.cloudAI?'Enabled':'Disabled';$('ai-hint').textContent=s.cloudAI?'Approved provider configured':'Disabled — restart with -AllowCloudAI'}
async function loadFiles(){
 const data=await run(()=>api('files',{path:state.path}));if(!data)return;
 $('cwd').textContent=data.path;$('file-count').textContent=data.items.length;const tbody=$('file-table');clear(tbody);
 for(const item of data.items){
  const tr=el('tr');const td=el('td','name-cell',(item.directory?'▣  ':'▤  ')+item.name);if(item.directory)td.classList.add('folder');tr.append(td,el('td','',item.directory?'Folder':item.extension||'File'),el('td','',size(item.size)),el('td','',new Date(item.modified).toLocaleString()));
  tr.addEventListener('click',()=>item.directory?openFolder(item.path):preview(item.path));tbody.append(tr)
 }
 if(!data.items.length){const tr=el('tr');const td=el('td','','Folder is empty');td.colSpan=4;tr.append(td);tbody.append(tr)}
}
function openFolder(path){state.path=path;loadFiles()}
$('up').addEventListener('click',()=>{state.path=state.path==='.'?'.':(state.path.split('/').slice(0,-1).join('/')||'.');loadFiles()});
async function preview(path){$('preview-name').textContent=path;const data=await run(()=>api('preview',{path}));$('preview-text').textContent=data?data.text:'Preview unavailable for this file'}
$('refresh').addEventListener('click',async()=>{await loadStatus();await loadFiles()});
$('index').addEventListener('click',async()=>{const data=await run(()=>api('index',{path:state.path,recurse:$('recurse').checked}),'Index built');if(data){$('index-state').textContent=data.indexed+' files indexed';notify('Indexed '+data.indexed+' files.')}})
function addResult(parent,title,subtitle,detail){const row=el('div','result');row.append(el('strong','',title));if(subtitle)row.append(el('small','',subtitle));if(detail)row.append(el('p','muted',detail));parent.append(row)}
$('search-form').addEventListener('submit',async e=>{e.preventDefault();const data=await run(()=>api('search',{query:$('search-query').value}),'Search complete');if(!data)return;const target=$('search-results');clear(target);for(const item of data.items)addResult(target,item.name,item.path+' · score '+item.score,item.snippet);if(!data.items.length)target.textContent='No matches found.'})
async function duplicates(visual){const data=await run(()=>api('duplicates',{visual}),'Duplicate scan complete');if(!data)return;const target=$('duplicate-results');clear(target);for(const group of data.groups)addResult(target,group.kind+' group · '+group.files.length+' files',group.key,group.files.join('  •  '));if(!data.groups.length)target.textContent='No duplicate groups detected.'}
$('exact').addEventListener('click',()=>duplicates(false));$('visual').addEventListener('click',()=>duplicates(true));
$('plan').addEventListener('click',async()=>{
 let rules;try{rules=JSON.parse($('rules').value);if(!Array.isArray(rules))throw Error('Rules must be a JSON array')}catch(e){notify('Invalid rules: '+e.message,true);return}
 const data=await run(()=>api('plan',{destination:$('destination').value,rules}),'Plan generated. Review every proposed move.');if(!data)return;
 state.plan=data;$('apply').disabled=!data.count;const target=$('plan-results');clear(target);target.append(el('h3','',data.count+' proposed moves'));
 for(const op of data.operations)addResult(target,op.source,'→ '+op.destination,op.reason)
});
$('apply').addEventListener('click',async()=>{
 if(!state.plan||!state.plan.count)return;
 if(!confirm('Move '+state.plan.count+' files? Review the preview carefully. This changes files on disk.'))return;
 const phrase=prompt('Type APPLY to authorize the proposed moves:');if(phrase!=='APPLY')return;
 const data=await run(()=>api('apply',{confirm:phrase}),'Apply completed. Inspect results before further changes.');if(!data)return;
 $('apply').disabled=true;state.plan=null;const target=$('plan-results');clear(target);
 for(const r of data.results)addResult(target,r.Status,r.Source+' → '+r.Destination,r.Error||'');
});
$('undo').addEventListener('click',async()=>{
 if(!confirm('Attempt to restore files from the last journal? Existing destinations will not be overwritten.'))return;
 const phrase=prompt('Type UNDO to confirm:');if(phrase!=='UNDO')return;
 const data=await run(()=>api('undo',{confirm:phrase}),'Undo attempted. Review restored files.');if(data)notify('Undo returned '+(data.restored||[]).length+' restored entries.')
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
 try{const data=await api('ai',{prompt,includeIndex:$('chat-index').checked});pending.textContent=data.text||'(No response)';notify('AI response received')}
 catch(err){pending.textContent='Request failed: '+err.message;notify(err.message,true)}
});
loadStatus().then(loadFiles);
