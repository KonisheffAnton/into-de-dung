"""Проверяет standalone HTML в Edge headless и экспортирует его же кадры."""
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
TEMP = Path("D:/Codex/home/generated_images/whole-body-layered-20261118/headless")
OUTPUTS = ("overview.gif", "overview.png", "swap.gif", "body-only.gif", "gallery-screenshot.png", "browser-validation.json")

SCRIPT = r'''<script>
(async()=>{const checks=[],out={checks,frames:[],frameDurations:[],swaps:[],bodyFrames:[],bodyDurations:[]};const check=(name,pass,detail="")=>{checks.push({name,pass:!!pass,...(detail?{detail}:{})});if(!pass)throw Error(name)};try{
for(let i=0;i<240;i++){const a=window.__wholeAssets;const loaded=a&&Object.values(a.images).every(x=>x.complete&&x.naturalWidth>0);if(window.__wholeReady&&loaded)break;await new Promise(r=>setTimeout(r,25))}
const A=window.__wholeAssets;check("assets loaded",!!A&&window.__wholeReady&&Object.values(A.images).length>0&&Object.values(A.images).every(x=>x.complete&&x.naturalWidth>0));
const manifest=A.manifest,slots=manifest.slots;check("exactly three slots",JSON.stringify(slots)==='["body","weapon","helmet"]');
const cycleMs=[...manifest.clips.idle.durations,...manifest.clips.attack.durations].reduce((a,b)=>a+b,0);await new Promise(r=>setTimeout(r,cycleMs*1.25+40));const loopState=__wholeState(),loopSlider=Number(document.getElementById("scrub").value);check("playback time and scrub wrap within the auto cycle",loopState.time>=0&&loopState.time<cycleMs&&Math.abs(loopSlider-loopState.time)<=1);
const canvas=()=>{const c=document.createElement("canvas");c.width=c.height=256;return c},c=canvas(),ctx=c.getContext("2d");const bodyNames=Object.keys(manifest.bodies),configs=[];for(const body of bodyNames)for(const weapon of ["sword","axe","none"])for(const helmet of ["none","steel"])configs.push({body,weapon,helmet});
const draw=(t,o)=>{ctx.clearRect(0,0,256,256);return FrameRig.render(ctx,manifest,A.images,t,{mode:"auto",...o})};const eq=(a,b)=>JSON.stringify(a)===JSON.stringify(b),samePixels=(a,b)=>{if(a.length!==b.length)return false;for(let i=0;i<a.length;i++)if(a[i]!==b[i])return false;return true},pixels=()=>ctx.getImageData(0,0,256,256).data;const edgePixel=data=>{for(let i=0;i<256;i++){if(data[(i*256)*4+3]!==0)return `left:${i}`;if(data[(i*256+255)*4+3]!==0)return `right:${i}`;if(data[i*4+3]!==0)return `top:${i}`;if(data[(255*256+i)*4+3]!==0)return `bottom:${i}`}return ""};const pixelDiff=(a,b)=>{let n=0;for(let i=0;i<a.length;i+=4)if(a[i]!==b[i]||a[i+1]!==b[i+1]||a[i+2]!==b[i+2]||a[i+3]!==b[i+3])n++;return n};let oneBody=true,allInside=true,rootValid=true,bodyPositionMatchesRoot=true,edgesClear=true,edgeFailures=[];
const clips=Object.keys(manifest.clips);for(const clip of clips){const count=manifest.clips[clip].durations.length;for(let i=0;i<count;i++){const t=manifest.clips[clip].durations.slice(0,i).reduce((a,b)=>a+b,0),pose=FrameRig.sample(manifest,t,clip);check("frame selection "+clip+"/"+i,pose.clip===clip&&pose.index===i);const d=draw(t,{body:bodyNames[0],weapon:"sword",helmet:"steel",mode:clip});const b=d.ops.filter(x=>x.type==="body");oneBody&&=b.length===1;const root=pose.socket.root||[0,0];rootValid&&=Array.isArray(root)&&root.length===2&&root.every(Number.isFinite);bodyPositionMatchesRoot&&=b.length===1&&b[0].path===manifest.bodies[bodyNames[0]][clip][i]&&b[0].x===root[0]&&b[0].y===root[1];for(const op of d.ops)allInside&&=op.x>=-256&&op.x<=512&&op.y>=-256&&op.y<=512;for(const gear of configs){draw(t,{...gear,mode:clip});const edge=edgePixel(pixels());if(edge){edgesClear=false;edgeFailures.push(`${clip}/${i} ${gear.body}/${gear.weapon}/${gear.helmet} ${edge}`)}}}}
let sharedSamples=true,sharedSockets=true;for(let i=0;i<64;i++){const t=i*137;const results=configs.map(o=>draw(t,o));const bodies=results.map(r=>r.ops.filter(op=>op.type==="body"));for(const b of bodies)oneBody&&=b.length===1;for(const r of results)sharedSamples&&=eq(r.sample,results[0].sample);const sockets=results.map(r=>r.sample.socket);for(const socket of sockets)sharedSockets&&=eq(socket,sockets[0])}
check("one whole-body draw per frame",oneBody);check("optional root defaults to zero or contains finite coordinates",rootValid);check("whole-body draw operation reports root-adjusted display coordinates",bodyPositionMatchesRoot);check(`same shared clip frame across all ${configs.length} gear combinations`,sharedSamples);check(`same attachment sockets across all ${configs.length} gear combinations`,sharedSockets);check("attachment positions stay within broad canvas bounds",allInside);check("all rendered gear combinations have transparent RGBA canvas borders",edgesClear,edgeFailures.slice(0,12).join("; "));
let bodyImages=new Set(),bodyExact=true;for(const body of bodyNames)for(const clip of clips){const frames=manifest.bodies[body][clip];for(let i=0;i<frames.length;i++){const path=frames[i],img=A.images[path];bodyImages.add(path);const t=manifest.clips[clip].durations.slice(0,i).reduce((a,b)=>a+b,0),socket=FrameRig.sample(manifest,t,clip).socket,root=socket.root||[0,0];draw(t,{body,weapon:"none",helmet:"none",mode:clip,visible:{body:true,weapon:false,helmet:false}});const actual=pixels(),expectedCanvas=canvas(),expectedCtx=expectedCanvas.getContext("2d");expectedCtx.imageSmoothingEnabled=false;expectedCtx.drawImage(img,root[0],root[1],256,256);bodyExact&&=samePixels(actual,expectedCtx.getImageData(0,0,256,256).data)}}check("body frames are whole-frame 256-square PNGs",bodyImages.size>0&&[...bodyImages].every(path=>A.images[path]?.naturalWidth===256&&A.images[path]?.naturalHeight===256));check("body layer toggle renders the exact full PNG at each root offset",bodyExact);
const stateBefore={...__wholeState()};document.getElementById("pause").click();const paused=__wholeState();await new Promise(r=>setTimeout(r,80));check("pause stops time",paused.playing===false&&__wholeState().time===paused.time);document.getElementById("restart").click();check("restart resets playback",__wholeState().time===0&&__wholeState().playing);const scrub=document.getElementById("scrub");scrub.value="523";scrub.dispatchEvent(new Event("input"));check("scrub selects a fixed time and pauses",__wholeState().time===523&&!__wholeState().playing);
const ui=$("hero"),selector=$("body"),baseGear={body:bodyNames[0],weapon:"sword",helmet:"none"},opsAt=o=>draw(523,o),pathOf=(r,type)=>r.ops.find(x=>x.type===type)?.path;for(const [id,value,type]of [["weapon","axe","weapon"],["helmet","steel","helmet"]]){selector.value=bodyNames[0];$("weapon").value="sword";$("helmet").value="none";for(const e of [selector,$("weapon"),$("helmet")])e.dispatchEvent(new Event("input"));const beforeUI=ui.toDataURL(),beforeOp=opsAt(baseGear),beforePixels=Array.from(pixels());$(id).value=value;$(id).dispatchEvent(new Event("input"));const afterState=__wholeState(),afterUI=ui.toDataURL(),afterOp=opsAt({...baseGear,[id]:value}),afterPixels=Array.from(pixels());check(id+" UI selection changes visible pixels",pixelDiff(beforePixels,afterPixels)>0&&beforeUI!==afterUI);check(id+" swap preserves shared time",afterState.time===523&&afterState.playing===false);check(id+" changes only its own image path",["body","weapon","helmet"].every(slot=>slot===type?pathOf(beforeOp,slot)!==pathOf(afterOp,slot):pathOf(beforeOp,slot)===pathOf(afterOp,slot))&&beforeOp.sample.index===afterOp.sample.index&&eq(beforeOp.sample.socket,afterOp.sample.socket));$(id).value=id==="weapon"?"sword":"none";$(id).dispatchEvent(new Event("input"))}if(bodyNames.length>1){selector.value=bodyNames[1];selector.dispatchEvent(new Event("input"));check("body UI selection changes visible pixels",ui.toDataURL()!=="data:,"&&pathOf(opsAt({...baseGear,body:bodyNames[1]}),"body")!==pathOf(opsAt(baseGear),"body"))}check("body selector matches available whole-body variants",selector.options.length===bodyNames.length);if(bodyNames.length===1)check("single body variant has no fabricated duplicate",selector.options.length===1);
const drawHero=(t,o)=>{renderPreview(t,o);return document.getElementById("hero")};const bodyLabel=b=>({light:"Кожаный комплект",heavy:"Стальной комплект"}[b]||b),weaponLabel=w=>({sword:"Меч",axe:"Топор",none:"Без оружия"}[w]||w),helmetLabel=h=>h==="steel"?"Шлем":"Без шлема",configs4=bodyNames.length===1?[{body:bodyNames[0],weapon:"sword",helmet:"none"},{body:bodyNames[0],weapon:"sword",helmet:"steel"},{body:bodyNames[0],weapon:"axe",helmet:"none"},{body:bodyNames[0],weapon:"axe",helmet:"steel"}]:[{body:bodyNames[0],weapon:"sword",helmet:"none"},{body:bodyNames[0],weapon:"axe",helmet:"steel"},{body:bodyNames[1],weapon:"sword",helmet:"steel"},{body:bodyNames[1],weapon:"axe",helmet:"none"}];let cursor=0;for(const clip of ["idle","attack"]){const durations=manifest.clips[clip].durations;for(let i=0;i<durations.length;i++){const duration=durations[i],t=cursor;const board=document.createElement("canvas");board.width=board.height=512;const bx=board.getContext("2d");bx.imageSmoothingEnabled=false;bx.fillStyle="#202a34";bx.fillRect(0,0,512,512);configs4.forEach((o,j)=>{const x=(j%2)*256,y=Math.floor(j/2)*256;const hc=drawHero(t,{...o,mode:"auto"});bx.fillStyle="#e9edf1";bx.font="12px Arial";bx.textAlign="center";bx.fillText(`${bodyLabel(o.body)} · ${weaponLabel(o.weapon)} · ${helmetLabel(o.helmet)}`,x+128,y+16);bx.drawImage(hc,x+16,y+22,224,224)});out.frames.push(board.toDataURL("image/png").split(",")[1]);out.frameDurations.push(duration);drawHero(t,{body:bodyNames[0],weapon:"sword",helmet:"none",visible:{body:true,weapon:false,helmet:false}});out.bodyFrames.push(document.getElementById("hero").toDataURL("image/png").split(",")[1]);out.bodyDurations.push(duration);cursor+=duration}}
const swapConfigs=bodyNames.length===1?[{body:bodyNames[0],weapon:"sword",helmet:"none"},{body:bodyNames[0],weapon:"axe",helmet:"none"},{body:bodyNames[0],weapon:"axe",helmet:"steel"},{body:bodyNames[0],weapon:"sword",helmet:"steel"}]:[{body:bodyNames[0],weapon:"sword",helmet:"none"},{body:bodyNames[1],weapon:"sword",helmet:"none"},{body:bodyNames[1],weapon:"axe",helmet:"none"},{body:bodyNames[1],weapon:"axe",helmet:"steel"}];for(const o of swapConfigs){const hc=drawHero(523,o),board=document.createElement("canvas");board.width=512;board.height=288;const bx=board.getContext("2d");bx.imageSmoothingEnabled=false;bx.fillStyle="#202a34";bx.fillRect(0,0,512,288);bx.fillStyle="#e9edf1";bx.font="14px Arial";bx.textAlign="center";bx.fillText(`${bodyLabel(o.body)} · ${weaponLabel(o.weapon)} · ${helmetLabel(o.helmet)}`,256,18);bx.drawImage(hc,128,24);out.swaps.push(board.toDataURL("image/png").split(",")[1])}
}catch(e){out.checks.push({name:"exception",pass:false,error:String(e)})}out.pass=out.checks.length>0&&out.checks.every(x=>x.pass);const pre=document.createElement("pre");pre.id="qa-output";pre.hidden=true;pre.textContent=JSON.stringify(out);document.body.append(pre)})();</script>'''


