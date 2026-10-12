// Рендерит только трансляцию готовых пикселей: так проверяется задержка слоёв без перерисовки.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = __dirname;
const sourcePath = path.join(root, 'source.png');
const rigPath = path.join(root, 'rig.json');
const sourceSize = 128;
const faceROI = { x: 69, y: 45, width: 11, height: 11 };
const footROIs = [
  { name: 'left', x: 40, y: 78, width: 16, height: 12 },
  { name: 'right', x: 70, y: 90, width: 19, height: 13 },
];
const diagnostics = {};

function fail(message, details = {}) {
  throw Object.assign(new Error(message), { details });
}

function validateRig(rig) {
  if (!rig || rig.scale !== 4 || rig.frames !== 48 || rig.frameMs !== 50 ||
      !Number.isFinite(rig.amplitudeNative) || rig.amplitudeNative < 0 ||
      !Number.isInteger(rig.headLagFrames) || !Array.isArray(rig.headPolygon) || !Array.isArray(rig.bodyPolygon)) {
    fail('rig.json must define scale=4, frames=48, frameMs=50, amplitudeNative, headLagFrames and both polygons');
  }
  for (const [name, polygon] of [['headPolygon', rig.headPolygon], ['bodyPolygon', rig.bodyPolygon]]) {
    if (polygon.length < 3 || polygon.some((point) => !Array.isArray(point) || point.length !== 2 ||
        !point.every((value) => Number.isFinite(value) && value >= 0 && value <= sourceSize))) {
      fail(`${name} must have at least three [x,y] points within the 128x128 source`);
    }
  }
}

function contains(polygon, x, y) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const [xi, yi] = polygon[i], [xj, yj] = polygon[j];
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

function validateBinaryAlpha(raw) {
  let nonBinary = 0;
  for (let i = 3; i < raw.length; i += 4) if (raw[i] !== 0 && raw[i] !== 255) nonBinary += 1;
  if (nonBinary) fail('source.png alpha must be binary 0/255', { nonBinaryAlphaPixels: nonBinary });
}

function makeMasks(raw, rig) {
  const count = sourceSize * sourceSize;
  const owner = new Uint8Array(count); // 0=прозрачно, 1=нижний слой, 2=тело, 3=голова.
  const head = new Uint8Array(count), body = new Uint8Array(count), lower = new Uint8Array(count);
  const headUnderpaint = new Uint8Array(count), lowerUnderpaint = new Uint8Array(count);
  const headSource = new Int32Array(count).fill(-1), bodySource = new Int32Array(count).fill(-1), lowerSource = new Int32Array(count).fill(-1);
  let opaquePixels = 0;
  for (let y = 0; y < sourceSize; y += 1) for (let x = 0; x < sourceSize; x += 1) {
    const index = y * sourceSize + x;
    if (raw[index * 4 + 3] === 0) continue;
    opaquePixels += 1;
    const px = x + 0.5, py = y + 0.5;
    owner[index] = contains(rig.headPolygon, px, py) ? 3 : contains(rig.bodyPolygon, px, py) ? 2 : 1;
    if (owner[index] === 3) { head[index] = 1; headSource[index] = index; }
    else if (owner[index] === 2) { body[index] = 1; bodySource[index] = index; }
    else { lower[index] = 1; lowerSource[index] = index; }
  }
  // Underpaint берёт исходные пиксели по тем же координатам и прекращается на первом прозрачном/чужом пикселе.
  let bodyUnderpaintPixels = 0, lowerUnderpaintPixels = 0;
  for (let x = 0; x < sourceSize; x += 1) {
    let firstBody = -1, firstLower = -1;
    for (let y = 0; y < sourceSize; y += 1) {
      const index = y * sourceSize + x;
      if (firstBody < 0 && owner[index] === 2) firstBody = y;
      if (firstLower < 0 && owner[index] === 1) firstLower = y;
    }
    for (let step = 1; step <= 3 && firstBody >= step; step += 1) {
      const index = (firstBody - step) * sourceSize + x;
      if (owner[index] !== 3) break;
      body[index] = 1; headUnderpaint[index] = 1; bodySource[index] = firstBody * sourceSize + x; bodyUnderpaintPixels += 1;
    }
    for (let step = 1; step <= 3 && firstLower >= step; step += 1) {
      const index = (firstLower - step) * sourceSize + x;
      if (owner[index] === 0 || owner[index] === 1) break;
      lower[index] = 1; lowerUnderpaint[index] = 1; lowerSource[index] = firstLower * sourceSize + x; lowerUnderpaintPixels += 1;
    }
  }
  diagnostics.masks = {
    sourceOpaquePixels: opaquePixels,
    originalHeadPixels: head.reduce((sum, value) => sum + value, 0),
    originalBodyPixels: owner.reduce((sum, value) => sum + (value === 2 ? 1 : 0), 0),
    originalLowerPixels: lower.reduce((sum, value, i) => sum + (value && !lowerUnderpaint[i] ? 1 : 0), 0),
    bodyUnderpaintPixels, lowerUnderpaintPixels,
  };
  return { owner, head, body, lower, headUnderpaint, lowerUnderpaint, headSource, bodySource, lowerSource };
}

