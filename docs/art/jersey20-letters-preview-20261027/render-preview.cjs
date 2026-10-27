// Рендер отдельного HTML-макета; этот каталог исключён из импорта Godot.
// node render-preview.cjs <путь к node_modules с playwright>
const fs = require('node:fs/promises');
const path = require('node:path');
const {pathToFileURL} = require('node:url');
const {chromium} = require(process.argv[2] ? path.join(process.argv[2], 'playwright') : 'playwright');

function glyphIndex(buffer, code) {
  const tables = buffer.readUInt16BE(4);
  let cmap = 0;
  for(let i=0;i<tables;i++) {
    const p=12+16*i;
    if(buffer.toString('ascii',p,p+4)==='cmap') cmap=buffer.readUInt32BE(p+8);
  }
  if(!cmap) throw new Error('No cmap');
  for(let i=0;i<buffer.readUInt16BE(cmap+2);i++) {
    const p=cmap+4+i*8, sub=cmap+buffer.readUInt32BE(p+4), format=buffer.readUInt16BE(sub);
    if(format===12) {
      for(let j=0;j<buffer.readUInt32BE(sub+12);j++) {
        const s=sub+16+j*12, start=buffer.readUInt32BE(s), end=buffer.readUInt32BE(s+4);
        if(code>=start && code<=end) return buffer.readUInt32BE(s+8)+code-start;
      }
    }
    if(format===4 && code<=65535) {
      const count=buffer.readUInt16BE(sub+6)/2, ends=sub+14, starts=ends+2*count+2;
      const deltas=starts+2*count, offsets=deltas+2*count;
      for(let j=0;j<count;j++) {
        const start=buffer.readUInt16BE(starts+j*2), end=buffer.readUInt16BE(ends+j*2);
        if(code<start || code>end) continue;
        const delta=buffer.readInt16BE(deltas+j*2), off=buffer.readUInt16BE(offsets+j*2);
        if(!off) return (code+delta)&65535;
        const glyph=buffer.readUInt16BE(offsets+j*2+off+2*(code-start));
        if(glyph) return (glyph+delta)&65535;
      }
    }
  }
  return 0;
}

