// Проверяет исходные кадры до обрезки, чтобы не скрыть ошибку рамки потерей позы.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = __dirname;
const inputDir = path.join(root, 'pixellab');
const size = 128;
const pad = 16;
const nativeSize = 96;
const delayMs = 200;
const frameNames = Array.from({ length: 12 }, (_, i) => `frame-${String(i + 1).padStart(2, '0')}.png`);

async function loadImage(file) {
  const image = sharp(file);
  const metadata = await image.metadata();
  if (metadata.width !== size || metadata.height !== size) {
    throw new Error(`${path.basename(file)} must be ${size}x${size}`);
  }
  return image.ensureAlpha().raw().toBuffer();
}

function analyze(pixels) {
  let minX = size, minY = size, maxX = -1, maxY = -1;
  let opaque = 0;
  const alphaCounts = [0, 0, 0, 0];
  const colors = new Set();
  for (let y = 0; y < size; y += 1) for (let x = 0; x < size; x += 1) {
    const offset = (y * size + x) * 4;
    const alpha = pixels[offset + 3];
    alphaCounts[alpha === 0 ? 0 : alpha < 128 ? 1 : alpha < 255 ? 2 : 3] += 1;
    if (alpha >= 128) {
      opaque += 1;
      minX = Math.min(minX, x); maxX = Math.max(maxX, x);
      minY = Math.min(minY, y); maxY = Math.max(maxY, y);
    }
    if (alpha > 0) colors.add(`${pixels[offset]},${pixels[offset + 1]},${pixels[offset + 2]},${alpha}`);
    if ((x < pad || x >= size - pad || y < pad || y >= size - pad) && alpha >= 128) {
      throw new Error(`Opaque content outside 16px crop`);
    }
  }
  return {
    bbox: opaque ? { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 } : null,
    uniqueColorsIncludingAlpha: colors.size,
    alphaPixels: { transparent: alphaCounts[0], partialBelow128: alphaCounts[1], partialAtLeast128: alphaCounts[2], opaque: alphaCounts[3] },
  };
}

function cropPixels(pixels) {
  const out = Buffer.alloc(nativeSize * nativeSize * 4);
  for (let y = 0; y < nativeSize; y += 1) {
    const start = ((y + pad) * size + pad) * 4;
    pixels.copy(out, y * nativeSize * 4, start, start + nativeSize * 4);
  }
  return out;
}

async function writeGif(pages, width, height, filename) {
  await sharp(Buffer.concat(pages), { raw: { width, height: height * pages.length, channels: 4, pageHeight: height } })
    .gif({ loop: 0, delay: Array(pages.length).fill(delayMs), dither: 0, effort: 10 })
    .toFile(path.join(root, filename));
}

