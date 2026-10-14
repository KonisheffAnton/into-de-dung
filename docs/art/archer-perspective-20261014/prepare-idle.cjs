// Только равномерный nearest-вход для API; позы и alpha не ретушируются.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require(process.env.SHARP_MODULE||'sharp');
const out=path.join(__dirname,'pixellab');
const description='One quiet idle breathing cycle: almost motionless hold, a very slight slow inhale in the upper chest and scarf, then an equally slight exhale back to the exact starting pose. Maximum one pixel of chest movement at 128px. No swaying or translation of the body, no change of stance or camera. Feet, knees, hips, head, ponytail, hands, bow and bowstring remain fixed in position and shape. Keep the same crouch and depth between the near and far foot. Do not straighten the legs or lift the body. No gesture, aiming, stepping, blinking, weapon motion, squash or stretching. The last frame returns to the first for a seamless quiet loop.';
(async()=>{
 fs.mkdirSync(out,{recursive:true});
 const original=fs.readFileSync(path.join(__dirname,'archer-corrected.png'));
 const ref=await sharp(original).resize(128,128,{fit:'contain',kernel:'nearest',background:{r:0,g:0,b:0,alpha:0}}).png().toBuffer();
 fs.writeFileSync(path.join(out,'reference-128.png'),ref);
 const encoded={type:'base64',base64:ref.toString('base64'),format:'png'};
 const request={first_frame:encoded,last_frame:encoded,description,frame_count:12,seed:2026101407,
  no_background:true,drift_threshold:0,enhance_prompt:false,view:'high top-down',direction:'south-east',
  subject_description:'A female archer with a dark ponytail, olive scarf, brown leather armor, back quiver and one lowered wooden bow.',
  initial_pose:'A compact wide crouched guard stance seen from an elevated isometric camera, torso turned three-quarter south-east, far boot higher in image space, near boot lower, bow held low on viewer-right.'};
 fs.writeFileSync(path.join(out,'request.json'),JSON.stringify(request,null,2)+'\n');
 fs.writeFileSync(path.join(out,'prompt.txt'),description+'\n');
 const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
 const manifest={endpoint:'https://api.pixellab.ai/v2/animate-pixminimax',schema:'AnimatePixminimaxRequest',
  source:'archer-corrected.png',source_sha256:hash(original),reference_sha256:hash(ref),reference_size:[128,128],
  preparation:'uniform nearest resize of complete RGBA source; no threshold, paint, pose edit or background removal',
  first_equals_last:true,requested_frames:12,cycle_ms:2600,request_sha256:hash(fs.readFileSync(path.join(out,'request.json'))),
  scope:'One separate idle trial. Preserve all returned PNGs unchanged; no game integration.'};
 fs.writeFileSync(path.join(out,'request-manifest.json'),JSON.stringify(manifest,null,2)+'\n');
 console.log(JSON.stringify({reference_size:[128,128],requested_frames:12,reference_sha256:manifest.reference_sha256}));
})().catch(e=>{console.error(e);process.exitCode=1;});
