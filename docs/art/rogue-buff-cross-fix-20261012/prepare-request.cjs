// PixelLab создаёт новые позы; локально сохраняем только запрос и происхождение.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = __dirname;
const variant = {id: 'buff-01-cross-fixed', kind: 'buff', title: 'B1 — резкий крест, два кинжала', seed: 2026101231};
const dir = path.join(root, variant.id, 'pixellab');
assert.ok(!fs.existsSync(path.join(dir, 'submission-attempt.json')), 'Already submitted; do not resubmit');
const png = fs.readFileSync(path.join(root, 'reference-128.png'));
const sourceSha256 = crypto.createHash('sha256').update(png).digest('hex');
assert.equal(sourceSha256, 'ccf04fbb0c7b73fce0eba232ce5e595c7c2d037b7a9a8eaa176309e6ad11dbb5');
const action = 'One snappy self-buff gesture, not an attack. From this ready stance, sharply raise BOTH hands, cross the TWO dagger blades into an X in front of the chest, hold with a firm stop, then briskly uncross and return to the exact initial stance. Each hand always holds ONE short single-ended dagger: one hilt and one blade only. At the X, both fists and hilts stay BELOW the crossing and exactly TWO blade tips point upward; NO blade extends below a fist. Keep a clear overlap where one blade passes in front of the other. No extra knives, mirrored blades, double-ended blades, ghost copies, trails, smears or detached weapon parts at any time. Strong discrete key poses, quick transitions, short accent hold, no slow flowing motion. Boots fixed. Face and hood stay unchanged and move together with chest. Preserve original olive/brown palette, proportions, crisp pixels, camera and scale. Whole figure and both weapons inside transparent 128x128. No glow or added objects.';
assert.ok(action.length <= 1000, action.length);
const image = {type: 'base64', format: 'png', base64: png.toString('base64')};
const request = {first_frame: image, last_frame: image, action, frame_count: 8, seed: variant.seed, no_background: true, enhance_prompt: false};
fs.writeFileSync(path.join(dir, 'request.json'), JSON.stringify(request, null, 2) + '\n');
fs.writeFileSync(path.join(root, 'request-manifest.json'), JSON.stringify({
  base: 'a3ed01be6f26d8ce56796b9c01f85c00c41adc92', provider: 'PixelLab',
  endpoint: '/v2/animate-with-text-v3', source: '../rogue-buff-death-variants-20261012/reference-128.png', sourceSha256,
  requestedFrames: 8, frameMs: 200, previewDurationsMs: [200,80,80,120,240,80,80,100,200],
  scope: 'User selected B1 for correction: sharper motion and exactly two daggers while crossed. D3 death accepted unchanged; no runtime integration.',
  variants: [{...variant, action}]
}, null, 2) + '\n');
console.log(JSON.stringify({variant: variant.id, actionLength: action.length, requestedFrames: 8, sourceSha256}));
