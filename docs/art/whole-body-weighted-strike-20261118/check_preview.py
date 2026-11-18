"""Проверяет браузерную отрисовку и экспортирует GIF на границах кадров."""
from __future__ import annotations

import base64
import hashlib
import html
import io
import json
import re
import subprocess
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent
TEMP = Path("D:/Codex/home/generated_images/whole-body-weighted-strike-20261118/headless")
OUTPUTS = ("body-only.gif", "sword.gif", "axe.gif", "sequence.gif", "comparison.gif", "overview.png", "browser-validation.json")
VARIANTS = ("body", "sword", "axe")
GIF_NAMES = {"body": "body-only.gif", "sword": "sword.gif", "axe": "axe.gif"}

SCRIPT = r'''<script>
(async()=>{
  const out={pass:false,checks:[],frames:{body:[],sword:[],axe:[]},durations:{body:[],sword:[],axe:[]},comparison:[],comparisonDurations:[],gripPreview:"",samples:[],errors:[]};
  let phase="waiting for image decode";
  const check=(name,pass,detail="")=>{out.checks.push({name,pass:!!pass,...(detail?{detail}:{})});if(!pass)throw Error(name)};
  try {
    for(let i=0;i<1200;i++){
      const a=window.__wholeAssets,loaded=a&&Object.values(a.images).every(x=>x.complete&&x.naturalWidth>0);
      const old=document.getElementById("legacy-view")?.contentWindow?.__wholeAssets;
      const oldLoaded=old&&Object.values(old.images).every(x=>x.complete&&x.naturalWidth>0);
      if(window.__wholeReady&&loaded&&oldLoaded)break;
      await new Promise(r=>setTimeout(r,25));
    }
    const A=window.__wholeAssets;
    check("new gallery assets fully loaded",!!A&&window.__wholeReady&&Object.values(A.images).length>0&&Object.values(A.images).every(x=>x.complete&&x.naturalWidth>0));
    const legacyWindow=document.getElementById("legacy-view")?.contentWindow,legacyAssets=legacyWindow?.__wholeAssets;
    const legacyFailures=legacyAssets?Object.entries(legacyAssets.images).filter(([,image])=>!image.complete||image.naturalWidth<=0).map(([path])=>path):["iframe or assets unavailable"];
    check("legacy gallery images fully loaded",!!legacyAssets&&legacyWindow.__wholeReady&&legacyFailures.length===0,legacyFailures.slice(0,8).join(", "));
    phase="sampling dynamic manifest frames";
    const frameRows=[];let cursor=0,rootReference=null;
    for(const clip of ["idle","attack"]){
      const data=A.manifest.clips[clip];
      if(!data)continue;
      for(let i=0;i<data.durations.length;i++){
        frameRows.push({time:cursor,clip,index:i,duration:data.durations[i]});cursor+=data.durations[i];
      }
    }
    check("idle and attack contain frames",frameRows.length>0);
    const body=Object.keys(A.manifest.bodies)[0];
    const variants=[{key:"body",weapon:"none"},{key:"sword",weapon:"sword"},{key:"axe",weapon:"axe"}];
    const checkSamples=[];
    for(let vi=0;vi<variants.length;vi++){
      const variant=variants[vi];
      for(const p of frameRows){
        const canvas=document.createElement("canvas");canvas.width=canvas.height=256;
        const ctx=canvas.getContext("2d",{willReadFrequently:true});ctx.clearRect(0,0,256,256);
        const rendered=FrameRig.render(ctx,A.manifest,A.images,p.time,{body,weapon:variant.weapon,helmet:"none",mode:"auto"});
        const root=rendered.sample.socket.root||[0,0];
        if(rootReference===null)rootReference=root.slice();
        check("root preserves authored placement "+p.clip+"/"+p.index,JSON.stringify(root)===JSON.stringify(rootReference),JSON.stringify(root));
        const bodyOps=rendered.ops.filter(o=>o.type==="body"),weaponOps=rendered.ops.filter(o=>o.type==="weapon"),helmetOps=rendered.ops.filter(o=>o.type==="helmet");
        check(variant.key+" one full body draw "+p.clip+"/"+p.index,bodyOps.length===1);
        check(variant.key+" correct weapon operation "+p.clip+"/"+p.index,variant.weapon==="none"?weaponOps.length===0:weaponOps.length===1&&weaponOps[0].path===A.manifest.equipment[variant.weapon].file);
        check(variant.key+" has no helmet operation "+p.clip+"/"+p.index,helmetOps.length===0);
        const sampleRow={sample:rendered.sample,body:bodyOps.map(o=>o.path)};
        if(vi===0)checkSamples.push(sampleRow);else check(variant.key+" same sample, body path and socket "+p.clip+"/"+p.index,JSON.stringify(sampleRow)===JSON.stringify(checkSamples[frameRows.indexOf(p)]));
        if(vi===0){
          for(const weapon of ["none","sword","axe"])for(const helmet of ["none","steel"]){
            const comboCanvas=document.createElement("canvas");comboCanvas.width=comboCanvas.height=256;
            const comboCtx=comboCanvas.getContext("2d");comboCtx.clearRect(0,0,256,256);
            const combo=FrameRig.render(comboCtx,A.manifest,A.images,p.time,{body,weapon,helmet,mode:"auto"});
            const comboBody=combo.ops.filter(o=>o.type==="body"),comboWeapon=combo.ops.filter(o=>o.type==="weapon"),comboHelmet=combo.ops.filter(o=>o.type==="helmet");
            check("gear combination one full body "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,comboBody.length===1);
            check("gear combination keeps same body and socket "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,JSON.stringify({sample:combo.sample,body:comboBody.map(o=>o.path)})===JSON.stringify(sampleRow));
            check("weapon operation matches selection "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,weapon==="none"?comboWeapon.length===0:comboWeapon.length===1&&comboWeapon[0].path===A.manifest.equipment[weapon].file);
            check("helmet operation matches selection "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,helmet==="none"?comboHelmet.length===0:comboHelmet.length===1);
            const comboPixels=comboCtx.getImageData(0,0,256,256).data;let comboEdgeClear=true;
            for(let edge=0;edge<256;edge++)if(comboPixels[(edge*256)*4+3]||comboPixels[(edge*256+255)*4+3]||comboPixels[edge*4+3]||comboPixels[(255*256+edge)*4+3])comboEdgeClear=false;
            check("gear combination no crop at native perimeter "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,comboEdgeClear);
          }
        }
        const px=ctx.getImageData(0,0,256,256).data;let clear=true;
        for(let k=0;k<256;k++)if(px[(k*256)*4+3]||px[(k*256+255)*4+3]||px[k*4+3]||px[(255*256+k)*4+3])clear=false;
        check(variant.key+" native perimeter transparent "+p.clip+"/"+p.index,clear);
        const composite=document.createElement("canvas");composite.width=composite.height=256;
        const cc=composite.getContext("2d");cc.fillStyle="#202a34";cc.fillRect(0,0,256,256);cc.drawImage(canvas,0,0);
        const image=document.createElement("canvas");image.width=768;image.height=832;
        const ic=image.getContext("2d",{willReadFrequently:true});ic.imageSmoothingEnabled=false;ic.fillStyle="#202a34";ic.fillRect(0,0,768,832);
        ic.fillStyle="#e9edf1";ic.textAlign="center";ic.font="bold 22px Arial";ic.fillText(["Цельное тело","С мечом","С топором"][vi],384,39);
        ic.font="16px Arial";ic.fillText(p.clip==="idle"?"Покой · 1×":"Атака · 1×",384,59);ic.drawImage(canvas,0,64,768,768);
        const expected=cc.getImageData(0,0,256,256).data,actual=ic.getImageData(0,64,768,768).data;let exact=true;
        for(let y=0;y<768&&exact;y++)for(let x=0;x<768;x++){
          const si=(Math.floor(y/3)*256+Math.floor(x/3))*4,di=(y*768+x)*4;
          if(actual[di]!==expected[si]||actual[di+1]!==expected[si+1]||actual[di+2]!==expected[si+2]||actual[di+3]!==expected[si+3]){exact=false;break;}
        }
        check(variant.key+" exact nearest 3x composite "+p.clip+"/"+p.index,exact);
        out.frames[variant.key].push(image.toDataURL("image/png").split(",")[1]);out.durations[variant.key].push(p.duration);
      }
    }
    out.samples=checkSamples;out.frameCount=frameRows.length;out.cycleDurationMs=cursor;
    phase="building 1x side-by-side comparison";
    const oldWindow=document.getElementById("legacy-view").contentWindow,oldAssets=oldWindow.__wholeAssets;
    const oldManifest=oldAssets.manifest,oldRig=oldWindow.FrameRig;
    const total=(manifest)=>["idle","attack"].reduce((sum,name)=>sum+(manifest.clips[name]?.durations||[]).reduce((a,b)=>a+b,0),0);
    const oldDuration=total(oldManifest),boundaries=new Set([0,cursor]);
    for(const manifest of [A.manifest]){
      let at=0;
      for(const clip of ["idle","attack"]){
        for(const duration of manifest.clips[clip]?.durations||[]){if(at>0&&at<cursor)boundaries.add(at);at+=duration;}
      }
    }
    for(let cycle=0;cycle*oldDuration<cursor;cycle++){
      let at=cycle*oldDuration;
      for(const clip of ["idle","attack"]){
        for(const duration of oldManifest.clips[clip]?.durations||[]){if(at>0&&at<cursor)boundaries.add(at);at+=duration;}
      }
    }
    const sorted=[...boundaries].sort((a,b)=>a-b),oldBody=Object.keys(oldManifest.bodies)[0],comparisonDurations=[];
    for(let i=0;i<sorted.length-1;i++){
      const t=sorted[i],duration=sorted[i+1]-t,board=document.createElement("canvas");board.width=1024;board.height=576;
      const bx=board.getContext("2d");bx.imageSmoothingEnabled=false;bx.fillStyle="#202a34";bx.fillRect(0,0,1024,576);
      bx.fillStyle="#e9edf1";bx.font="bold 20px Arial";bx.textAlign="center";bx.fillText("Предыдущая версия · собственный цикл 1×",256,30);bx.fillText("Новое цельное тело · собственный цикл 1×",768,30);
      for(const [x,rig,manifest,images,selectedBody] of [[0,oldRig,oldManifest,oldAssets.images,oldBody],[512,FrameRig,A.manifest,A.images,body]]){
        const cell=document.createElement("canvas");cell.width=cell.height=256;const cx=cell.getContext("2d");cx.clearRect(0,0,256,256);
        try{rig.render(cx,manifest,images,t,{body:selectedBody,weapon:"sword",helmet:"none",mode:"auto"});}
        catch(error){throw Error((x===0?"legacy":"new")+" comparison draw at "+t+": "+error);}
        bx.drawImage(cell,x,48,512,512);
      }
      out.comparison.push(board.toDataURL("image/png").split(",")[1]);comparisonDurations.push(duration);
    }
    out.comparisonDurations=comparisonDurations;out.oldCycleDurationMs=oldDuration;out.comparisonDurationMs=comparisonDurations.reduce((a,b)=>a+b,0);
    phase="capturing sword/axe grip example";
    const attack=A.manifest.clips.attack,gripIndex=Math.min(15,attack.durations.length-1);
    const gripTime=A.manifest.clips.idle.durations.reduce((a,b)=>a+b,0)+attack.durations.slice(0,gripIndex).reduce((a,b)=>a+b,0);
    const gripBoard=document.createElement("canvas");gripBoard.width=1024;gripBoard.height=576;
    const gb=gripBoard.getContext("2d");gb.imageSmoothingEnabled=false;gb.fillStyle="#202a34";gb.fillRect(0,0,1024,576);
    gb.fillStyle="#e9edf1";gb.font="bold 22px Arial";gb.textAlign="center";gb.fillText("Атака · кадр "+(gripIndex+1)+" · шлем и меч",256,42);gb.fillText("Атака · кадр "+(gripIndex+1)+" · шлем и топор",768,42);
    for(const [x,weapon] of [[0,"sword"],[512,"axe"]]){
      const gripCanvas=document.createElement("canvas");gripCanvas.width=gripCanvas.height=256;
      FrameRig.render(gripCanvas.getContext("2d"),A.manifest,A.images,gripTime,{body,weapon,helmet:"steel",mode:"auto"});
      gb.drawImage(gripCanvas,x,64,512,512);
    }
    out.gripPreview=gripBoard.toDataURL("image/png").split(",")[1];out.gripFrame={clip:"attack",index:gripIndex,timeMs:gripTime};
    out.pass=out.checks.every(c=>c.pass);
  }catch(e){
    const images=(asset)=>asset?Object.entries(asset.images).filter(([,image])=>!image.complete||image.naturalWidth<=0).slice(0,12).map(([path,image])=>({path,complete:image.complete,naturalWidth:image.naturalWidth,srcPrefix:String(image.src).slice(0,40)})):[];
    out.errorPhase=phase;out.checksBeforeError=out.checks.length;out.errorStack=String(e.stack||e);
    out.failedNewImages=images(window.__wholeAssets);out.failedLegacyImages=images(document.getElementById("legacy-view")?.contentWindow?.__wholeAssets);
    out.errors.push(String(e));out.pass=false;
  }
  const pre=document.createElement("pre");pre.id="qa-output";pre.hidden=true;pre.textContent=JSON.stringify(out);document.body.append(pre);
})();</script>'''


