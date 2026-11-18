"use strict";
(() => {
 const TAU=Math.PI*2,mod=(x,n)=>((x%n)+n)%n;
 const mix=(a,b,t)=>a+(b-a)*t, ease=t=>t*t*(3-2*t);
 // Бёдра начинают перенос веса раньше кисти; ударная фаза заметно короче замаха.
 // ms, hipX,hipY,lean,yaw,wristX,wristY,weaponAngle,headLag
 const TRACK=[
 [0,125,153,-.025,.22,153,158,2.28,0],
 [260,120,158,-.10,-.22,140,123,.45,-.06],
 [540,118,159,-.14,-.50,126,84,-.32,-.12],
 [620,119,159,-.12,-.48,127,83,-.35,-.10],
 [750,134,152,.18,.65,184,137,1.25,.08],
 [850,137,155,.23,.78,174,162,2.05,.14],
 [1060,134,156,.16,.62,167,164,2.25,.12],
 [1420,127,154,.025,.30,155,160,2.35,.04],
 [2000,125,153,-.025,.22,153,158,2.28,0]];
 const point=(o,x,y,r=0)=>({x:o.x+x*Math.cos(r)-y*Math.sin(r),y:o.y+x*Math.sin(r)+y*Math.cos(r)});
 // Две кости замыкаются на заданной кисти/лодыжке; стопы не следуют за тазом.
 function solve(a,target,l1,l2,side){
   const dx=target.x-a.x,dy=target.y-a.y,raw=Math.hypot(dx,dy),d=Math.max(.001,Math.min(raw,l1+l2-.001));
   const ux=dx/(raw||1),uy=dy/(raw||1),along=(l1*l1-l2*l2+d*d)/(2*d),height=Math.sqrt(Math.max(0,l1*l1-along*along));
   const end={x:a.x+ux*d,y:a.y+uy*d};
   return {joint:{x:a.x+ux*along-uy*height*side,y:a.y+uy*along+ux*height*side},end,reachError:Math.abs(raw-d)};
 }
 function pose(timeMs,mode='auto'){
   const cycle=mod(timeMs,4000),actionTimeMs=mode==='strike'?mod(timeMs,2000):(mode==='auto'&&cycle>=1500&&cycle<=3500?cycle-1500:0);
   let v=TRACK[0].slice(1);
   for(let i=0;i<TRACK.length-1;i++){let a=TRACK[i],b=TRACK[i+1];if(actionTimeMs>=a[0]&&actionTimeMs<=b[0]){let t=ease((actionTimeMs-a[0])/(b[0]-a[0]));v=a.slice(1).map((x,k)=>mix(x,b[k+1],t));break;}}
   const breath=Math.sin(mod(timeMs,mode==='strike'?2000:4000)*TAU/(mode==='strike'?2000:4000));
   const [hx,hy,lean,yaw,wx,wy,wa,lag]=v,hips={x:hx,y:hy+breath*.65};
   const chest={x:hx,y:hips.y-4,rotation:lean,yaw,scaleX:1-.16*Math.abs(yaw),shear:Math.sin(yaw)*.11};
   const local=(x,y)=>point(chest,x*chest.scaleX+y*chest.shear,y,lean);
   const legs={};
   for(const [name,offset,fx,bend] of [['far',-10,94,1],['near',10,160,-1]]){
     const hip={x:hx+offset,y:hips.y},ankle={x:fx,y:198};const ik=solve(hip,ankle,28,29,bend);
     legs[name]={hip,knee:ik.joint,ankle:ik.end,foot:ankle,reachError:ik.reachError};
   }
   const headAt=local(2+Math.sin(yaw)*4,-45),head={...headAt,rotation:lean*.28-lag*.25,scaleX:1-.08*Math.abs(yaw),yaw};
   const arms={};
   for(const name of ['far','near']){
     const near=name==='near';const shoulder=local((near?21:-21)+Math.sin(yaw)*4,-39+(near?0:2));
     const target=near?{x:wx,y:wy+breath*.35}:local(-22-Math.sin(yaw)*8,-3);
     const ik=solve(shoulder,target,26,27,near?-1:1);
     arms[name]={shoulder,elbow:ik.joint,wrist:ik.end,reachError:ik.reachError};
   }
   return {timeMs,mode,cycle,actionTimeMs,breath,hips,chest,head,legs,arms,weaponAngle:wa};
 }
 function render(ctx,manifest,images,timeMs,options={}){
   const p=pose(timeMs,options.mode||'auto'),ops=[];ctx.imageSmoothingEnabled=false;
   const armor=['light','heavy'].includes(options.armor)?options.armor:'none';
   const weapon=options.weapon==='axe'?'axe':'sword',helmet=options.helmet==='steel'?'steel':'none';
   function draw(key,x,y,rotation=0,group='body',sx=1,sy=1,shear=0,cropTop=null){
     const d=manifest.parts[key],img=images[key];if(!d||!img||!img.complete)throw Error('Missing part '+key);
     ctx.save();ctx.translate(x,y);ctx.rotate(rotation);ctx.transform(sx,0,shear,sy,0,0);
     if(d.flip_x)ctx.scale(-1,1);
     if(cropTop!==null)ctx.drawImage(img,0,0,d.width,cropTop,-d.pivot[0]*d.width,-d.pivot[1]*d.height,d.width,cropTop);
     else ctx.drawImage(img,-d.pivot[0]*d.width,-d.pivot[1]*d.height,d.width,d.height);
     ctx.restore();ops.push({key:cropTop!==null?'collar':key,group,x,y,rotation,scaleX:sx,scaleY:sy,shear});
   }
   function segment(key,a,b,group='body'){
     const d=manifest.parts[key],len=Math.hypot(b.x-a.x,b.y-a.y),angle=Math.atan2(b.y-a.y,b.x-a.x)-Math.PI/2;
     draw(key,a.x,a.y,angle,group,1,(len+5)/d.height);
   }
   // Один слот брони атомарно выбирает весь комплект. Кости не знают о вещах.
   const armoredSegment=(part,a,b)=>{if(armor!=='none')segment('armor_'+armor+'_'+part,a,b,'armor');};
   for(const name of ['far','near']){const l=p.legs[name];segment('thigh_'+name,l.hip,l.knee);armoredSegment('thigh',l.hip,l.knee);segment('shin_'+name,l.knee,l.ankle);armoredSegment('shin',l.knee,l.ankle);draw('boot_'+name,l.foot.x,l.foot.y);}
   function arm(name){const a=p.arms[name];segment('upper_arm',a.shoulder,a.elbow);segment('forearm',a.elbow,a.wrist);
     armoredSegment('upper_arm',a.shoulder,a.elbow);armoredSegment('forearm',a.elbow,a.wrist);
     if(name==='near')draw(weapon,a.wrist.x,a.wrist.y,p.weaponAngle,'weapon');
     draw('hand',a.wrist.x,a.wrist.y,Math.atan2(a.wrist.y-a.elbow.y,a.wrist.x-a.elbow.x)-Math.PI/2);
   }
   arm('far');
   draw('pelvis',p.hips.x,p.hips.y,.04*Math.sin(p.chest.yaw));
   if(armor!=='none')draw('armor_'+armor+'_pelvis',p.hips.x,p.hips.y,.04*Math.sin(p.chest.yaw),'armor');
   const c=p.chest;
   draw('torso',c.x,c.y,c.rotation,'body',c.scaleX,1,c.shear);
   if(armor!=='none')draw('armor_'+armor+'_torso',c.x,c.y,c.rotation,'armor',c.scaleX,1,c.shear);
   draw('torso',c.x,c.y,c.rotation,'body',c.scaleX,1,c.shear,15);
   const h=p.head;draw('head',h.x,h.y,h.rotation,'body',h.scaleX);
   if(helmet==='steel')draw(Math.abs(h.yaw)>.68?'helmet_profile':'helmet',h.x,h.y,h.rotation,'helmet',h.scaleX);
   arm('near');
   if(options.joints){ctx.strokeStyle='#edc65b';ctx.lineWidth=1;for(const l of Object.values(p.legs)){ctx.beginPath();ctx.moveTo(l.hip.x,l.hip.y);ctx.lineTo(l.knee.x,l.knee.y);ctx.lineTo(l.ankle.x,l.ankle.y);ctx.stroke();}for(const a of Object.values(p.arms)){ctx.beginPath();ctx.moveTo(a.shoulder.x,a.shoulder.y);ctx.lineTo(a.elbow.x,a.elbow.y);ctx.lineTo(a.wrist.x,a.wrist.y);ctx.stroke();}ctx.fillStyle='#fff38c';for(const l of Object.values(p.legs)){ctx.fillRect(l.knee.x-2,l.knee.y-2,4,4);}}
   return {pose:p,ops,armor,weapon,helmet};
 }
 window.NaturalRig={pose,render,solve};
})();
