const {chromium}=require('C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const path=require('node:path'),fs=require('node:fs');
const dir=__dirname;
(async()=>{
 const browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage({viewport:{width:1440,height:1150}});
 const errors=[];page.on('pageerror',e=>errors.push(String(e)));
 await page.goto('file:///'+dir.replaceAll('\\','/')+'/gallery.html');
 const rows=[];
 for(const id of ['02','05','11','12','17','18']){
  await page.click(`[data-id="${id}"]`);
  await page.waitForFunction(()=>players.length>0&&players.every(p=>p.loaded));
  await page.click('#restart');await page.click('#play');
  const start=await page.evaluate(()=>players.map(p=>p.frame));
  await page.click('#step');
  const advanced=await page.evaluate(()=>players.every(p=>p.frame===1));
  const meta=await page.evaluate(()=>({count:players.length,images:players.every(p=>p.img.naturalWidth===2048),hasLocal:players.filter(p=>p.c.provider==='local').length,hasPixel:players.filter(p=>p.c.provider==='pixellab').length}));
  rows.push({id,...meta,startZero:start.every(f=>f===0),advanced});
 }
 await page.click('[data-id="02"]');
 await page.waitForFunction(()=>players.every(p=>p.loaded));
 await page.screenshot({path:path.join(dir,'gallery-preview.png'),fullPage:true});
 await page.selectOption('#scale','game');
 const gameWidth=await page.locator('canvas').first().evaluate(e=>e.getBoundingClientRect().width);
 await page.selectOption('#scale','');
 await page.setViewportSize({width:390,height:900});
 const mobileOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
 const report={rows,gameWidth,mobileOverflow,errors,complete:rows.every(r=>r.count===12&&r.hasPixel===9&&r.hasLocal===3),pass:rows.every(r=>r.images&&r.startZero&&r.advanced)&&Math.abs(gameWidth-102.4)<0.1&&!mobileOverflow&&!errors.length};
 fs.writeFileSync(path.join(dir,'gallery-validation.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report));await browser.close();if(!report.pass)process.exitCode=1;
})().catch(e=>{console.error(e);process.exit(1)});
