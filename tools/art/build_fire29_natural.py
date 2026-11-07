#!/usr/bin/env python3
"""Собирает принятый runtime-перенос fire29 из исходных PNG без перекодирования."""

from __future__ import annotations

import argparse
from hashlib import sha256
from io import BytesIO
import json
from pathlib import Path
import re
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
INPUTS = {
    "floor": ("docs/art/fire-low-styles-20261104/fire-low-29.png", "3f89930f385e43a1efe4d4895c25ff74a7cfc4215d740c2d697263261122756e", (1254, 1254), "RGBA"),
    "mask": ("docs/art/fire29-natural-20261107/inputs/natural29-02-fixed-display-mask.png", "300b88ac0c2e0d22e5434dfb0def83527d0201410905b7a185590fdfb6804875", (256, 256), "L"),
    "pose-01": ("docs/art/fire29-natural-20261107/raw/natural29-02/01.png", "c89e6495600caa52d40784166323130f278337b4cea4895b9b3b0950c53e1dcd", (256, 256), "RGBA"),
    "pose-02": ("docs/art/fire29-natural-20261107/raw/natural29-02/02.png", "1419cd04a7e546d0f771ca186f336b9a49e5dfce3f2d6fe1d4c76b3388333499", (256, 256), "RGBA"),
    "pose-03": ("docs/art/fire29-natural-20261107/raw/natural29-02/03.png", "ee997f41f62c18beb615e3b1dcdecd5180d1be45d0be132705302c980a1f02d3", (256, 256), "RGBA"),
    "pose-04": ("docs/art/fire29-natural-20261107/raw/natural29-02/04.png", "f23dd2ed04d2c04ddd9ebae5638a5a9943ac78c208c578c25438e16e2eeaf6b5", (256, 256), "RGBA"),
    "pose-05": ("docs/art/fire29-natural-20261107/raw/natural29-02/05.png", "99f543c199ba0d97553a46193e14fd6c319a057d242578506dc3e8e0c1e80fae", (256, 256), "RGBA"),
    "pose-06": ("docs/art/fire29-natural-20261107/raw/natural29-02/06.png", "88a45844f505ce05feeb08ff8921b48d79619792be65d9191411e4b5b157ec31", (256, 256), "RGBA"),
    "pose-07": ("docs/art/fire29-natural-20261107/raw/natural29-02/07.png", "838e1ec3d2303b41cbbb9ae29fa318e2e3548a7ff0c8818420d7a0b809ee6702", (256, 256), "RGBA"),
}
OUT = ROOT / "assets/art_presets/approved/fire29_natural_v1"
FRAMES = [1, 2, 3, 4, 5, 6, 7, 6, 5, 4, 3, 2]
def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def read_import_config(name: str, source_hash: str) -> tuple[Path, bytes]:
    path = OUT / f"{name}.png.import"
    data = path.read_bytes()
    text = data.decode("utf-8")
    expected_source = f'res://assets/art_presets/approved/fire29_natural_v1/{name}.png'
    expected = {
        "source_file": f'"{expected_source}"',
        "compress/mode": "0",
        "mipmaps/generate": "false",
        "process/fix_alpha_border": "false",
        "process/premult_alpha": "false",
    }
    for key, value in expected.items():
        require(re.search(rf"(?m)^{re.escape(key)}={re.escape(value)}$", text) is not None,
                f"Godot import setting mismatch: {name}.png.import [{key}={value}]")
    require("uid=\"uid://" in text and "path=\"res://.godot/imported/" in text,
            f"Godot-generated UID or remap is missing: {name}.png.import")
    return path, data


