// Только вертикальные переносы: руки сохраняют внутреннюю геометрию и слегка запаздывают.
// Суставные ограничения проверяют запрос; сгенерированные PNG требуют отдельного просмотра.
const fs=require('node:fs'),path=require('node:path');
const source=path.join(__dirname,'../defender-idle-breathing-20261010/pixellab-breath');
const target=path.join(__dirname,'pixellab');
const request=JSON.parse(fs.readFileSync(path.join(source,'request.json'),'utf8').replace(/^\uFEFF/,''));
const frames=12,delayMs=200,amplitude=3,armLagFrames=1;
const fixed=new Set(['LEFT HIP','RIGHT HIP','LEFT KNEE','RIGHT KNEE','LEFT LEG','RIGHT LEG']);
const arms=new Set(['LEFT SHOULDER','RIGHT SHOULDER','LEFT ELBOW','RIGHT ELBOW','LEFT ARM','RIGHT ARM']);
const poses=[],offsets=[];
for(let i=0;i<frames;i++){
 const phase=2*Math.PI*i/frames;
 const bodyY=-amplitude*(1-Math.cos(phase))/2;
 const armY=-amplitude*(1-Math.cos(phase-2*Math.PI*armLagFrames/frames))/2;
 const dy=request.first_frame_keypoints.map(j=>fixed.has(j.label)?0:arms.has(j.label)?armY:bodyY);
 poses.push(request.first_frame_keypoints.map((j,k)=>({...j,y:j.y+dy[k]/128})));
 offsets.push({frame:i+1,bodyY,armsY:armY,lowerBodyY:0});
}
request.action='Simple quiet breathing idle. Only straight vertical up and down movement. Head and torso rise and settle; both arms, shield and sword follow slightly later as rigid shapes. Preserve all horizontal positions and shapes. No sideways movement, no sway, no bending or twisting, no rotation or turning. Feet firmly planted.';
request.keypoints=poses;
const allXAndZFixed=poses.every(p=>p.every((j,i)=>j.x===request.first_frame_keypoints[i].x&&j.z_index===request.first_frame_keypoints[i].z_index));
const lowerBodyFixed=poses.every(p=>p.every((j,i)=>!fixed.has(j.label)||j.y===request.first_frame_keypoints[i].y));
const armGeometryFixed=poses.every(p=>['LEFT','RIGHT'].every(side=>{
 const ids=['SHOULDER','ELBOW','ARM'].map(part=>request.first_frame_keypoints.findIndex(j=>j.label===side+' '+part));
 const deltas=ids.map(i=>p[i].y-request.first_frame_keypoints[i].y);
 return deltas.every(d=>Math.abs(d-deltas[0])<1e-12);
}));
if(!allXAndZFixed||!lowerBodyFixed||!armGeometryFixed)throw Error('Vertical motion contract failed');
fs.mkdirSync(target,{recursive:true});
fs.copyFileSync(path.join(source,'reference-128.png'),path.join(target,'reference-128.png'));
fs.writeFileSync(path.join(target,'request.json'),JSON.stringify(request,null,2)+'\n');
fs.writeFileSync(path.join(target,'pose-validation.json'),JSON.stringify({frames,delayMs,cycleMs:frames*delayMs,amplitudePixels:amplitude,armLagFrames,armLagMs:armLagFrames*delayMs,allXAndZFixed,lowerBodyFixed,armGeometryFixed,offsetsPixels:offsets,note:'No X motion. Each whole arm translates vertically without changing internal joint geometry. These checks do not prove generated image geometry.'},null,2)+'\n');
console.log(JSON.stringify({frames,allXAndZFixed,lowerBodyFixed,armGeometryFixed}));
