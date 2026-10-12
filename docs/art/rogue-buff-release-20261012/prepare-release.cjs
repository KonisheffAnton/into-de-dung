// Выход из исправленного креста генерирует PixelLab; локальных поз/интерполяции нет.
const fs=require('node:fs'), path=require('node:path'), crypto=require('node:crypto'), assert=require('node:assert/strict');
const root=__dirname, dir=path.join(root,'release');
fs.mkdirSync(dir,{recursive:true});
assert.ok(!fs.existsSync(path.join(dir,'submission-attempt.json')), 'Already submitted');
const first='blade-size-refine/pixellab/frame-04.png', last='reference-128.png';
const makeImage=file=>({type:'base64',format:'png',base64:fs.readFileSync(path.join(root,file)).toString('base64')});
const action='From this crossed-dagger pose, FORCEFULLY SNAP both hands apart outward and downward into the supplied low ready end pose. Explosive start: the FIRST movement after the X hold covers most of the whole distance, driven by a brief strong chest and shoulder effort. Then decelerate: each later movement is much smaller, settling firmly with a tiny follow-through into the exact end pose. No slow initial opening, no extra windup, no reversal or bouncing. Exactly TWO rigid daggers keep the original neutral-reference blade length, width and hilt size in EVERY frame, even while turning. Never shrink, stretch, bend, split or duplicate either dagger; no backward blades, fragments or trails. Hands firmly grip the hilts. Head, face and hood stay rigid together; no expression change. Boots stay planted in the same positions. Preserve pixel style, palette, body proportions, camera and scale, transparent 128x128. No glow, smear, blur or target attack.';
assert.ok(action.length<=1000, action.length);
fs.writeFileSync(path.join(dir,'request.json'),JSON.stringify({first_frame:makeImage(first),last_frame:makeImage(last),action,frame_count:4,seed:2026101243,no_background:true,enhance_prompt:false},null,2)+'\n');
const digest=file=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex');
fs.writeFileSync(path.join(dir,'manifest.json'),JSON.stringify({endpoint:'/v2/animate-with-text-v3',first,last,firstSha256:digest(first),lastSha256:digest(last),action,seed:2026101243,requestedFrames:4},null,2)+'\n');
console.log(JSON.stringify({actionLength:action.length,requestedFrames:4}));