def make_outputs() -> dict[Path, bytes]:
    out: dict[Path, bytes] = {}
    records: dict[str, dict[str, object]] = {}
    import_records: dict[str, dict[str, str]] = {}
    for key, (source, expected_hash, size, mode) in INPUTS.items():
        # Побайтная копия сохраняет пользовательский выбор и даёт проверяемое происхождение каждого ресурса.
        data = (ROOT / source).read_bytes()
        require(sha256(data).hexdigest() == expected_hash, f"SHA-256 источника изменился: {source}")
        with Image.open(BytesIO(data)) as image:
            require(image.size == size and image.mode == mode, f"Ожидался {mode} {size}: {source}")
        name = "floor" if key == "floor" else "mask" if key == "mask" else key
        target = OUT / f"{name}.png"
        out[target] = data
        records[key] = {"source": source, "source_sha256": expected_hash, "runtime": target.relative_to(ROOT).as_posix(), "runtime_sha256": expected_hash, "size": list(size), "mode": mode}
        import_path, import_data = read_import_config(name, expected_hash)
        import_records[name] = {"path": import_path.relative_to(ROOT).as_posix(), "sha256": sha256(import_data).hexdigest()}

    lines = ['[gd_resource type="SpriteFrames" load_steps=8 format=3]', ""]
    for index in range(1, 8):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/approved/fire29_natural_v1/pose-{index:02d}.png" id="pose_{index:02d}"]')
    lines.extend(["", "[resource]", "animations = [", "{", '"frames": ['])
    for index, pose in enumerate(FRAMES):
        comma = "," if index < len(FRAMES) - 1 else ""
        lines.append(f'{{"duration": 1.000000000, "texture": ExtResource("pose_{pose:02d}")}}{comma}')
    lines.extend(("],", '"loop": true,', '"name": &"fire",', '"speed": 8.333333333333334', "}]", ""))
    frames_data = "\n".join(lines).encode()
    out[OUT / "fire29_frames.tres"] = frames_data
    manifest = {
        "schema": "fire29-natural-runtime-v1",
        "acceptance": {"provenance": "user-accepted integration request 2026-11-07", "historic_study_status_preserved": "candidate_unaccepted"},
        "inputs": records,
        "timeline_pose_numbers": FRAMES,
        "slot_ms": 120,
        "fps": 8.333333333333334,
        "duration_ms": 1440,
        "loop": True,
        "floor_rgba_bytes": 1254 * 1254 * 4,
        "runtime_frame_rgba_bytes": 7 * 256 * 256 * 4,
        "mask_bytes": 256 * 256,
        "source_decoded_bytes": 1254 * 1254 * 4 + 7 * 256 * 256 * 4 + 256 * 256,
        "decoded_bytes_note": "Decoded source asset memory size; not a GPU memory measurement.",
        "copy_policy": "byte-exact; no generation or image alteration",
        "import_policy": {"preserve_godot_uid_and_remap": True, "fix_alpha_border": False, "mipmaps": False, "compression_mode": 0, "sidecars": import_records},
        "sprite_frames": {"path": "assets/art_presets/approved/fire29_natural_v1/fire29_frames.tres", "sha256": sha256(frames_data).hexdigest(), "standalone_textures": 7},
        "transforms": {"floor_polygon": [[0, -48], [64, 0], [0, 48], [-64, 0]], "floor_uv": [[627, 265], [932, 496], [627, 727], [322, 496]], "scale": [0.555737705, 0.549471147], "position": [-71.1344262, -(99.4580897 + 29.0) * 0.549471147]},
    }
    out[OUT / "manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="сверить ожидаемые байты, ничего не записывая")
    args = parser.parse_args()
    try:
        outputs = make_outputs()
        if args.check:
            # Godot может создавать import sidecar локально; они не являются выходами сборщика.
            existing = {path for path in OUT.iterdir() if path.is_file()} if OUT.is_dir() else set()
            imports = {OUT / f"{name}.png.import" for name in ("floor", "mask", *(f"pose-{index:02d}" for index in range(1, 8)))}
            require(existing == set(outputs) | imports, f"Состав runtime-каталога отличается: {sorted(p.name for p in existing)}")
            for path, expected in outputs.items():
                require(path.read_bytes() == expected, f"Выход отсутствует или изменён: {path.relative_to(ROOT)}")
        else:
            OUT.mkdir(parents=True, exist_ok=True)
            for path, data in outputs.items():
                path.write_bytes(data)
    except (OSError, ValueError, KeyError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("PASS: fire29 natural runtime deterministic" if args.check else "PASS: fire29 natural runtime built")
    print(f"Assets: {len(INPUTS)} source PNGs, {1254 * 1254 * 4 + 7 * 256 * 256 * 4 + 256 * 256} decoded source bytes (not GPU memory)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
