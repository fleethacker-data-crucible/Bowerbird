// Captures every docs screenshot (README pair and the walkthrough) from the current Web/ UI with
// Playwright Chromium, on any OS and without PowerShell. Dev-only; never needed on a workstation.
//   node docs/screenshots/capture-demo.js            (writes the README pair and the walkthrough)
//   node docs/screenshots/capture-demo.js readme     (README pair only)
//   node docs/screenshots/capture-demo.js walkthrough
// It serves Web/ exactly as Start-BowerbirdStudio.ps1 does (same static allow-list, same routes) on
// 127.0.0.1:8767 and answers /api/* from a throwaway folder of invented demo files that it creates
// in the OS temp folder: real listings, sizes, previews and SHA-256 duplicate groups from those files.
// The workspace shows as Q:\Sample-Workspace so no real path appears. Values only the PowerShell
// engine computes (search score, Smart Rename proposals) are the engine's own output for the same
// demo files. For shots from the real engine on Windows, use capture-landing.js.
'use strict';
const fs=require('node:fs');
const os=require('node:os');
const path=require('node:path');
const http=require('node:http');
const crypto=require('node:crypto');
const zlib=require('node:zlib');
const {chromium}=require('playwright');

const repo=path.resolve(__dirname,'..','..');
const PORT=8767,ROOT_LABEL='Q:\\Sample-Workspace',MTIME=new Date('2026-10-25T21:53:38Z');
const STATIC={
 '/':'Web/index.html','/app.js':'Web/app.js','/lifecycle.js':'Web/lifecycle.js','/diagnostics.js':'Web/diagnostics.js',
 '/shell.js':'Web/shell.js','/icons.js':'Web/icons.js','/style.css':'Web/style.css','/vendor/fleet/fleet.css':'Web/vendor/fleet/fleet.css',
 '/mark.svg':'assets/brand/mark.svg','/brand/emblem-dark.png':'Web/brand/emblem-dark.png','/brand/emblem-light.png':'Web/brand/emblem-light.png',
 '/brand/icon-256.png':'Web/brand/icon-256.png','/favicon.ico':'Web/brand/favicon.ico'
};
const TYPES={'.html':'text/html; charset=utf-8','.js':'application/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.png':'image/png','.svg':'image/svg+xml','.ico':'image/x-icon'};

// A small solid-colour PNG (invented content; stands in for a screenshot).
function png(w,h,rgb){
 const crcTable=[];for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;crcTable[n]=c>>>0}
 const crc=b=>{let c=0xffffffff;for(const x of b)c=crcTable[(c^x)&255]^(c>>>8);return (c^0xffffffff)>>>0};
 const chunk=(type,data)=>{const len=Buffer.alloc(4);len.writeUInt32BE(data.length);const td=Buffer.concat([Buffer.from(type),data]);const c=Buffer.alloc(4);c.writeUInt32BE(crc(td));return Buffer.concat([len,td,c])};
 const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(w,0);ihdr.writeUInt32BE(h,4);ihdr[8]=8;ihdr[9]=2;
 const raw=Buffer.alloc((w*3+1)*h);for(let y=0;y<h;y++)for(let x=0;x<w;x++){const o=y*(w*3+1)+1+x*3;raw[o]=rgb[0]+(x%16);raw[o+1]=rgb[1]+(y%16);raw[o+2]=rgb[2]}
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',ihdr),chunk('IDAT',zlib.deflateSync(raw,{level:1})),chunk('IEND',Buffer.alloc(0))]);
}
const DATASETS={
 // README pair: the File Explorer landing view.
 readme:{
  'Notes/harbour-log-sample.txt':'Invented harbour log for the Bowerbird demo.\n',
  'Reports/tide-table-sample.csv':'time,height_m\n06:00,1.2\n12:15,3.4\n',
  'Screenshots/Screenshot 2026-10-20 091500.png':png(96,64,[60,80,170]),
  'Scripts/sample-cleanup.ps1':'# Invented sample script for the Bowerbird demo.\nGet-ChildItem -File\n',
  'harbour-sketch.png':png(48,40,[40,110,140]),
  'README.txt':'Invented sample workspace for Bowerbird screenshots.\n'
 },
 // Walkthrough: a folder with a note, a report and three screenshots, two of them identical.
 walkthrough:{
  'notes/watch-turnover-sample.txt':'Sample turnover notes for the Bowerbird walkthrough.\n',
  'reports/tide-table-sample.csv':'time,height_m\n06:00,1.2\n12:15,3.4\n',
  'Screenshot 2026-10-20 091500.png':png(120,80,[50,70,160]),
  'Screenshot 2026-10-20 091500 - Copy.png':png(120,80,[50,70,160]),
  'Screenshot 2026-10-21 140200.png':png(120,84,[70,60,150])
 }
};
function makeWorkspace(name){
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bowerbird-demo-'));
 for(const [rel,content] of Object.entries(DATASETS[name])){
  const full=path.join(dir,...rel.split('/'));fs.mkdirSync(path.dirname(full),{recursive:true});fs.writeFileSync(full,content);
 }
 const touch=p=>{for(const e of fs.readdirSync(p,{withFileTypes:true})){const f=path.join(p,e.name);if(e.isDirectory())touch(f);fs.utimesSync(f,MTIME,MTIME)}};
 touch(dir);return dir;
}
const CATEGORY={'.png':'Image','.txt':'Document','.csv':'Spreadsheet','.ps1':'Code'};

