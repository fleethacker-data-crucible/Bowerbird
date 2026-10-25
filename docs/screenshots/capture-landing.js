// Captures the README landing-page screenshot (File Explorer) with Playwright Chromium.
// Mock data only: point Studio at a throwaway folder of invented sample files, never a real one.
// Map it to a neutral drive so no user profile path appears in the image, for example:
//   subst Q: <temp folder holding Sample-Workspace>
//   powershell.exe -NoProfile -File .\Start-BowerbirdStudio.ps1 -Root Q:\Sample-Workspace -LocalDev -NoBrowser -Stay
//   node docs/screenshots/capture-landing.js "<Session URL printed by Studio>"
// It builds a name-only index (no content extraction) and shoots the landing view at 1440x900.
// Bowerbird Studio has one (dark) theme, so only Night watch is captured.
'use strict';
const path=require('node:path');
const {chromium}=require('playwright');
const [sessionUrl]=process.argv.slice(2);
if(!sessionUrl)throw Error('Usage: node capture-landing.js <session-url-with-token>');
async function fresh(browser){
 const context=await browser.newContext({viewport:{width:1440,height:900},deviceScaleFactor:1,colorScheme:'dark'});
 const page=await context.newPage();
 await page.goto(sessionUrl);
 await page.waitForFunction(()=>document.getElementById('connection').textContent==='Local server connected');
 await page.waitForFunction(()=>document.querySelectorAll('#file-table tr').length>0);
 return {context,page};
}
(async()=>{
 const browser=await chromium.launch();
 try{
  const {context,page}=await fresh(browser);
  if(await page.textContent('#index-state')==='Not indexed'){
   await page.uncheck('#content-index');
   await page.click('#index');
   await page.waitForFunction(()=>/files indexed/.test(document.getElementById('index-state').textContent));
  }
  await context.close();
  const shot=await fresh(browser);
  await shot.page.waitForTimeout(500);
  await shot.page.mouse.move(0,0);
  await shot.page.screenshot({path:path.join(__dirname,'explorer-night-watch.png')});
  await shot.context.close();
 }finally{await browser.close();}
})().catch(err=>{console.error(err);process.exit(1)});
