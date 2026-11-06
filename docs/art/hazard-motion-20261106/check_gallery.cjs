const fs=require('node:fs'),path=require('node:path'),{pathToFileURL}=require('node:url');
const {chromium}=require('C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const report=path.resolve(__dirname,'../../../test_reports/hazard-motion-20261106');
(async()=>{
 fs.mkdirSync(report,{recursive:true});
 const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
 const results=[];
 for(const width of [1280,390]){
  const page=await browser.newPage({viewport:{width,height:900}});const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.clock.install({time:new Date('2026-11-06T00:00:00Z')});await page.clock.pauseAt(new Date('2026-11-06T00:00:01Z'));
  await page.goto(pathToFileURL(path.join(__dirname,'gallery.html')).href);await page.clock.runFor(10);
  const r={width,images:await page.locator('img').evaluateAll(es=>es.every(e=>e.complete&&e.naturalWidth===256)),noOverflow:await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)};
  await page.locator('#trap01 .restart').click();await page.clock.runFor(600);r.trapMiddle=(await page.locator('#trap01 .moving').getAttribute('src'))==='trap/half.png';
  await page.clock.runFor(450);r.trapExtended=(await page.locator('#trap01 .moving').getAttribute('src'))==='trap/extended.png';await page.clock.runFor(3000);r.trapStaysExtended=(await page.locator('#trap01 .moving').getAttribute('src'))==='trap/extended.png';
  await page.locator('#caltrops03 .restart').click();r.caltrops=[];
  for(const [ms,file] of [[4999,'rest'],[1,'glint-low-peak'],[150,'glint-low-tail'],[150,'rest'],[5000,'glint-high-peak'],[150,'glint-high-hold'],[150,'rest'],[5000,'rest']]){
   await page.clock.runFor(ms);r.caltrops.push((await page.locator('#caltrops03 .moving').getAttribute('src'))===`caltrops/${file}.png`);
  }
  await page.locator('#caltrops03 .show-glints').click();r.seek=(await page.locator('#caltrops03 .moving').getAttribute('src'))==='caltrops/glint-low-peak.png';await page.locator('#caltrops03 .play').click();const frozen=await page.locator('#caltrops03 .moving').getAttribute('src');await page.clock.runFor(2000);r.pause=(await page.locator('#caltrops03 .moving').getAttribute('src'))===frozen;
  r.fire=await page.evaluate(()=>Object.fromEntries(['fire24','fire29'].map(id=>{const c=window.__hazardGallery.clips[id];return [id,{pending:!!c.spec.pending,ready:c.ready,disabled:c.playButton.disabled,status:c.status.textContent}]})));
  r.errors=errors;r.pass=r.images&&r.noOverflow&&r.trapMiddle&&r.trapExtended&&r.trapStaysExtended&&r.caltrops.every(Boolean)&&r.seek&&r.pause&&!errors.length;
  await page.screenshot({path:path.join(report,`gallery-${width}.png`),fullPage:true});results.push(r);await page.close();
 }
 await browser.close();fs.writeFileSync(path.join(report,'gallery-validation.json'),JSON.stringify(results,null,2)+'\n');console.log(JSON.stringify(results));if(results.some(r=>!r.pass))process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1});
