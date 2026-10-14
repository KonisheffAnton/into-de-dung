from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "assets/art_presets/trials/archer_idle_v1"
SOURCE = ROOT / "docs/art/archer-perspective-20261014/pixellab"
BASE_COMMIT = "bd77eb7f7fcabf5d99f1b8b943619246bc1a7ca3"


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def resource_bytes() -> bytes:
    lines = ['[gd_resource type="SpriteFrames" load_steps=13 format=3]', ""]
    for index in range(1, 13):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/trials/archer_idle_v1/idle/frame-{index:02d}.png" id="idle_{index}"]')
    lines.extend(["", "[resource]", "animations = [{", '"frames": ['])
    for index in range(1, 13):
        suffix = "," if index < 12 else ""
        lines.append(f'{{"duration": 13.0, "texture": ExtResource("idle_{index}")}}{suffix}')
    lines.extend(["],", '"loop": true,', '"name": &"idle",', '"speed": 60.0', "}]"])
    return ("\n".join(lines) + "\n").encode("utf-8")


def outputs() -> dict[str, bytes]:
    result: dict[str, bytes] = {}
    frame_entries: list[dict[str, object]] = []
    for target_index, source_index in enumerate(range(2, 14), 1):
        name = f"idle/frame-{target_index:02d}.png"
        source = SOURCE / f"frame-{source_index:02d}.png"
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"{source}: invalid PNG signature")
        width, height = struct.unpack(">II", data[16:24])
        if (width, height) != (128, 128) or data[25] != 6:
            raise ValueError(f"{source}: expected 128x128 RGBA PNG")
        result[name] = data
        frame_entries.append({
            "source": f"docs/art/archer-perspective-20261014/pixellab/frame-{source_index:02d}.png",
            "runtime": f"assets/art_presets/trials/archer_idle_v1/{name}",
            "sha256": sha256(data),
            "duration_ticks": 13,
        })
    result["idle_frames.tres"] = resource_bytes()
    manifest = {
        "format": 1,
        "base_commit": BASE_COMMIT,
        "selection": "User explicitly approved integration of corrected Archer idle; source frames 02-13 in order; input echo frame 01 excluded.",
        "animation": {"name": "idle", "loop": True, "speed_fps": 60, "frame_duration_ticks": 13, "cycle_seconds": 2.6},
        "frames": frame_entries,
        "resource_sha256": sha256(result["idle_frames.tres"]),
    }
    result["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Сборка выбранного idle Archer без изменения кадров")
    parser.add_argument("--check", action="store_true", help="проверить файлы без записи")
    args = parser.parse_args()
    expected = outputs()
    if args.check:
        failures = [name for name, data in expected.items() if not (PACKAGE / name).is_file() or (PACKAGE / name).read_bytes() != data]
        if failures:
            print("FAIL: " + ", ".join(failures), file=sys.stderr)
            return 1
        print("PASS: 14 files match deterministic build; 12 source PNGs are byte-exact; idle cycle 2.6s")
        return 0
    for name, data in expected.items():
        path = PACKAGE / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print("Built 14 files; 12 source PNGs copied byte-exact; idle cycle 2.6s")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