function sourceLayer(raw, mask, sourceIndices) {
  const layer = Buffer.alloc(raw.length);
  for (let i = 0; i < mask.length; i += 1) if (mask[i]) {
    const sourceIndex = sourceIndices[i];
    if (sourceIndex < 0) fail('Layer mask pixel has no source-color mapping', { pixelIndex: i });
    raw.copy(layer, i * 4, sourceIndex * 4, sourceIndex * 4 + 4);
  }
  return layer;
}

function alphaCount(raw) {
  let count = 0;
  for (let i = 3; i < raw.length; i += 4) if (raw[i]) count += 1;
  return count;
}

function composite(layers) {
  const out = Buffer.alloc(layers[0].length);
  for (const layer of layers) for (let i = 0; i < layer.length; i += 4) {
    if (layer[i + 3]) layer.copy(out, i, i, i + 4);
  }
  return out;
}

async function upscale(layer, scale) {
  return sharp(layer, { raw: { width: sourceSize, height: sourceSize, channels: 4 } })
    .resize(sourceSize * scale, sourceSize * scale, { kernel: 'nearest' }).raw().toBuffer();
}

function translateY(layer, width, height, dy) {
  const moved = Buffer.alloc(layer.length);
  let clipped = 0;
  for (let y = 0; y < height; y += 1) {
    const targetY = y + dy;
    const rowStart = y * width * 4;
    if (targetY < 0 || targetY >= height) {
      clipped += alphaCount(layer.subarray(rowStart, rowStart + width * 4));
      continue;
    }
    layer.copy(moved, targetY * width * 4, rowStart, rowStart + width * 4);
  }
  return { pixels: moved, clipped };
}

function frameOffset(index, rig, phase) {
  const angle = (2 * Math.PI * phase) / rig.frames;
  return Math.round((-rig.amplitudeNative * rig.scale * (1 - Math.cos(angle))) / 2);
}

function checkNeutral(source, frame, scale) {
  const width = sourceSize * scale;
  let mismatches = 0;
  for (let y = 0; y < sourceSize; y += 1) for (let x = 0; x < sourceSize; x += 1) {
    const sourceOffset = (y * sourceSize + x) * 4;
    for (let py = 0; py < scale; py += 1) for (let px = 0; px < scale; px += 1) {
      const frameOffset = (((y * scale + py) * width) + x * scale + px) * 4;
      if (source[sourceOffset] !== frame[frameOffset] || source[sourceOffset + 1] !== frame[frameOffset + 1] ||
          source[sourceOffset + 2] !== frame[frameOffset + 2] || source[sourceOffset + 3] !== frame[frameOffset + 3]) mismatches += 1;
    }
  }
  return mismatches;
}

function checkHeadParity(source, rendered, mask, dy, scale, roi = null) {
  let checked = 0, mismatches = 0;
  const width = sourceSize * scale;
  for (let sy = 0; sy < sourceSize; sy += 1) for (let sx = 0; sx < sourceSize; sx += 1) {
    if (roi && (sx < roi.x || sx >= roi.x + roi.width || sy < roi.y || sy >= roi.y + roi.height)) continue;
    const sourceIndex = sy * sourceSize + sx;
    if (!mask[sourceIndex]) continue;
    for (let py = 0; py < scale; py += 1) for (let px = 0; px < scale; px += 1) {
      const out = (((sy * scale + py + dy) * width) + sx * scale + px) * 4;
      const original = sourceIndex * 4;
      checked += 1;
      if (rendered[out] !== source[original] || rendered[out + 1] !== source[original + 1] ||
          rendered[out + 2] !== source[original + 2] || rendered[out + 3] !== source[original + 3]) mismatches += 1;
    }
  }
  return { checkedPixels: checked, mismatches };
}

