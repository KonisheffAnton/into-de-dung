// Декодирует только окончательные ответы. PNG провайдера сохраняются без перекодирования.
const fs=require('fs'),path=require('path'),crypto=require('crypto');
const root=__dirname,report=path.resolve(root,'../../../test_reports/archer-idle-variants-20261014');
const read=p=>JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,''));
const manifest=read(path.join(root,'variants.json'));
const summaries=[];
for(const variant of manifest.variants){
 const folder=path.join(root,variant.path),out=path.join(report,variant.id);
 const responsePath=path.join(folder,'response.json');
 if(!fs.existsSync(responsePath)){summaries.push({id:variant.id,status:'no_acceptance_saved'});continue}
 const accepted=read(responsePath);let response,jobInfo;
 if(variant.sync){
  const responseFile=path.join(out,'sync-response.json');
  if(!fs.existsSync(responseFile)){summaries.push({id:variant.id,status:'no_sync_response_saved'});continue}
  response=read(responseFile);jobInfo={transport:'synchronous',status:'completed'};
 }else{
  const jobFile=path.join(out,'job-response.json');
  if(!fs.existsSync(jobFile)){summaries.push({id:variant.id,status:'not_polled'});continue}
  const job=read(jobFile);
  if(job.id!==accepted.background_job_id)throw Error('Job identity mismatch '+variant.id);
  if(job.status!=='completed'){summaries.push({id:variant.id,status:job.status});continue}
  response=job.last_response;const {last_response,...rest}=job;jobInfo=rest;
 }
 const {images,image,...metadata}=response;
 if(!Array.isArray(images)||!images.length)throw Error('Completed response has no images: '+variant.id);
 const decoded=images.map((entry,i)=>{const png=Buffer.from(entry.base64.replace(/^data:[^,]*,/,''),'base64');if(png.subarray(0,8).toString('hex')!=='89504e470d0a1a0a')throw Error('Not PNG');return {file:`frame-${String(i+1).padStart(2,'0')}.png`,png}});
 for(const {file,png}of decoded){const p=path.join(folder,file);if(fs.existsSync(p)&&!fs.readFileSync(p).equals(png))throw Error('Refuse overwrite '+p)}
 const files=decoded.map(({file,png})=>{fs.writeFileSync(path.join(folder,file),png);return {file,sha256:crypto.createHash('sha256').update(png).digest('hex')}});
 fs.writeFileSync(path.join(folder,'result.json'),JSON.stringify({...metadata,status:'completed',job_id:jobInfo.id||null,transport:variant.sync?'synchronous':'background_job',requested_frame_count:variant.requested_frame_count,frame_count:files.length,files},null,2)+'\n');
 fs.writeFileSync(path.join(folder,'job-status.json'),JSON.stringify({...jobInfo,last_response:{...metadata,frame_count:files.length}},null,2)+'\n');
 summaries.push({id:variant.id,status:'completed',frames:files.length,billing_usage:metadata.billing_usage,usage:metadata.usage});
}
console.log(JSON.stringify(summaries));
