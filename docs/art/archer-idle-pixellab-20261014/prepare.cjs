// Только форматирование входа: общий nearest-resize, без ретуши позы или alpha.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
const root = __dirname;
const repo = path.resolve(root, '../../..');
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
function save(name, bytes) {
  const target = path.join(root, name);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  if (fs.existsSync(target) && !fs.readFileSync(target).equals(Buffer.from(bytes))) {
    throw new Error('Refuse to overwrite a different trial file: ' + name);
  }
  fs.writeFileSync(target, bytes);
}
async function main() {
  const source = fs.readFileSync(path.join(root, '../archer-reference-20261012/archer-clean.png'));
  const video = fs.readFileSync('D:/Downloads/03_animate-pixminimax_subtle_raw.gif.mp4');
  const preset = fs.readFileSync('D:/Downloads/втдн/жопа/preset_03_pixminimax_subtle.md');
  save('source/archer-clean.png', source);
  save('source/user-motion.mp4', video);
  save('source/user-preset.md', preset);
  const input = await sharp(source).resize(128, 128, {fit:'fill', kernel:'nearest'}).png().toBuffer();
  save('pixellab/reference-128.png', input);
  const description = 'Extremely subtle idle breathing, barely visible: the chest and shoulders lift by a single pixel and settle back, the head follows one frame later by a single pixel. Everything else holds perfectly still: feet, legs, hips, bow, string and hands keep their exact pixels; the face, eyes, hair outline and ponytail keep their exact shape. No bobbing of the whole body, no swaying, no stepping, no blinking. One complete seamless breath, return exactly to the starting stance. Preserve the reference palette and broad clean pixel clusters; crisp stepped edges, no dithering, grain, gradients, extra details, motion blur, lighting changes or camera movement.';
  const image = {type:'base64', base64:input.toString('base64'), format:'png'};
  const request = {
    first_frame:image, last_frame:image, description,
    frame_count:12, seed:20261014, no_background:true, drift_threshold:0, enhance_prompt:false,
    direction:'east', view:'high top-down',
    subject_description:'An adult female archer with a high dark brown ponytail, olive scarf, brown leather pauldrons, bracers and boots, quiver with white-fletched arrows on her back, holding one wooden bow; muted earthy colors, charcoal brown outlines, matte broad pixel clusters.',
    initial_pose:'Standing in a wide ready stance with knees slightly bent, bow lowered in the hand on the right side of the image, the other arm hanging down. Both feet firmly planted, same full-body framing and fixed three-quarter overhead camera as the reference.'
  };
  if (description.length > 1000 || request.subject_description.length > 300 || request.initial_pose.length > 300) throw Error('Caption too long');
  save('pixellab/request.json', JSON.stringify(request, null, 2) + '\n');
  save('prompt.txt', ['DESCRIPTION', description, '\nSUBJECT', request.subject_description, '\nINITIAL POSE', request.initial_pose].join('\n') + '\n');
  const {first_frame, last_frame, ...settings} = request;
  const manifest = {
    base:'e5efedb42a64817059b8e4063ce2ed45e0513846', endpoint:'https://api.pixellab.ai/v2/animate-pixminimax',
    ...settings, width:128, height:128, first_last_same_reference:true,
    source_sha256:{clean:sha(source), video:sha(video), preset:sha(preset)}, input_sha256:sha(input),
    openapi_sha256:sha(fs.readFileSync(path.join(repo,'test_reports/archer-idle-pixellab-20261014/openapi.json'))),
    transformation:'Whole 1254x1254 RGBA source resized uniformly to 128x128 with nearest-neighbor; no crop, recoloring, alpha cleanup or pose edits.',
    motion_reference:'The MP4 and user preset were inspected. Only the clean PNG plus textual motion instructions are sent; this endpoint has no video/motion-frame input.',
    choice:'transfer-outfit-v2 accepts 13 guides only at <=64 output. Use one new 128px generation with the supplied subtle preset instead of reducing native detail or batching motion.',
    timing:{expected_frames:13, milliseconds_per_frame:200, expected_total_ms:2600},
    scope:'One isolated candidate. Preserve all provider PNGs. No game integration or acceptance; 90% Defender height remains a display-size target.'
  };
  save('request-manifest.json', JSON.stringify(manifest,null,2)+'\n');
  console.log(JSON.stringify({width:128,height:128,frame_count:12,description_chars:description.length,input_sha256:sha(input)}));
}
main().catch(e => { console.error(e); process.exitCode=1; });
