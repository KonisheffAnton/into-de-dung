// Сохраняет исходные позы: одинаковый таймлайн нужен для сравнения ритма без интерполяции.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');

const root = __dirname;
const frameSize = 96;
const sourceSize = 128;
const ticks = 24;
const tickMs = 100;
const loopMs = ticks * tickMs;

function orderedFrames(directory) {
  return fs.readdirSync(directory)
    .filter((name) => /^frame-\d+\.png$/.test(name))
    .sort((a, b) => Number(a.match(/\d+/)[0]) - Number(b.match(/\d+/)[0]));
}

async function readPose(file) {
  const metadata = await sharp(file).metadata();
  if (metadata.width !== sourceSize || metadata.height !== sourceSize) {
    throw new Error(`${path.basename(file)} must be ${sourceSize}x${sourceSize}`);
  }
  const pixels = await sharp(file).ensureAlpha().raw().toBuffer();
  // Поле должно быть пустым: его удаление не должно срезать часть рисунка.
  for (let y = 0; y < sourceSize; y += 1) {
    for (let x = 0; x < sourceSize; x += 1) {
      if (x >= 16 && x < 112 && y >= 16 && y < 112) continue;
      if (pixels[(y * sourceSize + x) * 4 + 3] >= 128) {
        throw new Error(`Opaque content outside 16px crop: ${path.basename(file)}`);
      }
    }
  }
  return sharp(file).extract({ left: 16, top: 16, width: frameSize, height: frameSize })
    .ensureAlpha().raw().toBuffer();
}

function poseAt(poses, tick) {
  return poses[Math.floor(tick * poses.length / ticks)];
}

async function writeGif(frames, width, height, filename) {
  await sharp(Buffer.concat(frames), {
    raw: { width, height: height * frames.length, channels: 4, pageHeight: height },
  }).gif({ loop: 0, delay: Array(frames.length).fill(tickMs), dither: 0, effort: 10 })
    .toFile(path.join(root, filename));
}

async function makeComparisonFrame(previousPose, swayPose) {
  const width = 800;
  const height = 590;
  const labels = Buffer.from(`<svg width="${width}" height="${height}">
    <g fill="#e6eadc" font-size="20" font-family="Arial" text-anchor="middle">
      <text x="200" y="42">PREVIOUS IDLE</text><text x="600" y="42">PIXELLAB · SOFT SWAY</text>
    </g>
    <g fill="#a7b49b" font-size="16" font-family="Arial">
      <text x="24" y="78">80% art scale · enlarged ×4 · matched 2.4 s / 24 × 100 ms</text>
      <text x="24" y="438">Camera 75% / 100% / 125% · approximate display size</text>
    </g></svg>`);
  const layers = [{ input: labels, left: 0, top: 0 }];
  for (const [column, pose] of [[0, previousPose], [1, swayPose]]) {
    const largeSize = Math.round(frameSize * 0.8 * 4);
    const large = await sharp(pose, { raw: { width: frameSize, height: frameSize, channels: 4 } })
      .resize(largeSize, largeSize, { kernel: 'nearest' }).png().toBuffer();
    layers.push({ input: large, left: Math.round(400 * (column + 0.5) - largeSize / 2), top: 95 });
    for (let zoom = 0; zoom < 3; zoom += 1) {
      const size = Math.round(frameSize * 0.8 * [0.75, 1, 1.25][zoom]);
      const image = await sharp(pose, { raw: { width: frameSize, height: frameSize, channels: 4 } })
        .resize(size, size, { kernel: 'nearest' }).png().toBuffer();
      layers.push({ input: image,
        left: Math.round(400 * column + 400 * (zoom + 0.5) / 3 - size / 2), top: 561 - size });
    }
  }
  return sharp({ create: { width, height, channels: 4, background: '#27312b' } })
    .composite(layers).raw().toBuffer();
}

