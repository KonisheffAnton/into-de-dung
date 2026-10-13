// Скрипт собирает только просмотр и метаданные, чтобы генерации оставались нетронутыми.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = __dirname;
const readJson = p => JSON.parse(fs.readFileSync(path.join(root, p), 'utf8').replace(/^\uFEFF/, ''));
const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const exists = p => fs.existsSync(path.join(root, p));

async function rgba(file) {
  return sharp(file).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
}

function stats(data, width, height) {
  let x0 = width, y0 = height, x1 = -1, y1 = -1;
  let transparent = 0, opaque = 0, partialAlpha = 0;
  const colors = new Set();
  for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
    const p = (y * width + x) * 4;
    const a = data[p + 3];
    if (a === 0) transparent++; else if (a === 255) opaque++; else partialAlpha++;
    if (a >= 128) {
      x0 = Math.min(x0, x); y0 = Math.min(y0, y);
      x1 = Math.max(x1, x); y1 = Math.max(y1, y);
      colors.add(data.subarray(p, p + 4).toString('hex'));
    }
  }
  const bbox = x1 < 0 ? null : [x0, y0, x1 + 1, y1 + 1];
  return {
    bbox_alpha128: bbox, transparent, opaque, partial_alpha: partialAlpha,
    colors_alpha128: colors.size,
    art_flags: {
      no_transparent_pixels: transparent === 0,
      touches_canvas_edge: bbox !== null && (bbox[0] === 0 || bbox[1] === 0 || bbox[2] === width || bbox[3] === height),
      empty_visible_image: bbox === null,
    },
  };
}

function frameDelays(count, cycleMs) {
  // Кумулятивное округление до 10 мс сохраняет точную длину цикла при любом числе кадров.
  const result = [];
  let previous = 0;
  for (let i = 1; i <= count; i++) {
    const current = Math.round((i * cycleMs / count) / 10) * 10;
    result.push(current - previous);
    previous = current;
  }
  if (previous !== cycleMs) throw new Error('Длительность цикла не делится на 10 мс');
  return result;
}

async function makeAnimation(frames, width, height, delay, file) {
  const sequence = await Promise.all(frames.map(f => sharp(f.data, { raw: { width, height, channels: 4 } })
    .resize(width * f.scale, height * f.scale, { kernel: 'nearest' }).raw().toBuffer()));
  const outWidth = width * frames[0].scale;
  const outHeight = height * frames[0].scale;
  const stacked = sharp(Buffer.concat(sequence), {
    raw: { width: outWidth, height: outHeight * frames.length, channels: 4, pageHeight: outHeight },
  });
  await stacked.gif({ delay, loop: 0, dither: 0, effort: 7 }).toFile(file);
  const meta = await sharp(file, { animated: true }).metadata();
  const actualDelays = Array.isArray(meta.delay) ? meta.delay : [];
  const actualTotal = actualDelays.reduce((sum, ms) => sum + ms, 0);
  if (actualTotal !== delay.reduce((sum, ms) => sum + ms, 0)) {
    throw new Error(`GIF timing mismatch in ${path.basename(file)}: ${actualTotal} ms`);
  }
  // GIF может склеить визуально одинаковые соседние кадры; длительность, а не pages, задаёт паритет.
  return {
    width: meta.width, height: meta.height, encoded_pages: meta.pages,
    encoded_delay_ms: actualDelays, timing_summary: {
      source_frames: frames.length, source_total_ms: delay.reduce((sum, ms) => sum + ms, 0),
      encoded_total_ms: actualTotal, total_duration_verified_by_sum_ms: actualTotal,
      description: 'Проверена только общая длительность суммой задержек GIF; сама по себе эта сумма не доказывает покадровый временной паритет. Порядок исходных кадров сохранён кодом сборки.',
      total_duration_check_does_not_prove_frame_by_frame_temporal_parity: true,
      duplicate_coalescing_allowed: true,
    },
  };
}

