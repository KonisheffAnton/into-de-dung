// Сравнивает выданные PNG без изменения исходников и без вывода о художественной приёмке.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = __dirname;
const size = 128;
const faceROI = { left: 69, top: 45, width: 11, height: 11 };
const headROI = { left: 58, top: 25, width: 31, height: 40 };

function frameFiles(directory) {
  const matches = fs.readdirSync(directory).filter((name) => /^frame-?\d+\.png$/.test(name));
  const byIndex = new Map(matches.map((name) => [Number(name.match(/\d+/)[0]), name]));
  if (matches.length !== 12 || [...Array(12)].some((_, i) => !byIndex.has(i + 1))) {
    throw new Error(`Expected exactly 12 numbered frame PNGs in ${directory}`);
  }
  return [...Array(12)].map((_, i) => path.join(directory, byIndex.get(i + 1)));
}

async function readRaw(file) {
  const image = sharp(file);
  const metadata = await image.metadata();
  if (metadata.width !== size || metadata.height !== size) throw new Error(`${path.basename(file)} must be 128x128`);
  return image.ensureAlpha().raw().toBuffer();
}

function crop(raw, roi) {
  const result = Buffer.alloc(roi.width * roi.height * 4);
  for (let y = 0; y < roi.height; y += 1) {
    const start = ((roi.top + y) * size + roi.left) * 4;
    raw.copy(result, y * roi.width * 4, start, start + roi.width * 4);
  }
  return result;
}

function pixelStats(face) {
  let changedAlpha = 0, transparent = 0, partial = 0, opaque = 0;
  for (let i = 0; i < face.length; i += 4) {
    const a = face[i + 3];
    if (a === 0) transparent += 1;
    else if (a < 255) partial += 1;
    else opaque += 1;
  }
  return { transparent, partialAlpha: partial, opaque };
}

function difference(a, b) {
  let changedPixels = 0, alphaChangedPixels = 0;
  for (let i = 0; i < a.length; i += 4) {
    if (a[i] !== b[i] || a[i + 1] !== b[i + 1] || a[i + 2] !== b[i + 2] || a[i + 3] !== b[i + 3]) changedPixels += 1;
    if (a[i + 3] !== b[i + 3]) alphaChangedPixels += 1;
  }
  return { changedPixels, alphaChangedPixels, totalPixels: a.length / 4 };
}

function alignedDifference(previous, current) {
  let best = null;
  // ROI сдвигается внутри raw-кадра: диапазон остаётся в границах, поэтому всегда сравниваются 121 пиксель.
  for (let dy = -2; dy <= 2; dy += 1) for (let dx = -2; dx <= 2; dx += 1) {
    let changedPixels = 0, alphaChangedPixels = 0;
    for (let y = 0; y < faceROI.height; y += 1) for (let x = 0; x < faceROI.width; x += 1) {
      const a = ((faceROI.top + y) * size + faceROI.left + x) * 4;
      const b = ((faceROI.top + y + dy) * size + faceROI.left + x + dx) * 4;
      if (previous[a] !== current[b] || previous[a + 1] !== current[b + 1] || previous[a + 2] !== current[b + 2] || previous[a + 3] !== current[b + 3]) changedPixels += 1;
      if (previous[a + 3] !== current[b + 3]) alphaChangedPixels += 1;
    }
    const candidate = { dx, dy, changedPixels, alphaChangedPixels, comparedPixels: faceROI.width * faceROI.height };
    if (!best || candidate.changedPixels < best.changedPixels ||
        (candidate.changedPixels === best.changedPixels && candidate.alphaChangedPixels < best.alphaChangedPixels)) best = candidate;
  }
  return best;
}

