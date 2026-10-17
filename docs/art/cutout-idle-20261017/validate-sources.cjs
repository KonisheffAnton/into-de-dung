const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const sharp=require(process.env.SHARP_MODULE||'sharp');
const root=__dirname,manifest=JSON.parse(fs.readFileSync(path.join(root,'provenance.json'),'utf8'));
const hash=b=>crypto.createHash('sha256').update(b).digest('hex');
(async()=>{
 const records=[];
 for(const [file,native]of Object.entries({...manifest.originals,...manifest.references})){
  const bytes=fs.readFileSync(path.join(root,file)),original=fs.readFileSync(native);
  const meta=await sharp(bytes).metadata();await sharp(bytes).raw().toBuffer();
  records.push({file,sha256:hash(bytes),size:[meta.width,meta.height],hasAlpha:meta.hasAlpha,provider_bytes_equal:bytes.equals(original)});
 }
 const menu=hash(fs.readFileSync(path.resolve(root,'../../../scenes/demo/main_menu.tscn')));
 const result={status:records.every(r=>r.provider_bytes_equal)&&menu===manifest.main_menu_sha256?'PASS':'FAIL',records,main_menu_unchanged:menu===manifest.main_menu_sha256,imagegen_calls:manifest.imagegen_calls,pixellab_calls:manifest.pixellab_calls};
 fs.writeFileSync(path.join(root,'source-validation.json'),JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify(result));if(result.status!=='PASS')process.exitCode=1;
})().catch(e=>{console.error(e);process.exitCode=1;});
