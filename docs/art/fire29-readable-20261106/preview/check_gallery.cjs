const {chromium}=require('C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs'),path=require('path'),crypto=require('crypto');
(async()=>{const browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});const checks=[];
try{for(const width of [1280,390]){const page=await browser.newPage({viewport:{width,height:900}}),errors=[];page.on('pageerror',e=>errors.push(e.message));
await page.goto('file:///'+path.join(__dirname,'gallery.html').replaceAll('\\','/'));await page.waitForFunction(()=>window.FIRE_COMPARE_READY===true);
await page.locator('#play').click();await page.locator('#seek').fill('1');await page.locator('#seek').fill('0');
const pixels=async()=>{const result=[];for(let i=0;i<2;i++)result.push(crypto.createHash('sha256').update(await page.locator('canvas').nth(i).screenshot()).digest('hex'));return result};const first=await pixels();
await page.locator('#seek').fill('47');const middle=await pixels();
const moving=first.map((x,i)=>x!==middle[i]);const comparisonDifferent=[middle[0]!==middle[1]];
await page.locator('#seek').fill('95');await page.locator('#step').click();const wrap=await pixels();
const state=await page.evaluate(()=>({slot:document.querySelector('#seek').value,overflow:document.documentElement.scrollWidth>innerWidth,dims:[...document.querySelectorAll('canvas')].map(c=>[c.width,c.height])}));
await page.screenshot({path:path.join(__dirname,`surface-${width}.png`),fullPage:true});
await page.locator('#view').selectOption('full');await page.locator('#size').selectOption('256');
const full=await page.evaluate(()=>({overflow:document.documentElement.scrollWidth>innerWidth,dims:[...document.querySelectorAll('canvas')].map(c=>[c.width,c.height])}));
await page.locator('#restart').click();const restartPlaying=await page.locator('#play').textContent()==='Пауза';await page.locator('#play').click();
const passed=!state.overflow&&!full.overflow&&state.slot==='0'&&state.dims.length===2&&state.dims.every(d=>d[0]===678&&d[1]===513)&&full.dims.every(d=>d[0]===1254&&d[1]===1254)&&moving.every(Boolean)&&comparisonDifferent.every(Boolean)&&first.every((x,i)=>x===wrap[i])&&restartPlaying&&errors.length===0;
checks.push({width,passed,moving,comparisonDifferent,wrapExact:first.every((x,i)=>x===wrap[i]),state,full,errors});await page.close();}
const report={pass:checks.every(c=>c.passed),checks,manifest_sha256:crypto.createHash('sha256').update(fs.readFileSync(path.join(__dirname,'manifest.json'))).digest('hex')};fs.writeFileSync(path.join(__dirname,'browser-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(!report.pass)process.exitCode=1;
}finally{await browser.close()}})().catch(e=>{console.error(e);process.exitCode=1});
