#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const PACKAGE_DIR = __dirname;
const PROMPTS_PATH = path.join(PACKAGE_DIR, 'prompts.json');
const SOURCES_PATH = path.join(PACKAGE_DIR, 'sources.json');
const OUTPUT_PATH = path.join(PACKAGE_DIR, 'gallery.html');
const REFERENCE_RELATIVE_PATH = '../current-tile-reference-20261103/tile.png';
const REFERENCE_PATH = path.resolve(PACKAGE_DIR, REFERENCE_RELATIVE_PATH);
const GROUPS = ['caltrops', 'fire', 'acid'];
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function fail(message) {
  console.error(`Ошибка галереи: ${message}`);
  process.exitCode = 1;
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (error) {
    throw new Error(`не удалось прочитать ${path.basename(filePath)}: ${error.message}`);
  }
}

function packageFile(relativePath, label) {
  if (typeof relativePath !== 'string' || relativePath.length === 0 || path.isAbsolute(relativePath)) {
    throw new Error(`${label}: ожидался относительный путь к файлу`);
  }
  const resolved = path.resolve(PACKAGE_DIR, relativePath);
  if (resolved !== PACKAGE_DIR && !resolved.startsWith(`${PACKAGE_DIR}${path.sep}`)) {
    throw new Error(`${label}: путь выходит за пределы пакета`);
  }
  return resolved;
}

