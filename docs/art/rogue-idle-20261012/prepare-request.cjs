// Нижняя часть остаётся опорой; руки следуют дыханию с задержкой в один кадр.
const fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'pixellab');
const read=(name)=>JSON.parse(fs.readFileSync(path.join(dir,name),'utf8').replace(/^\uFEFF/,''));
const joints=read('skeleton-estimate.json').keypoints;
if(joints.length!==18||new Set(joints.map(j=>j.label)).size!==18) throw Error('Expected 18 unique joints');
const lower=new Set(['LEFT HIP','RIGHT HIP','LEFT KNEE','RIGHT KNEE','LEFT LEG','RIGHT LEG']);
const arms=new Set(['LEFT SHOULDER','RIGHT SHOULDER','LEFT ELBOW','RIGHT ELBOW','LEFT ARM','RIGHT ARM']);
const count=12,amplitude=2,offsets=[];
const poses=Array.from({length:count},(_,i)=>{
 const phase=2*Math.PI*i/count;
 const body=-amplitude*(1-Math.cos(phase))/2;
 const arm=-amplitude*(1-Math.cos(phase-2*Math.PI/count))/2;
 offsets.push({frame:i+1,bodyY:body,armY:arm});
 return joints.map(j=>({...j,y:j.y+(lower.has(j.label)?0:arms.has(j.label)?arm:body)/128}));
});
const fixedXZ=poses.every(p=>p.every((j,i)=>j.x===joints[i].x&&j.z_index===joints[i].z_index));
const lowerFixed=poses.every(p=>p.every((j,i)=>!lower.has(j.label)||j.y===joints[i].y));
const armsRigid=poses.every(p=>['LEFT','RIGHT'].every(side=>{
 const ids=['SHOULDER','ELBOW','ARM'].map(part=>joints.findIndex(j=>j.label===side+' '+part));
 const delta=ids.map(i=>p[i].y-joints[i].y);return delta.every(d=>Math.abs(d-delta[0])<1e-12);
}));
if(!fixedXZ||!lowerFixed||!armsRigid) throw Error('Invalid vertical rig');
const request={
 description:'A male hooded rogue with olive hood and cloth, brown leather armor and boots, muted gray shoulder guards, two short straight steel daggers, one in each gloved hand',
 action:'Quiet breathing idle in the same crouched ready stance. Only subtle vertical rise and settle of head and chest. Each arm and its dagger follows slightly later as one rigid shape. Preserve both straight blades, their tips, face, hood and all equipment. Feet and legs planted. No stepping, turning, sideways sway, twisting, attacking, weapon flourishes, blinking or effects. Seamless quiet loop.',
 direction:'south-east',view:'high top-down',template_id:'mannequin',seed:20261012,no_background:true,
 first_frame:{base64:fs.readFileSync(path.join(dir,'reference-128.png')).toString('base64')},
 first_frame_keypoints:joints,keypoints:poses
};
fs.writeFileSync(path.join(dir,'request.json'),JSON.stringify(request,null,2)+'\n');
fs.writeFileSync(path.join(dir,'pose-validation.json'),JSON.stringify({endpoint:'https://api.pixellab.ai/v2/animate-with-skeleton-v3',frames:count,frameMs:200,amplitudePixels:amplitude,armLagFrames:1,fixedXZ,lowerFixed,armsRigid,offsets,note:'These are requested skeleton constraints, not proof of generated PNG stability.'},null,2)+'\n');
console.log(JSON.stringify({frames:count,fixedXZ,lowerFixed,armsRigid}));
