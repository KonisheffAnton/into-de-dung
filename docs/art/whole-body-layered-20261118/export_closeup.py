"""Экспортирует крупные кадры существующей галереи без изменения ее исходников."""
from __future__ import annotations

import base64
import hashlib
import html
import io
import json
import re
import subprocess
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "closeup"
TEMP = Path("D:/Codex/home/generated_images/whole-body-layered-20261118/closeup-headless")
NAMES = ("body-3x.gif", "sword-3x.gif", "axe-3x.gif", "sequence-3x.gif", "body-first.png", "sword-strike.png", "validation.json")
SCRIPT = r'''<script>
(async()=>{const out={pass:false,frames:{},durations:{},checks:[],errors:[]};const check=(name,ok,detail)=>{out.checks.push({name,pass:!!ok,...(detail===undefined?{}:{detail})});if(!ok)throw Error(name)};try{
for(let i=0;i<1200;i++){const a=window.__wholeAssets;if(window.__wholeReady&&a&&Object.values(a.images).length&&Object.values(a.images).every(x=>x.complete&&x.naturalWidth>0))break;await new Promise(r=>setTimeout(r,25))}
const A=window.__wholeAssets;check('gallery assets loaded',!!A&&window.__wholeReady&&Object.values(A.images).every(x=>x.complete&&x.naturalWidth>0));
const manifest=A.manifest,body=Object.keys(manifest.bodies)[0],clips=['idle','attack'],configs=[['body','none'],['sword','sword'],['axe','axe']],frames=[];let cursor=0;const positions=[],sampleRows=[];
for(const clip of clips){for(let i=0;i<manifest.clips[clip].durations.length;i++){positions.push({time:cursor,clip,index:i,duration:manifest.clips[clip].durations[i]});cursor+=manifest.clips[clip].durations[i]}}
check('expected 29 sampled frames',positions.length===29);check('cycle duration is 2920ms',cursor===2920,String(cursor));
for(let v=0;v<configs.length;v++){const [key,weapon]=configs[v];out.frames[key]=[];out.durations[key]=[];for(let pi=0;pi<positions.length;pi++){const p=positions[pi];const c=document.createElement('canvas');c.width=c.height=256;const ctx=c.getContext('2d',{willReadFrequently:true});ctx.clearRect(0,0,256,256);const result=FrameRig.render(ctx,manifest,A.images,p.time,{body,weapon,helmet:'none',mode:'auto'});const ops=result.ops,bodyOps=ops.filter(o=>o.type==='body'),weaponOps=ops.filter(o=>o.type==='weapon'),helmetOps=ops.filter(o=>o.type==='helmet');const row={sample:result.sample,body:bodyOps.map(o=>o.path)};if(v===0)sampleRows.push(row);else check(key+' same socket, time and body path '+pi,JSON.stringify(row)===JSON.stringify(sampleRows[pi]));check(key+' body path and socket '+p.clip+'/'+p.index,bodyOps.length===1&&bodyOps[0].path===manifest.bodies[body][p.clip][p.index]);check(key+' no helmet ops '+p.clip+'/'+p.index,helmetOps.length===0);check(key+' weapon ops '+p.clip+'/'+p.index,weapon==='none'?weaponOps.length===0:weaponOps.length===1&&weaponOps[0].path===manifest.equipment[weapon].file);const px=ctx.getImageData(0,0,256,256).data;let border=true;for(let k=0;k<256;k++)if(px[(k*256)*4+3]!==0||px[(k*256+255)*4+3]!==0||px[k*4+3]!==0||px[(255*256+k)*4+3]!==0)border=false;check(key+' transparent native border '+p.clip+'/'+p.index,border);
const bg='rgb(32,42,52)',expectedCanvas=document.createElement('canvas');expectedCanvas.width=expectedCanvas.height=256;const ec=expectedCanvas.getContext('2d',{willReadFrequently:true});ec.fillStyle=bg;ec.fillRect(0,0,256,256);ec.drawImage(c,0,0);const expected=ec.getImageData(0,0,256,256).data;const canvas=document.createElement('canvas');canvas.width=768;canvas.height=832;const x=canvas.getContext('2d',{willReadFrequently:true});x.imageSmoothingEnabled=false;x.fillStyle='#202a34';x.fillRect(0,0,768,832);x.fillStyle='#e9edf1';x.font='bold 22px Arial';x.textAlign='center';x.fillText(['1/3 · Цельное тело','2/3 · С мечом','3/3 · С топором'][v],384,40);x.font='16px Arial';x.fillText(p.clip==='idle'?'Дыхание · скорость 1×':'Удар · скорость 1×',384,59);x.drawImage(c,0,64,768,768);const exported=x.getImageData(0,64,768,768).data;let exact=true,why='';for(let yy=0;yy<768&&exact;yy++)for(let xx=0;xx<768;xx++){const ni=(Math.floor(yy/3)*256+Math.floor(xx/3))*4,ei=(yy*768+xx)*4;if(exported[ei]!==expected[ni]||exported[ei+1]!==expected[ni+1]||exported[ei+2]!==expected[ni+2]||exported[ei+3]!==expected[ni+3]){exact=false;why=JSON.stringify({x:xx,y:yy,expected:Array.from(expected.slice(ni,ni+4)),exported:Array.from(exported.slice(ei,ei+4))});break}}check(key+' nearest-neighbor exact 3x '+p.clip+'/'+p.index,exact,why);out.frames[key].push(canvas.toDataURL('image/png').split(',')[1]);out.durations[key].push(p.duration);
if(v===0&&p.clip==='idle'&&p.index===0)out.first=canvas.toDataURL('image/png').split(',')[1];}
}
out.pass=out.checks.every(x=>x.pass);
}catch(e){out.errors.push(String(e));out.pass=false}const node=document.createElement('pre');node.id='closeup-result';node.hidden=true;node.textContent=JSON.stringify(out);document.body.append(node)})();</script>'''


