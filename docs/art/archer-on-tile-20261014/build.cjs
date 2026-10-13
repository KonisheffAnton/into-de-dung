// Примерка через Canvas сохраняет байты исходников и не корректирует позу лучницы.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const repo = path.resolve(__dirname, '../../..');
const sources = {
  tile: 'assets/art_presets/trials/grass_reference_v3/grass_a.png',
  defender: 'assets/art_presets/trials/defender_field_v1/defender_new.png',
  b1: 'docs/art/archer-idle-variants-20261014/variants/b-transfer-128/frame-01.png',
  b2: 'docs/art/archer-idle-variants-20261014/variants/b-transfer-128/frame-02.png',
  b3: 'docs/art/archer-idle-variants-20261014/variants/b-transfer-128/frame-03.png',
};

(async () => {
  const records = {}, images = {};
  for (const [key, file] of Object.entries(sources)) {
    const bytes = fs.readFileSync(path.join(repo, file));
    const {data, info} = await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject:true});
    let left=info.width, top=info.height, right=0, bottom=0;
    for (let y=0; y<info.height; y++) for (let x=0; x<info.width; x++) {
      if (data[(y*info.width+x)*4+3] >= 128) {
        left=Math.min(left,x); top=Math.min(top,y); right=Math.max(right,x+1); bottom=Math.max(bottom,y+1);
      }
    }
    records[key] = {path:file, sha256:crypto.createHash('sha256').update(bytes).digest('hex'),
      size:[info.width,info.height], bbox_alpha128:[left,top,right,bottom]};
    images[key] = 'data:image/png;base64,'+bytes.toString('base64');
  }
  const defenderScale=0.0745342*0.8;
  const defenderHeight=966*defenderScale;
  const archerScale=defenderHeight*0.9/(records.b1.bbox_alpha128[3]-records.b1.bbox_alpha128[1]);
  const bottom=(-65.14+966*0.0745342)*0.8;
  const geometry = {
    tile:{vertices:[[0,-48],[64,0],[0,48],[-64,0]], uv:[[724,110],[1350,543],[724,975],[96,543]], tint:[0.79,0.8,0.75]},
    defender:{crop:[89,206,1034,966], native:[77,72], position:[-44.42*0.8,-65.14*0.8], scale:defenderScale, height:defenderHeight},
    archer:{position:[-5-64*archerScale,bottom-117*archerScale], scale:archerScale,
      height_b1:defenderHeight*0.9, ratio_b1:0.9, source_anchor:[64,117], destination_anchor:[-5,bottom],
      note:'Provisional display placement: body axis x=64, lower edge y=117 of B1. Same transform for all frames; no pose, alpha or perspective correction.'},
  };
  const manifest={base:'3321b359f5e687a532a84c958bf2ff367703cc80',sources:records,geometry,
    scope:'Offline Canvas fitting; current trial grass A and static Defender geometry. Not a Godot render or accepted game anchor. No generation or source PNG changes.'};
  fs.writeFileSync(path.join(__dirname,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
  const html=`<!doctype html><html lang="ru"><meta charset="utf-8"><title>Лучница B на тайле</title>
<style>*{box-sizing:border-box}body{margin:0;padding:24px;background:#25292a;color:#eee9dc;font:16px Arial,sans-serif;width:1152px}h1{font-size:25px;margin:0 0 8px}p{color:#c4c6b9;line-height:1.5;margin:8px 0 16px}.row{display:flex;gap:16px}.panel{width:544px;text-align:center;background:#303633;border:1px solid #444d43;border-radius:8px;overflow:hidden}h2{font-size:18px;margin:16px 0 0}canvas{display:block;image-rendering:pixelated;margin:auto}.controls{display:flex;align-items:center;gap:18px;margin:18px 0}select{font:inherit;padding:4px;background:#303633;color:#eee9dc}label{cursor:pointer}.small{font-size:13px;color:#b9beaf}.native{margin-top:16px}.native .panel{background:none;border:none}</style>
<h1>Лучница B — примерка на тайле</h1><p>Одинаковая поверхность 4:3. Высота B1 — 90% Защитника; пропорции исходников сохранены.</p>
<div class="row" id="comparison"><section class="panel"><h2>Защитник · текущий статичный образ</h2><canvas id="defender" width="544" height="448"></canvas></section><section class="panel"><h2 id="frame-title">Лучница · B1</h2><canvas id="archer" width="544" height="448"></canvas></section></div>
<div class="controls"><label>Кадр <select id="frame"><option value="b1">B1</option><option value="b2">B2</option><option value="b3">B3</option></select></label><label><input type="checkbox" id="axes"> Оси поверхности</label><span class="small">Увеличение ×4 · без исправления ракурса</span></div>
<div class="row native"><section class="panel"><canvas id="defender-native" width="160" height="118"></canvas></section><section class="panel"><canvas id="archer-native" width="160" height="118"></canvas></section></div>
<p class="small">Нижний ряд — условный масштаб ×1. Посадка лучницы предварительная. Отдельная Canvas-примерка, не кадр из игры.</p>
<script>
const sourceData=${JSON.stringify(images)}, geometry=${JSON.stringify(geometry)};
const loaded={};
function canvas(w,h){const c=document.createElement('canvas');c.width=w;c.height=h;return c;}
function polygon(ctx,points){ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();}
// Два аффинных треугольника воспроизводят заданные UV, не деформируя персонажей.
function triangle(ctx,img,src,dst){
 const [s0,s1,s2]=src,[d0,d1,d2]=dst;
 const sx1=s1[0]-s0[0],sy1=s1[1]-s0[1],sx2=s2[0]-s0[0],sy2=s2[1]-s0[1];
 const dx1=d1[0]-d0[0],dy1=d1[1]-d0[1],dx2=d2[0]-d0[0],dy2=d2[1]-d0[1],det=sx1*sy2-sx2*sy1;
 const a=(dx1*sy2-dx2*sy1)/det,c=(dx2*sx1-dx1*sx2)/det,b=(dy1*sy2-dy2*sy1)/det,d=(dy2*sx1-dy1*sx2)/det;
 ctx.save();polygon(ctx,dst);ctx.clip();ctx.transform(a,b,c,d,d0[0]-a*s0[0]-c*s0[1],d0[1]-b*s0[0]-d*s0[1]);ctx.drawImage(img,0,0);ctx.restore();
}
let ground,defenderNative;
function draw(id,key,zoom){
 const c=document.getElementById(id),ctx=c.getContext('2d');ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,c.width,c.height);
 ctx.imageSmoothingEnabled=false;ctx.translate(c.width/2,zoom===4?242:64);ctx.scale(zoom,zoom);
 const tile=geometry.tile;polygon(ctx,tile.vertices);ctx.fillStyle='#535e3e';ctx.fill();
 for(const ix of [[0,1,2],[0,2,3]]) triangle(ctx,ground,ix.map(i=>tile.uv[i]),ix.map(i=>tile.vertices[i]));
 polygon(ctx,tile.vertices);ctx.strokeStyle='rgba(64,74,43,.6)';ctx.lineWidth=.7;ctx.stroke();
 if(document.getElementById('axes').checked){ctx.beginPath();ctx.moveTo(-64,0);ctx.lineTo(64,0);ctx.moveTo(0,-48);ctx.lineTo(0,48);ctx.strokeStyle='#a4c9c1';ctx.lineWidth=.35;ctx.stroke();}
 if(key==='defender'){const g=geometry.defender;ctx.drawImage(defenderNative,...g.position,g.crop[2]*g.scale,g.crop[3]*g.scale);}
 else{const g=geometry.archer;ctx.drawImage(loaded[key],...g.position,128*g.scale,128*g.scale);}
}
function render(){const key=document.getElementById('frame').value;document.getElementById('frame-title').textContent='Лучница · '+key.toUpperCase();for(const [id,k,z] of [['defender','defender',4],['archer',key,4],['defender-native','defender',1],['archer-native',key,1]])draw(id,k,z);}
window.ready=(async()=>{for(const [key,url]of Object.entries(sourceData)){const im=new Image();im.src=url;await im.decode();loaded[key]=im;}
 ground=canvas(loaded.tile.width,loaded.tile.height);const gc=ground.getContext('2d');gc.drawImage(loaded.tile,0,0);const pix=gc.getImageData(0,0,ground.width,ground.height);for(let i=0;i<pix.data.length;i+=4)for(let j=0;j<3;j++)pix.data[i+j]*=geometry.tile.tint[j];gc.putImageData(pix,0,0);
 defenderNative=canvas(...geometry.defender.native);const dc=defenderNative.getContext('2d');dc.imageSmoothingEnabled=false;dc.drawImage(loaded.defender,...geometry.defender.crop,0,0,...geometry.defender.native);
 render();document.getElementById('frame').addEventListener('change',render);document.getElementById('axes').addEventListener('change',render);return true;})();
</script></html>`;
  fs.writeFileSync(path.join(__dirname,'comparison.html'),html);
  console.log(JSON.stringify({sources:Object.keys(records).length,defenderHeight,archerHeight:geometry.archer.height_b1,placement:geometry.archer.position}));
})().catch(error=>{console.error(error);process.exitCode=1;});
