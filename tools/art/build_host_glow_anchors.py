"""Track the small face patch in approved frames; never modify the source art."""
import json
import argparse
import re
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
EYES = {
    "watch_shield": [(137, 82), (145, 81)],
    "grey_bastion": [(138, 78), (147, 79)],
    "red_bastion": [(123, 89), (113, 88)],
    "short_cape": [(145, 85)],
    "star_hood": [(144, 81), (153, 80)],
    "silver_ranger": [(139, 86), (148, 84)],
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    result = {}
    for skin, eyes in EYES.items():
        folder = ROOT / "assets/art_presets/approved/character_skins_v1" / skin
        source = np.asarray(Image.open(folder / "still.png").convert("RGBA"), dtype=np.float32)
        left = min(p[0] for p in eyes) - 6
        top = min(p[1] for p in eyes) - 9
        right = max(p[0] for p in eyes) + 7
        bottom = max(p[1] for p in eyes) + 10
        patch = source[top:bottom, left:right]
        text = (folder / "frames.tres").read_text(encoding="utf-8")
        resources = dict((rid, Path(path).name) for path, rid in re.findall(r'path="([^"]+\.png)" id="([^"]+)"', text))
        images = {rid: Image.open(folder / name).convert("RGBA") for rid, name in resources.items()}
        values = {}
        for rid, x, y, w, h in re.findall(r'atlas = ExtResource\("([^"]+)"\)\s+region = Rect2\((\d+), (\d+), (\d+), (\d+)\)', text):
            if "death" in resources[rid]:
                continue
            x, y, w, h = map(int, (x, y, w, h))
            frame = np.asarray(images[rid].crop((x, y, x + w, y + h)), dtype=np.float32)
            # Restrict tracking to the head neighbourhood, not similar colours on gear.
            radius = 24
            region = frame[top-radius:bottom+radius, left-radius:right+radius]
            windows = np.lib.stride_tricks.sliding_window_view(region, patch.shape[:2], axis=(0, 1))
            windows = windows.transpose(0, 1, 3, 4, 2)
            errors = np.mean(np.abs(windows - patch), axis=(2, 3, 4))
            dy, dx = np.unravel_index(np.argmin(errors), errors.shape)
            values[f"{resources[rid]}@{x},{y}"] = [int(dx)-radius, int(dy)-radius]
        result[skin] = values
    path = ROOT / "assets/ui/host_glow_anchors.json"
    expected = json.dumps(result, indent=2) + "\n"
    if args.check:
        if not path.exists() or path.read_text(encoding='utf-8') != expected:
            raise SystemExit('Host glow anchors differ; rebuild required')
    else:
        path.write_text(expected, encoding="utf-8")
    print(f"{sum(map(len, result.values()))} living animation anchors -> {path}")


if __name__ == "__main__":
    main()
