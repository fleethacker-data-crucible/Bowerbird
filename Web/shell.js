'use strict';
// Fleet shell for Bowerbird Studio (docs/UNIFIED-UI.md sections 3.1, 5, 6 and 7).
// Loaded synchronously in <head> so a remembered theme and sidebar state apply before the first
// paint; everything that needs the page is wired on DOMContentLoaded.
(function(root){
 const doc=root.document;
 const THEME_KEY='bowerbird-theme';
 const SIDEBAR_KEY='bowerbird-sidebar';
 const NARROW='(max-width: 1023px)';
 // Storage can be unavailable (managed browsers, blocked site data); the shell works without it.
 function load(key){try{return root.localStorage.getItem(key)}catch(_){return null}}
 function save(key,value){try{if(value===null)root.localStorage.removeItem(key);else root.localStorage.setItem(key,value)}catch(_){/* applies for this page only */}}

 const THEMES=['system','dark','light'];
 const THEME_NAME={system:'Follow Windows',dark:'Night watch',light:'Chart room'};
 const THEME_ICON={system:'themeSystem',dark:'themeDark',light:'themeLight'};
 function readTheme(){const v=load(THEME_KEY);return v==='dark'||v==='light'?v:'system'}
 function applyTheme(choice){
  if(choice==='system')doc.documentElement.removeAttribute('data-theme');
  else doc.documentElement.setAttribute('data-theme',choice);
 }
 let theme=readTheme();
 applyTheme(theme);

 function narrow(){try{return root.matchMedia(NARROW).matches}catch(_){return false}}
 let collapsedPref=load(SIDEBAR_KEY)==='collapsed';
 function applySidebar(){
  const collapsed=collapsedPref||narrow();
  doc.documentElement.classList.toggle('sidebar-collapsed',collapsed);
  doc.documentElement.classList.toggle('sidebar-narrow',narrow());
  const button=doc.getElementById('sidebar-toggle');
  if(button){
   button.setAttribute('aria-expanded',String(!collapsed));
   button.title=collapsed?'Expand the sidebar':'Collapse the sidebar';
   swapIcon(button,collapsed?'expand':'collapse');
  }
 }
 applySidebar();

 function swapIcon(button,name){
  const icons=root.BowerbirdIcons;if(!icons)return;
  const current=button.querySelector('svg.icon');
  if(current&&current.getAttribute('data-icon-name')===name)return;
  const next=icons.icon(name,20);if(!next)return;
  if(current)current.replaceWith(next);else button.prepend(next);
 }
 function renderTheme(){
  const button=doc.getElementById('theme-toggle');if(!button)return;
  const next=THEMES[(THEMES.indexOf(theme)+1)%THEMES.length];
  button.title='Theme: '+THEME_NAME[theme]+'. Click for '+THEME_NAME[next]+'.';
  const label=doc.getElementById('theme-label');if(label)label.textContent=THEME_NAME[theme];
  swapIcon(button,THEME_ICON[theme]);
 }

 // Engine state in the status bar: a dot plus a word, never colour alone.
 const ENGINE_WORD={connecting:'Connecting',running:'Running',disconnected:'Disconnected',stopped:'Stopped'};
 const ENGINE_TITLE={connecting:'Connecting to the local server',running:'Local server connected',disconnected:'Local server not responding',stopped:'The local server has stopped'};
 function setEngine(state){
  const word=doc.getElementById('connection');const engine=doc.getElementById('engine');
  if(engine){engine.dataset.state=state;engine.title=ENGINE_TITLE[state]||''}
  if(word)word.textContent=ENGINE_WORD[state]||state;
 }

 // Dialogs: focus moves in, Tab stays inside, Esc closes, focus returns afterwards.
 const FOCUSABLE='button:not([disabled]), [href], input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';
 let openDialog=null,returnFocus=null;
 function showDialog(id){
  const backdrop=doc.getElementById(id);if(!backdrop||openDialog)return;
  returnFocus=doc.activeElement;openDialog=backdrop;backdrop.hidden=false;
  const box=backdrop.querySelector('[role=dialog]');
  const first=box&&box.querySelector(FOCUSABLE);(first||box).focus();
 }
 function closeDialog(){
  if(!openDialog)return;
  openDialog.hidden=true;openDialog=null;
  if(returnFocus&&returnFocus.focus)returnFocus.focus();returnFocus=null;
 }
 function onKey(e){
  if(openDialog){
   if(e.key==='Escape'){e.preventDefault();e.stopPropagation();closeDialog();return}
   if(e.key==='Tab'){
    const items=[...openDialog.querySelectorAll(FOCUSABLE)].filter(x=>x.offsetParent!==null);
    if(!items.length){e.preventDefault();return}
    const first=items[0],last=items[items.length-1];
    if(e.shiftKey&&doc.activeElement===first){e.preventDefault();last.focus()}
    else if(!e.shiftKey&&doc.activeElement===last){e.preventDefault();first.focus()}
   }
   return;
  }
  const t=e.target;const typing=t&&(t.isContentEditable||/^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName));
  if(e.key==='?'&&!typing&&!e.ctrlKey&&!e.metaKey&&!e.altKey){e.preventDefault();showDialog('shortcuts-dialog')}
 }

 // Notices behave like .fl-toast: bottom right above the status bar; anything but an error
 // dismisses itself after 5 s. The text stays in the element, so app.js and the tests still read it.
 function watchNotice(){
  const notice=doc.getElementById('notice');if(!notice||typeof root.MutationObserver!=='function')return;
  let timer=null;
  const update=()=>{
   if(timer){root.clearTimeout(timer);timer=null}
   if(notice.classList.contains('dismissed'))notice.classList.remove('dismissed');
   if(notice.textContent&&!notice.classList.contains('error'))timer=root.setTimeout(()=>notice.classList.add('dismissed'),5000);
  };
  // Text changes only: app.js sets the text and the error class together, so the class is current here.
  new root.MutationObserver(update).observe(notice,{childList:true,characterData:true,subtree:true});
  notice.addEventListener('click',()=>notice.classList.add('dismissed'));
  notice.title='Click to dismiss';
 }

 function wire(){
  const address=doc.getElementById('bound-address');
  if(address)address.textContent=root.location.host||'file';
  const themeButton=doc.getElementById('theme-toggle');
  if(themeButton)themeButton.addEventListener('click',()=>{
   theme=THEMES[(THEMES.indexOf(theme)+1)%THEMES.length];
   applyTheme(theme);save(THEME_KEY,theme==='system'?null:theme);renderTheme();
  });
  const sidebarButton=doc.getElementById('sidebar-toggle');
  if(sidebarButton)sidebarButton.addEventListener('click',()=>{
   collapsedPref=!(collapsedPref||narrow());save(SIDEBAR_KEY,collapsedPref?'collapsed':'expanded');applySidebar();
  });
  try{const mq=root.matchMedia(NARROW);(mq.addEventListener?mq.addEventListener.bind(mq,'change'):mq.addListener.bind(mq))(applySidebar)}catch(_){}
  const shortcuts=doc.getElementById('shortcuts-open');
  if(shortcuts)shortcuts.addEventListener('click',()=>showDialog('shortcuts-dialog'));
  for(const b of doc.querySelectorAll('[data-dialog-close]'))b.addEventListener('click',closeDialog);
  for(const backdrop of doc.querySelectorAll('.modal-backdrop'))backdrop.addEventListener('click',e=>{if(e.target===backdrop)closeDialog()});
  doc.addEventListener('keydown',onKey,true);
  renderTheme();applySidebar();watchNotice();
 }
 if(doc.readyState==='loading')doc.addEventListener('DOMContentLoaded',wire);else wire();
 root.BowerbirdShell={setEngine,showDialog,closeDialog,themeName:()=>THEME_NAME[theme]};
})(window);
