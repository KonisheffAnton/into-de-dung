// PNG сохраняются точными байтами API. Повторная генерация здесь невозможна.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const root = __dirname;
const target = path.join(root, 'pixellab');
const readJson = p => JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/,''));
const accepted = readJson(path.join(target, 'response.json'));
const job = readJson(process.argv[2]);
if (accepted.background_job_id !== '5c629c12-e56f-4ba6-abf6-340ac7637ef5' || job.id !== accepted.background_job_id || job.status !== 'completed') throw Error('Wrong or unfinished job');
const {images, image, ...metadata} = job.last_response;
if (!Array.isArray(images) || !images.length) throw Error('No completed images');
const files = images.map((item, i) => {
  const png = Buffer.from(item.base64.replace(/^data:[^,]*,/,''),'base64');
  if (png.subarray(0,8).toString('hex') !== '89504e470d0a1a0a') throw Error('Not PNG');
  const file = `frame-${String(i+1).padStart(2,'0')}.png`;
  const full = path.join(target,file);
  if (fs.existsSync(full) && !fs.readFileSync(full).equals(png)) throw Error('Refuse to overwrite '+file);
  fs.writeFileSync(full,png);
  return {file,sha256:crypto.createHash('sha256').update(png).digest('hex')};
});
const result = {...metadata,job_id:job.id,status:job.status,requested_frame_count:12,frame_count:files.length,files};
fs.writeFileSync(path.join(target,'result.json'),JSON.stringify(result,null,2)+'\n');
const {last_response,...status} = job;
fs.writeFileSync(path.join(target,'job-status.json'),JSON.stringify({...status,last_response:{...metadata,frame_count:files.length}},null,2)+'\n');
console.log(JSON.stringify({status:job.status,frame_count:files.length,billing_usage:metadata.billing_usage,seed:metadata.seed}));
