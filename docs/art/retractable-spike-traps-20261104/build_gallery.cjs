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
const EXPECTED_COUNT = 10;
const FIRST_NUMBER = 1;
const CRC_TABLE = Uint32Array.from({ length: 256 }, (_, value) => {
  let crc = value;
  for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  return crc >>> 0;
});

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) crc = CRC_TABLE[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function inspectPng(filePath, label) {
  const bytes = fs.readFileSync(filePath);
  if (bytes.length < 45 || !bytes.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error(`${label}: файл не имеет структуры PNG`);
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
    if (!/^[A-Za-z]{4}$/.test(type)) throw new Error(`${label}: неверный тип PNG-блока`);
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (crc32(bytes.subarray(offset + 4, offset + 8 + length)) !== bytes.readUInt32BE(offset + 8 + length)) {
      throw new Error(`${label}: неверная CRC блока ${type}`);
    }
    if (!sawHeader && type !== 'IHDR') throw new Error(`${label}: IHDR не первый PNG-блок`);
    if (type === 'IHDR') {
      if (sawHeader || length !== 13) throw new Error(`${label}: повторный или неверный IHDR`);
      width = data.readUInt32BE(0);
      height = data.readUInt32BE(4);
      const depths = { 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8], 4: [8, 16], 6: [8, 16] };
      if (width < 1 || height < 1 || !depths[data[9]]?.includes(data[8])
        || data[10] !== 0 || data[11] !== 0 || data[12] > 1) {
        throw new Error(`${label}: недопустимый размер или параметры изображения`);
      }
      sawHeader = true;
    } else if (type === 'IDAT') {
      if (dataClosed) throw new Error(`${label}: блоки IDAT не следуют подряд`);
      sawData = true;
      dataChunks.push(data);
    } else if (type === 'IEND') {
      if (length !== 0 || !sawData || chunkEnd !== bytes.length) throw new Error(`${label}: некорректный IEND`);
      sawEnd = true;
      offset = chunkEnd;
      break;
    } else {
      if (sawData) dataClosed = true;
      if (type[0] === type[0].toUpperCase() && type !== 'PLTE') {
        throw new Error(`${label}: неизвестный критический блок ${type}`);
      }
    }
    offset = chunkEnd;
  }
  if (!sawHeader || !sawData || !sawEnd || offset !== bytes.length) throw new Error(`${label}: неполная PNG`);
  try {
    if (zlib.inflateSync(Buffer.concat(dataChunks)).length === 0) throw new Error('пустой поток изображения');
  } catch (error) {
    throw new Error(`${label}: повреждённый сжатый поток PNG (${error.message})`);
  }
  return {
    bytes,
    width,
    height,
    sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
  };
}

