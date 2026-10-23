"""Copy the user-selected Rogue and Death 3 without changing any PNG bytes."""
import argparse
import hashlib
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = ROOT / "assets/art_presets/trials/rogue_selected_v1"
STAGE = Path(__file__).resolve().parent
DEFAULT_SOURCE = Path(r"C:\Users\Aston\.codex\generated_images\rogue-selected-pixellab-20261023")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    args = parser.parse_args()
    source = args.source.resolve()
    (PACKAGE / "death").mkdir(parents=True, exist_ok=True)
    pairs = [(source / "input-transparent.png", PACKAGE / "still.png")]
    pairs += [(source / f"pixellab/death-3/frames/{i:02d}.png",
               PACKAGE / f"death/frame-{i + 1:02d}.png") for i in range(17)]
    records = []
    for original, target in pairs:
        with Image.open(original) as im:
            assert im.mode == "RGBA" and im.size == (128, 128), original
            bbox = im.getchannel("A").getbbox()
            assert bbox and 0 < bbox[0] < bbox[2] < 128 and 0 < bbox[1] < bbox[3] < 128, original
        target.write_bytes(original.read_bytes())
        assert sha(original) == sha(target)
        records.append({"source": str(original), "target": target.relative_to(ROOT).as_posix(),
                        "sha256": sha(target), "alpha_bbox": bbox, "byte_equal": True})
    with Image.open(PACKAGE / "still.png") as still, Image.open(PACKAGE / "death/frame-01.png") as first:
        assert still.tobytes() == first.tobytes()
    assert sha(PACKAGE / "still.png") == sha(ROOT / "docs/art/rogue-selected-pixellab-20261023/input-transparent.png")
    lines = ['[gd_resource type="SpriteFrames" load_steps=18 format=3]', '']
    for i in range(1, 18):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/trials/rogue_selected_v1/death/frame-{i:02d}.png" id="death_{i}"]')
    lines += ['', '[resource]', 'animations = [{', '"frames": [']
    lines += [f'{{"duration": 15.0, "texture": ExtResource("death_{i}")}}' + (',' if i < 17 else '') for i in range(1, 18)]
    lines += ['],', '"loop": false,', '"name": &"death",', '"speed": 100.0', '}]', '']
    (PACKAGE / "death_frames.tres").write_text('\n'.join(lines), encoding="utf-8", newline="\n")
    report = {"source_job": "3d86081f-9a2c-4a33-9c7e-fceea5f1cd5b", "selected": "death-3",
              "integration": True, "original_rgba_and_png_bytes": True, "records": records,
              "first_frame_rgba_equals_still": True, "frame_seconds": 0.15, "clip_seconds": 2.55,
              "hold_seconds": 0.25, "fade_seconds": 0.8, "total_seconds": 3.6,
              "sprite_frames_sha256": sha(PACKAGE / "death_frames.tres")}
    (STAGE / "source-validation.json").write_text(json.dumps(report, indent=2) + '\n', encoding="utf-8", newline="\n")
    print("PASS: 18 byte-exact PNG copies; 17 x 150 ms; first frame equals static model")


if __name__ == "__main__":
    main()
