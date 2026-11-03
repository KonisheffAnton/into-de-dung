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
if (variants.length !== 5) throw new Error(`Expected 5 variants, found ${variants.length}`);
const ids = variants.map(variant => String(variant.id));
const files = variants.map(variant => variant.file);
const expectedIds = ['14-01', '14-02', '14-03', '14-04', '14-05'];
if (new Set(ids).size !== 5 || new Set(files).size !== 5) throw new Error('Duplicate variant ID or PNG path');
if (ids.slice().sort().join(',') !== expectedIds.join(',')) throw new Error('Expected variant IDs 14-01 through 14-05');
if (expectedIds.some(id => !files.includes(`archer-${id}.png`)) || files.some(file => !expectedIds.some(id => file === `archer-${id}.png`))) {
	throw new Error('Expected archer-14-01.png through archer-14-05.png');
}
if (variants.some(variant => !variant.name || !variant.prompt)) throw new Error('Every variant needs a Russian name and prompt');
if (!Array.isArray(provenance.images) || provenance.images.length !== 5) throw new Error('sources.json must contain 5 image records');
if (!Array.isArray(provenance.references) || provenance.references.length !== 3) throw new Error('sources.json must contain 3 reference records');

const imageRecords = new Map();
for (const record of provenance.images) {
	if (imageRecords.has(record.file)) throw new Error(`Duplicate sources.json image: ${record.file}`);
	imageRecords.set(record.file, record);
}
const referenceSpecs = [
	{ file: '../archer-variants-20261103/archer-14.png', label: 'Лучница 14 · оригинал' },
	{ file: '../warrior-variants-20261029/warrior-11.png', label: 'Воин 11' },
	{ file: '../warrior-variants-20261029/warrior-02.png', label: 'Защитник 02' },
];
const referenceRecords = new Map();
for (const record of provenance.references) {
	if (referenceRecords.has(record.file)) throw new Error(`Duplicate sources.json reference: ${record.file}`);
	referenceRecords.set(record.file, record);
}
if (new Set(provenance.images.map(record => String(record.id))).size !== 5
	|| provenance.images.some(record => record.id === undefined || record.id === null)) {
	throw new Error('sources.json image IDs must be present and unique');
}
if (new Set(provenance.references.map(record => String(record.id))).size !== 3
	|| provenance.references.some(record => record.id === undefined || record.id === null)) {
	throw new Error('sources.json reference IDs must be present and unique');
}

