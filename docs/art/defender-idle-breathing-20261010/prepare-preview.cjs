// Показывает исходные кадры PixelLab: без регистрации, интерполяции и дорисовки.
const fs=require('node:fs'),path=require('node:path');
const sharp=require(process.env.SHARP_MODULE||'sharp');
const root=__dirname,N=96,breath=process.argv.includes('--breath'),rig=breath||process.argv.includes('--rig'),delay=rig?300:400;
const outputPrefix=breath?'breath-':rig?'rig-':'';
async function rgba(file){
  const metadata=await sharp(file).metadata();
  if(rig&&metadata.width===128&&metadata.height===128){
    const pixels=await sharp(file).ensureAlpha().raw().toBuffer();
    for(let y=0;y<128;y++)for(let x=0;x<128;x++)if((x<16||y<16||x>=112||y>=112)&&pixels[(y*128+x)*4+3]>=128)throw Error('Opaque content outside reference crop');
    return sharp(file).extract({left:16,top:16,width:N,height:N}).ensureAlpha().raw().toBuffer();
  }
  return sharp(file).ensureAlpha().raw().toBuffer();
}
async function gif(frames,w,h,file){
  await sharp(Buffer.concat(frames),{raw:{width:w,height:h*frames.length,channels:4,pageHeight:h}})
    .gif({loop:0,delay:Array(frames.length).fill(delay),dither:0,effort:10}).toFile(path.join(root,outputPrefix+file));
}
async function main(){
  const dir=path.join(root,breath?'pixellab-breath':rig?'pixellab-rig':'pixellab');
  const all=fs.readdirSync(dir).filter(n=>/^frame-\d+\.png$/.test(n)).sort();
  const wanted=rig?8:4;
  if(![wanted,wanted+1].includes(all.length))throw Error('Unexpected animation frame count');
  const sourceFrames=all.slice(-wanted),poses=await Promise.all(sourceFrames.map(n=>rgba(path.join(dir,n))));
  // Провайдер заканчивает подъёмом груди: обратный проход тех же поз даёт выдох.
  const order=rig?[0,1,2,3,4,5,6,7]:[0,1,2,3,2,1],selected=order.map(i=>sourceFrames[i]),frames=order.map(i=>poses[i]);
  if(frames.some(p=>p.length!==N*N*4))throw Error('Unexpected frame dimensions');
  const reference=await rgba(path.join(dir,rig?'reference-128.png':'reference-96.png'));
  await gif(frames,N,N,'idle-native.gif');
  const width=800,height=590,variants=[{label:'CURRENT SPRITE',frames:Array(frames.length).fill(reference)},{label:'PIXELLAB / BREATHING',frames}];
  const labels=Buffer.from(`<svg width="${width}" height="${height}"><g fill="#e6eadc" font-size="20" font-family="Arial" text-anchor="middle"><text x="200" y="42">${variants[0].label}</text><text x="600" y="42">${variants[1].label}</text></g><g fill="#a7b49b" font-size="16" font-family="Arial"><text x="24" y="78">80% art scale · enlarged ×4 · ${wanted} source poses / 2.4 s loop</text><text x="24" y="438">Camera 75% / 100% / 125% · approximate display size</text></g></svg>`);
  const output=[];
  for(let f=0;f<frames.length;f++){
    const layers=[{input:labels,left:0,top:0}];
    for(let v=0;v<2;v++){
      const pixels=variants[v].frames[f],bigSize=Math.round(N*0.8*4);
      const big=await sharp(pixels,{raw:{width:N,height:N,channels:4}}).resize(bigSize,bigSize,{kernel:'nearest'}).png().toBuffer();
      layers.push({input:big,left:Math.round(400*(v+0.5)-bigSize/2),top:95});
      for(let z=0;z<3;z++){
        const size=Math.round(N*0.8*[0.75,1,1.25][z]);
        const image=await sharp(pixels,{raw:{width:N,height:N,channels:4}}).resize(size,size,{kernel:'nearest'}).png().toBuffer();
        layers.push({input:image,left:Math.round(400*v+400*(z+0.5)/3-size/2),top:561-size});
      }
    }
    output.push(await sharp({create:{width,height,channels:4,background:'#27312b'}}).composite(layers).raw().toBuffer());
  }
  await gif(output,width,height,'preview.gif');
  await sharp(output[0],{raw:{width,height,channels:4}}).png().toFile(path.join(root,outputPrefix+'preview-still.png'));
  const strip=await Promise.all(poses.map(p=>sharp(p,{raw:{width:N,height:N,channels:4}}).resize(288,288,{kernel:'nearest'}).png().toBuffer()));
  await sharp({create:{width:strip.length*288,height:288,channels:4,background:'#27312b'}}).composite(strip.map((input,i)=>({input,left:i*288,top:0}))).png().toFile(path.join(root,outputPrefix+'filmstrip.png'));
  const metadata=await sharp(path.join(root,outputPrefix+'preview.gif'),{animated:true}).metadata();
  const info={sourceFrames,selectedFrames:selected,allOriginalFrames:all,delayMs:delay,cycleMs:frames.length*delay,transform:rig?'Remove only 16px transparent padding, original order, nearest display resize; no pose edits or per-frame registration':'Forward/reverse playback of four source poses. Nearest display resize only; original frame registration and pose unchanged',gif:{pages:metadata.pages,delay:metadata.delay,width:metadata.width,pageHeight:metadata.pageHeight}};
  fs.writeFileSync(path.join(root,outputPrefix+'preview.json'),JSON.stringify(info,null,2)+'\n');console.log(JSON.stringify(info));
}
main().catch(e=>{console.error(e.message);process.exitCode=1;});
