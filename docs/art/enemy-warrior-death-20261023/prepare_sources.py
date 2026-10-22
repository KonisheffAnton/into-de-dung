"""Preserve the selected PixelLab death and approved character reference, without pixel edits."""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
REPORT = Path(__file__).resolve().parent
SOURCE = Path(r"C:\Users\Aston\.codex\generated_images\warrior-death-kneel-round2-20261023\pixellab2\death-2")
ASSET = ROOT / "assets/art_presets/trials/enemy_warrior_death_v1"
REFERENCE = ROOT / "assets/art_presets/approved/warrior_format_v1"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_exact(source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists():
        assert target.read_bytes() == source.read_bytes(), str(target)
    else:
        shutil.copyfile(source, target)
    assert digest(source) == digest(target)


metadata = json.loads((SOURCE / "metadata.json").read_text(encoding="utf-8-sig"))
assert metadata["taskId"] == "6c1f9328-8311-4a7d-b01d-48570a5426f8"
assert metadata["sourceStatus"] == "completed"
frames = []
for index in range(17):
    source = SOURCE / "frames" / f"{index:02}.png"
    target = ASSET / "frames" / f"frame-{index + 1:02}.png"
    assert digest(source) == metadata["fileSha256"][index]
    image = Image.open(source).convert("RGBA")
    assert image.size == (128, 128)
    bounds = image.getchannel("A").getbbox()
    assert bounds and 0 < bounds[0] < bounds[2] < 128 and 0 < bounds[1] < bounds[3] < 128
    copy_exact(source, target)
    frames.append({"frame": index + 1, "source": str(source),
                   "destination": target.relative_to(ROOT).as_posix(), "sha256": digest(target),
                   "alphaBounds": bounds})

idle_first = ROOT / "assets/art_presets/trials/enemy_warrior_idle_v1/frames/frame-01.png"
assert (ASSET / "frames/frame-01.png").read_bytes() == idle_first.read_bytes()
manifest = {"selectionDate": "2026-10-23", "selection": "death-2 — Колено, затем вперёд",
            "sourceJob": metadata["taskId"], "sourcePackage": str(SOURCE),
            "frameCount": 17, "frameDurationSeconds": 0.15, "durationSeconds": 2.55,
            "timingAuthored": True, "previewFinalHoldUsedInGame": False,
            "loop": False, "anchorSourcePixels": [71, 83], "mirrored": True,
            "warriorArtScale": 0.8, "pixelEdits": False, "frames": frames}
(ASSET / "source-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

lines = ['[gd_resource type="SpriteFrames" load_steps=18 format=3]', '']
for index in range(17):
    lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/trials/enemy_warrior_death_v1/frames/frame-{index + 1:02}.png" id="death_{index + 1}"]')
lines += ['', '[resource]', 'animations = [{', '"frames": [']
lines += [f'{{"duration": 9.0, "texture": ExtResource("death_{index + 1}")}}' + (',' if index < 16 else '') for index in range(17)]
lines += ['],', '"loop": false,', '"name": &"death",', '"speed": 60.0', '}]', '']
(ASSET / "death_frames.tres").write_text('\n'.join(lines), encoding="utf-8")
copy_exact(idle_first, REFERENCE / "character.png")
copy_exact(ROOT / "docs/art/enemy-warrior-placement-20261023/enemy-on-tile.png", REFERENCE / "on-tile.png")
preset = {"selectedByUser": "2026-10-23", "scope": "New format reference for all future character art",
          "supersedesCharacterReference": "defender_brighter_v1", "canvas": [128, 128],
          "still": "character.png", "stillSha256": digest(REFERENCE / "character.png"),
          "onTile": "on-tile.png", "onTileSha256": digest(REFERENCE / "on-tile.png"),
          "idleResource": "res://assets/art_presets/trials/enemy_warrior_idle_v1/idle_frames.tres",
          "deathResource": "res://assets/art_presets/trials/enemy_warrior_death_v1/death_frames.tres",
          "placementReference": "docs/art/enemy-warrior-placement-20261023/user-reference.png",
          "tileTop": [128, 96], "neighborSteps": [[64, 48], [-64, 48]],
          "currentWarriorAnchor": [71, 83], "currentWarriorArtScale": 0.8,
          "firstFrameVisibleSize": [54, 72], "firstFrameVisibleSizeOnTile": [43.2, 57.6],
          "brighterPaletteStrength": 0, "sourcePixelsUnchanged": True,
          "newCharactersNeedOwnPlacementVerification": True, "massRuntimeReplacement": False}
(REFERENCE / "preset.json").write_text(json.dumps(preset, ensure_ascii=False, indent=2) + '\n', encoding="utf-8")
(REPORT / "source-validation.json").write_text(json.dumps({"sourceJob": metadata["taskId"],
    "framesVerified": 17, "byteExact": True, "firstFrameEqualsIdleStill": True,
    "alphaBoundsWithinCanvas": True, "referenceCopiesByteExact": True}, indent=2) + '\n', encoding="utf-8")
print("SOURCE VALIDATION PASS: 17 byte-exact frames, idle/still continuity, 2 approved reference copies")
