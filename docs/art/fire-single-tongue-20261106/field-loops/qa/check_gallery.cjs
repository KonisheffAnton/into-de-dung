const {chromium}=require('C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs');
const path=require('path');

(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const url='file:///'+path.resolve(__dirname,'../gallery.html').replaceAll('\\','/');
  const report={url,checks:[]};
  for(const width of [1100,390]){
    const page=await browser.newPage({viewport:{width,height:800}});
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.goto(url);await page.waitForTimeout(250);
    for(const key of ['fire24-field07','fire29-field01']){
      await page.selectOption('#clip',key);await page.locator('#play').click();
      const max=Number(await page.locator('#scrub').getAttribute('max'));
      await page.locator('#scrub').fill(String(max));
      const data=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,images:[...document.querySelectorAll('img')].map(x=>({loaded:x.complete&&x.naturalWidth>0,width:x.naturalWidth,height:x.naturalHeight})),counter:document.querySelector('#counter').textContent,metrics:document.querySelector('#metrics').textContent}));
      const passed=!data.overflow&&data.images.length===4&&data.images.every(x=>x.loaded)&&errors.length===0&&data.metrics.includes('Стык: точно совпадает');
      report.checks.push({width,key,max_slot:max,passed,...data,page_errors:errors});
      await page.locator('#restart').click();
    }
    await page.screenshot({path:path.join(__dirname,`gallery-${width}.png`),fullPage:true});
    await page.close();
  }
  await browser.close();
  report.passed=report.checks.every(x=>x.passed);
  fs.writeFileSync(path.join(__dirname,'browser-validation.json'),JSON.stringify(report,null,2)+'\n');
  if(!report.passed)process.exitCode=1;
  console.log(JSON.stringify({passed:report.passed,checks:report.checks.map(x=>({key:x.key,width:x.width,passed:x.passed}))}));
})().catch(e=>{console.error(e);process.exitCode=1});
