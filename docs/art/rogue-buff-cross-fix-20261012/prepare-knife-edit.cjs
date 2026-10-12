// Точечная правка трёх плохих поз выполняется PixelLab, не локальной дорисовкой.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const root = __dirname;
const target = path.join(root, 'knife-edit');
assert.ok(!fs.existsSync(path.join(target, 'submission-attempt.json')), 'Edit already submitted');
const frames = [4,5,6].map(index => {
  const source = `buff-01-cross-fixed/pixellab/frame-${String(index).padStart(2,'0')}.png`;
  const data = fs.readFileSync(path.join(root,source));
  return {index, source, sha256:crypto.createHash('sha256').update(data).digest('hex'), frame:{image:{type:'base64',format:'png',base64:data.toString('base64')},size:{width:128,height:128}}};
});
const description = 'Fix ONLY the malformed daggers in these three consecutive animation frames. The crossed weapons wrongly look like four blades, a white propeller or double-ended swords. Replace that weapon tangle with exactly TWO ordinary short steel daggers, one held by each existing hand. Each dagger consists of a brown handle gripped in one fist, a small guard and ONE triangular pointed blade extending from the guard in ONE direction. Two daggers only, two blade tips only. Show the two solid blades crossing once into a clean readable X in front of the chest, with both hands/handles at the LOWER ends of the X and the two pointed tips at the UPPER ends. Nothing silver or pointed extends backwards through or below the fists. Keep correct front/back occlusion at the crossing, do not draw a star, scissors, extra blades or detached fragments. Preserve both hands and the intended crossed gesture. Make this correction consistent across all three frames. Preserve every other part of each input pose: identical face, hood, body, boots, olive cloth, brown leather, pixel shapes, palette, camera, size and position. Do not add or remove equipment except the erroneous extra blade shapes. Transparent 128x128 pixel art; no glow, motion trails or smoothing.';
const request={description,frames:frames.map(f=>f.frame),image_size:{width:128,height:128},seed:2026101232,no_background:true};
fs.writeFileSync(path.join(target,'request.json'),JSON.stringify(request,null,2)+'\n');
fs.writeFileSync(path.join(target,'manifest.json'),JSON.stringify({endpoint:'/v2/edit-animation-v2',purpose:'Targeted correction after first new animation still showed malformed blades in frames4-6',sourceFrames:frames.map(({frame,...f})=>f),description,seed:request.seed},null,2)+'\n');
console.log(JSON.stringify({frames:frames.map(f=>f.index),descriptionLength:description.length}));
