// Ракурс исправлен генерацией; Canvas задаёт лишь масштаб и положение неизменённых PNG.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const repo = path.resolve(__dirname, '../../..');
const sources = {
  tile: 'assets/art_presets/trials/grass_reference_v3/grass_a.png',
  defender: 'assets/art_presets/trials/defender_field_v1/defender_new.png',
  original: 'docs/art/archer-idle-variants-20261014/variants/b-transfer-128/frame-01.png',
  corrected: 'docs/art/archer-perspective-20261014/archer-corrected.png',
};

(async () => {
  const records = {}, images = {};
  for (const [key, file] of Object.entries(sources)) {
    const bytes = fs.readFileSync(path.join(repo, file));
    const {data, info} = await sharp(bytes).ensureAlpha().raw().toBuffer({resolveWithObject: true});
    let left = info.width, top = info.height, right = 0, bottom = 0;
    for (let y = 0; y < info.height; y++) for (let x = 0; x < info.width; x++) {
      if (data[(y * info.width + x) * 4 + 3] >= 128) {
        left = Math.min(left, x); top = Math.min(top, y); right = Math.max(right, x + 1); bottom = Math.max(bottom, y + 1);
      }
    }
    if (!right || !bottom) throw new Error(`${key} has no alpha>=128 pixels`);
    records[key] = {path: file, sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
      size: [info.width, info.height], bbox_alpha128: [left, top, right, bottom]};
    images[key] = 'data:image/png;base64,' + bytes.toString('base64');
  }
  const defenderScale = 0.0745342 * 0.8;
  const defenderHeight = 966 * defenderScale;
  const targetHeight = 51.840026784;
  const correctedBox = records.corrected.bbox_alpha128;
  // По умолчанию опора — нижний центр alpha bbox; переменная задаёт доли всего source canvas.
  const anchorEnv = process.env.ARCHER_SOURCE_ANCHOR;
  const anchorPercent = anchorEnv ? anchorEnv.split(',').map(Number) : [
    ((correctedBox[0] + correctedBox[2]) / 2) / records.corrected.size[0] * 100,
    correctedBox[3] / records.corrected.size[1] * 100,
  ];
  if (anchorPercent.length !== 2 || anchorPercent.some(v => !Number.isFinite(v) || v < 0 || v > 100))
    throw new Error('ARCHER_SOURCE_ANCHOR must be two canvas percentages, x,y');
  const correctedScale = targetHeight / (correctedBox[3] - correctedBox[1]);
  const groundAnchor = [-5, (-65.14 + 966 * 0.0745342) * 0.8];
  const geometry = {
    tile: {vertices: [[0,-48],[64,0],[0,48],[-64,0]], uv: [[724,110],[1350,543],[724,975],[96,543]], tint: [0.79,0.8,0.75]},
    defender: {crop: [89,206,1034,966], native: [77,72], position: [-44.42*0.8,-65.14*0.8], scale: defenderScale, height: defenderHeight},
    original: {position: [-38.17761714176,-55.16480157728001], scale: 0.51840026784, height: 51.840026784},
    corrected: {position: [groundAnchor[0] - records.corrected.size[0] * correctedScale * anchorPercent[0] / 100,
      groundAnchor[1] - records.corrected.size[1] * correctedScale * anchorPercent[1] / 100],
      scale: correctedScale, height: targetHeight, source_anchor_percent: anchorPercent, destination_anchor: groundAnchor,
      anchor_method: anchorEnv ? 'configured source canvas percentages' : 'provisional alpha>=128 bbox lower center'},
  };
  const manifest = {base: '15b0ece63f7679a450f79aad27896d1aab3516d3', sources: records, geometry,
    scope: 'Three-column offline Canvas comparison at x4 and x1. Full RGBA source PNGs shown without alpha cutoff; alpha>=128 is measurement only. No source edits, warp, stabilization, animation or game acceptance.'};
  fs.writeFileSync(path.join(__dirname, 'manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
  const html = `<!doctype html><html lang="ru"><meta charset="utf-8"><title>Сравнение ракурса лучницы</title>
<style>*{box-sizing:border-box}body{margin:0;padding:24px;background:#25292a;color:#eee9dc;font:16px Arial,sans-serif;width:1728px}h1{font-size:25px;margin:0 0 8px}p{color:#c4c6b9;line-height:1.5;margin:8px 0 16px}.row{display:flex;gap:12px}.panel{width:544px;text-align:center;background:#303633;border:1px solid #444d43;border-radius:8px;overflow:hidden}h2{font-size:18px;margin:16px 0 0}canvas{display:block;image-rendering:pixelated;margin:auto}.controls{display:flex;align-items:center;gap:18px;margin:18px 0}label{cursor:pointer}.small{font-size:13px;color:#b9beaf}.native{margin-top:16px}.native .panel{background:none;border:none}</style>
<h1>Лучница — проба более высокого ракурса</h1><p>До и после на одинаковых тайлах 4:3. Обе лучницы — 90% высоты Защитника; пропорции каждого рисунка сохранены.</p>
<div class="row"><section class="panel"><h2>Защитник · текущий статичный образ</h2><canvas id="defender" width="544" height="448"></canvas></section><section class="panel"><h2>Лучница · исходная B1</h2><canvas id="original" width="544" height="448"></canvas></section><section class="panel"><h2>Лучница · исправленная</h2><canvas id="corrected" width="544" height="448"></canvas></section></div>
<div class="controls"><label><input type="checkbox" id="axes"> Оси поверхности</label><span class="small">Верхний ряд ×4 · нижний ряд ×1 · посадка предварительная · отдельная проба, в игру не подключена</span></div>
<div class="row native"><section class="panel"><canvas id="defender-native" width="160" height="118"></canvas></section><section class="panel"><canvas id="original-native" width="160" height="118"></canvas></section><section class="panel"><canvas id="corrected-native" width="160" height="118"></canvas></section></div>
<script>
const sourceData=${JSON.stringify(images)}, geometry=${JSON.stringify(geometry)}; const loaded={};
function canvas(w,h){const c=document.createElement('canvas');c.width=w;c.height=h;return c;}
function polygon(ctx,points){ctx.beginPath();points.forEach((p,i)=>i?ctx.lineTo(...p):ctx.moveTo(...p));ctx.closePath();}
function triangle(ctx,img,src,dst){const [s0,s1,s2]=src,[d0,d1,d2]=dst;const sx1=s1[0]-s0[0],sy1=s1[1]-s0[1],sx2=s2[0]-s0[0],sy2=s2[1]-s0[1],dx1=d1[0]-d0[0],dy1=d1[1]-d0[1],dx2=d2[0]-d0[0],dy2=d2[1]-d0[1],det=sx1*sy2-sx2*sy1;const a=(dx1*sy2-dx2*sy1)/det,c=(dx2*sx1-dx1*sx2)/det,b=(dy1*sy2-dy2*sy1)/det,d=(dy2*sx1-dy1*sx2)/det;ctx.save();polygon(ctx,dst);ctx.clip();ctx.transform(a,b,c,d,d0[0]-a*s0[0]-c*s0[1],d0[1]-b*s0[0]-d*s0[1]);ctx.drawImage(img,0,0);ctx.restore();}
let ground,defenderNative;
function draw(id,key,zoom){const c=document.getElementById(id),ctx=c.getContext('2d');ctx.setTransform(1,0,0,1,0,0);ctx.clearRect(0,0,c.width,c.height);ctx.imageSmoothingEnabled=false;ctx.translate(c.width/2,zoom===4?242:64);ctx.scale(zoom,zoom);const tile=geometry.tile;polygon(ctx,tile.vertices);ctx.fillStyle='#535e3e';ctx.fill();for(const ix of [[0,1,2],[0,2,3]])triangle(ctx,ground,ix.map(i=>tile.uv[i]),ix.map(i=>tile.vertices[i]));polygon(ctx,tile.vertices);ctx.strokeStyle='rgba(64,74,43,.6)';ctx.lineWidth=.7;ctx.stroke();if(document.getElementById('axes').checked){ctx.beginPath();ctx.moveTo(-64,0);ctx.lineTo(64,0);ctx.moveTo(0,-48);ctx.lineTo(0,48);ctx.strokeStyle='#a4c9c1';ctx.lineWidth=.35;ctx.stroke();}if(key==='defender'){const g=geometry.defender;ctx.drawImage(defenderNative,...g.position,g.crop[2]*g.scale,g.crop[3]*g.scale);}else{const g=geometry[key];const size=key==='original'?records.original.size:records.corrected.size;ctx.drawImage(loaded[key],...g.position,size[0]*g.scale,size[1]*g.scale);}}
const records=${JSON.stringify(Object.fromEntries(Object.entries(records).map(([k,v])=>[k,{size:v.size}]))) };
function render(){for(const [id,key,z] of [['defender','defender',4],['original','original',4],['corrected','corrected',4],['defender-native','defender',1],['original-native','original',1],['corrected-native','corrected',1]])draw(id,key,z);}
window.ready=(async()=>{for(const [key,url]of Object.entries(sourceData)){const im=new Image();im.src=url;await im.decode();loaded[key]=im;}ground=canvas(loaded.tile.width,loaded.tile.height);const gc=ground.getContext('2d');gc.drawImage(loaded.tile,0,0);const pix=gc.getImageData(0,0,ground.width,ground.height);for(let i=0;i<pix.data.length;i+=4)for(let j=0;j<3;j++)pix.data[i+j]*=geometry.tile.tint[j];gc.putImageData(pix,0,0);defenderNative=canvas(...geometry.defender.native);const dc=defenderNative.getContext('2d');dc.imageSmoothingEnabled=false;dc.drawImage(loaded.defender,...geometry.defender.crop,0,0,...geometry.defender.native);render();document.getElementById('axes').addEventListener('change',render);return true;})();
</script></html>`;
  fs.writeFileSync(path.join(__dirname, 'comparison.html'), html);
  console.log(JSON.stringify({sources: Object.keys(records).length, correctedScale, correctedHeight: targetHeight, sourceAnchorPercent: anchorPercent}));
})().catch(error => { console.error(error); process.exitCode = 1; });
