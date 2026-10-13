// Предпросмотр всех пяти кадров в исходном порядке. Игровые файлы не используются.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = __dirname;
const readJson = p => JSON.parse(fs.readFileSync(path.join(root,p),'utf8').replace(/^\uFEFF/,''));
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
async function rgba(file) { return sharp(file).ensureAlpha().raw().toBuffer({resolveWithObject:true}); }
function stats(data, width, height) {
  let x0=width,y0=height,x1=-1,y1=-1,zero=0,opaque=0,partial=0;
  const colors=new Set();
  for(let y=0;y<height;y++) for(let x=0;x<width;x++) {
    const p=(y*width+x)*4, a=data[p+3];
    if(a===0) zero++; else if(a===255) opaque++; else partial++;
    if(a>=128) {x0=Math.min(x,x0);y0=Math.min(y,y0);x1=Math.max(x,x1);y1=Math.max(y,y1);colors.add(data.subarray(p,p+4).toString('hex'));}
  }
  return {bbox_alpha128:[x0,y0,x1+1,y1+1],transparent:zero,opaque,partial_alpha:partial,colors_alpha128:colors.size};
}
function difference(a,b,width,yStart=0) {
  let changed=0;
  for(let p=yStart*width*4;p<a.length;p+=4) if(!a.subarray(p,p+4).equals(b.subarray(p,p+4))) changed++;
  return changed;
}
async function main() {
  const result=readJson('pixellab/result.json'), manifest=readJson('request-manifest.json');
  const input=await rgba(path.join(root,'pixellab/reference-128.png'));
  const frames=[], checks=[];
  for(const item of result.files) {
    const bytes=fs.readFileSync(path.join(root,'pixellab',item.file));
    if(hash(bytes)!==item.sha256) throw Error('PNG changed: '+item.file);
    const f=await rgba(bytes);
    if(f.info.width!==128 || f.info.height!==128) throw Error('Wrong dimensions');
    const s=stats(f.data,128,128);
    if(!s.transparent || s.bbox_alpha128[0]<=0 || s.bbox_alpha128[1]<=0 || s.bbox_alpha128[2]>=128 || s.bbox_alpha128[3]>=128) throw Error('Background/clip check failed');
    frames.push(f.data); checks.push({file:item.file,sha256:item.sha256,...s,changed_pixels_from_input:difference(input.data,f.data,128),changed_pixels_in_bottom_28_rows:difference(input.data,f.data,128,100)});
  }
  if(frames.length!==5) throw Error('Unexpected frame count; inspect and document before preview');
  for(const scale of [1,4]) {
    const side=128*scale;
    const enlarged=await Promise.all(frames.map(data=>sharp(data,{raw:{width:128,height:128,channels:4}}).resize(side,side,{kernel:'nearest'}).raw().toBuffer()));
    const animation=()=>sharp(Buffer.concat(enlarged),{raw:{width:side,height:side*frames.length,channels:4,pageHeight:side}});
    await animation().gif({delay:frames.map(()=>520),loop:0,dither:0,effort:7}).toFile(path.join(root,scale===1?'idle-native.gif':'idle-4x.gif'));
    if(scale===4) await animation().webp({lossless:true,delay:frames.map(()=>520),loop:0,effort:4}).toFile(path.join(root,'idle-lossless-4x.webp'));
  }
  const composites=[];
  for(let i=0;i<frames.length;i++) {
    const x=12+(i%5)*268,y=12+Math.floor(i/5)*288;
    composites.push({input:await sharp(frames[i],{raw:{width:128,height:128,channels:4}}).resize(256,256,{kernel:'nearest'}).png().toBuffer(),left:x,top:y});
    composites.push({input:Buffer.from(`<svg width="256" height="20"><text x="128" y="16" text-anchor="middle" fill="#e2ded0" font-size="14" font-family="sans-serif">${String(i+1).padStart(2,'0')} · ${(i*.52).toFixed(2)}s</text></svg>`),left:x,top:y+258});
  }
  await sharp({create:{width:1352,height:300,channels:4,background:'#333a35'}}).composite(composites).png().toFile(path.join(root,'filmstrip.png'));
  const images=result.files.map(item=>'data:image/png;base64,'+fs.readFileSync(path.join(root,'pixellab',item.file)).toString('base64'));
  const video='data:video/mp4;base64,'+fs.readFileSync(path.join(root,'../archer-idle-pixellab-20261014/source/user-motion.mp4')).toString('base64');
  const html=`<!doctype html><html lang="ru"><meta charset="utf-8"><title>Лучница — исходный ролик и PixelLab</title><style>body{background:#202521;color:#eee8d9;font:17px system-ui;margin:24px}main{display:flex;gap:24px;flex-wrap:wrap}section{width:512px}video,canvas{width:512px;height:512px;display:block}canvas{image-rendering:pixelated;background:repeating-conic-gradient(#333a35 0% 25%,#424942 0% 50%) 0/24px 24px}button{font:inherit;padding:8px 18px}p{max-width:1000px}small{color:#b9beac}</style><h1>Лучница: спокойное дыхание</h1><p>Слева — предоставленный MP4. Справа — новая проба PixelLab: исходные RGBA PNG, 5 × 520 мс. Новая генерация по чистому рисунку и описанию движения; точное повторение старых кадров не заявлено.</p><main><section><h2>Референс движения</h2><video id="v" src="${video}" muted loop playsinline></video><small>320×320, чёрный фон, видеосжатие</small></section><section><h2>PixelLab · 128×128 → ×4</h2><canvas id="c" width="128" height="128"></canvas><small id="frame"></small></section></main><p><button id="toggle">Пауза</button> <button id="restart">Сначала</button></p><p>Пробы сохранены без ручной ретуши. Размер в игре — отдельная настройка: целевая высота лучницы 90% Защитника. Эта проба в игру не подключена.</p><script>const urls=${JSON.stringify(images)};const images=urls.map(src=>{const i=new Image();i.src=src;return i});const ctx=c.getContext('2d');ctx.imageSmoothingEnabled=false;Promise.all(images.map(i=>i.decode())).then(()=>{v.play().catch(()=>{});function draw(){const index=Math.min(4,Math.floor((v.currentTime%2.6)/.52));ctx.clearRect(0,0,128,128);ctx.drawImage(images[index],0,0);frame.textContent='Кадр '+String(index+1).padStart(2,'0')+' / 5 · '+v.currentTime.toFixed(2)+' с';requestAnimationFrame(draw)}draw()});toggle.onclick=()=>{if(v.paused){v.play();toggle.textContent='Пауза'}else{v.pause();toggle.textContent='Продолжить'}};restart.onclick=()=>{v.currentTime=0;v.play();toggle.textContent='Пауза'};</script></html>`;
  fs.writeFileSync(path.join(root,'comparison.html'),html);
  const validation={input_sha256:manifest.source_sha256,frames:checks,frame_count:frames.length,frame_ms:520,total_ms:2600,first_rgba_equals_input:input.data.equals(frames[0]),last_rgba_equals_input:input.data.equals(frames.at(-1)),seam_changed_rgba_pixels:difference(frames.at(-1),frames[0],128),adjacent_changed_rgba_pixels:frames.slice(1).map((f,i)=>difference(frames[i],f,128)),no_manual_png_edits:true};
  for(const file of ['idle-native.gif','idle-4x.gif','idle-lossless-4x.webp']) {
    const meta=await sharp(path.join(root,file),{animated:true}).metadata();
    validation[file]={width:meta.width,pageHeight:meta.pageHeight,pages:meta.pages,delay:meta.delay,loop:meta.loop};
    if(meta.pages!==5 || meta.delay.length!==5 || meta.delay.some(ms=>ms!==520) || meta.loop!==0) throw Error('Wrong preview timeline: '+file);
  }
  fs.writeFileSync(path.join(root,'validation.json'),JSON.stringify(validation,null,2)+'\n');
  console.log(JSON.stringify({frames:5,total_ms:2600,first_rgba_equals_input:validation.first_rgba_equals_input,last_rgba_equals_input:validation.last_rgba_equals_input,seam_changed:validation.seam_changed_rgba_pixels}));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