function hash(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function labeledTile(raw, roi, scale, width, height, title, background) {
  const cropPng = await sharp(crop(raw, roi), { raw: { width: roi.width, height: roi.height, channels: 4 } })
    .resize(roi.width * scale, roi.height * scale, { kernel: 'nearest' }).png().toBuffer();
  const label = Buffer.from(`<svg width="${width}" height="${height}"><rect width="100%" height="24" fill="#26312c"/><text x="${width / 2}" y="17" text-anchor="middle" fill="#eff1e7" font-family="Arial" font-size="12">${title}</text></svg>`);
  return sharp({ create: { width, height, channels: 4, background } })
    .composite([
      { input: cropPng, left: Math.floor((width - roi.width * scale) / 2), top: 27 },
      { input: label, left: 0, top: 0 },
    ]).png().toBuffer();
}

async function writeFaceFilmstrip(oldFrames, newFrames) {
  const cellW = 104, cellH = 116, columns = 12;
  const tiles = [];
  for (const [label, frames] of [['OLD', oldFrames], ['NEW', newFrames]]) {
    for (let i = 0; i < frames.length; i += 1) {
      tiles.push(await labeledTile(frames[i], faceROI, 8, cellW, cellH, `${label} ${String(i + 1).padStart(2, '0')}`, '#dedfd5'));
    }
  }
  await sharp({ create: { width: cellW * columns, height: cellH * 2, channels: 4, background: '#dedfd5' } })
    .composite(tiles.map((input, i) => ({ input, left: (i % columns) * cellW, top: Math.floor(i / columns) * cellH })))
    .png().toFile(path.join(root, 'face-filmstrip.png'));
}

async function writeHeadFilmstrip(newFrames) {
  const cellW = 120, cellH = 156, columns = 6;
  const tiles = await Promise.all(newFrames.map((frame, i) => labeledTile(
    frame, headROI, 3, cellW, cellH, `NEW ${String(i + 1).padStart(2, '0')}`, '#46524a')));
  await sharp({ create: { width: cellW * columns, height: cellH * 2, channels: 4, background: '#46524a' } })
    .composite(tiles.map((input, i) => ({ input, left: (i % columns) * cellW, top: Math.floor(i / columns) * cellH })))
    .png().toFile(path.join(root, 'head-filmstrip.png'));
}

async function main() {
  const newDir = path.join(root, 'pixellab');
  const oldDir = path.join(root, '..', 'rogue-idle-20261012', 'pixellab');
  const oldFiles = frameFiles(oldDir), newFiles = frameFiles(newDir);
  const oldFrames = await Promise.all(oldFiles.map(readRaw));
  const newFrames = await Promise.all(newFiles.map(readRaw));
  const oldFaces = oldFrames.map((frame) => crop(frame, faceROI));
  const newFaces = newFrames.map((frame) => crop(frame, faceROI));
  const oldHashes = oldFaces.map(hash), newHashes = newFaces.map(hash);

  await writeFaceFilmstrip(oldFrames, newFrames);
  await writeHeadFilmstrip(newFrames);

  const reference = await readRaw(path.join(newDir, 'reference-128.png'));
  const headPixels = crop(reference, headROI);
  const faceMetrics = (faces, hashes) => faces.map((face, i) => ({
    frame: i + 1,
    vsFirst: difference(faces[0], face),
    vsPrevious: i ? difference(faces[i - 1], face) : null,
    sha256: hashes[i],
    alpha: pixelStats(face),
  }));
  let referenceOpaque = 0, referenceLowerQuarterOpaque = 0;
  for (let y = 0; y < headROI.height; y += 1) for (let x = 0; x < headROI.width; x += 1) {
    const alpha = headPixels[(y * headROI.width + x) * 4 + 3];
    if (alpha >= 128) {
      referenceOpaque += 1;
      if (y >= Math.floor(headROI.height * 0.75)) referenceLowerQuarterOpaque += 1;
    }
  }
  const report = {
    rois: { face: faceROI, head: headROI },
    sources: {
      old: path.relative(root, oldDir),
      new: path.relative(root, newDir),
      reference: 'pixellab/reference-128.png',
    },
    exactPixelEqualityFaces: {
      oldMatchingFirst: oldHashes.filter((value) => value === oldHashes[0]).length,
      newMatchingFirst: newHashes.filter((value) => value === newHashes[0]).length,
    },
    uniqueFaceHashes: { old: new Set(oldHashes).size, new: new Set(newHashes).size },
    frames: { old: faceMetrics(oldFaces, oldHashes), new: faceMetrics(newFaces, newHashes) },
    adjacentBestTranslation: {
      range: { dx: [-2, 2], dy: [-2, 2] },
      comparisonSamples: faceROI.width * faceROI.height,
      old: oldFrames.slice(1).map((frame, i) => ({ from: i + 1, to: i + 2, ...alignedDifference(oldFrames[i], frame) })),
      new: newFrames.slice(1).map((frame, i) => ({ from: i + 1, to: i + 2, ...alignedDifference(newFrames[i], frame) })),
      note: 'Сдвиг только для диагностики; исходные пиксели и ROI не меняются.',
    },
    referenceHeadROI: {
      opaquePixels: referenceOpaque,
      lowerQuarterOpaquePixels: referenceLowerQuarterOpaque,
      lowerQuarterShareOfROIAlpha: referenceOpaque ? referenceLowerQuarterOpaque / referenceOpaque : null,
      note: 'Проверка охвата ROI по reference, не художественная приёмка и не классификация пикселей как плеч.',
    },
    outputs: ['face-filmstrip.png', 'head-filmstrip.png', 'face-validation.json'],
    acceptance: 'Диагностические изображения и метрики не объявляют лицо fixed и не заменяют художественную приёмку.',
  };
  fs.writeFileSync(path.join(root, 'face-validation.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