def _clean() -> None:
    for name in OUTPUTS:
        path = ROOT / name
        if path.is_file():
            path.unlink()


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _read_dom(stdout: str) -> dict[str, Any]:
    match = re.search(r'<pre id="qa-output"[^>]*>(.*?)</pre>', stdout, re.S)
    if not match:
        raise RuntimeError("Edge не вернул браузерный QA DOM")
    return json.loads(html.unescape(match.group(1)))


def _images(values: list[str]) -> list[Image.Image]:
    return [Image.open(io.BytesIO(base64.b64decode(value))).convert("RGBA") for value in values]


def _save_gif(path: Path, frames: list[Image.Image], durations: list[int]) -> dict[str, Any]:
    if not frames or len(frames) != len(durations):
        raise RuntimeError(f"Некорректный набор GIF кадров: {path.name}")
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations, loop=0, disposal=2, optimize=False)
    with Image.open(path) as gif:
        actual = []
        for index in range(gif.n_frames):
            gif.seek(index)
            actual.append(int(gif.info.get("duration", 0)))
        return {"size": list(gif.size), "frames": gif.n_frames, "durations_ms": actual, "duration_ms": sum(actual), "bytes": path.stat().st_size}


def main() -> None:
    _clean()
    source = ROOT / "gallery.html"
    if not source.is_file():
        raise SystemExit("Сначала запустите build_preview.py")
    TEMP.mkdir(parents=True, exist_ok=True)
    target = TEMP / "preview-qa.html"
    target.write_text(source.read_text(encoding="utf-8") + SCRIPT, encoding="utf-8", newline="\n")
    edge = Path("C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe")
    cmd = [str(edge), "--headless", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
           "--user-data-dir=" + str(TEMP / "profile"), "--allow-file-access-from-files", "--hide-scrollbars",
           "--window-size=1440,1100", "--virtual-time-budget=90000", "--dump-dom", target.as_uri()]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=180, encoding="utf-8", errors="replace")
        report = _read_dom(proc.stdout)
        if proc.returncode:
            report["checks"].append({"name": "Edge exit code", "pass": False, "detail": str(proc.returncode)})
            report["pass"] = False
        if not report.get("pass"):
            raise RuntimeError(json.dumps(report.get("errors", []) + [x for x in report.get("checks", []) if not x.get("pass")][:4], ensure_ascii=False))
        frames = {name: _images(report["frames"][name]) for name in VARIANTS}
        durations = {name: report["durations"][name] for name in VARIANTS}
        report.pop("frames", None)
        report.pop("durations", None)
        artifacts = {}
        for name in VARIANTS:
            filename = GIF_NAMES[name]
            artifacts[filename] = _save_gif(ROOT / filename, frames[name], durations[name])
        seq_frames = frames["body"] + frames["sword"] + frames["axe"]
        seq_durations = durations["body"] + durations["sword"] + durations["axe"]
        artifacts["sequence.gif"] = _save_gif(ROOT / "sequence.gif", seq_frames, seq_durations)
        overview = frames["sword"][0].convert("RGB")
        overview.save(ROOT / "overview.png")
        expected_duration = report["cycleDurationMs"]
        for name in GIF_NAMES.values():
            meta = artifacts[name]
            report["checks"].append({"name": name + " dimensions 768x832", "pass": meta["size"] == [768, 832]})
            report["checks"].append({"name": name + " keeps cycle duration", "pass": meta["duration_ms"] == expected_duration and meta["frames"] > 0})
        seq = artifacts["sequence.gif"]
        report["checks"].append({"name": "sequence.gif dimensions 768x832", "pass": seq["size"] == [768, 832]})
        report["checks"].append({"name": "sequence.gif keeps three cycles", "pass": seq["duration_ms"] == expected_duration * 3 and seq["frames"] > 0})
        comparison_frames = _images(report.pop("comparison"))
        comparison_durations = report.pop("comparisonDurations")
        grip_preview = Image.open(io.BytesIO(base64.b64decode(report.pop("gripPreview")))).convert("RGBA")
        grip_frame = report.pop("gripFrame")
        temp_preview = TEMP / "grip-attack-sword-axe-helmet.png"
        grip_preview.save(temp_preview)
        artifacts["comparison.gif"] = _save_gif(ROOT / "comparison.gif", comparison_frames, comparison_durations)
        comparison = artifacts["comparison.gif"]
        report["checks"].append({"name": "comparison.gif dimensions 1024x576", "pass": comparison["size"] == [1024, 576]})
        report["checks"].append({"name": "comparison.gif spans one new cycle at 1x", "pass": comparison["duration_ms"] == expected_duration and report.get("comparisonDurationMs") == expected_duration})
        report["export"] = {"artifacts": artifacts, "grip_preview": {"path": str(temp_preview), "size": list(grip_preview.size), **grip_frame}, "frame_count_per_variant": report["frameCount"], "cycle_duration_ms": expected_duration, "source": "FrameRig.render at exact manifest frame boundaries"}
        report["source_hashes"] = {name: _digest(ROOT / name) for name in ("renderer.js", "gallery.html", "assets/manifest.json")}
        report["pass"] = all(c.get("pass") for c in report["checks"])
        (ROOT / "browser-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        print(json.dumps({"pass": report["pass"], "checks": len(report["checks"]), "frame_count": report["frameCount"], "cycle_duration_ms": expected_duration, "artifacts": artifacts}, ensure_ascii=False))
        if not report["pass"]:
            _clean()
            raise SystemExit(1)
    except Exception as exc:
        _clean()
        (ROOT / "browser-validation.json").write_text(json.dumps({"pass": False, "error": str(exc)}, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        raise


if __name__ == "__main__":
    main()
