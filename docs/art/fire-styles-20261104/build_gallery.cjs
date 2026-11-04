'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const zlib = require('node:zlib');

const PACKAGE_DIR = __dirname;
const PROMPTS_PATH = path.join(PACKAGE_DIR, 'prompts.json');
const OUTPUT_PATH = path.join(PACKAGE_DIR, 'gallery.html');
const VALIDATION_PATH = path.join(PACKAGE_DIR, 'gallery-validation.json');
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const EXPECTED_COUNT = 20;
const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  return crc >>> 0;
});

function fail(message) {
  console.error(`Ошибка сборки галереи: ${message}`);
  process.exitCode = 1;
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function inspectPng(filePath, label) {
  const bytes = fs.readFileSync(filePath);
  if (bytes.length < 45 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error(`${label}: файл не является PNG с корректной сигнатурой`);
  }

  let offset = 8;
  let width = 0;
  let height = 0;
  let sawHeader = false;
  let sawData = false;
  let dataClosed = false;
  let sawEnd = false;
  const dataChunks = [];
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) throw new Error(`${label}: обрезан заголовок PNG-блока`);
    const length = bytes.readUInt32BE(offset);
    const chunkEnd = offset + length + 12;
    if (chunkEnd > bytes.length) throw new Error(`${label}: блок PNG выходит за конец файла`);
    const type = bytes.toString('ascii', offset + 4, offset + 8);
    if (!/^[A-Za-z]{4}$/.test(type)) throw new Error(`${label}: некорректный тип PNG-блока`);
    const chunkData = bytes.subarray(offset + 8, offset + 8 + length);
    const expectedCrc = bytes.readUInt32BE(offset + 8 + length);
    if (crc32(bytes.subarray(offset + 4, offset + 8 + length)) !== expectedCrc) {
      throw new Error(`${label}: неверная CRC PNG-блока ${type}`);
    }
    if (!sawHeader && type !== 'IHDR') throw new Error(`${label}: IHDR не является первым блоком`);
    if (type === 'IHDR') {
      if (sawHeader || length !== 13) throw new Error(`${label}: некорректный или повторный IHDR`);
      width = chunkData.readUInt32BE(0);
      height = chunkData.readUInt32BE(4);
      const bitDepth = chunkData[8];
      const colorType = chunkData[9];
      const validDepths = {
        0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16],
      };
      if (width === 0 || height === 0 || !validDepths[colorType]?.includes(bitDepth)
        || chunkData[10] !== 0 || chunkData[11] !== 0 || chunkData[12] > 1) {
        throw new Error(`${label}: недопустимые размеры или параметры IHDR`);
      }
      sawHeader = true;
    } else if (type === 'IDAT') {
      if (dataClosed) throw new Error(`${label}: блоки IDAT должны идти подряд`);
      sawData = true;
      dataChunks.push(chunkData);
    } else if (type === 'IEND') {
      if (length !== 0 || !sawData || chunkEnd !== bytes.length) throw new Error(`${label}: некорректный IEND`);
      sawEnd = true;
      offset = chunkEnd;
      break;
    } else {
      if (sawData) dataClosed = true;
      // Неизвестные критические блоки нельзя безопасно пропустить при проверке PNG.
      if (type[0] === type[0].toUpperCase() && !['PLTE'].includes(type)) {
        throw new Error(`${label}: неизвестный критический PNG-блок ${type}`);
      }
    }
    offset = chunkEnd;
  }
  if (!sawHeader || !sawData || !sawEnd || offset !== bytes.length) {
    throw new Error(`${label}: неполная структура PNG`);
  }
  try {
    if (zlib.inflateSync(Buffer.concat(dataChunks)).length === 0) throw new Error('пустое изображение');
  } catch (error) {
    throw new Error(`${label}: повреждённый поток пикселей PNG (${error.message})`);
  }
  return {
    bytes,
    width,
    height,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  };
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;',
  })[character]);
}

