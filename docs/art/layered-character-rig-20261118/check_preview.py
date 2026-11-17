"""Headless-проверка общего каркаса и экспорт GIF из того же JS-рендерера."""
from pathlib import Path
import base64
import html
import io
import json
import re
import subprocess
from PIL import Image

ROOT=Path(__file__).resolve().parent
TEMP=Path('D:/Codex/home/generated_images/layered-character-rig-20261118')
SCRIPT=r'''<script>
(async()=>{
 const checks=[];const check=(name,pass)=>{checks.push({name,pass:!!pass});if(!pass)throw Error(name)};
 const result={checks,frames:[],swap:[]};
 try{
 for(let i=0;i<100&&!Object.values(window.__rigAssets.images).every(img=>img.complete&&img.naturalWidth>0);i++)await new Promise(r=>setTimeout(r,50));
 if(window.__rigState().playing)document.getElementById('pause').click();
 const {manifest,images}=window.__rigAssets;
 const make=()=>{const c=document.createElement('canvas');c.width=256;c.height=256;return c};
 const c=make(),ctx=c.getContext('2d');
 const configurations=[['light','sword'],['light','axe'],['heavy','sword'],['heavy','axe']];
 const draw=(t,armor,weapon,more={})=>{ctx.clearRect(0,0,256,256);return LayeredRig.render(ctx,manifest,images,t,{armor,weapon,...more})};
 const ops=(r,group)=>r.ops.filter(o=>o.group===group).map(o=>[o.x,o.y,o.rotation]);
 const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 check('16 transparent static layers loaded',Object.keys(images).length===16&&Object.values(images).every(i=>i.complete&&i.naturalWidth>0));
 let equalBody=true,equalSocket=true,edge=false,moving=false;let prev=null;
 for(let t=0;t<5000;t+=40){
   const renders=configurations.map(([armor,weapon])=>{const r=draw(t,armor,weapon);const px=ctx.getImageData(0,0,256,256).data;
     for(let q=0;q<256;q++)if(px[(q*256)*4+3]>128||px[(q*256+255)*4+3]>128||px[q*4+3]>128||px[(255*256+q)*4+3]>128)edge=true;return r});
   for(const r of renders){equalBody&&=same(ops(r,'body'),ops(renders[0],'body'));equalSocket&&=same(ops(r,'weapon'),ops(renders[0],'weapon'));}
   const v=JSON.stringify(ops(renders[0],'body'));if(prev&&v!==prev)moving=true;prev=v;
 }
 check('same body transforms across4equipment combinations125times',equalBody);
 check('same weapon socket across4equipment combinations125times',equalSocket);
 check('cycle actually moves',moving);check('no opaque edge clipping in500renders',!edge);
 check('loop endpoint identical transforms',same(ops(draw(0,'light','sword'),'body'),ops(draw(5000,'light','sword'),'body')));
 check('strike mode advances',!same(ops(draw(300,'light','sword',{mode:'strike'}),'body'),ops(draw(1100,'light','sword',{mode:'strike'}),'body')));
 check('armor toggle removes armor layers',draw(2800,'heavy','axe',{showArmor:false}).ops.every(o=>o.group!=='armor'));
 check('weapon toggle removes weapon layer',draw(2800,'heavy','axe',{showWeapon:false}).ops.every(o=>o.group!=='weapon'));
 check('exploded view separates armor',!same(ops(draw(0,'heavy','axe'),'armor'),ops(draw(0,'heavy','axe',{explode:16}),'armor')));
 const slider=document.getElementById('scrub');slider.value='2850';slider.dispatchEvent(new Event('input'));
 const before=window.__rigState();const beforePixels=document.getElementById('hero').toDataURL();
 for(const [id,value] of [['weapon','axe'],['armor','heavy']]){let e=document.getElementById(id);e.value=value;e.dispatchEvent(new Event('input'))}
 const after=window.__rigState();check('equipment swap preserves time and pause',before.time===after.time&&!before.playing&&!after.playing);
 check('equipment swap changes rendered image',beforePixels!==document.getElementById('hero').toDataURL());
 // GIF содержит только снимки этого рендерера, отдельной реализации анимации нет.
 const out=document.createElement('canvas');out.width=512;out.height=576;const o=out.getContext('2d');o.imageSmoothingEnabled=false;
 for(let t=0;t<5000;t+=100){o.fillStyle='#202a34';o.fillRect(0,0,512,576);configurations.forEach(([armor,weapon],i)=>{
   draw(t,armor,weapon);const x=i%2*256,y=Math.floor(i/2)*288;o.drawImage(c,x,y+32);o.fillStyle='#eff1e8';o.font='14px Arial';o.textAlign='center';o.fillText((armor==='light'?'Лёгкая':'Тяжёлая')+' · '+(weapon==='sword'?'Меч':'Топор'),x+128,y+22);
 });result.frames.push(out.toDataURL('image/png').split(',')[1]);}
 for(const [armor,weapon] of configurations){draw(2850,armor,weapon);result.swap.push(c.toDataURL('image/png').split(',')[1]);}
 draw(0,'heavy','axe',{explode:16,joints:true});result.exploded=c.toDataURL('image/png').split(',')[1];
 document.getElementById('scrub').value='0';document.getElementById('scrub').dispatchEvent(new Event('input'));
 }catch(e){checks.push({name:'exception',pass:false,error:String(e)})}
 result.pass=checks.every(x=>x.pass);const el=document.createElement('pre');el.id='qa-output';el.hidden=true;el.textContent=JSON.stringify(result);document.body.append(el);
})();</script>'''