// Mock of the Studio engine's /api routes (Start-BowerbirdStudio.ps1 Invoke-Api), backed by the demo folder.
function engine(dir){
 const st={indexed:null,log:[]};
 const abs=rel=>{const p=path.resolve(dir,...String(rel||'.').split('/').filter(x=>x&&x!=='.'));if(p!==dir&&!p.startsWith(dir+path.sep))throw Error('Path escapes workspace');return p};
 const relOf=p=>p===dir?'.':path.relative(dir,p).split(path.sep).join('/');
 const walk=(p,recurse)=>fs.readdirSync(p,{withFileTypes:true}).sort((a,b)=>a.name.localeCompare(b.name)).flatMap(e=>{const f=path.join(p,e.name);return e.isDirectory()?(recurse?walk(f,true):[]):[f]});
 const sha=f=>crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex').toUpperCase();
 const health=()=>[
  {name:'Local backend',ok:true,detail:'Loopback server is responsive'},
  {name:'Active workspace',ok:true,detail:'Folder availability'},
  {name:'Browser assets',ok:Object.values(STATIC).every(f=>fs.existsSync(path.join(repo,f))),detail:'Static UI files'},
  {name:'Application log',ok:true,detail:'Local diagnostic log'},
  {name:'Local index',ok:!!st.indexed,detail:'An index is optional until Build Index'},
  {name:'Cloud AI permission',ok:false,detail:'Off by default; not an endpoint connectivity test'}];
 const dupes=()=>{const by={};for(const f of st.indexed.files){(by[f.sha]=by[f.sha]||[]).push(f.rel)}return Object.entries(by).filter(([,v])=>v.length>1).map(([key,files])=>({kind:'Exact',key,files}))};
 const routes={
  status:()=>({ok:true,root:ROOT_LABEL,port:PORT,transport:'BowerbirdTcpBridge',indexExists:!!st.indexed,cloudAI:false,version:'2.3'}),
  files:b=>{const p=abs(b.path);return {path:relOf(p),root:ROOT_LABEL,items:fs.readdirSync(p,{withFileTypes:true}).sort((a,c)=>(c.isDirectory()-a.isDirectory())||a.name.localeCompare(c.name)).map(e=>{const f=path.join(p,e.name),s=fs.statSync(f);return {name:e.name,path:relOf(f),directory:e.isDirectory(),size:e.isDirectory()?null:s.size,modified:s.mtime.toISOString(),extension:e.isDirectory()?'':path.extname(e.name)}})}},
  preview:b=>{const f=abs(b.path);if(!/\.(txt|md|json|csv|ps1|psm1|js|log)$/i.test(f))throw Error('Preview supports text files only');return {path:relOf(f),text:fs.readFileSync(f,'utf8')}},
  index:b=>{const files=walk(abs(b.path),!!b.recurse).map(f=>({rel:relOf(f),name:path.basename(f),ext:path.extname(f).toLowerCase(),size:fs.statSync(f).size,sha:sha(f),text:b.includeContent&&/\.(txt|csv|md|ps1)$/i.test(f)?fs.readFileSync(f,'utf8'):''}));st.indexed={files,content:!!b.includeContent};return {indexed:files.length,root:ROOT_LABEL,content:!!b.includeContent}},
  insights:()=>{const f=st.indexed.files,cats={};for(const x of f){const c=CATEGORY[x.ext]||'Other';cats[c]=(cats[c]||0)+1}return {files:f.length,bytes:f.reduce((a,x)=>a+x.size,0),errors:0,duplicateGroups:dupes().length,categories:Object.entries(cats).sort((a,c)=>c[1]-a[1]).map(([name,count])=>({name,count}))}},
  // The score is the PowerShell engine's (Search-BowerbirdIndex) for this demo note and query.
  search:b=>{const q=String(b.query||'').toLowerCase();return {items:st.indexed.files.filter(f=>(f.name+' '+f.text).toLowerCase().includes(q)).map(f=>({path:f.rel,name:f.name,score:3.524,snippet:f.text.trim()}))}},
  duplicates:()=>({groups:dupes()}),
  // Smart Rename output of the PowerShell engine (New-BowerbirdSmartRenamePlan) for these screenshots.
  'rename-preview':()=>({id:'demo-rename',count:2,vision:0,
   operations:[{source:'Screenshot 2026-10-20 091500 - Copy.png',destination:'2026-10-20_Screenshot_2026.png',confidence:0.55,reason:'Smart rename: filename+metadata / Matched common screenshot filename pattern'},
    {source:'Screenshot 2026-10-21 140200.png',destination:'2026-10-21_Screenshot_2026.png',confidence:0.55,reason:'Smart rename: filename+metadata / Matched common screenshot filename pattern'}],
   skipped:[{source:'Screenshot 2026-10-20 091500.png',reason:'Target name already taken'}]}),
  // Same matching as New-BowerbirdPlan: first rule that matches by extension and name pattern.
  plan:b=>{const ops=[];for(const f of st.indexed.files){for(const r of b.rules){if(r.Extension&&[].concat(r.Extension).length&&![].concat(r.Extension).includes(f.ext))continue;if(r.NamePattern&&!new RegExp(String(r.NamePattern).replace(/^\(\?i\)/,''),/^\(\?i\)/.test(r.NamePattern)?'i':'').test(f.name))continue;ops.push({source:f.rel,destination:[b.destination,r.Folder,f.name].join('/'),reason:'Rule: '+r.Name});break}}return {id:'demo-plan',operations:ops,skipped:[],count:ops.length}},
  diagnostics:()=>({ok:true,version:'2.3',transport:'BowerbirdTcpBridge',port:PORT,events:st.log.slice(-250)}),
  'diagnostics/health':()=>({ok:true,checks:health(),version:'2.3'}),
  'feedback/list':()=>({issues:[]}),
  'client-event':()=>({ok:true}),
  heartbeat:()=>({ok:true})
 };
 return {dir,routes,st};
}
function serve(state){
 const server=http.createServer((req,res)=>{
  const url=new URL(req.url,'http://127.0.0.1');let body='';const started=Date.now();
  req.on('data',d=>body+=d);req.on('end',()=>{
   const eng=state.engine;
   const done=(status,obj,type)=>{res.writeHead(status,{'Content-Type':type||'application/json; charset=utf-8','Cache-Control':'no-store'});res.end(type?obj:JSON.stringify(obj));
    if(url.pathname.startsWith('/api/')&&url.pathname!=='/api/heartbeat'&&url.pathname!=='/api/client-event')eng.st.log.push({time:new Date().toISOString(),level:status<400?'INFO':'ERROR',event:'REQUEST',route:url.pathname,requestId:crypto.randomBytes(6).toString('hex'),message:'HTTP '+status+' '+(Date.now()-started)+'ms'})};
   try{
    if(req.method==='GET'&&STATIC[url.pathname]){const f=path.join(repo,STATIC[url.pathname]);return done(200,fs.readFileSync(f),TYPES[path.extname(f)])}
    if(req.method==='POST'&&url.pathname.startsWith('/api/')){
     const route=url.pathname.slice(5),data=body?JSON.parse(body):{};
     if(route==='media'){const f=path.join(eng.dir,...String(data.path).split('/'));return done(200,fs.readFileSync(f),'image/png')}
     if(!eng.routes[route])throw Error('Unknown endpoint');
     return done(200,eng.routes[route](data));
    }
    done(404,{error:'Not found'});
   }catch(err){done(400,{error:err.message})}
  });
 });
 return new Promise(r=>server.listen(PORT,'127.0.0.1',()=>r(server)));
}

