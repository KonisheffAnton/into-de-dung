// Изолированная копия проверяет сборку без личного каталога генераций и отказ при порче PNG.
const fs=require('node:fs'),path=require('node:path'),cp=require('node:child_process');
const root=__dirname,repo=path.resolve(root,'../../..');
const temp=path.join(repo,'test_reports/mage-archer-variants-20261101','portable-'+Date.now());
const target=path.join(temp,'docs/art/mage-archer-variants-20261101');
fs.mkdirSync(target,{recursive:true});
const manifest=JSON.parse(fs.readFileSync(path.join(root,'prompts.json'),'utf8'));
for(const file of ['build_gallery.cjs','sources.json',...manifest.variants.map(v=>v.file)])fs.copyFileSync(path.join(root,file),path.join(target,file));
for(const v of manifest.variants)v.source=path.join(temp,'unavailable-originals',v.file);
fs.writeFileSync(path.join(target,'prompts.json'),JSON.stringify(manifest));
for(const ref of ['../warrior-variants-20261029/warrior-11.png','../warrior-variants-20261029/warrior-02.png','../rogue-variants-20261101/rogue-02.png']){const to=path.resolve(target,ref);fs.mkdirSync(path.dirname(to),{recursive:true});fs.copyFileSync(path.resolve(root,ref),to)}
const run=args=>cp.spawnSync(process.execPath,[path.join(target,'build_gallery.cjs'),...args],{encoding:'utf8'});
const normal=run([]);if(normal.status!==0)throw Error(normal.stderr);
const html=fs.readFileSync(path.join(target,'gallery.html'),'utf8');
const originalCheck=run(['--verify-originals']);
fs.appendFileSync(path.join(target,'mage-01.png'),Buffer.from([1]));
const tampered=run([]);
const report={isolated_copy:temp,missing_originals:true,normal_build:normal.status===0,embedded_images:(html.match(/data:image\/png;base64,/g)||[]).length,explicit_original_check_rejects:originalCheck.status!==0,tampered_packaged_png_rejects:tampered.status!==0};
report.pass=report.normal_build&&report.embedded_images===23&&report.explicit_original_check_rejects&&report.tampered_packaged_png_rejects;
fs.writeFileSync(path.join(root,'portable-validation.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));if(!report.pass)process.exitCode=1;
