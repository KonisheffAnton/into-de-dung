"""Проверяет браузерный показ и экспортирует автономные GIF превью."""
from __future__ import annotations

import base64
import hashlib
import io
import json
import subprocess
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parent
TEMP = Path("D:/Codex/home/generated_images/whole-body-smooth-strike-20261119/headless")
OUTPUTS = ("body-only.gif", "sword.gif", "axe.gif", "sequence.gif", "comparison.gif", "overview.png", "browser-validation.json")
VARIANTS = ("body", "sword", "axe")
GIF_NAMES = {"body": "body-only.gif", "sword": "sword.gif", "axe": "axe.gif"}

SCRIPT = r'''<script>
(async()=>{
  const out={pass:false,checks:[],frames:{body:[],sword:[],axe:[]},durations:{body:[],sword:[],axe:[]},comparison:[],comparisonDurations:[],grips:[],errors:[]};
  let phase="waiting for image decode";
  const check=(name,pass,detail="")=>{out.checks.push({name,pass:!!pass,...(detail?{detail}:{})});if(!pass)throw Error(name)};
  const loaded=a=>a&&Object.values(a.images).length>0&&Object.values(a.images).every(i=>i.complete&&i.naturalWidth>0&&i.naturalHeight>0);
  try{
    for(let i=0;i<1200;i++){if(window.__wholeReady&&window.__legacyReady&&loaded(window.__wholeAssets)&&loaded(window.__legacyAssets))break;await new Promise(r=>setTimeout(r,25));}
    const A=window.__wholeAssets,L=window.__legacyAssets;
    check("new assets decoded",window.__wholeReady&&loaded(A));check("previous assets decoded",window.__legacyReady&&loaded(L));
    phase="sampling variable manifest frames";
    const rows=[];let cursor=0;
    for(const clip of ["idle","attack"]){const data=A.manifest.clips[clip];if(!data)continue;for(let i=0;i<data.durations.length;i++){rows.push({time:cursor,clip,index:i,duration:data.durations[i]});cursor+=data.durations[i];}}
    check("idle and attack frames present",rows.length>0);check("variable frame count exceeds fixed six-frame sample",rows.length>6,String(rows.length));
    const body=Object.keys(A.manifest.bodies)[0],oldBody=Object.keys(L.manifest.bodies)[0],sampleRows=[];
    const choices=[{key:"body",weapon:"none"},{key:"sword",weapon:"sword"},{key:"axe",weapon:"axe"}];
    const edgeClear=data=>{for(let k=0;k<256;k++)if(data[(k*256)*4+3]||data[(k*256+255)*4+3]||data[k*4+3]||data[(255*256+k)*4+3])return false;return true;};
    for(let vi=0;vi<choices.length;vi++){
      const v=choices[vi];
      for(const p of rows){
        const c=document.createElement("canvas");c.width=c.height=256;const x=c.getContext("2d",{willReadFrequently:true});x.clearRect(0,0,256,256);
        const result=FrameRig.render(x,A.manifest,A.images,p.time,{body,weapon:v.weapon,helmet:"none",mode:"auto"});
        const sample={frame:result.sample,body:result.ops.filter(o=>o.type==="body").map(o=>o.path)};
        const bodyOps=result.ops.filter(o=>o.type==="body"),weaponOps=result.ops.filter(o=>o.type==="weapon"),helmetOps=result.ops.filter(o=>o.type==="helmet");
        check(v.key+" one full-body draw "+p.clip+"/"+p.index,bodyOps.length===1);
        check(v.key+" weapon draw selection "+p.clip+"/"+p.index,v.weapon==="none"?weaponOps.length===0:weaponOps.length===1&&weaponOps[0].path===A.manifest.equipment[v.weapon].file);
        check(v.key+" no helmet in main export "+p.clip+"/"+p.index,helmetOps.length===0);
        if(vi===0)sampleRows.push(sample);else check(v.key+" same body frame and sockets "+p.clip+"/"+p.index,JSON.stringify(sample)===JSON.stringify(sampleRows[rows.indexOf(p)]));
        if(vi===0){
          for(const weapon of ["none","sword","axe"])for(const helmet of ["none","steel"]){
            const cc=document.createElement("canvas");cc.width=cc.height=256;const cx=cc.getContext("2d",{willReadFrequently:true});cx.clearRect(0,0,256,256);
            const r=FrameRig.render(cx,A.manifest,A.images,p.time,{body,weapon,helmet,mode:"auto"});
            check("combo one body "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,r.ops.filter(o=>o.type==="body").length===1);
            check("combo keeps frame and socket "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,JSON.stringify({frame:r.sample,body:r.ops.filter(o=>o.type==="body").map(o=>o.path)})===JSON.stringify(sample));
            const wo=r.ops.filter(o=>o.type==="weapon"),ho=r.ops.filter(o=>o.type==="helmet");
            check("combo weapon choice "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,weapon==="none"?wo.length===0:wo.length===1&&wo[0].path===A.manifest.equipment[weapon].file);
            check("combo helmet choice "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,helmet==="none"?ho.length===0:ho.length===1);
            check("combo fully transparent perimeter "+weapon+"/"+helmet+" "+p.clip+"/"+p.index,edgeClear(cx.getImageData(0,0,256,256).data));
          }
        }
        check(v.key+" transparent native perimeter "+p.clip+"/"+p.index,edgeClear(x.getImageData(0,0,256,256).data));
        const composite=document.createElement("canvas");composite.width=composite.height=256;const bx=composite.getContext("2d");bx.fillStyle="#202a34";bx.fillRect(0,0,256,256);bx.drawImage(c,0,0);
        const sheet=document.createElement("canvas");sheet.width=768;sheet.height=832;const sx=sheet.getContext("2d",{willReadFrequently:true});sx.imageSmoothingEnabled=false;sx.fillStyle="#202a34";sx.fillRect(0,0,768,832);
        sx.fillStyle="#e9edf1";sx.textAlign="center";sx.font="bold 22px Arial";sx.fillText(["Цельное тело","С мечом","С топором"][vi],384,39);sx.font="16px Arial";sx.fillText(p.clip==="idle"?"Дыхание · 1×":"Удар · 1×",384,59);sx.drawImage(c,0,64,768,768);
        const expected=bx.getImageData(0,0,256,256).data,actual=sx.getImageData(0,64,768,768).data;let exact=true;
        for(let y=0;y<768&&exact;y++)for(let xx=0;xx<768;xx++){const si=(Math.floor(y/3)*256+Math.floor(xx/3))*4,di=(y*768+xx)*4;if(actual[di]!==expected[si]||actual[di+1]!==expected[si+1]||actual[di+2]!==expected[si+2]||actual[di+3]!==expected[si+3]){exact=false;break;}}
        check(v.key+" exact 3x nearest grid "+p.clip+"/"+p.index,exact);out.frames[v.key].push(sheet.toDataURL("image/png").split(",")[1]);out.durations[v.key].push(p.duration);
      }
    }
    out.frameCount=rows.length;out.cycleDurationMs=cursor;
    phase="testing shared controls and gear-preserved time";
    const state=window.__wholeState;check("QA control state hook",typeof state==="function");
    const initial=state();document.getElementById("pause").click();check("pause toggles without changing time",!state().playing&&state().time===initial.time);
    const seek=Math.min(777,Math.max(1,Number(document.getElementById("scrub").max)-1));
    document.getElementById("scrub").value=String(seek);document.getElementById("scrub").dispatchEvent(new Event("input"));const scrubbed=state();check("scrub sets shared time and pauses",scrubbed.time===seek&&!scrubbed.playing);
    for(const [id,value]of [["weapon","axe"],["helmet","steel"]]){const control=document.getElementById(id);control.value=value;control.dispatchEvent(new Event("input"));check(id+" switching preserves time",state().time===seek);}
    const oldControl=document.getElementById("weapon");oldControl.value="sword";oldControl.dispatchEvent(new Event("input"));
    document.getElementById("helmet").value="none";document.getElementById("helmet").dispatchEvent(new Event("input"));
    document.getElementById("mode").value="auto";document.getElementById("mode").dispatchEvent(new Event("change"));
    phase="building boundary-exact comparison";
    const total=m=>["idle","attack"].reduce((s,n)=>s+(m.clips[n]?.durations||[]).reduce((a,b)=>a+b,0),0);
    const oldDuration=total(L.manifest),bounds=new Set([0,cursor]);
    const seam=window.__renderAtForQA(cursor),oldAtSeam=FrameRig.sample(L.manifest,cursor,"auto"),oldWrapped=FrameRig.sample(L.manifest,cursor%oldDuration,"auto"),newAtSeam=FrameRig.sample(A.manifest,cursor,"auto"),newAtStart=FrameRig.sample(A.manifest,0,"auto");
    const samePose=(a,b)=>JSON.stringify({clip:a.clip,index:a.index,duration:a.duration,socket:a.socket})===JSON.stringify({clip:b.clip,index:b.index,duration:b.duration,socket:b.socket});
    check("shared absolute clock keeps the previous pose at the new-loop boundary",samePose(oldAtSeam,oldWrapped)&&JSON.stringify(seam.old.sample)===JSON.stringify(oldAtSeam),JSON.stringify({oldAtSeam,oldWrapped,rendered:seam.old.sample}));
    check("new animation wraps at its own boundary",samePose(newAtSeam,newAtStart)&&JSON.stringify(seam.current.sample)===JSON.stringify(newAtSeam),JSON.stringify({newAtSeam,newAtStart,rendered:seam.current.sample}));
    check("gallery clock remains absolute at cycle boundary",window.__wholeState().time===cursor);
    document.getElementById("pause").click();const tickStart=window.__setTimeForQA(cursor-10);window.__tickForQA(tickStart+30);
    check("playback crosses new cycle without resetting shared clock",window.__wholeState().playing&&Math.abs(window.__wholeState().time-(cursor+20))<0.000001);
    document.getElementById("pause").click();
    for(let cycle=0;cycle*oldDuration<cursor;cycle++){let at=cycle*oldDuration;for(const clip of ["idle","attack"])for(const d of L.manifest.clips[clip]?.durations||[]){if(at>0&&at<cursor)bounds.add(at);at+=d;}}
    let at=0;for(const clip of ["idle","attack"])for(const d of A.manifest.clips[clip]?.durations||[]){if(at>0&&at<cursor)bounds.add(at);at+=d;}
    const sorted=[...bounds].sort((a,b)=>a-b),comDur=[];
    for(let i=0;i<sorted.length-1;i++){const t=sorted[i],d=sorted[i+1]-t,board=document.createElement("canvas");board.width=1024;board.height=576;const c=board.getContext("2d");c.imageSmoothingEnabled=false;c.fillStyle="#202a34";c.fillRect(0,0,1024,576);c.fillStyle="#e9edf1";c.font="bold 20px Arial";c.textAlign="center";c.fillText("Предыдущая версия · свой цикл 1×",256,30);c.fillText("Новое тело · свой цикл 1×",768,30);
      for(const [x,m,imgs,b]of [[0,L.manifest,L.images,oldBody],[512,A.manifest,A.images,body]]){const cell=document.createElement("canvas");cell.width=cell.height=256;FrameRig.render(cell.getContext("2d"),m,imgs,t,{body:b,weapon:"sword",helmet:"none",mode:"auto"});c.drawImage(cell,x,48,512,512);}
      out.comparison.push(board.toDataURL("image/png").split(",")[1]);comDur.push(d);}
    out.comparisonDurations=comDur;out.oldCycleDurationMs=oldDuration;out.comparisonDurationMs=comDur.reduce((a,b)=>a+b,0);
    phase="saving selected grip QA poses";
    const attack=A.manifest.clips.attack,indices=[...Array.from({length:11},(_,i)=>13+i),...Array.from({length:6},(_,i)=>27+i)].filter(i=>i<attack.durations.length);
    const gripItems=[],gripCols=6,gripRows=Math.ceil([...new Set(indices)].length*4/gripCols),gripSheet=document.createElement("canvas");gripSheet.width=gripCols*256;gripSheet.height=gripRows*256;const gs=gripSheet.getContext("2d");gs.imageSmoothingEnabled=false;
    for(const index of [...new Set(indices)])for(const weapon of ["sword","axe"])for(const helmet of ["none","steel"]){const t=A.manifest.clips.idle.durations.reduce((a,b)=>a+b,0)+attack.durations.slice(0,index).reduce((a,b)=>a+b,0);const c=document.createElement("canvas");c.width=c.height=256;const r=FrameRig.render(c.getContext("2d"),A.manifest,A.images,t,{body,weapon,helmet,mode:"auto"});const pos=gripItems.length,x=(pos%gripCols)*256,y=Math.floor(pos/gripCols)*256;gs.drawImage(c,x,y);gripItems.push({name:`grip-${weapon}-${helmet}-attack-${String(index).padStart(3,"0")}.png`,x,y,sample:r.sample});}
    out.grips=gripItems;out.gripSheet=gripSheet.toDataURL("image/png").split(",")[1];
    out.pass=out.checks.every(c=>c.pass);
  }catch(e){out.phase=phase;out.errorStack=String(e.stack||e);out.errors.push(String(e));out.pass=false;}
  const pre=document.createElement("pre");pre.id="qa-output";pre.hidden=true;pre.textContent=JSON.stringify(out);document.body.append(pre);
})();</script>'''