function checkFixedROIs(source, rendered, scale) {
  const width = sourceSize * scale;
  return footROIs.map((roi) => {
    let checkedPixels = 0, mismatches = 0;
    for (let y = roi.y; y < roi.y + roi.height; y += 1) for (let x = roi.x; x < roi.x + roi.width; x += 1) {
      const src = (y * sourceSize + x) * 4;
      for (let py = 0; py < scale; py += 1) for (let px = 0; px < scale; px += 1) {
        const out = (((y * scale + py) * width) + x * scale + px) * 4;
        checkedPixels += 1;
        if (rendered[out] !== source[src] || rendered[out + 1] !== source[src + 1] ||
            rendered[out + 2] !== source[src + 2] || rendered[out + 3] !== source[src + 3]) mismatches += 1;
      }
    }
    return { ...roi, checkedPixels, mismatches };
  });
}

function makeBackground(width, height) {
  const bg = Buffer.alloc(width * height * 4);
  for (let i = 0; i < bg.length; i += 4) {
    bg[i] = 63; bg[i + 1] = 75; bg[i + 2] = 67; bg[i + 3] = 255;
  }
  return bg;
}

function compositeOnBackground(frame, background) {
  const out = Buffer.from(background);
  for (let i = 0; i < frame.length; i += 4) if (frame[i + 3]) frame.copy(out, i, i, i + 4);
  return out;
}

async function writeGif(frames, width, height, file) {
  await sharp(Buffer.concat(frames), { raw: { width, height: height * frames.length, pageHeight: height, channels: 4 } })
    .gif({ loop: 0, delay: Array(frames.length).fill(50), dither: 0, effort: 10, keepDuplicateFrames: true, interFrameMaxError: 0 })
    .toFile(path.join(root, file));
}

async function checkGifFace(file, frames, frameInfo, headMask, scale) {
  const decoded = await sharp(path.join(root, file), { animated: true }).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
  const { width, pageHeight, pages } = decoded.info;
  let checked = 0, mismatches = 0;
  for (let i = 0; i < frames.length; i += 1) {
    const pageBase = i * width * pageHeight * 4;
    const dy = frameInfo[i].headDyDisplayPixels;
    for (let y = 0; y < faceROI.height; y += 1) for (let x = 0; x < faceROI.width; x += 1) {
      const sx = faceROI.x + x, sy = faceROI.y + y, sourceIndex = sy * sourceSize + sx;
      if (!headMask[sourceIndex]) continue;
      const output = pageBase + (((sy * scale + dy) * width) + sx * scale) * 4;
      const expected = (((sy * scale + dy) * width) + sx * scale) * 4;
      checked += 1;
      for (let channel = 0; channel < 4; channel += 1) {
        if (decoded.data[output + channel] !== frames[i][expected + channel]) { mismatches += 1; break; }
      }
    }
  }
  return { pages, checkedPixels: checked, mismatches };
}