async function makeComparisonGrid(ready, cycleMs, outFile) {
  if (ready.length === 0) return { status: 'no_completed_variants' };
  const columns = 3, rows = Math.ceil(ready.length / columns);
  const cellWidth = 256, imageHeight = 256, labelHeight = 40, gutter = 8;
  const cellHeight = labelHeight + imageHeight;
  const width = columns * cellWidth + (columns + 1) * gutter;
  const height = rows * cellHeight + (rows + 1) * gutter;
  const boundaries = new Set([0, cycleMs]);
  for (const trial of ready) {
    let time = 0;
    for (const delay of trial.delays) { time += delay; boundaries.add(time); }
  }
  const points = [...boundaries].sort((a, b) => a - b);
  const timeline = points.slice(1).map((end, i) => ({ start: points[i], delay: end - points[i] }));
  if (timeline.some(part => part.delay <= 0) || timeline.reduce((sum, part) => sum + part.delay, 0) !== cycleMs) {
    throw new Error('Comparison grid timeline does not total target cycle');
  }

  const rawFrames = [];
  for (const part of timeline) {
    const layers = [];
    for (let index = 0; index < ready.length; index++) {
      const trial = ready[index];
      let elapsed = part.start, frameIndex = 0;
      while (frameIndex < trial.delays.length - 1 && elapsed >= trial.delays[frameIndex]) {
        elapsed -= trial.delays[frameIndex];
        frameIndex++;
      }
      const x = gutter + (index % columns) * (cellWidth + gutter);
      const y = gutter + Math.floor(index / columns) * (cellHeight + gutter);
      const title = escapeHtml(`${trial.variant.title} · ${trial.width}×${trial.height}`);
      const label = Buffer.from(`<svg width="${cellWidth}" height="${labelHeight}" xmlns="http://www.w3.org/2000/svg"><rect width="100%" height="100%" fill="#343b36"/><text x="8" y="25" fill="#f2eddf" font-size="14" font-family="sans-serif">${title}</text></svg>`);
      const nearestPng = await sharp(trial.frames[frameIndex].data, { raw: { width: trial.width, height: trial.height, channels: 4 } })
        .resize(cellWidth, imageHeight, { kernel: 'nearest' }).png().toBuffer();
      layers.push({ input: label, left: x, top: y });
      layers.push({ input: nearestPng, left: x, top: y + labelHeight });
    }
    // Палитра нужна только GIF предпросмотра; все provider PNG остаются побайтно нетронутыми.
    const raw = await sharp({ create: { width, height, channels: 4, background: '#272d29' } })
      .composite(layers).raw().toBuffer();
    rawFrames.push(raw);
  }
  await sharp(Buffer.concat(rawFrames), {
    raw: { width, height: height * rawFrames.length, channels: 4, pageHeight: height },
  }).gif({ delay: timeline.map(part => part.delay), loop: 0, dither: 0, effort: 7 }).toFile(outFile);
  const meta = await sharp(outFile, { animated: true }).metadata();
  const actualDelays = Array.isArray(meta.delay) ? meta.delay : [];
  const encodedTotal = actualDelays.reduce((sum, ms) => sum + ms, 0);
  if (encodedTotal !== cycleMs) throw new Error(`Comparison grid timing mismatch: ${encodedTotal} ms`);
  return {
    status: 'completed', width: meta.width, height: meta.height, source_variants: ready.map(trial => trial.variant.id),
    timeline_segments: timeline.length, source_total_ms: cycleMs, encoded_pages: meta.pages,
    encoded_delay_ms: actualDelays, total_duration_verified_by_sum_ms: encodedTotal,
    timing_description: 'Проверена только общая длительность суммой задержек GIF; сама по себе эта сумма не доказывает покадровый временной паритет. Порядок исходных кадров сохранён кодом сборки.',
    total_duration_check_does_not_prove_frame_by_frame_temporal_parity: true,
    duplicate_coalescing_allowed: true,
  };
}

