"""Проверяет автономную natural-галерею в Edge и экспортирует её же кадры."""
from __future__ import annotations

import base64
import html
import io
import json
import re
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
TEMP = Path("D:/Codex/home/generated_images/natural-layered-character-20261118")

SCRIPT = r'''<script>
(async()=>{const checks=[];const check=(name,pass,detail="")=>{checks.push({name,pass:!!pass,...(detail?{detail}:{})});if(!pass)throw Error(name)};const out={checks,frames:[],swaps:[],comparison:[]};try{
 for(let i=0;i<160;i++){const a=window.__naturalAssets;const loaded=a&&Object.values(a.images).every(x=>x.complete&&x.naturalWidth>0);if(window.__naturalReady&&loaded&&document.getElementById('refsheet').complete&&document.getElementById('refsheet').naturalWidth)break;await new Promise(r=>setTimeout(r,50))}
 const A=window.__naturalAssets;check('manifest layers loaded',!!A&&Object.keys(A.manifest.parts).length>0&&Object.values(A.images).every(x=>x.complete&&x.naturalWidth>0));check('PixelLab reference sheet loaded',document.getElementById('refsheet').complete&&document.getElementById('refsheet').naturalWidth>0);if(window.__naturalState().playing)document.getElementById('pause').click();
 const make=()=>{const c=document.createElement('canvas');c.width=c.height=256;return c},c=make(),ctx=c.getContext('2d'),configs=[['light','sword','none'],['light','axe','steel'],['heavy','sword','steel'],['heavy','axe','none']];const draw=(t,armor='none',weapon='sword',helmet='none',mode='auto')=>{ctx.clearRect(0,0,256,256);return NaturalRig.render(ctx,A.manifest,A.images,t,{mode,armor,weapon,helmet})};const body=r=>r.ops.filter(o=>o.group==='body');const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
 const slots=[...document.querySelectorAll('#weapon,#armor,#helmet')].map(e=>[e.id,[...e.options].map(o=>o.value)]);check('exactly three equipment slots',slots.length===3&&JSON.stringify(slots)===JSON.stringify([['weapon',['sword','axe']],['armor',['none','light','heavy']],['helmet',['none','steel']]]));check('auto loop endpoint deterministic',eq(body(draw(0)),body(draw(4000))));check('pose deterministic at fixed time',eq(body(draw(1216)),body(draw(1216))));let sameBody=true,sameSocket=true,edge=false,moving=false,knee=false,hip=false,yaw=false,feetReach=true,jointsFinite=true,previous=null;
 let firstHip=null,firstYaw=null,firstKnee=null;for(let t=0;t<4000;t+=32){const rs=configs.map(q=>{const r=draw(t,...q),px=ctx.getImageData(0,0,256,256).data;for(let z=0;z<256;z++)if(px[(z*256)*4+3]>128||px[(z*256+255)*4+3]>128||px[z*4+3]>128||px[(255*256+z)*4+3]>128)edge=true;return r});const ref=body(rs[0]);for(const r of rs)sameBody&&=eq(body(r),ref);const weaponOps=rs.map(r=>r.ops.filter(o=>o.group==='weapon').map(o=>[o.x,o.y,o.rotation]));for(const w of weaponOps)sameSocket&&=eq(w,weaponOps[0]);const v=JSON.stringify(ref);moving||=previous!==null&&previous!==v;previous=v;const p=rs[0].pose;const legs=p.legs||{};for(const l of Object.values(legs)){feetReach&&=Number.isFinite(l.reachError)&&l.reachError<0.01;for(const point of [l.hip,l.knee,l.ankle,l.foot])jointsFinite&&=!!point&&Number.isFinite(point.x)&&Number.isFinite(point.y)}for(const a of Object.values(p.arms||{}))for(const point of [a.shoulder,a.elbow,a.wrist])jointsFinite&&=!!point&&Number.isFinite(point.x)&&Number.isFinite(point.y);const kneeAngle=l=>Math.atan2(l.ankle.y-l.knee.y,l.ankle.x-l.knee.x)-Math.atan2(l.hip.y-l.knee.y,l.hip.x-l.knee.x);const angle=kneeAngle(legs.near);knee||=firstKnee!==null&&Math.abs(angle-firstKnee)>0.01;if(firstKnee===null)firstKnee=angle;hip||=firstHip!==null&&Math.hypot(p.hips.x-firstHip.x,p.hips.y-firstHip.y)>0.1;if(firstHip===null)firstHip={...p.hips};yaw||=firstYaw!==null&&Math.abs(p.chest.yaw-firstYaw)>0.01;if(firstYaw===null)firstYaw=p.chest.yaw;
 }
 check('body transforms identical for all four equipment combinations at 125 samples',sameBody);check('weapon socket identical across equipment at 125 samples',sameSocket);check('character moves across the cycle',moving);check('knee angle changes',knee);check('hips shift',hip);check('chest yaw changes',yaw);check('foot IK reach error below 0.01 at all samples',feetReach);check('all joint coordinates finite at all samples',jointsFinite);check('no opaque edge clipping for all gear combinations at 125 samples',!edge);
 const expectedArmor=['torso','pelvis','upper_arm','forearm','thigh','shin'];let armorOps=true,handBoots=true;const bodyHandsBoots=[];for(const gear of ['light','heavy']){const r=draw(2360,gear,'sword','none');const keys=[...new Set(r.ops.filter(o=>o.group==='armor').map(o=>o.key))].map(k=>k.replace(/^armor_(light|heavy)_/,''));armorOps&&=expectedArmor.every(k=>keys.includes(k))&&keys.length===expectedArmor.length;bodyHandsBoots.push(r.ops.filter(o=>o.group==='body'&&(['hand','boot_far','boot_near'].includes(o.key))))}handBoots=eq(bodyHandsBoots[0],bodyHandsBoots[1]);check('armor group contains exactly six whole-suit parts',armorOps);check('hands and boots stay unchanged body parts',handBoots);
 const regions=[[95,100,70,65],[75,105,110,65],[80,160,100,65]], names=['torso','arms','legs'];const armorPixels={};for(const gear of ['none','light','heavy']){draw(2360,gear,'sword','none');armorPixels[gear]=ctx.getImageData(0,0,256,256).data.slice()}const regionDelta=(a,b,box)=>{let n=0;for(let y=box[1];y<box[1]+box[3];y++)for(let x=box[0];x<box[0]+box[2];x++){const i=(y*256+x)*4;if(a[i]!==b[i]||a[i+1]!==b[i+1]||a[i+2]!==b[i+2]||a[i+3]!==b[i+3])n++}return n};for(let i=0;i<regions.length;i++)check('full armor changes '+names[i]+' pixels',regionDelta(armorPixels.none,armorPixels.light,regions[i])>0&&regionDelta(armorPixels.light,armorPixels.heavy,regions[i])>0);
 const hero=document.getElementById('hero'),slider=document.getElementById('scrub'),base={weapon:'sword',armor:'light',helmet:'none'};slider.value='2360';slider.dispatchEvent(new Event('input'));for(const [id,val]of Object.entries(base)){const e=document.getElementById(id);e.value=val;e.dispatchEvent(new Event('input'))}const beforeState=__naturalState(),before=hero.toDataURL();for(const [id,val]of [['weapon','axe'],['armor','heavy'],['helmet','steel']]){for(const [key,v]of Object.entries(base)){const e=document.getElementById(key);e.value=v}const el=document.getElementById(id);el.value=val;document.querySelectorAll('#weapon,#armor,#helmet').forEach(e=>e.dispatchEvent(new Event('input')));const after=__naturalState();check(id+' changes image independently',hero.toDataURL()!==before);check(id+' swap preserves time and playback',after.time===beforeState.time&&after.playing===false);el.value=base[id];el.dispatchEvent(new Event('input'))}
 const modes=[];for(const mode of ['auto','breath','strike']){const a=draw(200, 'light','sword','none',mode),b=draw(700,'light','sword','none',mode);modes.push(!eq(body(a),body(b)))}check('auto, breath and strike advance',modes.every(Boolean));const modeEl=document.getElementById('mode'),modeOld=modeEl.value;modeEl.value='strike';modeEl.dispatchEvent(new Event('input'));slider.value='0';slider.dispatchEvent(new Event('input'));const frame0=Number(document.getElementById('refindex').textContent.split('/')[0]);slider.value='700';slider.dispatchEvent(new Event('input'));const frame700=Number(document.getElementById('refindex').textContent.split('/')[0]);check('PixelLab reference index advances in strike mode',frame700>frame0);modeEl.value=modeOld;modeEl.dispatchEvent(new Event('input'));
 const ac=document.createElement('canvas');ac.width=ac.height=512;const ax=ac.getContext('2d');ax.imageSmoothingEnabled=false;const labels=['Лёгкая · меч','Лёгкая · топор · шлем','Тяжёлая · меч · шлем','Тяжёлая · топор'];const compare=document.createElement('canvas');compare.width=512;compare.height=288;const qx=compare.getContext('2d'),sheet=document.getElementById('refsheet');qx.imageSmoothingEnabled=false;for(let t=0;t<4000;t+=80){ax.fillStyle='#202a34';ax.fillRect(0,0,512,512);configs.forEach((q,i)=>{const x=(i%2)*256,y=Math.floor(i/2)*256;draw(t,...q);ax.fillStyle='#202a34';ax.fillRect(x,y,256,256);ax.fillStyle='#e9edf1';ax.font='12px Arial';ax.textAlign='center';ax.fillText(labels[i],x+128,y+17);ax.drawImage(c,x+16,y+24,224,224)});out.frames.push(ac.toDataURL('image/png').split(',')[1]);draw(t,'light','sword','none','auto');qx.fillStyle='#202a34';qx.fillRect(0,0,512,288);qx.fillStyle='#e9edf1';qx.font='14px Arial';qx.textAlign='center';qx.fillText('Новый риг',128,18);qx.fillText('PixelLab',384,18);qx.drawImage(c,0,32);const pi=NaturalRig.pose(t,'auto'),fi=Math.max(0,Math.min(24,Math.floor((pi.actionTimeMs||0)/70)));qx.drawImage(sheet,(fi%8)*256,Math.floor(fi/8)*256,256,256,256,32,256,256);out.comparison.push(compare.toDataURL('image/png').split(',')[1])}
 const swapConfigs=[['light','sword','none'],['heavy','sword','none'],['heavy','axe','none'],['heavy','axe','steel']];for(const q of swapConfigs){draw(2360,...q);out.swaps.push(c.toDataURL('image/png').split(',')[1])}
 }catch(e){out.checks.push({name:'exception',pass:false,error:String(e)})}out.pass=out.checks.length>0&&out.checks.every(x=>x.pass);const pre=document.createElement('pre');pre.id='qa-output';pre.hidden=true;pre.textContent=JSON.stringify(out);document.body.append(pre)})();</script>'''


