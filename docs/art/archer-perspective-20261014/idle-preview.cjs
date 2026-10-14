// Поза и размер PNG не меняются: галерея использует один anchor и общий display transform.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const repo = path.resolve(__dirname, '../../..');
const staticManifest = JSON.parse(fs.readFileSync(path.join(__dirname, 'manifest.json'), 'utf8'));
const oldRoot = path.join(repo, 'docs/art/archer-idle-variants-20261014/variants/b-transfer-128');
const idleRoot = path.join(__dirname, 'pixellab');
const tilePath = 'assets/art_presets/trials/grass_reference_v3/grass_a.png';
const defenderPath = 'assets/art_presets/trials/defender_field_v1/defender_new.png';
const oldPaths = [1, 2, 3].map(i => `docs/art/archer-idle-variants-20261014/variants/b-transfer-128/frame-0${i}.png`);
const refPath = 'docs/art/archer-perspective-20261014/pixellab/reference-128.png';
const idleFiles = fs.existsSync(idleRoot) ? fs.readdirSync(idleRoot).filter(n => /^frame-\d+\.png$/i.test(n)).sort((a,b) => Number(a.match(/\d+/)[0])-Number(b.match(/\d+/)[0])) : [];
const idlePaths = idleFiles.map(name => `docs/art/archer-perspective-20261014/pixellab/${name}`);
const durationMs = 2600;

function delayPlan(count) {
  // GIF принимает задержки с шагом 10 мс; распределяем остаток равномерно, сохраняя общий цикл.
  const units = durationMs / 10;
  if (!Number.isInteger(units) || count < 1 || count > units) throw new Error('Нельзя распределить GIF duration по кадрам с шагом 10 мс');
  const base = Math.floor(units / count), extra = units % count;
  return Array.from({length: count}, (_, i) => (base + (i < extra ? 1 : 0)) * 10);
}

async function inspectSource(key, relativePath) {
  const bytes = fs.readFileSync(path.join(repo, relativePath));
  const {data, info} = await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject: true});
  let left = info.width, top = info.height, right = 0, bottom = 0;
  for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
    if (data[(y * info.width + x) * 4 + 3] >= 128) {
      left = Math.min(left, x); top = Math.min(top, y); right = Math.max(right, x + 1); bottom = Math.max(bottom, y + 1);
    }
  }
  if (!right || !bottom) throw new Error(`${key}: не найдено пикселей alpha>=128`);
  return {key, path: relativePath, sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
    size: [info.width, info.height], bbox_alpha128: [left, top, right, bottom], bytes};
}

