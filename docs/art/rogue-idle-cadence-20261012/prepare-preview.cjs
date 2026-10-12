// Пользователь выбрал это движение; меняем только частоту смены готовых кадров.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = __dirname;
const sourcePath = path.join(root, 'user-reference.gif');
const sourceSha256 = '9604a22eacb6c5ac4c9bf55b8d9db2ad6f0f33059149c1f96961c09308f39fa9';
const hash = data => crypto.createHash('sha256').update(data).digest('hex');

(async () => {
  assert.equal(hash(fs.readFileSync(sourcePath)), sourceSha256, 'Source GIF changed');
  const metadata = await sharp(sourcePath, { animated: true }).metadata();
  assert.equal(metadata.width, 512);
  assert.equal(metadata.pageHeight, 512);
  assert.equal(metadata.pages, 48);
  assert.deepEqual(metadata.delay, Array(48).fill(50));
  const { data, info } = await sharp(sourcePath, { animated: true }).ensureAlpha()
    .raw().toBuffer({ resolveWithObject: true });
  assert.equal(info.channels, 4);
  const frameBytes = 512 * 512 * 4;
  assert.equal(data.length, 48 * frameBytes);
  const indices = Array.from({ length: 12 }, (_, index) => index * 4);
  const frames = indices.map(index => data.subarray(index * frameBytes, (index + 1) * frameBytes));
  const output = path.join(root, 'preview.gif');
  // Повторяющиеся позы оставляем отдельными слотами по 200 мс, как у эталона.
  await sharp(Buffer.concat(frames), { raw: { width: 512, height: 512 * 12, channels: 4, pageHeight: 512 } })
    .gif({ loop: 0, delay: Array(12).fill(200), dither: 0, effort: 10,
      keepDuplicateFrames: true, interFrameMaxError: 0 }).toFile(output);
  const decodedMetadata = await sharp(output, { animated: true }).metadata();
  assert.equal(decodedMetadata.pages, 12);
  assert.deepEqual(decodedMetadata.delay, Array(12).fill(200));
  assert.equal(decodedMetadata.loop, 0);
  const decoded = await sharp(output, { animated: true }).ensureAlpha().raw().toBuffer();
  assert.equal(decoded.length, frameBytes * 12);
  const selection = frames.map((frame, i) => {
    const result = decoded.subarray(i * frameBytes, (i + 1) * frameBytes);
    assert.ok(frame.equals(result), `GIF changed source pixels in output frame ${i + 1}`);
    return { outputFrame: i + 1, sourceFrame: indices[i] + 1, sourceTimeMs: indices[i] * 50,
      durationMs: 200, decodedRgbaSha256: hash(frame) };
  });
  const tiles = await Promise.all(frames.map(async (frame, i) => ({
    input: await sharp(frame, { raw: { width: 512, height: 512, channels: 4 } })
      .resize(256, 256, { kernel: 'nearest' }).png().toBuffer(),
    left: (i % 4) * 256, top: Math.floor(i / 4) * 256,
  })));
  await sharp({ create: { width: 1024, height: 768, channels: 4, background: '#3f4b43' } })
    .composite(tiles).png().toFile(path.join(root, 'filmstrip.png'));
  const validation = {
    source: 'user-reference.gif', sourceSha256,
    sourceMatches: '../rogue-idle-layered-20261012/preview.gif',
    sourceFrames: 48, sourceFrameMs: 50, sourceCycleMs: 2400,
    reference: '../../../assets/art_presets/trials/defender_idle_v1/README.md',
    referenceFrameCount: 12, referenceFrameMs: 200, referenceCycleMs: 2400,
    outputFrames: 12, outputFrameMs: 200, outputCycleMs: 2400,
    decodedRgbaParity: true, allSourcePixelsPreserved: true,
    selection, outputSha256: hash(fs.readFileSync(output)),
    scope: 'Only frame selection and duration. No pose drawing, blending, interpolation, provider calls or runtime changes.',
    acceptance: 'User chose the supplied motion as the basis for cadence correction; final approval remains open.',
  };
  fs.writeFileSync(path.join(root, 'validation.json'), JSON.stringify(validation, null, 2) + '\n');
  console.log(JSON.stringify({ frames: 12, frameMs: 200, cycleMs: 2400, decodedRgbaParity: true, sourceFrames: selection.map(x => x.sourceFrame) }));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