function loadPng(file, record, shouldVerifyOriginal) {
	const filePath = path.resolve(root, file);
	const bytes = fs.readFileSync(filePath);
	if (bytes.length < 24 || bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Not a PNG: ${file}`);
	const actual = {
		sha256: crypto.createHash('sha256').update(bytes).digest('hex'),
		width: bytes.readUInt32BE(16),
		height: bytes.readUInt32BE(20),
	};
	if (!record || record.id === undefined || record.id === null || record.file !== file || record.sha256 !== actual.sha256
		|| record.width !== actual.width || record.height !== actual.height) {
		throw new Error(`Packaged PNG differs from sources.json: ${file}`);
	}
	if (shouldVerifyOriginal) {
		if (typeof record.source_path !== 'string' || record.source_path.length === 0) throw new Error(`No source_path to verify for ${file}`);
		if (!fs.readFileSync(path.resolve(root, record.source_path)).equals(bytes)) throw new Error(`Original source differs from packaged PNG: ${file}`);
	}
	return { bytes, sha256: actual.sha256 };
}

const embedded = new Map();
const variantHashes = new Set();
for (const variant of variants) {
	const file = variant.file;
	const imageRecord = imageRecords.get(file);
	if (!imageRecord || String(imageRecord.id) !== String(variant.id)) throw new Error(`sources.json ID differs for ${file}`);
	const result = loadPng(file, imageRecord, verifyOriginals);
	if (variantHashes.has(result.sha256)) throw new Error(`Duplicate PNG content: ${file}`);
	variantHashes.add(result.sha256);
	embedded.set(file, result.bytes.toString('base64'));
}
if (imageRecords.size !== 5 || [...imageRecords.keys()].some(file => !files.includes(file))) {
	throw new Error('sources.json image records do not match prompts.json');
}
for (const spec of referenceSpecs) {
	const record = referenceRecords.get(spec.file);
	// Референсы уже находятся в репозитории; выдачи генератора сверяем только у новых вариантов.
	const result = loadPng(spec.file, record, false);
	embedded.set(spec.file, result.bytes.toString('base64'));
}
if (referenceRecords.size !== 3 || [...referenceRecords.keys()].some(file => !referenceSpecs.some(spec => spec.file === file))) {
	throw new Error('sources.json references do not match the required comparison images');
}

const references = referenceSpecs.map((reference, index) => {
	const label = reference.label;
	return `<button class="card reference-card" type="button" data-kind="reference" data-id="${index + 1}" data-file="${escapeHtml(reference.file)}"><img src="data:image/png;base64,${embedded.get(reference.file)}" alt="${escapeHtml(label)}"><span>${escapeHtml(label)}</span></button>`;
}).join('\n');
const conceptCards = variants.map(variant => {
	const label = `${variant.id} · ${variant.name}`;
	return `<button class="card concept-card" type="button" data-kind="variant" data-id="${escapeHtml(variant.id)}" data-file="${escapeHtml(variant.file)}"><img src="data:image/png;base64,${embedded.get(variant.file)}" alt="${escapeHtml(label)}"><span>${escapeHtml(label)}</span></button>`;
}).join('\n');
const html = `<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Лучница 14 · пять переработок</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#0b1424;color:#eee6da;font:16px/1.4 system-ui,sans-serif}main{max-width:1800px;margin:auto;padding:24px}h1{margin:0 0 8px;font-size:30px}p{margin:0 0 18px;color:#b6c2d6}h2{margin:0 0 10px;font-size:21px}.comparison{display:grid;gap:22px}.reference-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:12px;width:calc(60% - 4.8px)}.variant-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:12px}.card{padding:0;color:inherit;font:inherit;text-align:left;cursor:pointer;background:#111d31;border:1px solid #2b3a52;border-radius:6px;overflow:hidden;min-width:0}.card img{width:100%;display:block;aspect-ratio:1;object-fit:contain;image-rendering:auto}.card span{display:block;padding:10px;font-weight:600}.reference-card{border-color:#59687f;background:#101a2b}.concept-card{border-color:#756047;background:#151e2d}.reference-card span::before{content:'РЕФЕРЕНС · ';color:#9fb1c8;font-size:.72em;letter-spacing:.06em}.concept-card span::before{content:'ПЕРЕРАБОТКА · ';color:#d6ad7b;font-size:.72em;letter-spacing:.04em}.card:hover,.card:focus-visible{border-color:#e1bd8e}dialog{background:#111d31;color:#eee6da;border:1px solid #52617c;border-radius:8px;max-width:min(94vw,1000px);padding:12px}dialog::backdrop{background:#000b}dialog img{max-width:100%;max-height:80vh;display:block;margin:auto;image-rendering:auto}dialog header{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:10px}dialog button{padding:8px 16px}@media(max-width:1000px){main{padding:16px}}@media(max-width:600px){main{padding:12px}.reference-grid,.variant-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:8px;width:100%}.card span{font-size:12px;padding:6px}h1{font-size:24px}}
</style>
</head>
<body><main><h1>Лучница 14 · пять переработок</h1><p>Сравнение с исходной лучницей, Воином 11 и Защитником 02. Пять статичных концептов для выбора; анимации и интеграции в игру здесь нет.</p><section class="comparison" id="comparison"><div><h2>Референсы</h2><div class="reference-grid" id="reference-grid">${references}</div></div><div><h2>Переработки · 14-01–14-05</h2><div class="variant-grid" id="variant-grid">${conceptCards}</div></div></section></main>
<dialog id="viewer" aria-label="Просмотр изображения"><header><strong id="viewer-title"></strong><button type="button" id="close">Закрыть</button></header><img id="large" alt=""></dialog>
<script>
const viewer=document.getElementById('viewer'),large=document.getElementById('large'),title=document.getElementById('viewer-title');
document.querySelectorAll('.card').forEach(card=>card.addEventListener('click',()=>{const img=card.querySelector('img');large.src=img.src;large.alt=img.alt;title.textContent=img.alt;viewer.showModal()}));
document.getElementById('close').addEventListener('click',()=>viewer.close());
viewer.addEventListener('click',event=>{if(event.target===viewer){const rect=viewer.getBoundingClientRect();if(event.clientX<rect.left||event.clientX>rect.right||event.clientY<rect.top||event.clientY>rect.bottom)viewer.close()}});
</script></body></html>`;
fs.writeFileSync(path.join(root, 'gallery.html'), html);
console.log(`5 unique variant PNG hashes and 3 reference hashes verified; self-contained comparison built. Originals checked: ${verifyOriginals}`);