function makeHtml(images, geometry, oldCount, idleCount) {
  return `<!doctype html><html lang="ru"><meta charset="utf-8"><title>Лучница — idle проба</title>
<style>*{box-sizing:border-box}body{margin:0;padding:24px;background:#25292a;color:#eee9dc;font:16px Arial,sans-serif;width:1728px}h1{font-size:25px;margin:0 0 8px}p{color:#c4c6b9;line-height:1.5;margin:8px 0 16px}.row{display:flex;gap:12px}.panel{width:544px;text-align:center;background:#303633;border:1px solid #444d43;border-radius:8px;overflow:hidden}h2{font-size:18px;margin:16px 0 0}canvas{display:block;image-rendering:pixelated;margin:auto}.controls{display:flex;align-items:center;gap:14px;margin:18px 0}.small{font-size:13px;color:#b9beaf}.native{margin-top:12px}.native .panel{background:none;border:none}button,input{font:inherit}button{padding:5px 12px;background:#3a463c;color:#eee9dc;border:1px solid #66745e;border-radius:4px;cursor:pointer}input[type=range]{width:520px}</style>
<h1>Лучница — idle проба</h1><p>Сравнение на одной поверхности. Цикл 2,6 секунды; рисунки сохраняют исходные пропорции и прозрачность.</p>
<div class="row"><section class="panel"><h2>Защитник · статичный образ</h2><canvas id="defender" width="544" height="448"></canvas></section><section class="panel"><h2>Лучница · прежняя B</h2><canvas id="old" width="544" height="448"></canvas></section><section class="panel"><h2>Лучница · новый idle</h2><canvas id="idle" width="544" height="448"></canvas></section></div>
<div class="controls"><button id="play">Пауза</button><button id="restart">Сначала</button><input id="seek" type="range" min="0" max="${durationMs}" step="1" value="0" aria-label="Положение цикла"><span id="time" class="small">0,00 с / 2,60 с</span></div>
<div class="row native"><section class="panel"><canvas id="defender-small" width="160" height="118"></canvas></section><section class="panel"><canvas id="old-small" width="160" height="118"></canvas></section><section class="panel"><canvas id="idle-small" width="160" height="118"></canvas></section></div>
<p class="small">Верхний ряд ×4 · нижний ряд ×1. Кадры повторяются в исходном порядке; положение и размер одинаковы весь цикл.</p>
<script>
const data=${JSON.stringify(images)}, g=${JSON.stringify(geometry)}, oldCount=${oldCount}, idleCount=${idleCount}, cycle=${durationMs};
const loaded={}; let playing=true, startedAt=0, pausedAt=0, raf=0;
function canvas(w,h){const c=document.createElement('canvas');c.width=w;c.height=h;return c;}
function polygon(ctx,pts){ctx.beginPath();pts.forEach((p,i)=>i?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();}
function triangle(ctx,img,src,dst){const [s0,s1,s2]=src,[d0,d1,d2]=dst;const sx1=s1[0]-s0[0],sy1=s1[1]-s0[1],sx2=s2[0]-s0[0],sy2=s2[1]-s0[1],dx1=d1[0]-d0[0],dy1=d1[1]-d0[1],dx2=d2[0]-d0[0],dy2=d2[1]-d0[1],det=sx1*sy2-sx2*sy1;const a=(dx1*sy2-dx2*sy1)/det,c=(dx2*sx1-dx1*sx2)/det,b=(dy1*sy2-dy2*sy1)/det,d=(dy2*sx1-dy1*sx2)/det;ctx.save();polygon(ctx,dst);ctx.clip();ctx.transform(a,b,c,d,d0[0]-a*s0[0]-c*s0[1],d0[1]-b*s0[0]-d*s0[1]);ctx.drawImage(img,0,0);ctx.restore();}
let ground, defenderNative;
function paintCanvas(id,key,frameIndex,zoom){const c=document.getElementById(id),ctx=c.getContext('2d');ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,c.width,c.height);ctx.imageSmoothingEnabled=false;ctx.translate(c.width/2,zoom===4?242:64);ctx.scale(zoom,zoom);polygon(ctx,g.tile.vertices);ctx.fillStyle='#535e3e';ctx.fill();for(const ix of [[0,1,2],[0,2,3]])triangle(ctx,ground,ix.map(i=>g.tile.uv[i]),ix.map(i=>g.tile.vertices[i]));polygon(ctx,g.tile.vertices);ctx.strokeStyle='rgba(64,74,43,.6)';ctx.lineWidth=.7;ctx.stroke();if(key==='defender'){const d=g.defender;ctx.drawImage(defenderNative,...d.position,d.crop[2]*d.scale,d.crop[3]*d.scale);return;}const frames=key==='old'?loaded.old:loaded.idle;const im=frames[frameIndex%frames.length],tr=key==='old'?g.original:g.archer;ctx.drawImage(im,...tr.position,im.width*tr.scale,im.height*tr.scale);}
function frameIndexAt(ms,count){return Math.min(count-1,Math.floor(((ms%cycle)+cycle)%cycle/cycle*count));}
function render(ms){const oi=frameIndexAt(ms,oldCount),ni=frameIndexAt(ms,idleCount);for(const [id,key,index,z]of [['defender','defender',0,4],['old','old',oi,4],['idle','idle',ni,4],['defender-small','defender',0,1],['old-small','old',oi,1],['idle-small','idle',ni,1]])paintCanvas(id,key,index,z);document.getElementById('seek').value=String(ms);document.getElementById('time').textContent=(ms/1000).toFixed(2).replace('.',',')+' с / 2,60 с';window.__previewState={ms,oldIndex:oi,idleIndex:ni,playing};}
function tick(now){if(!playing)return;const ms=(now-startedAt)%cycle;render(ms);raf=requestAnimationFrame(tick);}
function pause(){if(!playing)return;pausedAt=(performance.now()-startedAt)%cycle;playing=false;cancelAnimationFrame(raf);render(pausedAt);document.getElementById('play').textContent='Играть';}
function play(){if(playing)return;startedAt=performance.now()-pausedAt;playing=true;render(pausedAt);document.getElementById('play').textContent='Пауза';raf=requestAnimationFrame(tick);}
function seek(ms){pausedAt=Math.max(0,Math.min(cycle-1,Number(ms)));if(playing)startedAt=performance.now()-pausedAt;render(pausedAt);}
function restart(){pausedAt=0;startedAt=performance.now();render(0);if(!playing){playing=true;render(pausedAt);document.getElementById('play').textContent='Пауза';raf=requestAnimationFrame(tick);}}
window.__preview={pause,play,seek,restart,frameIndexAt};
window.ready=(async()=>{for(const [key,url] of Object.entries(data)){if(Array.isArray(url)){loaded[key]=[];for(const src of url){const im=new Image();im.src=src;await im.decode();loaded[key].push(im);}}else{const im=new Image();im.src=url;await im.decode();loaded[key]=im;}}ground=canvas(loaded.tile.width,loaded.tile.height);const gc=ground.getContext('2d');gc.drawImage(loaded.tile,0,0);const pix=gc.getImageData(0,0,ground.width,ground.height);for(let i=0;i<pix.data.length;i+=4)for(let j=0;j<3;j++)pix.data[i+j]*=g.tile.tint[j];gc.putImageData(pix,0,0);defenderNative=canvas(...g.defender.native);const dc=defenderNative.getContext('2d');dc.imageSmoothingEnabled=false;dc.drawImage(loaded.defender,...g.defender.crop,0,0,...g.defender.native);document.getElementById('play').addEventListener('click',()=>playing?pause():play());document.getElementById('restart').addEventListener('click',restart);document.getElementById('seek').addEventListener('input',e=>seek(e.target.value));render(0);startedAt=performance.now();raf=requestAnimationFrame(tick);return true;})();
</script></html>`;
}

