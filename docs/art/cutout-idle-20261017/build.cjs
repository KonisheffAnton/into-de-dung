const fs = require('node:fs');
const path = require('node:path');

const root = __dirname;
const rigPath = path.join(root, 'rig.json');
const read = (file) => fs.readFileSync(file);
if (!fs.existsSync(rigPath)) throw new Error(`Missing required input: ${rigPath}`);
const rig = JSON.parse(read(rigPath).toString('utf8'));
if (!Number.isFinite(rig.period_ms) || rig.period_ms <= 0 || !Array.isArray(rig.variants) || rig.variants.length !== 2) {
  throw new Error('rig.json must define period_ms and exactly two variants');
}
for (const variant of rig.variants) {
  if (!variant.id || !variant.title || !Array.isArray(variant.layers) || variant.layers.length !== 3) throw new Error(`Invalid variant: ${variant.id}`);
  for (const layer of variant.layers) {
    if (!['legs', 'torso', 'head'].includes(layer.id) || !Array.isArray(layer.crop) || layer.crop.length !== 4 || !Array.isArray(layer.position) || layer.position.length !== 2 || !Number.isFinite(layer.scale) || !Number.isFinite(layer.amplitude_y) || !Number.isFinite(layer.phase)) throw new Error(`Invalid layer in variant ${variant.id}`);
  }
}
const assets = {
  tile: read(path.resolve(root, '../../../assets/art_presets/approved/grass_defender_v1/grass_reference_v1.png')).toString('base64'),
  defender: read(path.resolve(root, '../../../assets/art_presets/approved/grass_defender_v1/defender_reference_v1.png')).toString('base64'),
  atlases: Object.fromEntries(rig.variants.map((v) => [v.id, read(path.join(root, v.atlas)).toString('base64')]))
};
const data = (mime, b64) => `data:${mime};base64,${b64}`;
const html = `<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Сравнение idle-вариантов</title>
<style>
:root{color-scheme:dark;font:16px/1.45 system-ui,"Segoe UI",sans-serif;background:#11171d;color:#edf1f2}*{box-sizing:border-box}body{margin:0;padding:24px;max-width:1440px;margin-inline:auto}h1{font-size:24px;margin:0 0 8px}.intro{color:#aebdc2;margin:0 0 18px}.controls{display:flex;flex-wrap:wrap;gap:10px 16px;align-items:center;padding:12px 14px;background:#202a31;border:1px solid #34434b;border-radius:10px;margin-bottom:14px}.controls button,.controls select{font:inherit;color:inherit;background:#303e46;border:1px solid #52636c;border-radius:6px;padding:6px 10px}.controls label{display:flex;align-items:center;gap:7px}.controls input[type=range]{width:min(32vw,320px)}canvas{display:block;width:100%;height:auto;image-rendering:pixelated;background:#11171d;border:1px solid #34434b;border-radius:8px}.hint{font-size:13px;color:#aebdc2;margin-top:10px}#status{margin-left:auto;color:#9fc7bb}
</style></head><body>
<h1>Два стиля · idle на тайле</h1><p class="intro">Эталон Защитника и две пробы. Голова и корпус слегка движутся, ноги остаются неподвижными.</p>
<div class="controls"><button id="toggle" type="button">Пауза</button><button id="restart" type="button">С начала</button><label>Фаза <input id="phase" type="range" min="0" max="${rig.period_ms}" value="0" step="1"><output id="phaseValue">0 мс</output></label><label>Скорость <select id="speed"><option value="0.5">0,5×</option><option value="1" selected>1×</option><option value="2">2×</option></select></label><label><input id="exploded" type="checkbox">Разнести слои</label><span id="status">Готово</span></div>
<canvas id="comparison" width="1536" height="652" aria-label="Сравнение трёх персонажей на травяной клетке"></canvas><p class="hint">Цикл 3,2 с. Большой вид — ×4, нижняя полоса — ×1 до масштабирования страницы. Отдельная примерка; художественная приёмка и внедрение в игру ещё впереди.</p>
<script>
const ASSETS=${JSON.stringify({tile:data('image/png',assets.tile),defender:data('image/png',assets.defender),atlases:Object.fromEntries(Object.entries(assets.atlases).map(([k,v])=>[k,data('image/png',v)]))})};
const RIG=${JSON.stringify(rig)};
const canvas=document.getElementById('comparison'),ctx=canvas.getContext('2d',{alpha:false});ctx.imageSmoothingEnabled=false;
const images={};function loadImage(key,src){return new Promise((resolve,reject)=>{const im=new Image();im.onload=()=>{images[key]=im;resolve()};im.onerror=()=>reject(new Error('Не удалось загрузить '+key));im.src=src})}
const layerCache={};
// Растеризуем части один раз: при дыхании меняется положение, а не выбор пикселей текстуры.
function prepareLayers(){for(const v of RIG.variants)for(const l of v.layers)for(const z of [1,4]){const c=document.createElement('canvas');c.width=Math.round(l.crop[2]*l.scale*z);c.height=Math.round(l.crop[3]*l.scale*z);const cc=c.getContext('2d');cc.imageSmoothingEnabled=false;cc.drawImage(images[v.id],...l.crop,0,0,c.width,c.height);layerCache[v.id+'-'+l.id+'-'+z]=c;}}
const ready=Promise.all([loadImage('tile',ASSETS.tile),loadImage('defender',ASSETS.defender),...RIG.variants.map(v=>loadImage(v.id,ASSETS.atlases[v.id]))]).then(()=>{prepareLayers();renderAt(0);return true});
const testMode=new URLSearchParams(location.search).has('test');
const PERIOD=RIG.period_ms, PANEL_W=128, PANEL_PIXELS=512, STRIP_Y=520, SCALE=4;
let playing=true,exploded=false,speed=1,time=0,last=performance.now(),raf=0;
function drawImageAt(im,sx,sy,sw,sh,dx,dy,dw,dh){ctx.drawImage(im,sx,sy,sw,sh,dx,dy,dw,dh)}
function drawVariant(v,cx,cy,t,scale,spread){const offsets={legs:[0,18],torso:[-18,0],head:[18,-10]},z=ctx.getTransform().a*scale>=4?4:1;for(const layer of v.layers){let dx=layer.position[0],dy=layer.position[1]-layer.amplitude_y*(1-Math.cos(2*Math.PI*t/PERIOD+layer.phase))/2;if(spread){dx+=offsets[layer.id][0];dy+=offsets[layer.id][1]}dx=Math.round(dx*z)/z;dy=Math.round(dy*z)/z;const img=layerCache[v.id+'-'+layer.id+'-'+z];ctx.drawImage(img,cx+dx*scale,cy+dy*scale,img.width/z*scale,img.height/z*scale);if(spread){ctx.save();ctx.strokeStyle={legs:'#e5c878',torso:'#85d6c2',head:'#ed9f9b'}[layer.id];ctx.lineWidth=1;ctx.strokeRect(cx+dx*scale,cy+dy*scale,img.width/z*scale,img.height/z*scale);ctx.restore()}}}
function renderAt(ms){if(!Number.isFinite(ms))throw new TypeError('renderAt(ms) expects a finite number');time=((ms%PERIOD)+PERIOD)%PERIOD;ctx.setTransform(1,0,0,1,0,0);ctx.fillStyle='#11171d';ctx.fillRect(0,0,canvas.width,canvas.height);const people=[{id:'defender',title:'Защитник · эталон'},...RIG.variants.map(v=>({id:v.id,title:v.title,variant:v}))];ctx.save();ctx.scale(4,4);people.forEach((p,i)=>{const left=i*PANEL_W,center=left+64,ground=72;ctx.fillStyle='#1e292e';ctx.fillRect(left+1,0,PANEL_W-2,128);ctx.fillStyle='#394a47';ctx.fillRect(left+4,ground+1,PANEL_W-8,1);drawImageAt(images.tile,0,0,512,408,center-64,ground-48,128,102);ctx.font='bold 4px system-ui';ctx.fillStyle='#e8eeed';ctx.fillText(p.title,left+6,11);if(p.variant)drawVariant(p.variant,center,ground,time,1,exploded);else drawImageAt(images.defender,0,0,312,292,center-45,ground-56,78,73);});ctx.restore();people.forEach((p,i)=>{const center=i*PANEL_PIXELS+256,ground=STRIP_Y+48;ctx.fillStyle='#d7e0df';ctx.font='16px system-ui';ctx.fillText('масштаб ×1',i*PANEL_PIXELS+24,STRIP_Y+125);drawImageAt(images.tile,0,0,512,408,center-64,ground-48,128,102);if(p.variant)drawVariant(p.variant,center,ground,time,1,exploded);else drawImageAt(images.defender,0,0,312,292,center-45,ground-56,78,73);});document.getElementById('phase').value=Math.round(time);document.getElementById('phaseValue').value=Math.round(time)+' мс';}
function loop(now){if(playing){time=(time+(now-last)*speed)%PERIOD;renderAt(time)}last=now;raf=requestAnimationFrame(loop)}
document.getElementById('toggle').addEventListener('click',e=>{playing=!playing;e.currentTarget.textContent=playing?'Пауза':'Воспроизвести';last=performance.now()});document.getElementById('restart').addEventListener('click',()=>{time=0;renderAt(time)});document.getElementById('phase').addEventListener('input',e=>{playing=false;document.getElementById('toggle').textContent='Воспроизвести';time=Number(e.target.value);renderAt(time)});document.getElementById('speed').addEventListener('change',e=>speed=Number(e.target.value));document.getElementById('exploded').addEventListener('change',e=>{exploded=e.target.checked;renderAt(time)});
window.ready=ready;window.preview={renderAt(ms){renderAt(ms)},setPlaying(value){playing=Boolean(value);last=performance.now();document.getElementById('toggle').textContent=playing?'Пауза':'Воспроизвести'},setExploded(value){exploded=Boolean(value);document.getElementById('exploded').checked=exploded;renderAt(time)},getState(){return {time,playing,exploded,speed,period_ms:PERIOD}},exportFrame(){return canvas.toDataURL('image/png')}};
ready.then(()=>{last=performance.now();if(!testMode)raf=requestAnimationFrame(loop)});
</script></body></html>`;
fs.writeFileSync(path.join(root, 'preview.html'), html, 'utf8');
console.log(`Built preview.html from ${rig.variants.length} variants (${rig.period_ms} ms cycle)`);
