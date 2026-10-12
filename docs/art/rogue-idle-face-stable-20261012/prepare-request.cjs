// После отзыва U голова закреплена; меняется только Y плеч и рук на один пиксель.
// Это ограничение запроса, фактическое лицо в PNG проверяется отдельно.
const fs=require('node:fs'),path=require('node:path');
const original=JSON.parse(fs.readFileSync(path.join(__dirname,'../rogue-idle-20261012/pixellab/request.json'),'utf8'));
const dir=path.join(__dirname,'pixellab');
const joints=original.first_frame_keypoints;
const arms=new Set(['LEFT SHOULDER','RIGHT SHOULDER','LEFT ELBOW','RIGHT ELBOW','LEFT ARM','RIGHT ARM']);
const head=new Set(['NOSE','LEFT EYE','RIGHT EYE','LEFT EAR','RIGHT EAR','NECK']);
const offsets=[];
const poses=Array.from({length:12},(_,i)=>{
 const y=-(1-Math.cos(2*Math.PI*i/12))/2;
 offsets.push(y);
 return joints.map(j=>({...j,y:j.y+(arms.has(j.label)?y/128:0)}));
});
const fixedHead=poses.every(p=>p.every((j,i)=>!head.has(j.label)||JSON.stringify(j)===JSON.stringify(joints[i])));
const fixedOther=poses.every(p=>p.every((j,i)=>arms.has(j.label)||JSON.stringify(j)===JSON.stringify(joints[i])));
if(!fixedHead||!fixedOther) throw Error('Head or legs move in rig');
const request={...original,seed:20261014,keypoints:poses,action:'Quiet minimal breathing idle. The entire head, hood and face remain absolutely still in the exact first-frame position with the exact same shape and expression throughout all frames. No head movement, no nodding, no blinking, no eyebrow or mouth movement, no facial redraw or changing features. Only shoulders and arms rise and settle by one pixel; each arm and its dagger stays rigid. Chest breathes very gently beneath the fixed head. Legs, feet and hips stay fixed. Keep the same face, hood, two straight daggers, clothes, colors and anatomy in every frame. No sway, turning, twisting, steps or effects. Seamless loop.'};
fs.writeFileSync(path.join(dir,'request.json'),JSON.stringify(request,null,2)+'\n');
fs.writeFileSync(path.join(dir,'pose-validation.json'),JSON.stringify({endpoint:'https://api.pixellab.ai/v2/animate-with-skeleton-v3',frames:12,frameMs:200,armAmplitude:1,fixedHead,fixedOther,offsets,note:'Requested fixed head; generated image stability must be checked.'},null,2)+'\n');
console.log(JSON.stringify({fixedHead,fixedOther,frames:12}));