function inspectPng(filePath, expected, label) {
  const bytes = fs.readFileSync(filePath);
  if (bytes.length < 24 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error(`${label}: файл не имеет корректной сигнатуры PNG`);
  }
  if (bytes.toString('ascii', 12, 16) !== 'IHDR') {
    throw new Error(`${label}: отсутствует PNG IHDR`);
  }
  const width = bytes.readUInt32BE(16);
  const height = bytes.readUInt32BE(20);
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  if (width === 0 || height === 0) throw new Error(`${label}: нулевой размер PNG`);
  if (expected.width !== width || expected.height !== height) {
    throw new Error(`${label}: размер ${width}x${height}, в sources.json указан ${expected.width}x${expected.height}`);
  }
  if (typeof expected.sha256 !== 'string' || expected.sha256.toLowerCase() !== sha256) {
    throw new Error(`${label}: SHA-256 не совпадает с sources.json`);
  }
  return { bytes, width, height, sha256 };
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

function validateAndBuild(verifyOriginals) {
  const prompts = readJson(PROMPTS_PATH);
  const sources = readJson(SOURCES_PATH);
  if (!Array.isArray(prompts.variants) || prompts.variants.length !== 15) {
    throw new Error('prompts.json должен содержать ровно 15 вариантов');
  }
  if (!Array.isArray(sources.images) || sources.images.length !== 15) {
    throw new Error('sources.json должен содержать ровно 15 записей images');
  }
  if (!sources.reference || typeof sources.reference !== 'object') {
    throw new Error('в sources.json отсутствует reference');
  }

  const promptIds = new Set();
  const variantFiles = new Set();
  const variantHashes = new Set();
  const sourceById = new Map();
  for (const image of sources.images) {
    if (!image || typeof image.id !== 'string' || sourceById.has(image.id)) {
      throw new Error('sources.json содержит отсутствующий или повторный id');
    }
    sourceById.set(image.id, image);
  }

  const groupCounts = new Map(GROUPS.map((group) => [group, 0]));
  const variants = prompts.variants.map((variant) => {
    if (!variant || typeof variant.id !== 'string' || promptIds.has(variant.id)) {
      throw new Error('prompts.json содержит отсутствующий или повторный id');
    }
    if (typeof variant.name !== 'string' || variant.name.trim().length === 0
      || typeof variant.prompt !== 'string' || variant.prompt.trim().length === 0) {
      throw new Error(`${variant.id}: name и prompt должны быть непустыми строками`);
    }
    promptIds.add(variant.id);
    if (!GROUPS.includes(variant.group) || variant.id !== `${variant.group}-${String(groupCounts.get(variant.group) + 1).padStart(2, '0')}`) {
      throw new Error(`неожиданный id или группа варианта ${variant.id}`);
    }
    groupCounts.set(variant.group, groupCounts.get(variant.group) + 1);
    const manifest = sourceById.get(variant.id);
    if (!manifest || manifest.file !== variant.file) {
      throw new Error(`${variant.id}: нет соответствующей записи или filename в sources.json`);
    }
    if (typeof manifest.sha256 !== 'string' || variantFiles.has(manifest.file) || variantHashes.has(manifest.sha256.toLowerCase())) {
      throw new Error(`${variant.id}: filename и SHA-256 вариантов должны быть уникальными`);
    }
    variantFiles.add(manifest.file);
    variantHashes.add(manifest.sha256.toLowerCase());
    const filePath = packageFile(manifest.file, variant.id);
    const png = inspectPng(filePath, manifest, variant.id);
    if (verifyOriginals) {
      if (typeof manifest.source_path !== 'string' || manifest.source_path.length === 0) {
        throw new Error(`${variant.id}: source_path не задан для --verify-originals`);
      }
      const originalPath = path.resolve(manifest.source_path);
      const original = fs.readFileSync(originalPath);
      if (!original.equals(png.bytes)) throw new Error(`${variant.id}: PNG отличается от ${manifest.source_path}`);
    }
    return {
      id: variant.id,
      group: variant.group,
      name: variant.name,
      width: png.width,
      height: png.height,
      data: `data:image/png;base64,${png.bytes.toString('base64')}`,
    };
  });
  if ([...groupCounts.values()].some((count) => count !== 5)) {
    throw new Error('требуются ровно пять вариантов в каждой группе');
  }
  if (sourceById.size !== promptIds.size || [...sourceById.keys()].some((id) => !promptIds.has(id))) {
    throw new Error('набор id в prompts.json и sources.json отличается');
  }

  if (prompts.reference !== REFERENCE_RELATIVE_PATH || path.resolve(PACKAGE_DIR, sources.reference.file) !== REFERENCE_PATH) {
    throw new Error(`reference должен указывать на ${REFERENCE_RELATIVE_PATH}`);
  }
  const referencePath = REFERENCE_PATH;
  const referencePng = inspectPng(referencePath, sources.reference, 'reference');
  return {
    variants,
    reference: {
      width: referencePng.width,
      height: referencePng.height,
      data: `data:image/png;base64,${referencePng.bytes.toString('base64')}`,
    },
  };
}

function card(image, reference = false) {
  const label = reference ? 'Текущий тайл · эталон' : image.name;
  const id = reference ? 'reference-image' : image.id;
  return `<figure class="card"><button class="image-button" type="button" data-image="${escapeHtml(image.data)}" data-label="${escapeHtml(label)}" aria-label="Открыть: ${escapeHtml(label)}"><span class="frame"><img id="${id}" src="${escapeHtml(image.data)}" alt="${escapeHtml(label)}"></span></button><figcaption>${escapeHtml(label)}</figcaption></figure>`;
}

function makeHtml(payload) {
  const sections = GROUPS.map((group) => {
    const images = payload.variants.filter((variant) => variant.group === group);
    const heading = { caltrops: 'Кальтропы', fire: 'Огонь', acid: 'Кислота' }[group];
    return `<section id="${group}" aria-labelledby="${group}-title"><h2 id="${group}-title">${heading}</h2><div class="grid">${images.map((image) => card(image)).join('\n')}</div></section>`;
  }).join('\n');
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Статичные пробы эффектов опасностей</title>
<style>
:root{color-scheme:dark;background:#171b20;color:#e5e8eb;font:16px/1.45 system-ui,sans-serif}
*{box-sizing:border-box}body{margin:0;background:#171b20}main{width:min(1500px,100%);margin:auto;padding:24px clamp(12px,2vw,28px) 48px}
h1{font-size:clamp(1.45rem,3vw,2.2rem);margin:0 0 8px}h2{font-size:1.35rem;margin:30px 0 12px}.note{color:#b7c0c8;margin:0 0 20px}
section{scroll-margin-top:12px}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:14px}.card{min-width:0;margin:0;padding:10px;background:#22282e;border:1px solid #343d45;border-radius:8px}
.image-button{display:block;width:100%;padding:0;border:0;background:transparent;color:inherit;cursor:zoom-in}.frame{display:grid;place-items:center;width:100%;aspect-ratio:1/1;overflow:hidden;background:#11161a;border-radius:4px}.frame img{display:block;width:100%;height:100%;object-fit:contain;transform:scale(1.4)}
figcaption{padding-top:9px;text-align:center;font-size:.92rem}.reference{max-width:320px}.reference .frame{aspect-ratio:1/1}
dialog{width:min(94vw,1100px);max-width:none;max-height:94vh;padding:12px;background:#20262c;color:#e5e8eb;border:1px solid #52606c;border-radius:8px}dialog::backdrop{background:#05080bcc}.dialog-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:10px}.dialog-head strong{font-weight:600}dialog img{display:block;max-width:100%;max-height:calc(94vh - 76px);width:auto;height:auto;margin:auto;object-fit:contain}dialog button{padding:7px 12px;border:1px solid #64717c;border-radius:5px;background:#303941;color:#fff;cursor:pointer}
@media(max-width:1050px){.grid{grid-template-columns:repeat(3,minmax(0,1fr))}}@media(max-width:620px){.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:9px}.card{padding:7px}}@media(max-width:390px){.grid{grid-template-columns:1fr}}
</style>
</head>
<body><main><h1>Статичные пробы эффектов опасностей</h1><p class="note">15 статичных проб; текущий тайл — эталон. Эффекты не внедрены.</p>
<section id="reference" aria-labelledby="reference-title"><h2 id="reference-title">Текущий тайл · эталон</h2><div class="reference">${card(payload.reference, true)}</div></section>
${sections}
</main>
<dialog id="viewer" aria-label="Просмотр изображения"><div class="dialog-head"><strong id="viewer-label"></strong><button id="close-viewer" type="button">Закрыть</button></div><img id="viewer-image" alt=""></dialog>
<script>
const viewer=document.getElementById('viewer'),viewerImage=document.getElementById('viewer-image'),viewerLabel=document.getElementById('viewer-label');
document.querySelectorAll('.image-button').forEach((button)=>button.addEventListener('click',()=>{viewerImage.src=button.dataset.image;viewerImage.alt=button.dataset.label;viewerLabel.textContent=button.dataset.label;viewer.showModal()}));
document.getElementById('close-viewer').addEventListener('click',()=>viewer.close());
viewer.addEventListener('click',(event)=>{if(event.target===viewer)viewer.close()});
</script></body></html>
`;
}

try {
  const verifyOriginals = process.argv.includes('--verify-originals');
  const payload = validateAndBuild(verifyOriginals);
  fs.writeFileSync(OUTPUT_PATH, makeHtml(payload), 'utf8');
  console.log(`Галерея создана: ${OUTPUT_PATH}`);
} catch (error) {
  fail(error.message);
}
