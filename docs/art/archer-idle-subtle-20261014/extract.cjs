const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=__dirname,target=path.join(root,'pixellab');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const accepted=read(path.join(target,'response.json')),job=read(process.argv[2]);
if(job.id!==accepted.background_job_id||job.status!=='completed')throw Error('Wrong or unfinished job');
const {images,image,...metadata}=job.last_response;
if(!Array.isArray(images)||!images.length)throw Error('Missing images');
const decoded=images.map((item,i)=>{const png=Buffer.from(item.base64.replace(/^data:[^,]*,/,''),'base64');if(png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Not PNG');return {file:`frame-${String(i+1).padStart(2,'0')}.png`,png}});
for(const {file,png}of decoded){const p=path.join(target,file);if(fs.existsSync(p)&&!fs.readFileSync(p).equals(png))throw Error('Refuse overwrite: '+file)}
const files=decoded.map(({file,png})=>{fs.writeFileSync(path.join(target,file),png);return {file,sha256:crypto.createHash('sha256').update(png).digest('hex')}});
fs.writeFileSync(path.join(target,'result.json'),JSON.stringify({...metadata,job_id:job.id,status:job.status,requested_frame_count:4,frame_count:files.length,files},null,2)+'\n');
const {last_response,...status}=job;
fs.writeFileSync(path.join(target,'job-status.json'),JSON.stringify({...status,last_response:{...metadata,frame_count:files.length}},null,2)+'\n');
console.log(JSON.stringify({status:job.status,frame_count:files.length,billing_usage:metadata.billing_usage,seed:metadata.seed}));