async function main() {
  const rig = JSON.parse(fs.readFileSync(rigPath, 'utf8'));
  validateRig(rig);
  const sourceImage = sharp(sourcePath);
  const metadata = await sourceImage.metadata();
  if (metadata.width !== sourceSize || metadata.height !== sourceSize || metadata.channels !== 4) {
    fail('source.png must be 128x128 RGBA', { metadata });
  }
  const source = await sourceImage.ensureAlpha().raw().toBuffer();
  validateBinaryAlpha(source);
  diagnostics.sourceSha256 = crypto.createHash('sha256').update(fs.readFileSync(sourcePath)).digest('hex');
  diagnostics.canvas = { width: sourceSize * rig.scale, height: sourceSize * rig.scale };

  const masks = makeMasks(source, rig);
  const lower = await upscale(sourceLayer(source, masks.lower, masks.lowerSource), rig.scale);
  const body = await upscale(sourceLayer(source, masks.body, masks.bodySource), rig.scale);
  const head = await upscale(sourceLayer(source, masks.head, masks.headSource), rig.scale);
  const width = sourceSize * rig.scale, height = width;
  const neutral = composite([lower, body, head]);
  const neutralMismatches = checkNeutral(source, neutral, rig.scale);
  diagnostics.neutralRGBA = { mismatchedPixels: neutralMismatches, totalPixels: width * height };
  if (neutralMismatches) fail('Neutral composite differs from source RGBA', diagnostics.neutralRGBA);

  const frames = [], frameInfo = [];
  let clippingTotal = 0;
  for (let i = 0; i < rig.frames; i += 1) {
    const bodyDy = frameOffset(i, rig, i);
    const headDy = frameOffset(i, rig, i - rig.headLagFrames);
    const movedLower = translateY(lower, width, height, 0);
    const movedBody = translateY(body, width, height, bodyDy);
    const movedHead = translateY(head, width, height, headDy);
    const clipping = movedLower.clipped + movedBody.clipped + movedHead.clipped;
    clippingTotal += clipping;
    const frame = composite([movedLower.pixels, movedBody.pixels, movedHead.pixels]);
    const faceParity = checkHeadParity(source, frame, masks.head, headDy, rig.scale, faceROI);
    const headParity = checkHeadParity(source, frame, masks.head, headDy, rig.scale);
    if (!faceParity.checkedPixels || !headParity.checkedPixels) fail('Face ROI or original head mask contains no opaque pixels', { frame: i + 1, faceROI });
    const feet = checkFixedROIs(source, frame, rig.scale);
    const frameHash = crypto.createHash('sha256').update(frame).digest('hex');
    frameInfo.push({ frame: i + 1, bodyDyDisplayPixels: bodyDy, headDyDisplayPixels: headDy, sha256: frameHash, faceParity, headMaskParity: headParity, fixedFootROIs: feet, boundaryClippingPixels: clipping });
    frames.push(frame);
  }
  diagnostics.frameHashesAndOffsets = frameInfo;
  diagnostics.boundaryClippingPixels = clippingTotal;
  diagnostics.fixedFootROIs = footROIs;
  const failedFeet = frameInfo.flatMap((frame) => frame.fixedFootROIs.filter((roi) => roi.mismatches).map((roi) => ({ frame: frame.frame, roi: roi.name, mismatches: roi.mismatches })));
  const failedFace = frameInfo.filter((frame) => frame.faceParity.mismatches || frame.headMaskParity.mismatches);
  if (clippingTotal) fail('Layer translation clips opaque pixels outside the 512x512 canvas', { boundaryClippingPixels: clippingTotal });
  if (failedFace.length) fail('Translated face pixels differ from their source pixels', { failedFrames: failedFace.map((frame) => frame.frame) });
  if (failedFeet.length) fail('Fixed foot ROI pixels changed during layered rendering', { failures: failedFeet });

  await fs.promises.mkdir(path.join(root, 'frames'), { recursive: true });
  for (let i = 0; i < frames.length; i += 1) {
    await sharp(frames[i], { raw: { width, height, channels: 4 } }).png()
      .toFile(path.join(root, 'frames', `frame-${String(i + 1).padStart(3, '0')}.png`));
  }
  const backgrounds = Array.from({ length: frames.length }, () => makeBackground(width, height));
  await writeGif(frames, width, height, 'idle-transparent.gif');
  await writeGif(frames.map((frame, i) => compositeOnBackground(frame, backgrounds[i])), width, height, 'preview.gif');

  const sampleIndexes = [0, 6, 13, 20, 27, 34, 41, 47];
  const cellW = width / 2, cellH = width / 2 + 24;
  const samples = await Promise.all(sampleIndexes.map(async (index) => {
    const small = await sharp(compositeOnBackground(frames[index], makeBackground(width, height)),
      { raw: { width, height, channels: 4 } }).resize(cellW, cellW, { kernel: 'nearest' }).png().toBuffer();
    const label = Buffer.from(`<svg width="${cellW}" height="${cellH}"><rect width="100%" height="24" fill="#26312c"/><text x="${cellW / 2}" y="17" text-anchor="middle" fill="#eff1e7" font-family="Arial" font-size="14">FRAME ${String(index + 1).padStart(2, '0')}</text></svg>`);
    return sharp({ create: { width: cellW, height: cellH, channels: 4, background: '#26312c' } })
      .composite([{ input: small, left: 0, top: 24 }, { input: label, left: 0, top: 0 }]).png().toBuffer();
  }));
  await sharp({ create: { width: cellW * 4, height: cellH * 2, channels: 4, background: '#26312c' } })
    .composite(samples.map((input, i) => ({ input, left: (i % 4) * cellW, top: Math.floor(i / 4) * cellH })))
    .png().toFile(path.join(root, 'filmstrip.png'));

  const maskColors = { 1: [218, 190, 94], 2: [78, 169, 198], 3: [203, 108, 153] };
  const maskPreview = Buffer.alloc(source.length);
  for (let i = 0; i < masks.owner.length; i += 1) {
    if (!masks.owner[i]) continue;
    const [r, g, b] = maskColors[masks.owner[i]], at = i * 4;
    maskPreview[at] = r; maskPreview[at + 1] = g; maskPreview[at + 2] = b; maskPreview[at + 3] = source[at + 3];
  }
  await sharp(maskPreview, { raw: { width: sourceSize, height: sourceSize, channels: 4 } })
    .resize(width, height, { kernel: 'nearest' }).png().toFile(path.join(root, 'mask-preview.png'));

  const gifMetadata = {};
  const gifFaceChecks = {};
  for (const [file, expectedWidth, expectedHeight] of [['preview.gif', width, height], ['idle-transparent.gif', width, height]]) {
    const meta = await sharp(path.join(root, file), { animated: true }).metadata();
    gifMetadata[file] = { pages: meta.pages, delay: meta.delay, width: meta.width, pageHeight: meta.pageHeight, loop: meta.loop };
    if (meta.pages !== rig.frames || meta.width !== expectedWidth || meta.pageHeight !== expectedHeight || meta.loop !== 0 ||
        !Array.isArray(meta.delay) || meta.delay.length !== rig.frames || meta.delay.some((delay) => delay !== rig.frameMs)) {
      fail(`${file} metadata does not match rig.json`, { actual: gifMetadata[file] });
    }
    gifFaceChecks[file] = await checkGifFace(file, frames, frameInfo, masks.head, rig.scale);
    if (gifFaceChecks[file].pages !== rig.frames || gifFaceChecks[file].mismatches) {
      fail(`${file} decoded face pixels do not preserve the rendered source face`, { check: gifFaceChecks[file] });
    }
  }
  const report = {
    status: 'validated', sourceSha256: diagnostics.sourceSha256, canvas: diagnostics.canvas,
    motion: { amplitudeNative: rig.amplitudeNative, displayOffsets: frameInfo.map(({ frame, bodyDyDisplayPixels, headDyDisplayPixels }) => ({ frame, bodyDyDisplayPixels, headDyDisplayPixels })), quarterPixelNativeEquivalence: 'One display pixel at scale 4 equals 0.25 native pixels; no pixel values are resampled after nearest upscale.' },
    masks: diagnostics.masks,
    neutralRGBA: diagnostics.neutralRGBA,
    faceROI: { ...faceROI, checkedAcrossFrames: frameInfo.length, parityMismatches: 0 },
    originalHeadMaskParity: { checkedPerFrame: frameInfo[0].headMaskParity.checkedPixels, checkedAcrossFrames: frameInfo.length, mismatches: 0 },
    fixedFootROIs: footROIs,
    boundaryClippingPixels: clippingTotal,
    frameHashes: frameInfo.map(({ frame, sha256 }) => ({ frame, sha256 })),
    gif: gifMetadata,
    gifFaceParity: gifFaceChecks,
    outputs: ['frames/frame-001.png..frame-048.png', 'preview.gif', 'idle-transparent.gif', 'filmstrip.png', 'mask-preview.png', 'rig-validation.json'],
    acceptance: 'Pixel-space diagnostic render; not a statement of animation smoothness or art acceptance.',
  };
  await fs.promises.writeFile(path.join(root, 'rig-validation.json'), `${JSON.stringify(report, null, 2)}\n`);
  console.log(JSON.stringify(report));
}

main().catch(async (error) => {
  const report = { status: 'failed', error: error.message, details: error.details || {}, diagnostics };
  try { await fs.promises.writeFile(path.join(root, 'rig-validation.json'), `${JSON.stringify(report, null, 2)}\n`); } catch (_) { /* До создания выходной папки сбой остаётся в stdout. */ }
  console.error(error.message);
  process.exitCode = 1;
});
