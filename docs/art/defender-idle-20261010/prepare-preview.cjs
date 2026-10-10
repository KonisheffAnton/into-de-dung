// Только нарезка, общий масштаб и упаковка готовых кадров, без дорисовки/интерполяции.
const fs=require('node:fs');
const path=require('node:path');
const sharp=require(process.env.SHARP_MODULE || 'sharp');
const root=__dirname, N=96, count=8, delay=200;
function bounds(data,w,h) {
  let x0=w,y0=h,x1=-1,y1=-1;
  for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(data[(y*w+x)*4+3]>=128){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}
  return {x:x0,y:y0,width:x1-x0+1,height:y1-y0+1};
}
async function raw(file){return sharp(file).ensureAlpha().raw().toBuffer();}
function footAnchor(pixels){
  const b=bounds(pixels,N,N),bottom=b.y+b.height-1;let sum=0,n=0;
  for(let y=bottom-4;y<=bottom;y++)for(let x=0;x<N;x++)if(pixels[(y*N+x)*4+3]>=128){sum+=x;n++;}
  return {x:Math.round(sum/n),y:bottom};
}
function registerFoot(pixels,target){
  const from=footAnchor(pixels),dx=target.x-from.x,dy=target.y-from.y,out=Buffer.alloc(N*N*4);
  for(let y=0;y<N;y++)for(let x=0;x<N;x++){
    const xx=x+dx,yy=y+dy;if(xx>=0&&yy>=0&&xx<N&&yy<N)pixels.copy(out,(yy*N+xx)*4,(y*N+x)*4,(y*N+x)*4+4);
  }
  return {pixels:out,translation:{x:dx,y:dy}};
}
async function gif(frames,w,h,file) {
  await sharp(Buffer.concat(frames),{raw:{width:w,height:h*frames.length,channels:4,pageHeight:h}})
    .gif({loop:0,delay:Array(frames.length).fill(delay),dither:0,effort:10}).toFile(file);
}
async function main(){
  const input=path.join(root,'imagegen/sheet-corrected.png'), meta=await sharp(input).metadata();
  const cells=[];
  for(let i=0;i<count;i++){
    const col=i%4,row=Math.floor(i/4),left=Math.round(col*meta.width/4),top=Math.round(row*meta.height/2);
    const width=Math.round((col+1)*meta.width/4)-left,height=Math.round((row+1)*meta.height/2)-top;
    cells.push(await sharp(input).extract({left,top,width,height}).resize(N,N,{kernel:'nearest'}).ensureAlpha().raw().toBuffer());
  }
  const reference=await raw(path.join(root,'reference-96.png')), target=bounds(reference,N,N), first=bounds(cells[0],N,N);
  const scale=target.height/first.height, resized=Math.round(N*scale);
  const offset={x:Math.round(target.x+target.width/2-(first.x+first.width/2)*scale),y:Math.round(target.y+target.height-(first.y+first.height)*scale)};
  const frames=[],stats=[],registration=[],anchor=footAnchor(reference);
  for(let i=0;i<count;i++){
    // Общий масштаб последовательности; затем техническая регистрация стопы.
    const small=await sharp(cells[i],{raw:{width:N,height:N,channels:4}}).resize(resized,resized,{kernel:'nearest'}).raw().toBuffer();
    const pixels=Buffer.alloc(N*N*4);
    for(let y=0;y<resized;y++)for(let x=0;x<resized;x++){
      const dx=x+offset.x,dy=y+offset.y,s=(y*resized+x)*4;
      if(dx<0||dy<0||dx>=N||dy>=N||small[s+3]<128)continue;
      const d=(dy*N+dx)*4;pixels[d]=small[s];pixels[d+1]=small[s+1];pixels[d+2]=small[s+2];pixels[d+3]=255;
    }
    const registered=registerFoot(pixels,anchor);
    frames.push(registered.pixels);registration.push(registered.translation);stats.push(bounds(registered.pixels,N,N));
    await sharp(registered.pixels,{raw:{width:N,height:N,channels:4}}).png().toFile(path.join(root,`imagegen/frame-${String(i).padStart(2,'0')}.png`));
  }
  await gif(frames,N,N,path.join(root,'imagegen/idle-native.gif'));
  fs.writeFileSync(path.join(root,'imagegen/normalization.json'),JSON.stringify({sheet:{width:meta.width,height:meta.height},layout:{columns:4,rows:2},scale,offset,alphaThreshold:128,frameBounds:stats,footAnchor:anchor,registration,delayMs:delay,loopMs:count*delay,notes:'Shared rest-height scale, nearest sampling, then per-frame integer translation to register the lower boot. No redrawing or interpolation. Original sheets retained; shape flicker is not corrected. Preview only.'},null,2)+'\n');
  const variants=[{label:'REFERENCE',frames:Array(count).fill(reference)},{label:'IMAGEGEN',frames}];
  const pixelFiles=Array.from({length:count},(_,i)=>path.join(root,`pixellab/frame-${String(i+2).padStart(2,'0')}.png`));
  if(pixelFiles.every(file=>fs.existsSync(file))){
    const registered=(await Promise.all(pixelFiles.map(raw))).map(p=>registerFoot(p,anchor));
    variants.push({label:'PIXELLAB',frames:registered.map(r=>r.pixels)});
    await gif(registered.map(r=>r.pixels),N,N,path.join(root,'pixellab/idle-native.gif'));
    fs.writeFileSync(path.join(root,'pixellab/preview.json'),JSON.stringify({selectedFrames:pixelFiles.map(f=>path.basename(f)),omitted:'frame-01.png: near-duplicate introductory rest frame; all nine source frames retained',registration:registered.map(r=>r.translation),delayMs:delay,loopMs:count*delay},null,2)+'\n');
  }
  const width=960,height=590,panels=variants.length,panel=width/panels;
  const labels=variants.map((v,i)=>`<text x="${panel*(i+0.5)}" y="42" text-anchor="middle" fill="#e6eadc" font-size="20" font-family="Arial">${v.label}</text>`).join('');
  const overlay=Buffer.from(`<svg width="${width}" height="${height}">${labels}<text x="24" y="78" fill="#a7b49b" font-family="Arial" font-size="16">80% art scale · enlarged ×4 · 8 frames / 1.6 s</text><text x="24" y="438" fill="#a7b49b" font-family="Arial" font-size="16">Camera 75% / 100% / 125% · approximate display size</text></svg>`);
  const rendered=[];
  for(let f=0;f<count;f++){
    const composites=[{input:overlay,left:0,top:0}];
    for(let v=0;v<variants.length;v++){
      const bigSize=Math.round(N*0.8*4),big=await sharp(variants[v].frames[f],{raw:{width:N,height:N,channels:4}}).resize(bigSize,bigSize,{kernel:'nearest'}).png().toBuffer();
      composites.push({input:big,left:Math.round(panel*(v+0.5)-bigSize/2),top:95});
      for(let z=0;z<3;z++){
        const size=Math.round(N*0.8*[0.75,1,1.25][z]);
        const sprite=await sharp(variants[v].frames[f],{raw:{width:N,height:N,channels:4}}).resize(size,size,{kernel:'nearest'}).png().toBuffer();
        composites.push({input:sprite,left:Math.round(panel*v+panel*(z+0.5)/3-size/2),top:Math.round(465+(96-size))});
      }
    }
    rendered.push(await sharp({create:{width,height,channels:4,background:'#27312b'}}).composite(composites).raw().toBuffer());
  }
  await gif(rendered,width,height,path.join(root,'comparison.gif'));
  await sharp(rendered[0],{raw:{width,height,channels:4}}).png().toFile(path.join(root,'comparison-still.png'));
  const info=await sharp(path.join(root,'comparison.gif'),{animated:true}).metadata();
  console.log(JSON.stringify({providers:variants.map(v=>v.label),gif:{pages:info.pages,delay:info.delay,width:info.width,pageHeight:info.pageHeight},imagegenBounds:stats}));
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;});