async function main() {
  const manifest = readJson('variants.json');
  const cycleMs = manifest.target_cycle_ms;
  if (!Number.isInteger(cycleMs) || cycleMs <= 0 || cycleMs % 10 !== 0) throw new Error('target_cycle_ms должен быть положительным кратным 10');
  const videoRel = 'source/user-motion.mp4';
  const videoData = exists(videoRel) ? fs.readFileSync(path.join(root, videoRel)) : null;
  const validation = { target_cycle_ms: cycleMs, variants: [] };
  const cards = [];
  const summaries = [];
  const readyForGrid = [];

  for (const variant of manifest.variants) {
    const dir = variant.path;
    const resultPath = path.join(dir, 'result.json');
    const entry = { id: variant.id, status: 'missing_result', frames: [] };
    const sourcePath = path.join(dir, 'source.png');
    let reference = null;
    if (fs.existsSync(path.join(root, sourcePath))) {
      const sourceBytes = fs.readFileSync(path.join(root, sourcePath));
      const source = await rgba(sourceBytes);
      if (source.info.width !== variant.width || source.info.height !== variant.height) throw new Error(`${variant.id}/source.png: expected ${variant.width}x${variant.height}`);
      reference = { data: `data:image/png;base64,${sourceBytes.toString('base64')}`, stats: stats(source.data, source.info.width, source.info.height) };
      entry.reference = { file: 'source.png', sha256: hash(sourceBytes), ...reference.stats };
    } else {
      entry.reference = { status: 'missing_source_png' };
    }
    if (!fs.existsSync(path.join(root, resultPath))) {
      validation.variants.push(entry);
      cards.push({ variant, reference, status: 'Результат генерации пока не предоставлен' });
      continue;
    }
    const result = readJson(resultPath);
    if (result.status !== 'completed') {
      entry.status = `provider_${result.status || 'unknown'}`;
      validation.variants.push(entry);
      cards.push({ variant, reference, status: `Статус источника: ${entry.status}` });
      continue;
    }
    if (!Array.isArray(result.files) || result.files.length !== result.frame_count || result.frame_count < 1) {
      throw new Error(`${variant.id}: frame_count не совпадает с files`);
    }
    const frames = [];
    let dimensions = null;
    for (const item of result.files) {
      const file = path.join(dir, item.file);
      const bytes = fs.readFileSync(path.join(root, file));
      const actualHash = hash(bytes);
      if (actualHash !== item.sha256) throw new Error(`${variant.id}/${item.file}: SHA-256 mismatch`);
      const decoded = await rgba(bytes);
      const size = { width: decoded.info.width, height: decoded.info.height };
      if (size.width !== variant.width || size.height !== variant.height) throw new Error(`${variant.id}/${item.file}: expected ${variant.width}x${variant.height}, got ${size.width}x${size.height}`);
      if (dimensions && (size.width !== dimensions.width || size.height !== dimensions.height)) throw new Error(`${variant.id}: frame dimensions differ`);
      dimensions = size;
      frames.push({ data: decoded.data, bytes, item, file, stats: stats(decoded.data, size.width, size.height) });
      entry.frames.push({ file: item.file, sha256: actualHash, ...frames.at(-1).stats });
    }
    entry.status = 'completed';
    entry.frame_count = frames.length;
    entry.duration_ms = frameDelays(frames.length, cycleMs);
    readyForGrid.push({ variant, frames, width: dimensions.width, height: dimensions.height, delays: entry.duration_ms });
    entry.gif = {};
    entry.gif.native = await makeAnimation(frames.map(f => ({ data: f.data, scale: 1 })), dimensions.width, dimensions.height, entry.duration_ms, path.join(root, dir, 'idle-native.gif'));
    const scale = 512 / dimensions.width;
    if (!Number.isInteger(scale)) throw new Error(`${variant.id}: cannot nearest-scale ${dimensions.width}px to 512px exactly`);
    entry.gif['512'] = await makeAnimation(frames.map(f => ({ data: f.data, scale })), dimensions.width, dimensions.height, entry.duration_ms, path.join(root, dir, 'idle-512.gif'));
    await makeFilmstrip(frames, dimensions.width, dimensions.height, path.join(root, dir, 'filmstrip.png'));
    validation.variants.push(entry);
    cards.push({ variant, reference, status: 'Готово', frames, width: dimensions.width, height: dimensions.height });
    summaries.push({ id: variant.id, frame_count: frames.length, native_gif: entry.gif.native, gif_512: entry.gif['512'] });
  }

  const htmlCards = cards.map((card, index) => {
    const referenceMarkup = card.reference ? `<details><summary>Исходный PNG</summary><img class="reference" src="${card.reference.data}" alt="Исходный PNG ${escapeHtml(card.variant.title)}"><small>Показан без обработки; прозрачность и край холста отражены во флагах валидации.</small></details>` : '<p>Исходный PNG отсутствует.</p>';
    if (!card.frames) return `<article><h2>${escapeHtml(card.variant.title)}</h2><p>${escapeHtml(card.variant.description)}</p>${referenceMarkup}<p>${escapeHtml(card.status)}</p></article>`;
    const data = card.frames.map(f => `data:image/png;base64,${f.bytes.toString('base64')}`);
    const total = card.frames.length;
    return `<article><h2>${escapeHtml(card.variant.title)}</h2><p>${escapeHtml(card.variant.description)}</p>${referenceMarkup}<p>${card.width}×${card.height} · ${total} кадров</p><canvas id="c${index}" width="${card.width}" height="${card.height}"></canvas><p><a href="${escapeHtml(card.variant.path)}/idle-512.gif" target="_blank">Открыть GIF 512 px</a></p><small id="f${index}"></small><script>window.trials.push({canvas:document.getElementById('c${index}'),label:document.getElementById('f${index}'),frames:${JSON.stringify(data)},delays:${JSON.stringify(frameDelays(total, cycleMs))},count:${total}});</script></article>`;
  }).join('\n');
  const videoUri = videoData ? `data:video/mp4;base64,${videoData.toString('base64')}` : '';
  const html = `<!doctype html><html lang="ru"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Пробы анимации лучницы</title><style>body{margin:24px;background:#202521;color:#eee8d9;font:16px system-ui}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:18px}article{padding:16px;background:#303832;border-radius:8px;min-width:0}canvas,.reference{display:block;width:min(100%,512px);height:auto;image-rendering:pixelated;background:repeating-conic-gradient(#333a35 0% 25%,#424942 0% 50%) 0/24px 24px}video{width:min(100%,512px);image-rendering:pixelated}button,input{font:inherit;margin:8px 8px 8px 0}small{color:#c3c8b8}a{color:#bbd8ac}</style><h1>Лучница — визуальное сравнение проб</h1><p>Сравнение исходного ролика и кадров генераций в заданной последовательности. Каждая проба проигрывается в цикле ${cycleMs} мс.</p>${videoData ? `<section><h2>Исходный ролик движения</h2><video id="video" src="${videoUri}" muted playsinline loop></video></section>` : '<p>Исходный ролик отсутствует.</p>'}<p><button id="toggle">Пауза</button><button id="restart">Сначала</button><input id="seek" type="range" min="0" max="${cycleMs}" step="10" value="0"><span id="clock">0.00 с</span></p><script>window.trials=[];</script><main>${htmlCards}</main><script>const video=document.getElementById('video'),toggle=document.getElementById('toggle'),seek=document.getElementById('seek'),clock=document.getElementById('clock');let paused=false,anchor=performance.now();Promise.all(window.trials.flatMap(t=>t.frames.map(src=>{const im=new Image();im.src=src;t.images??=[];t.images.push(im);return im.decode()}))).then(()=>{function draw(now){let ms;if(video&&Number.isFinite(video.duration)&&video.duration>0){if(!paused) video.play().catch(()=>{});ms=(video.currentTime*1000)%${cycleMs}}else ms=((now-anchor)%${cycleMs}+${cycleMs})%${cycleMs};if(!paused)seek.value=String(Math.round(ms/10)*10);clock.textContent=(ms/1000).toFixed(2)+' с';for(const t of window.trials){let elapsed=ms,i=0;while(i<t.count-1&&elapsed>=t.delays[i]){elapsed-=t.delays[i];i++}const c=t.canvas.getContext('2d');c.imageSmoothingEnabled=false;c.clearRect(0,0,t.canvas.width,t.canvas.height);c.drawImage(t.images[i],0,0);t.label.textContent='Кадр '+(i+1)+' / '+t.count+' · '+(ms/1000).toFixed(2)+' с'}requestAnimationFrame(draw)}draw(performance.now())});toggle.onclick=()=>{paused=!paused;if(video){if(paused)video.pause();else video.play().catch(()=>{})}toggle.textContent=paused?'Продолжить':'Пауза'};document.getElementById('restart').onclick=()=>{anchor=performance.now();if(video)video.currentTime=0;seek.value='0';if(video)video.play().catch(()=>{});paused=false;toggle.textContent='Пауза'};seek.oninput=()=>{const ms=Number(seek.value);anchor=performance.now()-ms;if(video&&video.duration)video.currentTime=ms/1000};</script></html>`;
  fs.writeFileSync(path.join(root, 'comparison.html'), html);
  validation.comparison_grid = await makeComparisonGrid(readyForGrid, cycleMs, path.join(root, 'comparison-grid.gif'));
  fs.writeFileSync(path.join(root, 'validation.json'), JSON.stringify(validation, null, 2) + '\n');
  fs.writeFileSync(path.join(root, 'root-preview-summary.json'), JSON.stringify({ variants: summaries, missing: validation.variants.filter(v => v.status !== 'completed').map(v => ({ id: v.id, status: v.status })) }, null, 2) + '\n');
  console.log(JSON.stringify({ variants: validation.variants.map(v => ({ id: v.id, status: v.status, frame_count: v.frame_count || 0 })) }));
}

