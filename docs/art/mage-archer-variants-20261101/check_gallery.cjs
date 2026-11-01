const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const dir=__dirname;
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1800,height:1200},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(String(e)));
  await page.goto(pathToFileURL(path.join(dir,'gallery.html')).href);
  await page.waitForFunction(()=>[...document.querySelectorAll('.card img')].every(i=>i.complete&&i.naturalWidth>0));
  const report=await page.evaluate(()=>({cards:document.querySelectorAll('.card').length,mage:document.querySelectorAll('#mage img').length,archer:document.querySelectorAll('#archer img').length,embedded:[...document.querySelectorAll('.card img')].every(i=>i.src.startsWith('data:image/png;base64,'))}));
  for(const group of ['mage','archer'])await page.locator('#'+group).screenshot({path:path.join(dir,group+'-contact.png')});
  await page.locator('#archer .card').nth(2).click();
  report.selected=await page.locator('#title').textContent();
  report.dialogOpen=await page.locator('#viewer').evaluate(d=>d.open);
  await page.waitForFunction(()=>document.getElementById('large').naturalWidth>0);
  report.largeSize=await page.locator('#large').evaluate(i=>[i.naturalWidth,i.naturalHeight]);
  await page.keyboard.press('Escape');report.escapeClosed=await page.locator('#viewer').evaluate(d=>!d.open);
  await page.locator('#mage .card').nth(1).click();await page.locator('#close').click();report.buttonClosed=await page.locator('#viewer').evaluate(d=>!d.open);
  await page.setViewportSize({width:390,height:900});report.mobileOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
  report.errors=errors;report.pass=report.cards===23&&report.mage===10&&report.archer===10&&report.embedded&&report.dialogOpen&&report.escapeClosed&&report.buttonClosed&&!report.mobileOverflow&&!errors.length;
  fs.writeFileSync(path.join(dir,'gallery-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(!report.pass)process.exitCode=1;
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