async function main() {
  const present = fs.readdirSync(inputDir).filter((name) => /^frame-\d+\.png$/.test(name)).sort();
  if (present.length !== 12 || frameNames.some((name) => !present.includes(name))) {
    throw new Error(`Expected exactly frame-01.png through frame-12.png; found ${present.join(', ') || 'none'}`);
  }
  const frames = [];
  const sourceHashes = new Set();
  const frameInfo = [];
  for (const name of frameNames) {
    const file = path.join(inputDir, name);
    const raw = await loadImage(file);
    const stats = analyze(raw);
    frames.push(cropPixels(raw));
    const sha256 = crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
    sourceHashes.add(sha256);
    frameInfo.push({ file: name, sha256, ...stats });
  }
  const referenceName = 'reference-128.png';
  const referenceRaw = await loadImage(path.join(inputDir, referenceName));
  analyze(referenceRaw);

  await writeGif(frames, nativeSize, nativeSize, 'idle-native.gif');

  const previewW = 640, previewH = 600;
  const bg = { r: 75, g: 88, b: 76, alpha: 255 };
  const samples = [0.75, 1, 1.25];
  const labels = Buffer.from(`<svg width="${previewW}" height="${previewH}"><g fill="#e4e8df" font-family="Arial" text-anchor="middle"><text x="320" y="24" font-size="16">PIXELLAB IDLE · ×4 NEAREST</text><text x="107" y="590" font-size="13">75% approximate</text><text x="320" y="590" font-size="13">100% approximate</text><text x="533" y="590" font-size="13">125% approximate</text></g></svg>`);
  const previewPages = await Promise.all(frames.map(async (frame) => {
    const scaled = await sharp(frame, { raw: { width: nativeSize, height: nativeSize, channels: 4 } })
      .resize(384, 384, { kernel: 'nearest' }).png().toBuffer();
    const pageLayers = [{ input: scaled, left: 128, top: 40 }];
    for (let i = 0; i < samples.length; i += 1) {
      const displaySize = Math.round(nativeSize * samples[i]);
      const image = await sharp(frame, { raw: { width: nativeSize, height: nativeSize, channels: 4 } })
        .resize(displaySize, displaySize, { kernel: 'nearest' }).png().toBuffer();
      pageLayers.push({ input: image, left: Math.round(previewW * (i + 0.5) / 3 - displaySize / 2), top: 570 - displaySize });
    }
    pageLayers.push({ input: labels, left: 0, top: 0 });
    return sharp({ create: { width: previewW, height: previewH, channels: 4, background: bg } }).composite(pageLayers).raw().toBuffer();
  }));
  await sharp(previewPages[0], { raw: { width: previewW, height: previewH, channels: 4 } })
    .png().toFile(path.join(root, 'preview-still.png'));
  await writeGif(previewPages, previewW, previewH, 'preview.gif');

  const cell = 192;
  const thumbs = await Promise.all(frames.map((frame) => sharp(frame,
    { raw: { width: nativeSize, height: nativeSize, channels: 4 } }).resize(cell, cell, { kernel: 'nearest' }).png().toBuffer()));
  await sharp({ create: { width: cell * 6, height: cell * 2, channels: 4, background: bg } })
    .composite(thumbs.map((input, i) => ({ input, left: (i % 6) * cell, top: Math.floor(i / 6) * cell })))
    .png().toFile(path.join(root, 'filmstrip.png'));

  let diffSum = 0, changedChannels = 0;
  for (let i = 0; i < frames[0].length; i += 1) {
    const delta = Math.abs(frames[0][i] - frames[11][i]);
    diffSum += delta;
    if (delta !== 0) changedChannels += 1;
  }
  // Нижняя полоса сравнивается с первым кадром как наблюдение; это не критерий сохранности стоп.
  const footY = Math.floor(nativeSize * 0.8);
  let footChanged = 0;
  for (let y = footY; y < nativeSize; y += 1) for (let x = 0; x < nativeSize; x += 1) {
    const offset = (y * nativeSize + x) * 4;
    if (frames[0].subarray(offset, offset + 4).some((value, c) => value !== frames[11][offset + c])) footChanged += 1;
  }
  const nativeMeta = await sharp(path.join(root, 'idle-native.gif'), { animated: true }).metadata();
  const previewMeta = await sharp(path.join(root, 'preview.gif'), { animated: true }).metadata();
  const expectedDelay = Array(12).fill(delayMs);
  for (const [name, metadata, width, height] of [
    ['native', nativeMeta, nativeSize, nativeSize], ['preview', previewMeta, previewW, previewH],
  ]) {
    if (metadata.pages !== 12 || metadata.width !== width || metadata.pageHeight !== height ||
        metadata.loop !== 0 || !Array.isArray(metadata.delay) ||
        metadata.delay.length !== expectedDelay.length || metadata.delay.some((value) => value !== delayMs)) {
      throw new Error(`${name} GIF metadata mismatch: ${JSON.stringify(metadata)}`);
    }
  }
  const report = {
    frames: frameInfo,
    uniqueFrameCount: sourceHashes.size,
    reference: { file: referenceName, dimensions: '128x128 RGBA', expectedPadding: '16px around native 96x96', validated: true },
    delaysMs: Array(12).fill(delayMs),
    observations: {
      lastFirstPixelDifference: { meanAbsoluteChannelDifference: diffSum / frames[0].length, changedChannels, totalChannels: frames[0].length },
      lowerRegionComparedWithFirst: { yFrom: footY, changedPixels: footChanged, totalPixels: nativeSize * (nativeSize - footY), note: 'Наблюдение по пикселям, не вывод о гладкости или сохранности стоп.' },
    },
    gif: {
      native: { pages: nativeMeta.pages, delay: nativeMeta.delay, width: nativeMeta.width, pageHeight: nativeMeta.pageHeight, loop: 0 },
      preview: { pages: previewMeta.pages, delay: previewMeta.delay, width: previewMeta.width, pageHeight: previewMeta.pageHeight, loop: 0 },
    },
    outputs: ['idle-native.gif', 'preview.gif', 'filmstrip.png', 'preview-still.png', 'preview.json'],
    previewDisplay: '×4 nearest on muted grey-green; size row is approximate and does not represent Godot rendering.',
  };
  fs.writeFileSync(path.join(root, 'preview.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
