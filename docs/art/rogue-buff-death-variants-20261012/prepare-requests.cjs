// Все новые позы создаёт PixelLab; этот скрипт только сохраняет явные задания.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = __dirname;
const source = path.join(root, '..', 'rogue-idle-layered-20261012', 'source.png');
const png = fs.readFileSync(source);
const sha256 = crypto.createHash('sha256').update(png).digest('hex');
assert.equal(sha256, 'ccf04fbb0c7b73fce0eba232ce5e595c7c2d037b7a9a8eaa176309e6ad11dbb5');
fs.writeFileSync(path.join(root, 'reference-128.png'), png);
const image = { type: 'base64', format: 'png', base64: png.toString('base64') };
const shared = ' Same hooded rogue, olive cloth, brown leather, exactly two steel daggers, same pixel-art style, palette, proportions, fixed high top-down three-quarter camera and scale. Preserve the same face under the hood: no changing eyes, nose, mouth or expression; no talking or blinking. Keep the entire figure and both weapons inside the transparent 128x128 canvas. No added objects, glow, smoke, blood, trails, flashes or background. Crisp discrete readable key poses, no rubbery deformation.';
const variants = [
  { id: 'buff-01-cross', title: 'B1 — Клинки крестом', kind: 'buff', seed: 2026101221,
    motion: 'Self-empowerment readiness gesture, not an attack. From the supplied low stance, raise both daggers close to the chest into a clear X below the chin, pause with focus, then separate the hands outward and lower them back to the exact initial pose. Keep the face visible and both boots planted. No forward lunge, no slash at a target.' },
  { id: 'buff-02-grip', title: 'B2 — Перехват кинжалов', kind: 'buff', seed: 2026101222,
    motion: 'Self-empowerment weapon-readiness gesture, not an attack. Keep both boots fixed. Lift the dagger hands beside the torso, briefly rotate the wrists inward to re-seat both grips while always firmly holding the daggers, then set the arms decisively back into the exact initial low ready pose. Small controlled motion, no spinning or tossing weapons, no forward lunge.' },
  { id: 'buff-03-focus', title: 'B3 — Низкая стойка', kind: 'buff', seed: 2026101223,
    motion: 'Self-empowerment concentration gesture, not an attack. With feet firmly planted, sink into a slightly lower coiled crouch, pull both elbows close back beside the waist with dagger tips angled outward and down, briefly hold the focused pose, then rise slightly and relax into the exact initial ready stance. Head and hood move together with the chest. No forward lunge or attack swing.' },
  { id: 'death-01-forward', title: 'D1 — Вперёд', kind: 'death', seed: 2026101224,
    motion: 'One non-looping death animation. From the supplied stance the knees buckle, the torso folds forward, the rogue drops onto both knees and collapses forward, finishing face-down on the ground. Both daggers remain close to the hands beside the body. A heavy final settle, then the entire prone body stays completely motionless and visible through the last frames. Never stand up, recover, fade out or vanish.' },
  { id: 'death-02-back', title: 'D2 — Назад', kind: 'death', seed: 2026101225,
    motion: 'One non-looping death animation. From the supplied stance the rogue loses strength, shoulders lean backward, knees fold and the body falls back onto its back, slightly diagonal with the hooded head visible. Arms drop with the two daggers close beside the body. Finish fully lying down with a small heavy settle, then remain completely motionless and visible through the last frames. Never stand up, roll away, recover, fade out or vanish.' },
  { id: 'death-03-side', title: 'D3 — На бок', kind: 'death', seed: 2026101226,
    motion: 'One non-looping death animation. From the supplied stance one knee gives way, the rogue drops to that knee, loses balance and slumps onto the left side in a compact curled pose, hooded head low near the ground. Both daggers settle close beside the hands. Finish entirely lying on the side, then the body stays completely motionless and visible through the last frames. No recovery, standing up, rolling away, fading or disappearance.' },
];
for (const variant of variants) {
  const action = variant.motion + shared;
  assert.ok(action.length <= 1000, `${variant.id} prompt too long: ${action.length}`);
  const dir = path.join(root, variant.id, 'pixellab');
  fs.mkdirSync(dir, { recursive: true });
  assert.ok(!fs.existsSync(path.join(dir, 'submission-attempt.json')), 'Already submitted: ' + variant.id);
  const request = { first_frame: image, action, frame_count: 12, seed: variant.seed,
    no_background: true, enhance_prompt: false };
  if (variant.kind === 'buff') request.last_frame = image;
  fs.writeFileSync(path.join(dir, 'request.json'), JSON.stringify(request, null, 2) + '\n');
  variant.action = action;
  delete variant.motion;
}
fs.writeFileSync(path.join(root, 'request-manifest.json'), JSON.stringify({
  base: '21481904e2dcc51ffdcba56badbc870bd37ad73d', provider: 'PixelLab',
  endpoint: '/v2/animate-with-text-v3', source: '../rogue-idle-layered-20261012/source.png',
  sourceSha256: sha256, requestedFrames: 12, frameMs: 200,
  scope: 'Six explicitly requested distinct animation proposals; one submission per variant. No runtime integration or new mechanics.', variants,
}, null, 2) + '\n');
console.log(JSON.stringify(variants.map(v => ({ id: v.id, kind: v.kind, promptLength: v.action.length }))));