async function writeGif(frames, delays, outputPath) {
  const width = frames[0].size[0], height = frames[0].size[1];
  const page = Buffer.alloc(width * height * 4 * frames.length);
  for (let i = 0; i < frames.length; i++) {
    const raw = await sharp(frames[i].bytes).ensureAlpha().raw().toBuffer();
    raw.copy(page, i * raw.length);
  }
  await sharp(page, {raw: {width, height: height * frames.length, channels: 4, pageHeight: height}})
    .gif({delay: delays, loop: 0, effort: 7, dither: 0}).toFile(outputPath);
}

(async () => {
  if (!fs.existsSync(path.join(repo, refPath)) || !idlePaths.length)
    throw new Error('Ожидаются pixellab/reference-128.png и pixellab/frame-*.png; скрипт запускается после получения пробы');
  const sources = {};
  for (const [key, file] of [['tile', tilePath], ['defender', defenderPath], ...oldPaths.map((p,i) => [`old${i+1}`,p]), ['reference',refPath], ...idlePaths.map((p,i) => [`idle${i+1}`,p])])
    sources[key] = await inspectSource(key, file);
  const oldFrames = [sources.old1,sources.old2,sources.old3];
  const reference = sources.reference, refSize = reference.size;
  const generatedFrames = idlePaths.map((_,i) => sources[`idle${i+1}`]);
  for (const frame of generatedFrames) if (frame.size[0] !== refSize[0] || frame.size[1] !== refSize[1])
    throw new Error(`${frame.path}: все idle кадры должны совпадать размером с reference`);
  const referenceRaw = await sharp(reference.bytes).ensureAlpha().raw().toBuffer();
  const samePixels = async frame => (await sharp(frame.bytes).ensureAlpha().raw().toBuffer()).equals(referenceRaw);
  const hasReferenceEndpoints = await samePixels(generatedFrames[0]) && await samePixels(generatedFrames[generatedFrames.length - 1]);
  // Первый ответ повторяет полупрозрачный вход; остальные кадры имеют бинарную alpha.
  // Исключаем только переходный кадр из показа, сохраняя все 13 PNG в архиве без правок.
  if(generatedFrames.length!==13)throw new Error('Playback selection requires the reviewed 13-frame result');
  const idleFrames = generatedFrames.slice(1);
  const anchor = staticManifest.geometry.corrected.source_anchor_percent;
  const targetHeight = 51.840026784;
  const scale = targetHeight / (reference.bbox_alpha128[3] - reference.bbox_alpha128[1]);
  const destination = staticManifest.geometry.corrected.destination_anchor;
  const geometry = {
    tile: staticManifest.geometry.tile,
    defender: staticManifest.geometry.defender,
    original: staticManifest.geometry.original,
    archer: {position: [destination[0] - refSize[0] * scale * anchor[0] / 100,
      destination[1] - refSize[1] * scale * anchor[1] / 100], scale, height: targetHeight,
      source_anchor_percent: anchor, destination_anchor: destination},
  };
  const images = {tile: 'data:image/png;base64,'+sources.tile.bytes.toString('base64'),
    defender:'data:image/png;base64,'+sources.defender.bytes.toString('base64'),
    old:oldFrames.map(s=>'data:image/png;base64,'+s.bytes.toString('base64')),
    idle:idleFrames.map(s=>'data:image/png;base64,'+s.bytes.toString('base64'))};
  fs.writeFileSync(path.join(__dirname,'idle.html'), makeHtml(images,geometry,oldFrames.length,idleFrames.length));
  const delays = delayPlan(idleFrames.length);
  const gifPath = path.join(__dirname, 'idle-source.gif');
  await writeGif(idleFrames, delays, gifPath);
  const gifMeta = await sharp(gifPath,{animated:true}).metadata();
  const browser = await chromium.launch({headless:true,channel:'chrome'});
  let errors=[];
  try {
    const page = await browser.newPage({viewport:{width:1728,height:900},deviceScaleFactor:1});
    page.on('pageerror', e => errors.push(String(e)));
    await page.goto(require('node:url').pathToFileURL(path.join(__dirname,'idle.html')).href);
    await page.evaluate(() => window.ready);
    const controls = await page.evaluate(async () => {
      window.__preview.pause(); const paused = !window.__previewState.playing;
      window.__preview.seek(1300); const seekIndex = window.__previewState.idleIndex;
      window.__preview.restart(); const restartAtZero = window.__previewState.ms === 0;
      window.__preview.play(); const played = window.__previewState.playing;
      window.__preview.pause(); return {paused,seekIndex,restartAtZero,played};
    });
    await page.evaluate(()=>window.__preview.seek(0));
    await page.screenshot({path:path.join(__dirname,'idle-preview.png'),fullPage:true});
    const tileFrames=[];
    for(let i=0;i<idleFrames.length;i++){
      await page.evaluate(ms=>window.__preview.seek(ms),(i+.25)*durationMs/idleFrames.length);
      const bytes=await page.locator('#idle').screenshot();
      const meta=await sharp(bytes).metadata();tileFrames.push({bytes,size:[meta.width,meta.height]});
    }
    const tileGifPath=path.join(__dirname,'idle-on-tile.gif');
    await writeGif(tileFrames,delays,tileGifPath);
    const tileGifMeta=await sharp(tileGifPath,{animated:true}).metadata();
    await page.evaluate(()=>{
      const strip=document.createElement('div');strip.id='filmstrip';strip.style.cssText='display:flex;flex-wrap:wrap;width:1664px;background:#303633';
      for(const im of loaded.idle){const c=canvas(128,128);c.getContext('2d').drawImage(im,0,0);strip.append(c);}
      document.body.append(strip);
    });
    await page.locator('#filmstrip').screenshot({path:path.join(__dirname,'idle-filmstrip.png')});
    if (errors.length || !controls.paused || !controls.restartAtZero || !controls.played ||
        controls.seekIndex !== Math.floor(1300 / durationMs * idleFrames.length) ||
        (gifMeta.delay||[]).reduce((a,b)=>a+b,0) !== durationMs ||
        (tileGifMeta.delay||[]).reduce((a,b)=>a+b,0) !== durationMs || delays.reduce((a,b)=>a+b,0)!==durationMs)
      throw new Error(JSON.stringify({message:'Preview check failed',errors,controls,sourceGifDelays:gifMeta.delay,tileGifDelays:tileGifMeta.delay,delays}));
    const sourceChecks = Object.values(sources).map(s => ({path:s.path,sha256:s.sha256,size:s.size,bbox_alpha128:s.bbox_alpha128}));
    const validation = {status:'PASS', source_checks:sourceChecks, javascript_errors:errors, controls,
      old_frame_count:oldFrames.length,idle_frame_count:idleFrames.length,
      source_frame_count:generatedFrames.length,reference_endpoints_in_source:hasReferenceEndpoints,
      playback_files:idleFrames.map(f=>f.path),excluded_from_playback:[{path:generatedFrames[0].path,reason:'partial-alpha reference endpoint differs in opacity from the remaining binary-alpha frames; original PNG retained'}],
      reference_size:refSize,anchor_percent:anchor,display_scale:scale,display_alpha_height:targetHeight,
      gif:{path:'idle-source.gif',frames:gifMeta.pages,duration_ms:(gifMeta.delay||[]).reduce((a,b)=>a+b,0),delays_ms:delays,
        note:'GIF задержки квантованы по 10 мс; отдельные интервалы распределены максимально равномерно, общая длительность ровно 2600 мс.'},
      tile_gif:{path:'idle-on-tile.gif',duration_ms:(tileGifMeta.delay||[]).reduce((a,b)=>a+b,0),frames:tileGifMeta.pages},
      scope:'Offline Canvas visualizer and GIF previews; source PNGs unchanged. GIF may quantize palette/alpha and coalesce duplicate frames; HTML uses original PNGs. No art/game acceptance.'};
    fs.writeFileSync(path.join(__dirname,'idle-validation.json'),JSON.stringify(validation,null,2)+'\n');
    console.log(JSON.stringify(validation));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode=1; });