async function main() {
  const previousDir = path.join(root, '..', 'defender-idle-breathing-20261010', 'pixellab-breath');
  const swayDir = path.join(root, 'pixellab');
  const previousNames = orderedFrames(previousDir);
  const swayNames = orderedFrames(swayDir);
  if (previousNames.length !== 8) throw new Error(`Expected 8 previous poses, got ${previousNames.length}`);
  if (swayNames.length !== 12) throw new Error(`Expected 12 sway poses, got ${swayNames.length}`);

  const previousPoses = await Promise.all(previousNames.map((name) => readPose(path.join(previousDir, name))));
  const swayPoses = await Promise.all(swayNames.map((name) => readPose(path.join(swayDir, name))));
  const reference = await readPose(path.join(swayDir, 'reference-128.png'));
  const timeline = Array.from({ length: ticks }, (_, tick) =>
    makeComparisonFrame(poseAt(previousPoses, tick), poseAt(swayPoses, tick)));
  const comparisonFrames = await Promise.all(timeline);
  await writeGif(comparisonFrames, 800, 590, 'comparison.gif');
  await sharp(comparisonFrames[0], { raw: { width: 800, height: 590, channels: 4 } })
    .png().toFile(path.join(root, 'comparison-still.png'));

  const nativeFrames = Array.from({ length: swayPoses.length }, (_, i) => swayPoses[i]);
  await sharp(Buffer.concat(nativeFrames), {
    raw: { width: frameSize, height: frameSize * nativeFrames.length, channels: 4, pageHeight: frameSize },
  }).gif({ loop: 0, delay: Array(nativeFrames.length).fill(200), dither: 0, effort: 10 })
    .toFile(path.join(root, 'idle-native.gif'));

  const cell = 288;
  const strip = await Promise.all(swayPoses.map((pose) => sharp(pose,
    { raw: { width: frameSize, height: frameSize, channels: 4 } })
    .resize(cell, cell, { kernel: 'nearest' }).png().toBuffer()));
  await sharp({ create: { width: cell * 6, height: cell * 2, channels: 4, background: '#27312b' } })
    .composite(strip.map((input, i) => ({ input, left: (i % 6) * cell, top: Math.floor(i / 6) * cell })))
    .png().toFile(path.join(root, 'filmstrip.png'));

  const comparisonMetadata = await sharp(path.join(root, 'comparison.gif'), { animated: true }).metadata();
  const nativeMetadata = await sharp(path.join(root, 'idle-native.gif'), { animated: true }).metadata();
  const info = {
    inputs: {
      previousDirectory: path.relative(root, previousDir), previousFrames: previousNames,
      swayDirectory: path.relative(root, swayDir), swayFrames: swayNames,
      reference: path.relative(root, path.join(swayDir, 'reference-128.png')),
    },
    counts: { previousSource: previousPoses.length, swaySource: swayPoses.length,
      comparisonTicks: ticks, nativeSwayFrames: nativeFrames.length },
    durations: { comparisonTickMs: tickMs, comparisonCycleMs: loopMs,
      previousPoseHoldMs: loopMs / previousPoses.length, swayPoseHoldMs: loopMs / swayPoses.length,
      nativeFrameMs: 200, nativeCycleMs: nativeFrames.length * 200 },
    transforms: {
      source: '128x128 input; remove exactly 16px transparent padding on each edge to 96x96',
      cropValidation: 'reject alpha >= 128 in the removed border',
      display: 'nearest-neighbor enlargement only; 80% art scale, large view x4, approximate camera 75/100/125%',
      playback: 'repeat source poses on fixed ticks; no interpolation, registration, or pose drawing',
      comparison: 'previous 8 poses held 300ms; new 12 poses held 200ms on shared 24 x 100ms loop',
      native: 'new 12 poses in source order, 200ms each',
      reference: 'cropped source reference used for input validation only',
    },
    gif: {
      comparison: { pages: comparisonMetadata.pages, delay: comparisonMetadata.delay,
        width: comparisonMetadata.width, pageHeight: comparisonMetadata.pageHeight },
      native: { pages: nativeMetadata.pages, delay: nativeMetadata.delay,
        width: nativeMetadata.width, pageHeight: nativeMetadata.pageHeight },
    },
  };
  fs.writeFileSync(path.join(root, 'preview.json'), `${JSON.stringify(info, null, 2)}\n`);
  console.log(JSON.stringify(info));
}

main().catch((error) => { console.error(error.message); process.exitCode = 1; });
