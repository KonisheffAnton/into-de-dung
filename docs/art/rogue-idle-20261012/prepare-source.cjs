// Проба отдельная: native-размер и поля заданы явно, игровые сцены не меняются.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
async function main() {
  const target = path.join(__dirname, 'pixellab');
  fs.mkdirSync(target, {recursive:true});
  const source = path.join(__dirname, 'rogue-clean.png');
  const {data, info} = await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  let l=info.width,t=info.height,r=0,b=0;
  for(let y=0;y<info.height;y++) for(let x=0;x<info.width;x++) {
    if(data[(y*info.width+x)*4+3]>=128) {l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);}
  }
  const sprite = await sharp(source).extract({left:l,top:t,width:r-l+1,height:b-t+1})
    .resize(80,80,{fit:'inside',kernel:'nearest'}).png().toBuffer();
  const dim=await sharp(sprite).metadata();
  const left=Math.floor((96-dim.width)/2), top=86-dim.height;
  await sharp({create:{width:96,height:96,channels:4,background:'#00000000'}})
    .composite([{input:sprite,left,top}]).png().toFile(path.join(__dirname,'rogue-native.png'));
  await sharp(path.join(__dirname,'rogue-native.png')).extend({top:16,bottom:16,left:16,right:16,background:'#00000000'})
    .png().toFile(path.join(target,'reference-128.png'));
  const record={source:'rogue-clean.png',sourceSize:[info.width,info.height],alphaBBox:[l,t,r+1,b+1],nativeSprite:[dim.width,dim.height],nativeCanvas:[96,96],nativeOffset:[left,top],inputCanvas:[128,128],padding:16,method:'nearest, aspect preserved; no retouching'};
  fs.writeFileSync(path.join(__dirname,'source-preparation.json'),JSON.stringify(record,null,2)+'\n');
  console.log(JSON.stringify(record));
}
main().catch(e=>{console.error(e);process.exit(1)});