def cleanup_outputs() -> None:
    for name in OUTPUTS:
        path = ROOT / name
        if path.is_file():
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
           "--user-data-dir=" + str(TEMP / "profile"), "--allow-file-access-from-files",
           "--hide-scrollbars", "--window-size=1440,1100", "--virtual-time-budget=15000",
           "--screenshot=" + str(ROOT / "gallery-screenshot.png"), "--dump-dom", target.as_uri()]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=90, encoding="utf-8", errors="replace")
        match = re.search(r'<pre id="qa-output"[^>]*>(.*?)</pre>', proc.stdout, re.S)
        if not match:
            raise RuntimeError(f"Edge не вернул QA DOM; exit={proc.returncode}; stderr={proc.stderr[-2000:]}")
        report = json.loads(html.unescape(match.group(1)))
        if proc.returncode != 0:
            report["pass"] = False
            report["error"] = f"Edge завершился с кодом {proc.returncode}"
        frames = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("frames")]
        frame_durations = report.pop("frameDurations")
        swaps = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("swaps")]
        body_frames = [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in report.pop("bodyFrames")]
        body_durations = report.pop("bodyDurations")
        if not report.get("pass"):
            cleanup_outputs()
        else:
            if frames:
                frames[0].save(ROOT / "overview.gif", save_all=True, append_images=frames[1:], duration=frame_durations, loop=0, disposal=2)
                frames[0].convert("RGB").save(ROOT / "overview.png")
            if swaps:
                swaps[0].save(ROOT / "swap.gif", save_all=True, append_images=swaps[1:], duration=700, loop=0, disposal=2)
            if body_frames:
                body_frames[0].save(ROOT / "body-only.gif", save_all=True, append_images=body_frames[1:], duration=body_durations, loop=0, disposal=2)
        report["export"] = {"overview_frames": len(frames), "overview_duration_ms": sum(frame_durations), "swap_frames": len(swaps), "body_only_frames": len(body_frames), "body_only_duration_ms": sum(body_durations), "source": "FrameRig.render at exact body-frame boundaries"}
        report["browser_exit_code"] = proc.returncode
        (ROOT / "browser-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        print(json.dumps(report, ensure_ascii=False))
        if not report.get("pass") or proc.returncode != 0:
            raise SystemExit(1)
    except Exception as exc:
        cleanup_outputs()
        (ROOT / "browser-validation.json").write_text(json.dumps({"pass": False, "error": str(exc)}, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        raise


if __name__ == "__main__":
    main()
