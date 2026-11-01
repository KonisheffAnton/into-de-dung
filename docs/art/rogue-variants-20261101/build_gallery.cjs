// Показываем исходники целиком: размер персонажа относительно тайла остаётся видимым.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'prompts.json'), 'utf8'));
const esc = value => value.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;');
function card(file, title) {
  return `<a class="card" href="${esc(file)}"><img src="${esc(file)}" alt="${esc(title)}"><span>${esc(title)}</span></a>`;
}
const cards = manifest.variants.map(v => card(v.file, `${v.id} · ${v.name}`)).join('\n');
const references = [
  ['../warrior-variants-20261029/warrior-11.png', 'Воин №11 · эталон масштаба'],
  ['../warrior-variants-20261029/warrior-02.png', 'Защитник №02 · эталон семейства'],
  ['initial-trial.png', 'Первая проба · слишком крупная фигура'],
].map(([file, label]) => card(file, label)).join('\n');
const html = `<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Разбойник · 10 вариантов</title>
<style>*{box-sizing:border-box}body{margin:0;background:#0b1424;color:#f0e7db;font:16px/1.45 system-ui,sans-serif}main{max-width:1800px;margin:auto;padding:24px}h1{margin:0 0 8px;font-size:30px}h2{font-size:20px;margin:24px 0 12px}p{color:#afbacb;margin:0 0 18px}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px;padding:12px;background:#0b1424}.references{max-width:1000px;grid-template-columns:repeat(3,minmax(0,1fr))}.card{display:block;min-width:0;text-decoration:none;color:inherit;background:#111d31;border:1px solid #2a3850;border-radius:6px;overflow:hidden}.card img{display:block;width:100%;aspect-ratio:1;object-fit:contain;image-rendering:pixelated}.card span{display:block;padding:10px 12px;font-weight:600}.card:hover{border-color:#cf9770}@media(max-width:1000px){.grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:600px){main{padding:12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;padding:0}.references{grid-template-columns:1fr}.card span{font-size:13px;padding:8px}}</style>
<main><h1>Разбойник · 10 вариантов</h1><p>Компактные пропорции, общий масштаб тайла и два кинжала. Нажмите на изображение, чтобы открыть исходник. Концепты для выбора; в игру не добавлены.</p><h2>Ориентиры и первая проба</h2><section class="grid references">${references}</section><h2>Новая подборка · 01–10</h2><section class="grid" id="variants">${cards}</section></main></html>`;
fs.writeFileSync(path.join(root, 'gallery.html'), html);
const sources = manifest.variants.map(v => {
  const bytes = fs.readFileSync(path.join(root, v.file));
  const source = fs.readFileSync(v.source);
  if (!bytes.equals(source)) throw new Error(`Исходник изменён: ${v.id}`);
  if (bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Не PNG: ${v.id}`);
  return {id:v.id, file:v.file, source:v.source, sha256:crypto.createHash('sha256').update(bytes).digest('hex'), width:bytes.readUInt32BE(16), height:bytes.readUInt32BE(20), source_equal:true};
});
if (sources.length !== 10 || new Set(sources.map(s => s.sha256)).size !== 10) throw new Error('Нужны 10 разных исходников.');
fs.writeFileSync(path.join(root, 'sources.json'), JSON.stringify(sources,null,2)+'\n');
console.log('10 unique PNGs copied byte-for-byte; gallery created.');
