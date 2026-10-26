// Captures the README landing-page screenshots (File Explorer) with Playwright Chromium, in both
// Fleet themes: Night watch (dark) and Chart room (light), at 1440x900 with the sidebar expanded.
// Mock data only: point Studio at a throwaway folder of invented sample files, never a real one.
// Map it to a neutral drive so no user profile path appears in the image, for example:
//   subst Q: <temp folder holding Sample-Workspace>
//   powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root Q:\Sample-Workspace -LocalDev -NoBrowser -Stay
//   node docs/screenshots/capture-landing.js "<Session URL printed by Studio>"
// It builds a name-only index (no content extraction, no OCR, no cloud AI) and shoots the landing view.
'use strict';
const path=require('node:path');
const {chromium}=require('playwright');
const [sessionUrl]=process.argv.slice(2);
if(!sessionUrl)throw Error('Usage: node capture-landing.js <session-url-with-token>');
async function fresh(browser,colorScheme){
 const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,colorScheme});
 const page=await context.newPage();
 await page.goto(sessionUrl);
 await page.waitForFunction(()=>document.getElementById('connection').textContent==='Running');
 await page.waitForFunction(()=>document.querySelectorAll('#file-table tr').length>0);
 return {context,page};
}
(async()=>{
 const browser=await chromium.launch();
 try{
  const {context,page}=await fresh(browser,'dark');
  if(await page.textContent('#index-state')==='Not indexed'){
   await page.uncheck('#content-index');
   await page.uncheck('#ocr-index');
   await page.click('#index');
   await page.waitForFunction(()=>/files indexed/.test(document.getElementById('index-state').textContent));
  }
  await context.close();
  for(const [scheme,name] of [['dark','night-watch'],['light','chart-room']]){
   const shot=await fresh(browser,scheme);
   // Notices are toasts that dismiss themselves after 5 s; wait for the load notice to go.
   await shot.page.waitForFunction(()=>{const n=document.getElementById('notice');return !n.textContent||n.classList.contains('dismissed')},null,{timeout:15000});
   await shot.page.mouse.move(0,0);
   await shot.page.waitForTimeout(300);
   await shot.page.screenshot({path:path.join(__dirname,'explorer-'+name+'.png')});
   await shot.context.close();
  }
 }finally{await browser.close();}
})().catch(err=>{console.error(err);process.exit(1)});
