#!/usr/bin/env python3
"""Собирает утверждённые анимации хоб-гоблина без изменения исходных PNG."""
from __future__ import annotations
import argparse, hashlib, json, math, sys
from collections import Counter
from pathlib import Path
from PIL import Image
ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "assets/art_presets/approved/character_skins_v1/sick_hobgoblin"
FRAME = 256
CLIPS = {
    "idle": ("docs/art/rvanoukh-animation-20261115/pixellab/idle-3", True),
    "idle_secondary": ("docs/art/rvanoukh-animation-20261115/pixellab/idle-2", True),
    "buff": ("docs/art/rvanoukh-abilities-five-20261115/pixellab/ability-1", False),
    "death": ("docs/art/rvanoukh-selected-20261115/death-1-closed-eyes", False),
}
def sha(data: bytes) -> str: return hashlib.sha256(data).hexdigest()
def rel(path: Path) -> str: return path.relative_to(ROOT).as_posix()
def outputs() -> tuple[dict[str, bytes], dict]:
    out: dict[str, bytes] = {}
    sources = []
    still_src = ROOT / "docs/art/rvanoukh-animation-20261115/model/input-256.png"
    still = still_src.read_bytes()
    with Image.open(still_src) as im:
        if im.size != (FRAME, FRAME) or im.mode != "RGBA" or im.getchannel("A").getbbox() is None: raise ValueError("Invalid still geometry/content")
    out["still.png"] = still
    sources.append({"source":rel(still_src),"destination":"still.png","sha256":sha(still),"kind":"still"})
    records = {}
    for name, (folder_rel, loop) in CLIPS.items():
        folder = ROOT / folder_rel
        meta_path, sheet_path = folder / "clip.json", folder / "spritesheet.png"
        meta = json.loads(meta_path.read_text(encoding="utf-8")); sheet = sheet_path.read_bytes()
        if meta.get("key") != folder.name or meta.get("actual_frames") != 33 or meta.get("loop") is not loop or meta.get("canvas") != [256,256] or meta.get("anchor") != [128,200]: raise ValueError(f"Clip metadata mismatch: {rel(meta_path)}")
        durations = meta.get("durations_ms")
        if not isinstance(durations,list) or len(durations)!=33 or any(type(x) is not int or x<=0 for x in durations): raise ValueError(f"Bad durations: {rel(meta_path)}")
        with Image.open(sheet_path) as atlas:
            atlas.load()
            if atlas.size != (2048,1280) or atlas.mode != "RGBA": raise ValueError(f"Bad atlas geometry: {rel(sheet_path)}")
            for i in range(33):
                x,y=(i%8)*FRAME,(i//8)*FRAME
                if atlas.crop((x,y,x+FRAME,y+FRAME)).getchannel("A").getbbox() is None: raise ValueError(f"Empty atlas cell {i}: {rel(sheet_path)}")
        output_name = "buff.png" if name == "buff" else f"{name}.png"
        out[output_name] = sheet
        records[name] = {"durations_ms":durations,"loop":loop,"source":rel(sheet_path),"source_sha256":sha(sheet),"destination":output_name,"source_clip_json":rel(meta_path)}
        sources.append({"source":rel(sheet_path),"destination":output_name,"sha256":sha(sheet),"kind":name})
    anim_names = list(CLIPS)
    lines = ['[gd_resource type="SpriteFrames" load_steps=137 format=3]', '']
    for name in anim_names: lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/character_skins_v1/sick_hobgoblin/{records[name]["destination"]}" id="atlas_{name}"]')
    for name in anim_names:
        for i in range(33):
            ident=f"{name}_{i:02d}"; lines += ['',f'[sub_resource type="AtlasTexture" id="{ident}"]',f'atlas = ExtResource("atlas_{name}")',f'region = Rect2({i%8*256}, {i//8*256}, 256, 256)']
    lines += ['', '[resource]', 'animations = [']
    for aidx,name in enumerate(anim_names):
        rec=records[name]; durations=rec['durations_ms']; base=Counter(durations).most_common(1)[0][0]
        lines += ['{','"frames": [']
        for i,dur in enumerate(durations): lines.append(f'{{"duration": {dur/base:.9f}, "texture": SubResource("{name}_{i:02d}")}}' + (',' if i<32 else ''))
        lines += ['],',f'"loop": {str(rec["loop"]).lower()},',f'"name": &"{name}",',f'"speed": {1000/base:.9f}', '},' if aidx<3 else '}']
    lines += [']','']
    out['frames.tres']='\n'.join(lines).encode()
    out['skin.tres']='\n'.join(['[gd_resource type="Resource" script_class="CharacterSkinDefinition" load_steps=4 format=3]','','[ext_resource type="Script" path="res://scripts/demo/character_skin_definition.gd" id="1_script"]','[ext_resource type="Texture2D" path="res://assets/art_presets/approved/character_skins_v1/sick_hobgoblin/still.png" id="2_still"]','[ext_resource type="SpriteFrames" path="res://assets/art_presets/approved/character_skins_v1/sick_hobgoblin/frames.tres" id="3_animations"]','','[resource]','script = ExtResource("1_script")','id = &"sick_hobgoblin"','class_id = &"sick_hobgoblin"','display_name = "Нездоровый хоб-гоблин"','still = ExtResource("2_still")','animations = ExtResource("3_animations")','anchor = Vector2(128, 200)','texture_scale = 0.5','source_facing_x = 1','shieldbearer_palette_strength = 0.0','ambient_buff_interval = 18.0','']).encode()
    manifest={"format":1,"base_commit":"ad26edcb471e69e6069ff367d5c21253f8fe5dc2","skin":"sick_hobgoblin","class_id":"sick_hobgoblin","anchor":[128,200],"canvas":[256,256],"sheet_layout":{"size":[2048,1280],"columns":8,"frames":33},"source_pngs":sources,"clips":records,"death_provenance":"Derived closed-eyes PixelLab patch selection; source is not raw PixelLab output."}
    manifest["artifact_sha256"]={k:sha(v) for k,v in sorted(out.items())}
    out['manifest.json']=(json.dumps(manifest,ensure_ascii=False,indent=2,sort_keys=True)+'\n').encode()
    durations="\n".join(f"- `{n}`: {sum(r['durations_ms'])} ms; loop `{str(r['loop']).lower()}`; per-frame durations are in manifest." for n,r in records.items())
    out['README.md']=("# Нездоровый хоб-гоблин\n\nApproved `sick_hobgoblin` enemy skin built from the listed source PNG bytes. All clips use 33 frames, 256×256 cells, anchor (128,200), on 2048×1280 sheets; frames are atlas regions without normalization or editing.\n\n"+durations+"\n\n`death.png` comes from `rvanoukh-selected-20261115/death-1-closed-eyes`; it is a derived PixelLab patch selection, not raw provider output. Source and destination SHA-256 values are recorded in `manifest.json`.\n\nRun `python tools/art/build_hobgoblin_skin.py` to build, or `--check` for deterministic no-write validation.\n").encode()
    return out,manifest
def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('--check',action='store_true'); args=p.parse_args()
    expected,manifest=outputs()
    if args.check:
        bad=[n for n,b in expected.items() if not (PACKAGE/n).is_file() or (PACKAGE/n).read_bytes()!=b]
        if bad: print('FAIL: '+', '.join(bad),file=sys.stderr); return 1
        print(f"PASS: {len(manifest['source_pngs'])} source PNGs byte-exact; 132 atlas cells verified; deterministic outputs match")
        return 0
    PACKAGE.mkdir(parents=True,exist_ok=True)
    for n,b in expected.items(): (PACKAGE/n).write_bytes(b)
    print(f"Built {len(expected)} deterministic outputs in {PACKAGE}")
    print("PASS: 5 source PNGs byte-exact; 132 atlas cells verified")
    return 0
if __name__=='__main__':
    try: raise SystemExit(main())
    except (OSError,ValueError,KeyError,json.JSONDecodeError) as e: raise SystemExit(f"BUILD FAILED: {e}") from e
