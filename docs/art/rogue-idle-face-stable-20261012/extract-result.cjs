// Принимаем кадры лишь после completed: промежуточные images не означают готовность.
const fs=require('node:fs'),path=require('node:path');
const dir=path.join(__dirname,'pixellab');
const job=JSON.parse(fs.readFileSync(path.join(dir,'response.json'),'utf8').replace(/^\uFEFF/,''));
if(job.status!=='completed') throw Error('PixelLab job is not completed');
const result=job.last_response;
if(!Array.isArray(result.images)||result.images.length!==12) throw Error('Expected 12 images');
result.images.forEach((img,i)=>{
 if(typeof img.base64!=='string') throw Error('Missing base64 frame');
 const bytes=Buffer.from(img.base64,'base64');
 if(bytes.subarray(0,8).toString('hex')!=='89504e470d0a1a0a') throw Error('Frame is not PNG');
 fs.writeFileSync(path.join(dir,`frame-${String(i+1).padStart(2,'0')}.png`),bytes);
});
const summary={status:job.status,job_id:job.id,frame_count:result.images.length,billing_usage:result.billing_usage,billing_charged:result.billing_charged,generation_id:result.generation_id};
fs.writeFileSync(path.join(dir,'result.json'),JSON.stringify(summary,null,2)+'\n');
console.log(JSON.stringify(summary));