function safeScriptJson(value) {
  return JSON.stringify(value).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

function loadPayload() {
  const prompts = JSON.parse(fs.readFileSync(PROMPTS_PATH, 'utf8'));
  if (!Array.isArray(prompts.variants) || prompts.variants.length !== EXPECTED_COUNT) {
    throw new Error(`prompts.json должен содержать ${EXPECTED_COUNT} вариантов`);
  }
  const ids = new Set();
  const files = new Set();
  const validation = [];
  const variants = prompts.variants.map((variant, index) => {
    const number = FIRST_NUMBER + index;
    const id = `spike-trap-${String(number).padStart(2, '0')}`;
    const file = `${id}-pair.png`;
    if (!variant || variant.id !== id || variant.number !== number || variant.file !== file || ids.has(id)) {
      throw new Error(`ожидается уникальный id ${id}, номер ${number} и файл ${file}`);
    }
    if (typeof variant.name !== 'string' || variant.name.trim() === '') {
      throw new Error(`${id}: отсутствует русское имя`);
    }
    if (path.basename(variant.file) !== variant.file || files.has(file)) throw new Error(`${id}: неверный или повторный PNG filename`);
    ids.add(id);
    files.add(file);
    const image = inspectPng(path.join(PACKAGE_DIR, file), id);
    validation.push({ id, number, file, width: image.width, height: image.height, sha256: image.sha256 });
    return {
      id,
      number,
      file,
      name: variant.name,
      width: image.width,
      height: image.height,
      data: `data:image/png;base64,${image.bytes.toString('base64')}`,
    };
  });
  return {
    variants,
    validation: { source: 'prompts.json', count: variants.length, variants: validation },
  };
}

function makeHtml(variants) {
  return `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="dark">
<title>Выдвижные шипы · 10 пар</title>
<style>
:root{--card-min:500px;color-scheme:dark;background:#11171d;color:#e7edf1;font:16px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif}
*{box-sizing:border-box}body{margin:0;background:#11171d}button,input{font:inherit}button{color:inherit}
main{width:min(1500px,100%);margin:auto;padding:24px clamp(14px,2.5vw,36px) 48px}
h1{font-size:clamp(1.55rem,3vw,2.2rem);line-height:1.15;margin:0 0 7px}.note{color:#aebbc5;margin:0 0 20px}
.toolbar{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:18px;flex-wrap:wrap;padding:12px 0 14px;background:#11171df2;backdrop-filter:blur(8px);border-bottom:1px solid #303b44}
.zoom-control{display:flex;align-items:center;gap:9px}.zoom-control input{width:150px;accent-color:#df8243}.zoom-control output{min-width:45px;color:#d7e0e6}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,var(--card-min)),1fr));gap:14px;padding-top:18px}
.card{min-width:0;padding:10px;background:#1b242b;border:1px solid #303e48;border-radius:10px}.open-card{display:block;width:100%;padding:0;border:0;background:transparent;text-align:left;cursor:zoom-in}
.number{display:inline-block;color:#ffbd83;font:700 .86rem/1.2 ui-monospace,SFMono-Regular,Consolas,monospace;letter-spacing:.05em;margin-bottom:5px}.name{display:block;font-weight:650;margin-bottom:9px}
.stage{position:relative;display:grid;place-items:center;width:100%;aspect-ratio:3/2;overflow:hidden;background-color:#151a1f;background-image:linear-gradient(45deg,#242d34 25%,transparent 25%),linear-gradient(-45deg,#242d34 25%,transparent 25%),linear-gradient(45deg,transparent 75%,#242d34 75%),linear-gradient(-45deg,transparent 75%,#242d34 75%);background-size:24px 24px;background-position:0 0,0 12px,12px -12px,-12px 0;border-radius:6px;isolation:isolate}
.stage img{position:absolute;inset:0;display:block;width:100%;height:100%;object-fit:contain;image-rendering:auto;user-select:none;-webkit-user-drag:none}
dialog{width:min(94vw,980px);max-width:980px;max-height:94vh;padding:14px;background:#172027;color:#e7edf1;border:1px solid #4a5964;border-radius:12px;box-shadow:0 20px 80px #000a}
dialog::backdrop{background:#080c10d9;backdrop-filter:blur(3px)}.dialog-header{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:10px}.dialog-title{margin:0;font-size:1.15rem}.dialog-stage{width:min(72vh,100%);max-width:780px;margin:auto}.dialog-stage img{object-fit:contain}.dialog-footer{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-top:12px}.dialog-footer button,.close-button{border:1px solid #45535e;border-radius:6px;background:#202a32;padding:8px 12px;cursor:pointer}.dialog-footer button:focus-visible,.close-button:focus-visible,.open-card:focus-visible{outline:3px solid #f6b171;outline-offset:3px}
@media(max-width:520px){.toolbar{gap:10px}.dialog-stage{width:100%}.dialog-footer{flex-wrap:wrap}}
</style>
</head>
<body>
<main>
<h1>Выдвижные шипы · 10 пар</h1>
<p class="note">Слева — спрятаны · справа — выдвинуты · 10 вариантов</p>
<div class="toolbar"><label class="zoom-control" for="zoom-range"><span>Масштаб карточек</span><input id="zoom-range" type="range" min="0.7" max="1.6" step="0.1" value="1"><output id="zoom-value" for="zoom-range">100%</output></label></div>
<section id="gallery" class="grid" aria-label="Десять ловушек: спрятанные и выдвинутые шипы"></section>
</main>
<dialog id="viewer" aria-labelledby="viewer-title">
  <div class="dialog-header"><h2 id="viewer-title" class="dialog-title"></h2><button id="close-viewer" class="close-button" type="button" aria-label="Закрыть просмотр">Закрыть</button></div>
  <div id="viewer-stage" class="stage dialog-stage"></div>
  <div class="dialog-footer"><button id="previous" type="button" aria-label="Предыдущий вариант">← Предыдущий</button><span id="viewer-position" aria-live="polite"></span><button id="next" type="button" aria-label="Следующий вариант">Следующий →</button></div>
</dialog>
<script>
const ASSETS = ${safeScriptJson(variants)};
const gallery = document.getElementById('gallery');
const viewer = document.getElementById('viewer');
const viewerTitle = document.getElementById('viewer-title');
const viewerStage = document.getElementById('viewer-stage');
const viewerPosition = document.getElementById('viewer-position');
const zoomRange = document.getElementById('zoom-range');
const zoomValue = document.getElementById('zoom-value');
let currentIndex = 0;

function imageFor(variant) {
  const image = document.createElement('img');
  image.src = variant.data;
  image.alt = variant.id + ' · ' + variant.name;
  return image;
}

function setScale(value) {
  const scale = Number(value);
  document.documentElement.style.setProperty('--card-min', (500 * scale) + 'px');
  zoomValue.value = Math.round(scale * 100) + '%';
}

function openVariant(index) {
  currentIndex = (index + ASSETS.length) % ASSETS.length;
  const variant = ASSETS[currentIndex];
  viewerTitle.textContent = variant.id + ' · ' + variant.name;
  viewerPosition.textContent = (currentIndex + 1) + ' / ' + ASSETS.length;
  viewerStage.replaceChildren(imageFor(variant));
  if (!viewer.open) viewer.showModal();
}

ASSETS.forEach((variant, index) => {
  const card = document.createElement('article');
  card.className = 'card';
  const button = document.createElement('button');
  button.className = 'open-card';
  button.type = 'button';
  button.setAttribute('aria-label', 'Открыть ' + variant.number + ', ' + variant.name);
  const number = document.createElement('span');
  number.className = 'number';
  number.textContent = String(variant.number);
  const name = document.createElement('span');
  name.className = 'name';
  name.textContent = variant.name;
  const stage = document.createElement('div');
  stage.className = 'stage';
  stage.append(imageFor(variant));
  button.append(number, name, stage);
  button.addEventListener('click', () => openVariant(index));
  card.append(button);
  gallery.append(card);
});

zoomRange.addEventListener('input', () => setScale(zoomRange.value));
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
    fs.writeFileSync(OUTPUT_PATH, makeHtml(payload.variants), 'utf8');
    fs.writeFileSync(VALIDATION_PATH, `${JSON.stringify(payload.validation, null, 2)}\n`, 'utf8');
    console.log(`Галерея собрана: ${EXPECTED_COUNT} вариантов (01–10)`);
  } catch (error) {
    console.error(`Ошибка сборки SPIKE-PAIRS10: ${error.message}`);
    process.exitCode = 1;
  }
}

main();
