const {chromium}=require('C:/Users/Aston/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright');
const fs=require('fs');
const path=require('path');
const crypto=require('crypto');
let browser;
(async()=>{
  browser=await chromium.launch({headless:true,executablePath:'C:/Program Files/Google/Chrome/Application/chrome.exe'});
  const url='file:///'+path.resolve(__dirname,'../gallery.html').replaceAll('\\','/');
  const report={url,checks:[]};
  for(const width of [1280,390]){
    const page=await browser.newPage({viewport:{width,height:900}}),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      window.CROP_CALLS=[];
      const original=CanvasRenderingContext2D.prototype.drawImage;
      CanvasRenderingContext2D.prototype.drawImage=function(...args){
        if(this.canvas.classList.contains('source-surface')||this.canvas.classList.contains('animated-surface'))
          window.CROP_CALLS.push({target:this.canvas.className,source:args[0] instanceof HTMLCanvasElement?args[0].className:null,geometry:args.slice(1)});
        return original.apply(this,args);
      };
    });
    await page.goto(url);await page.waitForFunction(()=>window.FIELD_PREVIEW_READY===true);
    await page.locator('#play').click(); // Pause the production timer for exact comparisons.
    const defaultSize=await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--tile-size').trim());
    const priorGallery=path.resolve(__dirname,'../../../hazard-motion-20261106/gallery.html');
    const priorGalleryLinked=await page.locator(`a[href="../../hazard-motion-20261106/gallery.html"]`).count()===1&&fs.existsSync(priorGallery);
    await page.locator('#scrub').fill('23');
    const restart=await page.evaluate(()=>{
      document.querySelector('#restart').click();
      const playing=document.querySelector('#play').textContent==='Пауза';
      document.querySelector('#play').click();
      return {slot:document.querySelector('#scrub').value,playing,paused:document.querySelector('#play').textContent==='Воспроизвести'};
    });
    await page.locator('#scrub').fill('1');await page.locator('#scrub').fill('0');
    const fullAnimated=page.locator('.animated-full'),surfaceAnimated=page.locator('.animated-surface');
    const hash=async loc=>{await page.evaluate(()=>scrollTo(0,0));return crypto.createHash('sha256').update(await loc.screenshot()).digest('hex')};
    const firstFull=await Promise.all([hash(fullAnimated.nth(0)),hash(fullAnimated.nth(1))]);
    await page.locator('#viewMode').selectOption('surface');
    const surfaceVisible=await page.locator('.pair-surface').evaluateAll(nodes=>nodes.every(n=>getComputedStyle(n).display==='grid'));
    const fullHidden=await page.locator('.pair-full').evaluateAll(nodes=>nodes.every(n=>getComputedStyle(n).display==='none'));
    const firstSurface=await Promise.all([hash(surfaceAnimated.nth(0)),hash(surfaceAnimated.nth(1))]);
    const cropCalls=await page.evaluate(()=>{
      const expected=[288,233,678,513,0,0,678,513];
      const pairs=[['source-surface','source-full'],['animated-surface','animated-full']];
      return pairs.map(([target,source])=>{
        const calls=window.CROP_CALLS.filter(c=>c.target===target);
        return {target,source,count:calls.length,exact:calls.length>=2&&calls.every(c=>c.source===source&&c.geometry.length===8&&c.geometry.every((v,i)=>v===expected[i]))};
      });
    });
    await page.locator('#viewMode').selectOption('surface');
    await page.locator('#scrub').fill('47');
    const motionPresent=await Promise.all([0,1].map(async i=>await hash(surfaceAnimated.nth(i))!==firstSurface[i]));
    await page.locator('#scrub').fill('95');await page.locator('#step').click();
    const state=await page.evaluate(()=>({slot:document.querySelector('#scrub').value,clock:document.querySelector('#clock').textContent,overflow:document.documentElement.scrollWidth>innerWidth,canvases:[...document.querySelectorAll('#styles canvas')].map(c=>[c.width,c.height]),groups:[...document.querySelectorAll('.coverage')].map(e=>e.textContent),seam:document.querySelector('#seams').textContent,intro:document.querySelector('#intro').textContent}));
    const restartedSurface=await Promise.all([hash(surfaceAnimated.nth(0)),hash(surfaceAnimated.nth(1))]);
    await page.locator('#viewMode').selectOption('full');
    const restartedFull=await Promise.all([hash(fullAnimated.nth(0)),hash(fullAnimated.nth(1))]);
    await page.locator('#size').selectOption('512');
    const scaled=await page.evaluate(()=>getComputedStyle(document.documentElement).getPropertyValue('--tile-size').trim());
    await page.locator('#viewMode').selectOption('surface');
    const surfaceOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
    await page.screenshot({path:path.join(__dirname,`gallery-surface-${width}.png`),fullPage:true});
    await page.locator('#viewMode').selectOption('full');
    const fullVisible=await page.locator('.pair-full').evaluateAll(nodes=>nodes.every(n=>getComputedStyle(n).display==='grid'));
    const fullOverflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);
    const selectedCounts=windowCount(state.groups);
    const partialExpected=selectedCounts.some(([selected,total])=>selected<total);
    const introCorrect=partialExpected?state.intro.includes('Часть покрытия'):state.intro.toLowerCase().includes('кандидат');
    const passed=state.slot==='0'&&!state.overflow&&!surfaceOverflow&&!fullOverflow&&state.canvases.length===8&&state.canvases.filter(x=>x[0]===1254&&x[1]===1254).length===4&&state.canvases.filter(x=>x[0]===678&&x[1]===513).length===4&&state.groups.length===2&&state.seam.includes('95→0')&&surfaceVisible&&fullHidden&&fullVisible&&cropCalls.every(x=>x.exact)&&motionPresent.every(Boolean)&&firstFull.every((x,i)=>x===restartedFull[i])&&firstSurface.every((x,i)=>x===restartedSurface[i])&&defaultSize==='256px'&&scaled==='512px'&&restart.slot==='0'&&restart.playing&&restart.paused&&priorGalleryLinked&&introCorrect&&errors.length===0;
    report.checks.push({width,passed,roi_xywh:[288,233,678,513],crop_draw_calls:cropCalls,temporal_motion_between_slot0_and47:motionPresent,first_full_sha256:firstFull,after_wrap_full_sha256:restartedFull,first_surface_sha256:firstSurface,after_wrap_surface_sha256:restartedSurface,surfaceVisible,fullHidden,fullVisible,surfaceOverflow,fullOverflow,defaultSize,scaled,restart,priorGalleryLinked,partialExpected,introCorrect,...state,page_errors:errors});
    await page.screenshot({path:path.join(__dirname,`gallery-${width}.png`),fullPage:true});await page.close();
  }
  await browser.close();report.passed=report.checks.every(x=>x.passed);
  fs.writeFileSync(path.join(__dirname,'browser-validation.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({passed:report.passed,checks:report.checks.map(x=>({width:x.width,passed:x.passed,groups:x.groups}))}));
  if(!report.passed)process.exitCode=1;
})().catch(async e=>{console.error(e);if(browser)await browser.close();process.exitCode=1});

function windowCount(groups){return groups.map(text=>{const m=text.match(/(\d+) из (\d+)/);return m?[Number(m[1]),Number(m[2])]:[0,0]})}