(async()=>{
  const glyphs = {};
  const russian=Array.from({length:64},(_,i)=>String.fromCodePoint(0x410+i)).join('')+'Ёё';
  const numeric='0123456789.,+-%− ';
  const required = {jersey20:numeric, ...Object.fromEntries(['tektur','play','exo2','rubikmonoone','rubik','pixeloid'].map(id=>[id,russian+' HP·']))};
  for(const [id,characters] of Object.entries(required)) {
    const bytes = await fs.readFile(path.join(__dirname,'fonts',id+'.ttf'));
    glyphs[id] = Object.fromEntries([...new Set(characters)].map(c=>[c,glyphIndex(bytes,c.codePointAt(0))]));
    if(Object.values(glyphs[id]).some(index=>!index)) throw new Error(`Missing glyph: ${JSON.stringify(glyphs[id])}`);
  }
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:1432,height:1800},deviceScaleFactor:1});
    const errors = [];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('requestfailed',request=>errors.push(request.url()+': '+request.failure().errorText));
    await page.goto(pathToFileURL(path.join(__dirname,'comparison.html')).href);
    const metrics = await page.evaluate(()=>window.previewReady);
    if(metrics.some(m=>m.numbers!=='Jersey20' || m.numberWeight!==400 || m.numberSize!==metrics[0].numberSize)) throw new Error('Numbers must be identical');
    const dimensions = await page.evaluate(()=>({width:document.images[0].naturalWidth,height:document.images[0].naturalHeight}));
    if(dimensions.width!==1280 || dimensions.height!==850) throw new Error(`Source dimensions differ: ${JSON.stringify(dimensions)}`);
    const fonts = await page.evaluate(()=>[...document.fonts].map(f=>({family:f.family,status:f.status})));
    if(fonts.some(f=>f.status!=='loaded')) throw new Error('Font not loaded');
    const layout = await page.evaluate(()=>[...document.querySelectorAll('.viewport')].map(frame=>{
      const bound=frame.getBoundingClientRect();
      const labels=[...frame.querySelectorAll('.feedback')].map(label=>{
        const r=label.getBoundingClientRect();
        return {text:label.textContent,inside:r.left>=bound.left+3 && r.right<=bound.right-3 && r.top>=bound.top+3 && r.bottom<=bound.bottom-3,
          bounds:{x:r.x-bound.x,y:r.y-bound.y,width:r.width,height:r.height},
          faces:[...label.children].map(span=>({text:span.textContent,family:getComputedStyle(span).fontFamily,weight:getComputedStyle(span).fontWeight}))};
      });
      const overlaps=[];
      for(let i=0;i<labels.length;i++) for(let j=i+1;j<labels.length;j++) {
        const a=labels[i].bounds,b=labels[j].bounds;
        if(Math.min(a.x+a.width,b.x+b.width)>Math.max(a.x,b.x)-4 && Math.min(a.y+a.height,b.y+b.height)>Math.max(a.y,b.y)-4) overlaps.push([labels[i].text,labels[j].text]);
      }
      return {labels,overlaps};
    }));
    if(layout.some(l=>l.labels.some(label=>!label.inside) || l.overlaps.length)) throw new Error(`Overlay clipped or overlaps: ${JSON.stringify(layout)}`);
    const expectedNumbers=['−12.5','−28.0','+8.0','−6.0'];
    const expectedWords=['КРИТ','ЩИТ','БЛОК','ПРОМАХ','КРОВОТЕЧЕНИЕ'];
    for(let i=0;i<metrics.length;i++) {
      for(const face of layout[i].labels.flatMap(l=>l.faces)) {
        const expected=expectedNumbers.includes(face.text)?metrics[i].numbers:expectedWords.includes(face.text)?metrics[i].letters:null;
        if(face.family!==expected) throw new Error(`Wrong face: ${JSON.stringify(face)}`);
      }
    }
    const strips = await page.evaluate(()=>[...document.querySelectorAll('.specimen-row')].map(row=>{
      const bound=row.getBoundingClientRect(),last=row.lastElementChild.getBoundingClientRect();
      return last.right<=bound.right && last.left>=bound.left && last.top>=bound.top && last.bottom<=bound.bottom;
    }));
    if(strips.some(ok=>!ok)) throw new Error('Specimen overflow');
    const client=await page.context().newCDPSession(page);
    await client.send('DOM.enable');
    await client.send('CSS.enable');
    const {root}=await client.send('DOM.getDocument');
    const {nodeIds}=await client.send('DOM.querySelectorAll',{nodeId:root.nodeId,selector:'.number-font, .tag-font'});
    const platformFonts=[];
    for(const nodeId of nodeIds) {
      const result=await client.send('CSS.getPlatformFontsForNode',{nodeId});
      if(!result.fonts.length || result.fonts.some(f=>!f.isCustomFont || f.glyphCount<=0)) throw new Error('Unexpected system fallback: '+JSON.stringify(result));
      platformFonts.push(result.fonts);
    }
    await page.locator('main').screenshot({path:path.join(__dirname,'comparison.png')});
    for(const {id} of metrics) {
      await page.evaluate(id=>document.body.dataset.capture=id,id);
      await page.locator(`.${id} .viewport`).screenshot({path:path.join(__dirname,id+'-battle.png')});
    }
    if(errors.length) throw new Error(JSON.stringify(errors));
    const result = {status:'PASS',renderer:'Edge Chromium/CSS; not Godot',sourceDimensions:dimensions,fonts,metrics,glyphs,layout,specimenRowsWithinBounds:strips,platformFonts,browserErrors:errors,previewOnly:true};
    await fs.writeFile(path.join(__dirname,'validation.json'),JSON.stringify(result,null,2)+'\n');
    console.log(JSON.stringify({status:'PASS',dimensions,metrics,files:7}));
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