function safeScriptJson(value) {
  return JSON.stringify(value)
    .replace(/</g, '\\u003c')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

function loadPayload() {
  const prompts = JSON.parse(fs.readFileSync(PROMPTS_PATH, 'utf8'));
  if (!Array.isArray(prompts.variants) || prompts.variants.length !== EXPECTED_COUNT) {
    throw new Error(`prompts.json должен содержать ровно ${EXPECTED_COUNT} вариантов`);
  }
  if (typeof prompts.reference !== 'string' || prompts.reference.length === 0) {
    throw new Error('prompts.json не задаёт путь к tile reference');
  }
  const ids = new Set();
  const files = new Set();
  const validation = [];
  const variants = prompts.variants.map((variant, index) => {
    const sequence = String(index + 1).padStart(2, '0');
    const expectedId = `fire-${sequence}`;
    const expectedFile = `${expectedId}.png`;
    if (!variant || variant.id !== expectedId || variant.file !== expectedFile || ids.has(variant.id)) {
      throw new Error(`ожидается уникальный id ${expectedId} и файл ${expectedFile}`);
    }
    if (typeof variant.name !== 'string' || variant.name.trim() === ''
      || typeof variant.style !== 'string' || variant.style.trim() === '') {
      throw new Error(`${expectedId}: русское имя и стиль должны быть заданы`);
    }
    if (path.basename(variant.file) !== variant.file || files.has(variant.file)) {
      throw new Error(`${expectedId}: имя PNG должно быть уникальным и находиться в каталоге пакета`);
    }
    ids.add(variant.id);
    files.add(variant.file);
    const image = inspectPng(path.join(PACKAGE_DIR, variant.file), expectedId);
    validation.push({ id: expectedId, file: expectedFile, width: image.width, height: image.height, sha256: image.sha256 });
    return {
      id: expectedId,
      file: expectedFile,
      name: variant.name,
      width: image.width,
      height: image.height,
      data: `data:image/png;base64,${image.bytes.toString('base64')}`,
    };
  });

  const referencePath = path.resolve(PACKAGE_DIR, prompts.reference);
  const reference = inspectPng(referencePath, 'tile reference');
  const referenceAsset = {
    width: reference.width,
    height: reference.height,
    data: `data:image/png;base64,${reference.bytes.toString('base64')}`,
  };
  return {
    assets: { reference: referenceAsset, variants },
    validation: {
      source: 'prompts.json',
      reference: { path: prompts.reference, width: reference.width, height: reference.height, sha256: reference.sha256 },
      variants: validation,
    },
  };
}

function makeHtml(assets) {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>Визуальные пробы огня</title>
<style>
:root{--card-min:230px;color-scheme:dark;background:#11171d;color:#e7edf1;font:16px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
*{box-sizing:border-box}body{margin:0;background:#11171d}button,input{font:inherit}button{color:inherit}
main{width:min(1500px,100%);margin:auto;padding:24px clamp(14px,2.5vw,36px) 48px}
h1{font-size:clamp(1.55rem,3vw,2.2rem);line-height:1.15;margin:0 0 7px}.note{color:#aebbc5;margin:0 0 20px}
.toolbar{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:18px;flex-wrap:wrap;padding:12px 0 14px;background:#11171df2;backdrop-filter:blur(8px);border-bottom:1px solid #303b44}
.mode-control{display:inline-flex;padding:3px;background:#202a32;border:1px solid #3a4852;border-radius:8px;gap:3px}.mode-control button,.nav-button,.close-button{border:1px solid #45535e;border-radius:6px;background:#202a32;padding:8px 12px;cursor:pointer}
.mode-control button[aria-pressed="true"]{background:#b76a35;border-color:#e18a4b;color:#fff}.zoom-control{display:flex;align-items:center;gap:9px}.zoom-control input{width:150px;accent-color:#df8243}.zoom-control output{min-width:45px;color:#d7e0e6}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,var(--card-min)),1fr));gap:14px;padding-top:18px}
.card{min-width:0;padding:10px;background:#1b242b;border:1px solid #303e48;border-radius:10px}.open-card{display:block;width:100%;padding:0;border:0;background:transparent;text-align:left;cursor:zoom-in}
.number{display:inline-block;color:#ffbd83;font:700 .86rem/1.2 ui-monospace,SFMono-Regular,Consolas,monospace;letter-spacing:.05em;margin-bottom:5px}.name{display:block;font-weight:650;margin-bottom:9px}
.stage{position:relative;display:grid;place-items:center;width:100%;aspect-ratio:1;overflow:hidden;background:#12181d;border-radius:6px;isolation:isolate}
.stage[data-mode="fire"]{background-color:#151a1f;background-image:linear-gradient(45deg,#242d34 25%,transparent 25%),linear-gradient(-45deg,#242d34 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#242d34 75%),linear-gradient(-45deg,transparent 75%,#242d34 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0}
.layers{position:absolute;inset:0;display:grid;place-items:center}.layers img{position:absolute;display:block;width:100%;height:100%;object-fit:contain;image-rendering:auto;user-select:none;-webkit-user-drag:none}.layers .tile-layer{display:none}.stage[data-mode="tile"] .tile-layer{display:block}.fire-layer{z-index:1}
dialog{width:min(94vw,980px);max-width:980px;max-height:94vh;padding:14px;background:#172027;color:#e7edf1;border:1px solid #4a5964;border-radius:12px;box-shadow:0 20px 80px #000a}
dialog::backdrop{background:#080c10d9;backdrop-filter:blur(3px)}.dialog-header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:10px}.dialog-title{margin:0;font-size:1.15rem}.dialog-stage{width:min(72vh,100%);max-width:780px;margin:auto}.dialog-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:12px}.dialog-footer button:focus-visible,.mode-control button:focus-visible,.open-card:focus-visible{outline:3px solid #f6b171;outline-offset:3px}
@media(max-width:520px){.toolbar{gap:10px}.dialog-stage{width:100%}.dialog-footer{flex-wrap:wrap}}
</style>
</head>
<body>
<main>
<h1>Визуальные пробы огня</h1>
<p class="note">20 проб · выберите номер · статичные изображения</p>
<div class="toolbar" aria-label="Настройки просмотра">
  <div class="mode-control" role="group" aria-label="Режим изображения">
    <button id="mode-tile" type="button" aria-pressed="true">На тайле</button>
    <button id="mode-fire" type="button" aria-pressed="false">Только огонь</button>
  </div>
  <label class="zoom-control" for="zoom-range"><span>Масштаб</span><input id="zoom-range" type="range" min="0.7" max="1.6" step="0.1" value="1"><output id="zoom-value" for="zoom-range">100%</output></label>
</div>
<section id="gallery" class="grid" aria-label="Двадцать статичных вариантов огня"></section>
</main>
<dialog id="viewer" aria-labelledby="viewer-title">
  <div class="dialog-header"><h2 id="viewer-title" class="dialog-title"></h2><button id="close-viewer" class="close-button" type="button" aria-label="Закрыть просмотр">Закрыть</button></div>
  <div id="viewer-stage" class="stage dialog-stage" data-mode="tile"></div>
  <div class="dialog-footer"><button id="previous" class="nav-button" type="button" aria-label="Предыдущий стиль">← Предыдущий</button><span id="viewer-position" aria-live="polite"></span><button id="next" class="nav-button" type="button" aria-label="Следующий стиль">Следующий →</button></div>
</dialog>
<script>
const ASSETS = ${safeScriptJson(assets)};
const gallery = document.getElementById('gallery');
const viewer = document.getElementById('viewer');
const viewerTitle = document.getElementById('viewer-title');
const viewerStage = document.getElementById('viewer-stage');
const viewerPosition = document.getElementById('viewer-position');
const modeTile = document.getElementById('mode-tile');
const modeFire = document.getElementById('mode-fire');
const zoomRange = document.getElementById('zoom-range');
const zoomValue = document.getElementById('zoom-value');
let currentIndex = 0;
let mode = 'tile';

function makeStage(variant, extraClass = '') {
  const stage = document.createElement('div');
  stage.className = 'stage' + (extraClass ? ' ' + extraClass : '');
  stage.dataset.mode = mode;
  const layers = document.createElement('div');
  layers.className = 'layers';
  const tile = document.createElement('img');
  tile.className = 'tile-layer';
  tile.src = ASSETS.reference.data;
  tile.alt = '';
  const fire = document.createElement('img');
  fire.className = 'fire-layer';
  fire.src = variant.data;
  fire.alt = 'Огонь ' + variant.id;
  layers.append(tile, fire);
  stage.append(layers);
  return stage;
}

function setMode(nextMode) {
  mode = nextMode;
  modeTile.setAttribute('aria-pressed', String(mode === 'tile'));
  modeFire.setAttribute('aria-pressed', String(mode === 'fire'));
  document.querySelectorAll('.stage').forEach((stage) => { stage.dataset.mode = mode; });
}

function setZoom(value) {
  const scale = Number(value);
  document.documentElement.style.setProperty('--card-min', (230 * scale) + 'px');
  zoomValue.value = Math.round(scale * 100) + '%';
}

function openVariant(index) {
  currentIndex = (index + ASSETS.variants.length) % ASSETS.variants.length;
  const variant = ASSETS.variants[currentIndex];
  viewerTitle.textContent = variant.id + ' · ' + variant.name;
  viewerPosition.textContent = (currentIndex + 1) + ' / ' + ASSETS.variants.length;
  viewerStage.replaceChildren(makeStage(variant).firstElementChild);
  viewerStage.dataset.mode = mode;
  setZoom(zoomRange.value);
  if (!viewer.open) viewer.showModal();
}

ASSETS.variants.forEach((variant, index) => {
  const card = document.createElement('article');
  card.className = 'card';
  const button = document.createElement('button');
  button.className = 'open-card';
  button.type = 'button';
  button.setAttribute('aria-label', 'Открыть ' + variant.id + ', ' + variant.name);
  const number = document.createElement('span');
  number.className = 'number';
  number.textContent = variant.id;
  const name = document.createElement('span');
  name.className = 'name';
  name.textContent = variant.name;
  button.append(number, name, makeStage(variant));
  button.addEventListener('click', () => openVariant(index));
  card.append(button);
  gallery.append(card);
});

modeTile.addEventListener('click', () => setMode('tile'));
modeFire.addEventListener('click', () => setMode('fire'));
zoomRange.addEventListener('input', () => setZoom(zoomRange.value));
document.getElementById('close-viewer').addEventListener('click', () => viewer.close());
document.getElementById('previous').addEventListener('click', () => openVariant(currentIndex - 1));
document.getElementById('next').addEventListener('click', () => openVariant(currentIndex + 1));
viewer.addEventListener('click', (event) => { if (event.target === viewer) viewer.close(); });
</script>
</body>
</html>
`;
}

function main() {
  try {
    const payload = loadPayload();
    const html = makeHtml(payload.assets);
    const validation = `${JSON.stringify(payload.validation, null, 2)}\n`;
    fs.writeFileSync(OUTPUT_PATH, html, 'utf8');
    fs.writeFileSync(VALIDATION_PATH, validation, 'utf8');
    console.log(`Галерея собрана: ${EXPECTED_COUNT} вариантов, ${path.relative(process.cwd(), OUTPUT_PATH)}`);
  } catch (error) {
    fail(error.message);
  }
}

main();
