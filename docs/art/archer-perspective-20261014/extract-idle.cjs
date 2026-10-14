// Сохраняем PNG из окончательного ответа побайтно, без перекодирования и ретуши.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.join(__dirname,'pixellab');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const accepted=read(path.join(root,'response.json'));
const job=read(path.resolve(__dirname,'../../../test_reports/archer-perspective-20261014/job-response.json'));
if(job.id!==accepted.background_job_id||job.status!=='completed')throw Error('Job not completed or identity mismatch');
const {images,image,...metadata}=job.last_response;
if(!images?.length)throw Error('No returned images');
const files=images.map((entry,i)=>{
 const bytes=Buffer.from(entry.base64.replace(/^data:[^,]*,/,''),'base64');
 if(bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Not PNG');
 const file=`frame-${String(i+1).padStart(2,'0')}.png`,dest=path.join(root,file);
 if(fs.existsSync(dest)&&!fs.readFileSync(dest).equals(bytes))throw Error('Refuse overwrite');
 fs.writeFileSync(dest,bytes);return {file,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
});
const {last_response,...jobInfo}=job;
const result={...metadata,status:job.status,job_id:job.id,requested_frame_count:12,frame_count:files.length,files};
fs.writeFileSync(path.join(root,'result.json'),JSON.stringify(result,null,2)+'\n');
fs.writeFileSync(path.join(root,'job-status.json'),JSON.stringify({...jobInfo,last_response:{...metadata,frame_count:files.length}},null,2)+'\n');
console.log(JSON.stringify({status:job.status,frames:files.length,billing_usage:metadata.billing_usage,usage:metadata.usage}));