def _clean() -> None:
    for name in OUTPUTS:
        path = ROOT / name
        if path.is_file():
            path.unlink()


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


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
    capture = TEMP / "qa-result.json"
    if capture.exists():
        capture.unlink()
    cmd = ["node", str(ROOT / "capture_browser.mjs"), str(target), str(capture), str(TEMP)]
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=240, encoding="utf-8", errors="replace")
        if proc.returncode:
            raise RuntimeError(f"Browser capture exit {proc.returncode}: {proc.stderr[-2000:]}")
        report = json.loads(capture.read_text(encoding="utf-8"))
        if not report.get("pass"):
            raise RuntimeError(json.dumps(report.get("errors", []) + [x for x in report.get("checks", []) if not x.get("pass")][:5], ensure_ascii=False))
        frames = {name: _images(report["frames"][name]) for name in VARIANTS}
        durations = {name: report["durations"][name] for name in VARIANTS}
        grips = report.pop("grips")
        grip_sheet = Image.open(io.BytesIO(base64.b64decode(report.pop("gripSheet")))).convert("RGBA")
        report.pop("frames", None)
        report.pop("durations", None)
        artifacts: dict[str, Any] = {}
        for name in VARIANTS:
            artifacts[GIF_NAMES[name]] = _save_gif(ROOT / GIF_NAMES[name], frames[name], durations[name])
        sequence = frames["body"] + frames["sword"] + frames["axe"]
        sequence_durations = durations["body"] + durations["sword"] + durations["axe"]
        artifacts["sequence.gif"] = _save_gif(ROOT / "sequence.gif", sequence, sequence_durations)
        frames["sword"][0].convert("RGB").save(ROOT / "overview.png")
        comparison_frames = _images(report.pop("comparison"))
        comparison_durations = report.pop("comparisonDurations")
        artifacts["comparison.gif"] = _save_gif(ROOT / "comparison.gif", comparison_frames, comparison_durations)
        expected = report["cycleDurationMs"]
        for name in GIF_NAMES.values():
            meta = artifacts[name]
            variant = next(key for key, filename in GIF_NAMES.items() if filename == name)
            report["checks"].append({"name": name + " dimensions 768x832", "pass": meta["size"] == [768, 832]})
            report["checks"].append({"name": name + " actual GIF metadata matches cycle", "pass": meta["duration_ms"] == expected and meta["frames"] == report["frameCount"] and meta["durations_ms"] == durations[variant]})
            report["checks"].append({"name": name + " frames at least 20ms", "pass": min(meta["durations_ms"]) >= 20, "detail": str(min(meta["durations_ms"]))})
        seq = artifacts["sequence.gif"]
        report["checks"].append({"name": "sequence dimensions and three cycle metadata", "pass": seq["size"] == [768, 832] and seq["duration_ms"] == expected * 3 and seq["frames"] == report["frameCount"] * 3})
        comparison = artifacts["comparison.gif"]
        report["checks"].append({"name": "comparison exact new-cycle duration including old wraps", "pass": comparison["size"] == [1024, 576] and comparison["duration_ms"] == expected and comparison["durations_ms"] == comparison_durations and report["comparisonDurationMs"] == expected})
        grip_dir = TEMP / "grips"
        grip_dir.mkdir(parents=True, exist_ok=True)
        grip_paths = []
        for grip in grips:
            path = grip_dir / grip["name"]
            grip_sheet.crop((grip["x"], grip["y"], grip["x"] + 256, grip["y"] + 256)).save(path)
            grip_paths.append({"path": str(path), "sample": grip["sample"]})
        report["export"] = {"artifacts": artifacts, "grip_qa_poses": grip_paths, "frame_count_per_variant": report["frameCount"], "cycle_duration_ms": expected, "source": "FrameRig.render на границах каждого кадра манифеста"}
        report["source_hashes"] = {"renderer.js": _digest(ROOT / "renderer.js"), "gallery.html": _digest(ROOT / "gallery.html"), "new_manifest.json": _digest(ROOT / "assets/manifest.json"), "legacy_manifest.json": _digest(ROOT.parent / "whole-body-weighted-strike-20261118/assets/manifest.json")}
        report["pass"] = all(c.get("pass") for c in report["checks"])
        (ROOT / "browser-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        artifact_summary = {name: {"size": meta["size"], "frames": meta["frames"], "duration_ms": meta["duration_ms"], "min_frame_ms": min(meta["durations_ms"]), "bytes": meta["bytes"]} for name, meta in artifacts.items()}
        print(json.dumps({"pass": report["pass"], "checks": len(report["checks"]), "frame_count": report["frameCount"], "cycle_duration_ms": expected, "artifacts": artifact_summary}, ensure_ascii=False))
        if not report["pass"]:
            _clean()
            raise SystemExit(1)
    except Exception as exc:
        _clean()
        (ROOT / "browser-validation.json").write_text(json.dumps({"pass": False, "error": str(exc)}, ensure_ascii=False, indent=2), encoding="utf-8", newline="\n")
        raise


if __name__ == "__main__":
    main()