async function open(browser,colorScheme){
 const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,colorScheme,locale:'en-US',timezoneId:'America/New_York'});
 const page=await context.newPage();
 page.on('dialog',d=>d.accept(d.type()==='prompt'?'':undefined));
 page.on('pageerror',e=>{throw e});
 await page.goto('http://127.0.0.1:'+PORT+'/?token=demo-token');
 await page.waitForFunction(()=>document.getElementById('connection').textContent==='Running');
 await page.waitForFunction(()=>document.querySelectorAll('#file-table tr').length>0);
 return {context,page};
}
async function settle(page){
 // Notices are toasts that dismiss themselves after 5 s; wait so they never cover the shot.
 await page.waitForFunction(()=>{const n=document.getElementById('notice');return !n.textContent||n.classList.contains('dismissed')},null,{timeout:15000});
 await page.mouse.move(0,0);
 await page.evaluate(()=>document.activeElement&&document.activeElement.blur());
 await page.waitForTimeout(300);
}
async function shoot(page,file){await settle(page);await page.screenshot({path:file});console.log('wrote',path.relative(repo,file))}
const scrollTo=(page,sel,block)=>page.evaluate(([s,b])=>document.querySelector(s).scrollIntoView({block:b}),[sel,block||'start']);
async function index(page,{content}){
 await page.setChecked('#content-index',!!content);await page.uncheck('#ocr-index');
 await page.click('#index');await page.waitForFunction(()=>/files indexed/.test(document.getElementById('index-state').textContent));
}