def main():
    TEMP.mkdir(exist_ok=True)
    target=TEMP/'preview-qa.html'
    target.write_text((ROOT/'gallery.html').read_text(encoding='utf-8')+SCRIPT,encoding='utf-8')
    cmd=['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe','--headless','--disable-gpu','--no-first-run','--no-default-browser-check',
         '--user-data-dir='+str(TEMP/'headless-profile'),'--allow-file-access-from-files','--hide-scrollbars','--window-size=1400,1050',
         '--virtual-time-budget=8000','--screenshot='+str(ROOT/'gallery-screenshot.png'),'--dump-dom',target.as_uri()]
    p=subprocess.run(cmd,capture_output=True,timeout=60,encoding='utf-8',errors='replace')
    match=re.search(r'<pre id="qa-output"[^>]*>(.*?)</pre>',p.stdout,re.S)
    if not match:
        (TEMP/'qa-dom.html').write_text(p.stdout,encoding='utf-8')
        (TEMP/'qa-stderr.txt').write_text(p.stderr,encoding='utf-8')
        raise RuntimeError('Browser returned no QA report; diagnostic DOM/stderr saved outside repo')
    report=json.loads(html.unescape(match.group(1)))
    frames=[Image.open(io.BytesIO(base64.b64decode(s))).convert('RGB') for s in report.pop('frames')]
    swap=[Image.open(io.BytesIO(base64.b64decode(s))).convert('RGBA') for s in report.pop('swap')]
    exploded=report.pop('exploded',None)
    if report['pass']:
        frames[0].save(ROOT/'overview.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=2)
        frames[0].save(ROOT/'overview.png')
        strip=Image.new('RGB',(256*5,288),'#202a34')
        for i,index in enumerate([0,22,26,29,35]):strip.paste(frames[index].crop((0,0,256,288)),(i*256,0))
        strip.save(ROOT/'motion-poses.png')
        previews=[]
        for f in swap:
            bg=Image.new('RGBA',f.size,'#202a34');bg.alpha_composite(f);previews.append(bg.convert('RGB').resize((512,512),Image.Resampling.NEAREST))
        previews[0].save(ROOT/'swap.gif',save_all=True,append_images=previews[1:],duration=700,loop=0,disposal=2)
        if exploded:(ROOT/'exploded.png').write_bytes(base64.b64decode(exploded))
    report['export']={'frames':len(frames),'duration_ms':5000,'source':'Screenshots from exact shared JS renderer, not separate animation code'}
    (ROOT/'browser-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    if not report['pass']:raise SystemExit(1)

if __name__=='__main__':main()
