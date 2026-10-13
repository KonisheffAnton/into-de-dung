const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {pathToFileURL}=require('node:url');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
(async()=>{
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 try{
  const page=await browser.newPage({viewport:{width:1152,height:850},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',error=>errors.push(String(error)));
  await page.goto(pathToFileURL(path.join(__dirname,'comparison.html')).href);await page.evaluate(()=>window.ready);
  await page.screenshot({path:path.join(__dirname,'comparison.png'),fullPage:true});
  await page.locator('#archer').screenshot({path:path.join(__dirname,'archer-b1-on-tile.png')});
  const frames=[];
  for(const key of ['b1','b2','b3']){
   await page.selectOption('#frame',key);frames.push({key,title:await page.locator('#frame-title').textContent(),
    canvas_sha256:crypto.createHash('sha256').update(await page.locator('#archer').screenshot()).digest('hex')});
  }
  await page.check('#axes');const axes=await page.isChecked('#axes');
  const manifest=JSON.parse(fs.readFileSync(path.join(__dirname,'manifest.json'),'utf8'));
  const source_checks=Object.entries(manifest.sources).map(([key,s])=>({key,
    unchanged:crypto.createHash('sha256').update(fs.readFileSync(path.resolve(__dirname,'../../..',s.path))).digest('hex')===s.sha256}));
  if(errors.length||source_checks.some(s=>!s.unchanged)||!axes||frames.some(f=>!f.title.endsWith(f.key.toUpperCase())))throw Error('Preview validation failed');
  const result={status:'PASS',errors,source_checks,frames,axes_control:axes,ratio_b1:manifest.geometry.archer.ratio_b1,
   scope:'HTML loading, controls, source hashes; visual QA separate. Not Godot/F5/GPU or art acceptance.'};
  fs.writeFileSync(path.join(__dirname,'validation.json'),JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
 }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});
