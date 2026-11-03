const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const root = __dirname;
const manifest = JSON.parse(fs.readFileSync(path.join(root, 'prompts.json'), 'utf8'));
const provenance = JSON.parse(fs.readFileSync(path.join(root, 'sources.json'), 'utf8'));
const verifyOriginals = process.argv.includes('--verify-originals');
const escapeHtml = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;')
	.replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
const variants = manifest.variants;
if (variants.length !== 10) throw new Error(`Expected 10 variants, found ${variants.length}`);
const ids = variants.map(variant => String(variant.id));
const files = variants.map(variant => variant.file);
if (new Set(ids).size !== 10 || new Set(files).size !== 10) throw new Error('Duplicate variant ID or PNG path');
if (ids.slice().sort().join(',') !== ['11','12','13','14','15','16','17','18','19','20'].join(',')) {
	throw new Error('Expected variant IDs 11 through 20');
}
const expectedFiles = ids.map(id => `archer-${id}.png`);
if (files.some(file => !expectedFiles.includes(file)) || expectedFiles.some(file => !files.includes(file))) {
	throw new Error('Expected archer-11.png through archer-20.png');
}
if (variants.some(variant => !variant.name || !variant.prompt)) throw new Error('Every variant needs a Russian name and prompt');
if (!Array.isArray(provenance.images) || provenance.images.length !== 10) throw new Error('sources.json must contain 10 image records');

const records = new Map();
for (const record of provenance.images) {
	if (records.has(record.file)) throw new Error(`Duplicate sources.json file: ${record.file}`);
	records.set(record.file, record);
}
const imageBytes = new Map();
const hashes = new Set();
for (const variant of variants) {
	const filePath = path.resolve(root, variant.file);
	if (!filePath.startsWith(root + path.sep)) throw new Error(`PNG path escapes package: ${variant.file}`);
	const bytes = fs.readFileSync(filePath);
	if (bytes.length < 24 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Not a PNG: ${variant.file}`);
	const actual = {
		file: variant.file,
		sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
		width: bytes.readUInt32BE(16),
		height: bytes.readUInt32BE(20),
	};
	const recorded = records.get(variant.file);
	if (!recorded || recorded.sha256 !== actual.sha256 || recorded.width !== actual.width || recorded.height !== actual.height) {
		throw new Error(`Packaged PNG differs from sources.json: ${variant.file}`);
	}
	if (hashes.has(actual.sha256)) throw new Error(`Duplicate PNG content: ${variant.file}`);
	hashes.add(actual.sha256);
	if (verifyOriginals) {
		if (typeof recorded.source_path !== 'string' || recorded.source_path.length === 0) {
			throw new Error(`No source_path to verify for ${variant.file}`);
		}
		const originalPath = path.resolve(root, recorded.source_path);
		const original = fs.readFileSync(originalPath);
		if (!original.equals(bytes)) throw new Error(`Original source differs from packaged PNG: ${variant.file}`);
	}
	imageBytes.set(variant.file, bytes.toString('base64'));
}
if (records.size !== 10 || [...records.keys()].some(file => !files.includes(file))) {
	throw new Error('sources.json files do not match prompts.json');
}

const cards = variants.map(variant => {
	const label = `${variant.id} · ${variant.name}`;
	return `<button class="card" type="button" data-id="${escapeHtml(variant.id)}"><img src="data:image/png;base64,${imageBytes.get(variant.file)}" alt="${escapeHtml(label)}"><span>${escapeHtml(label)}</span></button>`;
}).join('\n');
const html = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Лучница · варианты 11–20</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b1424;color:#eee6da;font:16px/1.4 system-ui,sans-serif}main{max-width:1800px;margin:auto;padding:24px}h1{margin:0 0 8px;font-size:30px}p{margin:0 0 18px;color:#b6c2d6}.grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}.card{padding:0;color:inherit;font:inherit;text-align:left;cursor:pointer;background:#111d31;border:1px solid #2b3a52;border-radius:6px;overflow:hidden;min-width:0}.card img{width:100%;display:block;aspect-ratio:1;object-fit:contain;image-rendering:auto}.card span{display:block;padding:10px;font-weight:600}.card:hover,.card:focus-visible{border-color:#d7ac79}dialog{background:#111d31;color:#eee6da;border:1px solid #52617c;border-radius:8px;max-width:min(94vw,1000px);padding:12px}dialog::backdrop{background:#000b}dialog img{max-width:100%;max-height:80vh;display:block;margin:auto;image-rendering:auto}dialog header{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:10px}dialog button{padding:8px 16px}@media(max-width:1000px){main{padding:16px}}@media(max-width:600px){main{padding:12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.card span{font-size:12px;padding:6px}h1{font-size:24px}}
</style>
</head>
<body><main><h1>Лучница · варианты 11–20</h1><p>Десять концептов для выбора. Это статичные изображения; анимации и интеграции в игру здесь нет.</p><section class="grid" id="archer-grid">${cards}</section></main>
<dialog id="viewer" aria-label="Просмотр концепта"><header><strong id="viewer-title"></strong><button type="button" id="close">Закрыть</button></header><img id="large" alt=""></dialog>
<script>
const viewer=document.getElementById('viewer'),large=document.getElementById('large'),title=document.getElementById('viewer-title');
document.querySelectorAll('.card').forEach(card=>card.addEventListener('click',()=>{const img=card.querySelector('img');large.src=img.src;large.alt=img.alt;title.textContent=img.alt;viewer.showModal()}));
document.getElementById('close').addEventListener('click',()=>viewer.close());
viewer.addEventListener('click',event=>{if(event.target===viewer){const rect=viewer.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)viewer.close()}});
</script></body></html>`;
fs.writeFileSync(path.join(root, 'gallery.html'), html);
console.log(`10 unique packaged PNG hashes verified; self-contained gallery built. Originals checked: ${verifyOriginals}`);