def cleanup_outputs() -> None:
    for name in ("overview.gif", "overview.png", "swap.gif", "comparison.gif", "gallery-screenshot.png", "browser-validation.json"):
        path = ROOT / name
        if path.exists():
            path.unlink()


def main() -> None:
    TEMP.mkdir(parents=True, exist_ok=True)
    source = ROOT / "gallery.html"
    if not source.is_file():
        raise SystemExit("Сначала запустите build_preview.py")
    target = TEMP / "preview-qa.html"
    target.write_text(source.read_text(encoding="utf-8") + SCRIPT, encoding="utf-8", newline="\n")
    edge = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")
    cmd = [str(edge), "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
           "--user-data-dir=" + str(TEMP / "headless-profile"), "--allow-file-access-from-files",
           "--hide-scrollbars", "--window-size=1440,1100", "--virtual-time-budget=12000",
           "--screenshot=" + str(ROOT / "gallery-screenshot.png"), "--dump-dom", target.as_uri()]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=90, encoding="utf-8", errors="replace")
        match = re.search(r'<pre id="qa-output"[^>]*>(.*?)</pre>', proc.stdout, re.S)
        if not match:
            raise RuntimeError(f"Edge не вернул QA DOM; exit={proc.returncode}; stderr={proc.stderr[-2000:]}")
        report = json.loads(html.unescape(match.group(1)))
        # Даже полный DOM не делает аварийно завершившийся браузер успешным прогоном.
        if proc.returncode != 0:
            report["pass"] = False
            report["error"] = f"Edge завершился с кодом {proc.returncode}"
        frames = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("frames")]
        comparison = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("comparison")]
        swaps = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("swaps")]
        if not report.get("pass"):
            cleanup_outputs()
        else:
            frames[0].save(ROOT / "overview.gif", save_all=True, append_images=frames[1:], duration=80, loop=0, disposal=2)
            Image.alpha_composite(Image.new("RGBA", frames[0].size, "#202a34"), frames[0]).convert("RGB").save(ROOT / "overview.png")
            opaque = [Image.alpha_composite(Image.new("RGBA", im.size, "#202a34"), im).resize((512, 512), Image.Resampling.NEAREST) for im in swaps]
            opaque[0].save(ROOT / "swap.gif", save_all=True, append_images=opaque[1:], duration=700, loop=0, disposal=2)
            comparison[0].save(ROOT / "comparison.gif", save_all=True, append_images=comparison[1:], duration=80, loop=0, disposal=2)
        report["export"] = {"overview_frames": len(frames), "overview_duration_ms": 4000, "swap_frames": len(swaps), "swap_duration_ms": 2800, "comparison_frames": len(comparison), "comparison_duration_ms": 4000, "source": "NaturalRig.render through the browser QA page"}
        report["browser_exit_code"] = proc.returncode
        (ROOT / "browser-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        print(json.dumps(report, ensure_ascii=False))
        if not report.get("pass") or proc.returncode != 0:
            raise SystemExit(1)
    except Exception:
        cleanup_outputs()
        raise


if __name__ == "__main__":
    main()
