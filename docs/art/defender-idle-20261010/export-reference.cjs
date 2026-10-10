// Технический экспорт той же сетки, которую читает игровой native_sprite.gdshader.
// Ничего не рисует заново; исходный PNG и сцены не изменяются.
const fs = require('node:fs');
const path = require('node:path');
const sharp = require(process.env.SHARP_MODULE || 'sharp');
async function run() {
  const source = path.resolve(__dirname, '../../..', 'assets/art_presets/trials/defender_field_v1/defender_new.png');
  const {data, info} = await sharp(source).ensureAlpha().raw().toBuffer({resolveWithObject:true});
  const width=96, height=96, pixels=Buffer.alloc(width*height*4);
  const region={x:89,y:206,w:1034,h:966}, native={w:77,h:72}, offset={x:9,y:9};
  for(let y=0;y<native.h;y++) for(let x=0;x<native.w;x++) {
    const sx=Math.floor(region.x+(x+0.5)*region.w/native.w);
    const sy=Math.floor(region.y+(y+0.5)*region.h/native.h);
    const s=(sy*info.width+sx)*4, d=((y+offset.y)*width+x+offset.x)*4;
    if(data[s+3]>=128) {pixels[d]=data[s];pixels[d+1]=data[s+1];pixels[d+2]=data[s+2];pixels[d+3]=255;}
  }
  await sharp(pixels,{raw:{width,height,channels:4}}).png().toFile(path.join(__dirname,'reference-96.png'));
  fs.writeFileSync(path.join(__dirname,'reference.json'),JSON.stringify({source:'assets/art_presets/trials/defender_field_v1/defender_new.png',region,native,offset,canvas:{width,height},alphaThreshold:128,displayScale:0.8,gameOriginInCanvas:{x:53.42,y:74.14}},null,2)+'\n');
}
run().catch(error=>{console.error(error.message);process.exitCode=1;});