def clean() -> None:
    for name in NAMES:
        p = OUT / name
        if p.is_file():
            p.unlink()


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    clean()
    source = ROOT / "gallery.html"
    if not source.is_file():
        raise SystemExit("Не найден gallery.html")
    TEMP.mkdir(parents=True, exist_ok=True)
    target = TEMP / "closeup-export.html"
    target.write_text(source.read_text(encoding="utf-8") + SCRIPT, encoding="utf-8", newline="\n")
    edge = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")
    cmd = [str(edge), "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
           "--user-data-dir=" + str(TEMP / "profile"), "--allow-file-access-from-files", "--hide-scrollbars",
           "--window-size=1000,1000", "--virtual-time-budget=90000", "--dump-dom", target.as_uri()]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=180, encoding="utf-8", errors="replace")
        match = re.search(r'<pre id="closeup-result"[^>]*>(.*?)</pre>', proc.stdout, re.S)
        if not match or proc.returncode != 0:
            raise RuntimeError(f"Edge export failed exit={proc.returncode}; stderr={proc.stderr[-3000:]}")
        report = json.loads(html.unescape(match.group(1)))
        if not report.get("pass"):
            raise RuntimeError("Browser acceptance failed: " + json.dumps([c for c in report.get("checks", []) if not c.get("pass")][:3], ensure_ascii=False))
        frames = report.pop("frames")
        durations = report.pop("durations")
        first = Image.open(io.BytesIO(base64.b64decode(report.pop("first")))).convert("RGBA")
        decoded = {key: [Image.open(io.BytesIO(base64.b64decode(s))).convert("RGBA") for s in images] for key, images in frames.items()}
        for key in ("body", "sword", "axe"):
            decoded[key][0].save(OUT / f"{key}-3x.gif", save_all=True, append_images=decoded[key][1:], duration=durations[key], loop=0, disposal=2)
        sequence = decoded["body"] + decoded["sword"] + decoded["axe"]
        seq_durations = durations["body"] + durations["sword"] + durations["axe"]
        sequence[0].save(OUT / "sequence-3x.gif", save_all=True, append_images=sequence[1:], duration=seq_durations, loop=0, disposal=2)
        first.save(OUT / "body-first.png")
        idle_count = len(json.loads((ROOT / "assets/manifest.json").read_text(encoding="utf-8"))["clips"]["idle"]["durations"])
        strike_index = idle_count + 11
        strike_time_ms = sum(durations["sword"][:strike_index])
        if strike_time_ms != 2370:
            raise RuntimeError(f"Ожидался кадр атаки на 2370 мс, рассчитано {strike_time_ms} мс")
        # Для оценки замаха нужен кадр завершения удара, а не исходная idle-поза.
        decoded["sword"][strike_index].save(OUT / "sword-strike.png")
        artifacts = {}
        for name in NAMES[:4]:
            path = OUT / name
            with Image.open(path) as gif:
                actual_durations = []
                for index in range(gif.n_frames):
                    gif.seek(index)
                    actual_durations.append(int(gif.info.get("duration", 0)))
                artifacts[name] = {"frames": gif.n_frames, "duration_ms": sum(actual_durations), "frame_durations_ms": actual_durations, "size_bytes": path.stat().st_size}
        for key in ("body", "sword", "axe"):
            report.setdefault("checks", []).append({"name": key + " browser frame count", "pass": len(decoded[key]) == 29})
        for name in NAMES[:3]:
            report["checks"].append({"name": name + " GIF duration is 2920ms", "pass": artifacts[name]["duration_ms"] == 2920})
        report["checks"].append({"name": "sequence GIF duration is 8760ms", "pass": artifacts["sequence-3x.gif"]["duration_ms"] == 8760})
        report["export"] = {"native_frames_per_variant": 29, "browser_frame_durations_ms": durations, "gif_artifacts": artifacts, "first_frame_png_size_bytes": (OUT / "body-first.png").stat().st_size, "sword_strike": {"time_ms": strike_time_ms, "clip": "attack", "frame": 11, "size_bytes": (OUT / "sword-strike.png").stat().st_size}, "edge_exit_code": proc.returncode}
        report["source_hashes"] = {name: digest(ROOT / name) for name in ("renderer.js", "gallery.html", "assets/manifest.json")}
        (OUT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        if not all(c.get("pass") for c in report["checks"]):
            raise RuntimeError("Post-export frame-count acceptance failed")
    except Exception as exc:
        clean()
        (OUT / "validation.json").write_text(json.dumps({"pass": False, "error": str(exc)}, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        raise


if __name__ == "__main__":
    main()
