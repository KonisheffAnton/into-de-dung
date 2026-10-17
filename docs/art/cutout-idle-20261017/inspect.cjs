const fs=require('node:fs'),path=require('node:path');
const sharp=require(process.env.SHARP_MODULE||'sharp');
(async()=>{
for(const id of ['a','b']){
 const {data,info}=await sharp(path.join(__dirname,`atlas-${id}.png`)).ensureAlpha().raw().toBuffer({resolveWithObject:true});
 const cell=info.width/2, bboxes=[];
 for(const [name,cx,cy] of [['head',1,0],['torso',0,1],['legs',1,1]]){
  let l=info.width,t=info.height,r=0,b=0,count=0;
  const lowerStart=680,xStart=cx===1?750:0,xEnd=cy===1&&cx===0?750:(cx+1)*cell;
  for(let y=cy===1?lowerStart:0;y<(cy===1?info.height:750);y++) for(let x=xStart;x<xEnd;x++){
   if(data[(y*info.width+x)*4+3]>=128){l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x+1);b=Math.max(b,y+1);count++;}
  }
  bboxes.push({name,crop:[l,t,r-l,b-t],count});
 }
 console.log(JSON.stringify({id,width:info.width,height:info.height,channels:info.channels,parts:bboxes}));
}
})().catch(e=>{console.error(e);process.exitCode=1;});