async function makeFilmstrip(frames, width, height, out) {
  const cellWidth = width * 2, cellHeight = height * 2 + 24;
  const columns = Math.min(5, frames.length), rows = Math.ceil(frames.length / columns);
  const composites = [];
  frames.forEach((frame, i) => {
    const left = 8 + (i % columns) * (cellWidth + 8), top = 8 + Math.floor(i / columns) * (cellHeight + 8);
    composites.push({ input: sharp(frame.data, { raw: { width, height, channels: 4 } }).resize(cellWidth, height * 2, { kernel: 'nearest' }).png().toBuffer(), left, top });
    composites.push({ input: Buffer.from(`<svg width="${cellWidth}" height="20"><text x="${cellWidth / 2}" y="15" text-anchor="middle" fill="#eee8d9" font-size="13">${String(i + 1).padStart(2, '0')}</text></svg>`), left, top: top + height * 2 });
  });
  const resolved = await Promise.all(composites.map(async item => ({ ...item, input: await item.input })));
  await sharp({ create: { width: columns * (cellWidth + 8) + 8, height: rows * (cellHeight + 8) + 8, channels: 4, background: '#333a35' } }).composite(resolved).png().toFile(out);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch]));
}

main().catch(error => { console.error(error); process.exitCode = 1; });
