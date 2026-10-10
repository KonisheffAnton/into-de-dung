// Задаёт спокойный общий ритм и небольшое запаздывание рук, сохраняя опору.
// Ограничения суставов описывают запрос PixelLab, но не гарантируют выходные PNG.
const fs=require('node:fs'),path=require('node:path');
const source=path.join(__dirname,'../defender-idle-breathing-20261010/pixellab-breath');
const target=path.join(__dirname,'pixellab');
const request=JSON.parse(fs.readFileSync(path.join(source,'request.json'),'utf8').replace(/^\uFEFF/,''));
const head=new Set(['NOSE','LEFT EYE','RIGHT EYE','LEFT EAR','RIGHT EAR','NECK']);
const frames=12,poses=[],deltas=[];
for(let i=0;i<frames;i++){
 const phase=2*Math.PI*i/frames,inhale=(1-Math.cos(phase))/2;
 const sway=Math.sin(phase),rise=-2.5*inhale;
 const delta={};
 for(const joint of request.first_frame_keypoints){
  const label=joint.label;let x=sway,y=rise;
  if(head.has(label)){x=0.85*Math.sin(phase-0.15);y=rise;}
  else if(label.endsWith('HIP')){x=0.4*sway;y=-0.15*inhale;}
  else if(label.endsWith('KNEE')){x=0.15*sway;y=0;}
  else if(label.endsWith('LEG')){x=0;y=0;}
  else if(label==='LEFT ELBOW'){x+=0.8*Math.sin(phase-0.35);y+=0.65*Math.sin(phase-0.45);}
  else if(label==='LEFT ARM'){x+=2*Math.sin(phase-0.65);y+=1.1*Math.sin(phase-0.65);}
  else if(label==='RIGHT ELBOW'){x-=0.65*Math.sin(phase-0.1);y+=0.5*Math.sin(phase-0.25);}
  else if(label==='RIGHT ARM'){x-=1.5*Math.sin(phase-0.45);y+=0.9*Math.sin(phase-0.4);}
  delta[label]={x,y};
 }
 poses.push(request.first_frame_keypoints.map(j=>({...j,x:j.x+delta[j.label].x/128,y:j.y+delta[j.label].y/128})));
 deltas.push(delta);
}
request.action='Quiet living idle breathing, staying in the same facing direction. Gentle weight sway through hips and chest. Relaxed elbows flex slightly; shield arm and sword hand softly follow the breath with a small delayed settling motion. Shield and sword move subtly with their hands, not rigidly glued to the torso. Boots planted. Calm, restrained motion, no turn, no looking around, no step, no attack.';
request.keypoints=poses;
fs.mkdirSync(target,{recursive:true});
fs.copyFileSync(path.join(source,'reference-128.png'),path.join(target,'reference-128.png'));
const valid=poses.every(p=>p.length===18&&p.every(j=>j.x>=0&&j.x<=1&&j.y>=0&&j.y<=1));
const feetFixed=deltas.every(d=>['LEFT LEG','RIGHT LEG'].every(l=>d[l].x===0&&d[l].y===0));
const zFixed=poses.every(p=>p.every((j,i)=>j.z_index===request.first_frame_keypoints[i].z_index));
if(!valid||!feetFixed||!zFixed)throw Error('Invalid pose contract');
fs.writeFileSync(path.join(target,'request.json'),JSON.stringify(request,null,2)+'\n');
fs.writeFileSync(path.join(target,'pose-validation.json'),JSON.stringify({frames,periodMs:2400,delayMs:200,valid,feetFixed,zFixed,seed:request.seed,deltasPixels:deltas,note:'Head landmarks translate together, facing geometry unchanged. Arms have relative follow-through. Exact output must be reviewed.'},null,2)+'\n');
console.log(JSON.stringify({frames,valid,feetFixed,zFixed,actionLength:request.action.length}));
