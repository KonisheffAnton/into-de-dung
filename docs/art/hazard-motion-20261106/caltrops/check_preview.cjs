const fs=require('node:fs');
const path=require('node:path');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const dir=__dirname;
const report=path.resolve(dir,'../../../../test_reports/hazard-motion-20261106/caltrops');
const steps=[['rest',0],['glint-low-peak',5000],['glint-low-tail',150],['rest',150],
             ['glint-high-peak',5000],['glint-high-hold',150],['rest',150],['rest',5000]];
async function run(){
  fs.mkdirSync(report,{recursive:true});
  const browser=await chromium.launch({headless:true,executablePath:process.env.CHROME_EXE||'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
  await page.clock.install();
  await page.goto(pathToFileURL(path.join(dir,'preview.html')).href);
  const values={};
  values.imagesLoaded=await page.locator('img').evaluateAll(els=>els.every(x=>x.complete&&x.naturalWidth>0));
  values.mobileNoOverflow=await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth);
  await page.locator('#play').click();
  values.timeline=[];
  for(const [expected,advance] of steps){
    if(advance)await page.clock.runFor(advance);
    values.timeline.push({at_ms:values.timeline.reduce((s,x)=>s+x.advance_ms,0)+advance,
      advance_ms:advance,expected,actual:await page.locator('#view').getAttribute('src')});
  }
  const before=await page.locator('#view').getAttribute('src');
  await page.clock.runFor(1);
  values.afterCycle=await page.locator('#view').getAttribute('src');
  values.firstFinalQuiet=before==='rest.png'&&values.afterCycle==='rest.png';
  await page.locator('#pause').click();
  await page.screenshot({path:path.join(report,'preview-390.png'),fullPage:true});
  await browser.close();
  values.pass=values.imagesLoaded&&values.mobileNoOverflow&&values.firstFinalQuiet&&
    values.timeline.every(x=>x.actual===(x.expected==='rest'?'rest.png':x.expected+'.png'));
  fs.writeFileSync(path.join(report,'browser-validation.json'),JSON.stringify(values,null,2)+'\n');
  if(!values.pass)process.exitCode=1;
  process.stdout.write(JSON.stringify(values)+'\n');
}
run().catch(e=>{console.error(e);process.exitCode=1});