async function readme(browser,state){
 state.engine=engine(makeWorkspace('readme'));
 const first=await open(browser,'dark');await index(first.page,{content:false});await first.context.close();
 for(const [scheme,name] of [['dark','night-watch'],['light','chart-room']]){
  const {context,page}=await open(browser,scheme);
  await shoot(page,path.join(__dirname,'explorer-'+name+'.png'));await context.close();
 }
}
async function walkthrough(browser,state){
 state.engine=engine(makeWorkspace('walkthrough'));
 const out=n=>path.join(repo,'docs','assets','walkthrough',n);
 const {context,page}=await open(browser,'dark');
 await shoot(page,out('01-first-launch.png'));
 await index(page,{content:true});
 await page.click('#file-table tr:has-text("notes")');await page.waitForFunction(()=>document.getElementById('cwd').textContent==='notes');
 await page.click('#file-table tr:has-text("watch-turnover-sample.txt")');await page.waitForFunction(()=>/turnover/.test(document.getElementById('preview-text').textContent));
 await shoot(page,out('02-build-index.png'));
 await page.click('.nav[data-view="search"]');await page.fill('#search-query','turnover');await page.click('#search-form button[type="submit"], #search-form button');
 await page.waitForSelector('#search-results .result');await scrollTo(page,'#view-search');await shoot(page,out('03-search.png'));
 await page.click('.nav[data-view="duplicates"]');await page.click('#exact');await page.waitForSelector('#duplicate-results .result');
 await scrollTo(page,'#view-duplicates');await shoot(page,out('04-duplicates.png'));
 await page.click('.nav[data-view="files"]');await page.click('#up');await page.waitForFunction(()=>document.getElementById('cwd').textContent==='.');
 await page.click('.nav[data-view="rename"]');await page.click('#rename-plan');await page.waitForSelector('#rename-results .result');
 await scrollTo(page,'#rename-results','end');await shoot(page,out('05-smart-rename.png'));
 await page.click('.nav[data-view="organize"]');await page.click('#plan');await page.waitForSelector('#plan-results .result');
 await scrollTo(page,'#plan-results','center');await shoot(page,out('06-organize-plan.png'));
 await page.click('.nav[data-view="diagnostics"]');await page.click('#diag-health-refresh');await page.waitForSelector('#diag-health .diag-check-icon');
 await page.waitForSelector('#diag-server-events .diag-row');
 await scrollTo(page,'#diag-health','center');await shoot(page,out('07-diagnostics.png'));
 await context.close();
}
(async()=>{
 const which=process.argv[2]||'all';
 const state={};const server=await serve(state);const browser=await chromium.launch();
 try{
  if(which==='all'||which==='readme')await readme(browser,state);
  if(which==='all'||which==='walkthrough')await walkthrough(browser,state);
 }finally{await browser.close();server.close()}
})().catch(err=>{console.error(err);process.exit(1)});
