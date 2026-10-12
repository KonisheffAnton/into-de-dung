from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Any

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
PACKAGE = ROOT / "assets/art_presets/trials/rogue_animations_v1"
IDLE_SOURCE = ROOT / "docs/art/rogue-idle-layered-20261012/frames"
IDLE_PREVIEW = ROOT / "docs/art/rogue-idle-layered-20261012/preview.gif"
IDLE_VALIDATION = ROOT / "docs/art/rogue-idle-cadence-20261012/validation.json"
FEEDBACK_ROOT = ROOT / "docs/art/rogue-game-feedback-20261012"
BUFF_ROOT = FEEDBACK_ROOT / "buff-final"
BUFF_MANIFEST = BUFF_ROOT / "manifest.json"
DEATH_ROOT = FEEDBACK_ROOT / "death-final"
DEATH_MANIFEST = DEATH_ROOT / "manifest.json"

IDLE_NUMBERS = (1, 5, 9, 13, 17, 21, 25, 29, 33, 37, 41, 45)
BUFF_DURATIONS = (200, 350, 60, 120, 240)
DEATH_COUNT = 13
BASE_COMMIT = "d16bd004a5ab91a44e33965fc8515f16106f388b"
SCALE = 4
BG = (63, 75, 67, 255)


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read(path: Path) -> bytes:
    return path.read_bytes()


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def load_image(data: bytes, label: str) -> Image.Image:
    image = Image.open(__import__("io").BytesIO(data))
    image.load()
    if image.mode != "RGBA":
        raise ValueError(f"{label}: ожидается RGBA, получен {image.mode}")
    return image


def upscale(data: bytes, label: str) -> bytes:
    image = load_image(data, label)
    if image.size != (128, 128):
        raise ValueError(f"{label}: ожидается 128x128, получен {image.size}")
    image = image.resize((512, 512), Image.Resampling.NEAREST)
    output = __import__("io").BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()


def collect_manifest_frames(root: Path, manifest_path: Path, label: str, expected_durations: tuple[int, ...]) -> list[tuple[Path, bytes]]:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("base") != BASE_COMMIT:
        raise ValueError(f"{label}: manifest должен ссылаться на base {BASE_COMMIT}")
    frames = manifest.get("frames")
    if not isinstance(frames, list) or len(frames) != len(expected_durations):
        raise ValueError(f"{label}: ожидается ровно {len(expected_durations)} кадров")
    collected: list[tuple[Path, bytes]] = []
    for index, (item, expected_duration) in enumerate(zip(frames, expected_durations), 1):
        if item.get("duration_ms") != expected_duration:
            raise ValueError(f"{label} frame {index}: ожидается {expected_duration}ms")
        source = (root / str(item.get("source", ""))).resolve()
        try:
            source.relative_to(root.resolve())
        except ValueError as error:
            raise ValueError(f"{label} frame {index}: источник выходит за package root") from error
        data = read(source)
        if sha256(data) != item.get("sha256"):
            raise ValueError(f"{label} frame {index}: SHA-256 входа не совпадает с manifest")
        collected.append((source, data))
    return collected


def sprite_frames(animation: str, speed: float, loop: bool, names: list[str], durations: list[int]) -> bytes:
    # Godot считает duration множителем периода кадра; частоты и множители храним явно.
    lines = [f"[gd_resource type=\"SpriteFrames\" load_steps={len(names) + 1} format=3]", ""]
    for index, name in enumerate(names, 1):
        lines.append(f'[ext_resource type="Texture2D" path="res://assets/art_presets/trials/rogue_animations_v1/{name}" id="{animation}_{index}"]')
    lines.extend(["", "[resource]", "animations = [{", '"frames": ['])
    for index, duration in enumerate(durations, 1):
        suffix = "," if index < len(names) else ""
        lines.append(f'{{"duration": {duration / 10.0:.1f}, "texture": ExtResource("{animation}_{index}")}}{suffix}')
    lines.extend(["],", f'"loop": {str(loop).lower()},', f'"name": &"{animation}",', f'"speed": {speed:.1f}', "}]"])
    return ("\n".join(lines) + "\n").encode("utf-8")


def verify_idle_parity(selected: list[tuple[int, bytes]]) -> dict[str, Any]:
    validation = json.loads(IDLE_VALIDATION.read_text(encoding="utf-8"))
    if validation.get("selection") is None:
        raise ValueError("Нет cadence selection для idle")
    preview = Image.open(IDLE_PREVIEW)
    bg = Image.new("RGBA", (512, 512), BG)
    checked: list[dict[str, Any]] = []
    expected_by_number = {item["sourceFrame"]: item for item in validation["selection"]}
    for source_number, data in selected:
        source = load_image(data, f"idle frame {source_number}")
        composed = Image.alpha_composite(bg, source)
        entry = expected_by_number.get(source_number)
        if entry is None:
            raise ValueError(f"Кадр {source_number} отсутствует в cadence validation")
        timestamp = int(entry["sourceTimeMs"])
        elapsed = 0
        match: Image.Image | None = None
        preview_index = 0
        for frame_index in range(preview.n_frames):
            preview.seek(frame_index)
            duration = int(preview.info.get("duration", 0))
            if elapsed <= timestamp < elapsed + duration:
                match = preview.convert("RGBA")
                preview_index = frame_index
                break
            elapsed += duration
        if match is None:
            raise ValueError(f"В preview нет кадра на {timestamp}ms")
        if composed.size != match.size or composed.tobytes() != match.tobytes():
            raise ValueError(f"RGBA parity провален: idle source frame {source_number}, preview index {preview_index}")
        checked.append({"source_frame": source_number, "preview_time_ms": timestamp, "preview_frame_index": preview_index, "rgba_parity": True})
    return {"background_rgba": list(BG), "preview_frame_count": preview.n_frames, "duplicate_gif_frames_coalesced_by_pillow": True, "checks": checked}


def collect() -> tuple[dict[str, bytes], dict[str, Any]]:
    outputs: dict[str, bytes] = {}
    sources: list[dict[str, Any]] = []
    idle: list[tuple[int, bytes]] = []
    for frame_number in IDLE_NUMBERS:
        source = IDLE_SOURCE / f"frame-{frame_number:03d}.png"
        data = read(source)
        image = load_image(data, relative(source))
        if image.size != (512, 512):
            raise ValueError(f"{relative(source)}: требуется 512x512")
        output_name = f"idle/frame-{len(idle) + 1:02d}.png"
        outputs[output_name] = data
        idle.append((frame_number, data))
        sources.append({"role": "idle_frame", "path": relative(source), "sha256": sha256(data), "output": output_name, "operation": "byte_copy", "timing_ms": 200})

    buff_frames = collect_manifest_frames(FEEDBACK_ROOT, BUFF_MANIFEST, "B1", BUFF_DURATIONS)
    for index, (source, data) in enumerate(buff_frames, 1):
        output_name = f"buff/frame-{index:02d}.png"
        outputs[output_name] = upscale(data, relative(source))
        sources.append({"role": "buff_frame", "path": relative(source), "sha256": sha256(data), "output": output_name, "operation": "RGBA nearest-neighbor x4", "timing_ms": BUFF_DURATIONS[index - 1]})

    death_durations = (100,) * DEATH_COUNT
    death_frames = collect_manifest_frames(FEEDBACK_ROOT, DEATH_MANIFEST, "death", death_durations)
    for index, (source, data) in enumerate(death_frames, 1):
        output_name = f"death/frame-{index:02d}.png"
        outputs[output_name] = upscale(data, relative(source))
        sources.append({"role": "death_frame", "path": relative(source), "sha256": sha256(data), "output": output_name, "operation": "RGBA nearest-neighbor x4", "timing_ms": death_durations[index - 1]})

    reference = FEEDBACK_ROOT / "inputs/ready.png"
    ref_data = read(reference)
    outputs["still.png"] = upscale(ref_data, relative(reference))
    sources.append({"role": "still", "path": relative(reference), "sha256": sha256(ref_data), "output": "still.png", "operation": "RGBA nearest-neighbor x4", "timing_ms": None})
    corpse_data = outputs["death/frame-13.png"]
    outputs["corpse.png"] = corpse_data
    death_last = next(entry for entry in sources if entry["output"] == "death/frame-13.png")
    sources.append({"role": "corpse", "path": death_last["path"], "sha256": death_last["sha256"], "output": "corpse.png", "operation": "byte_copy of death frame 13", "timing_ms": None})

    outputs["idle_frames.tres"] = sprite_frames("idle", 5.0, True, [f"idle/frame-{i:02d}.png" for i in range(1, 13)], [10] * 12)
    outputs["buff_frames.tres"] = sprite_frames("buff", 100.0, False, [f"buff/frame-{i:02d}.png" for i in range(1, 6)], list(BUFF_DURATIONS))
    outputs["death_frames.tres"] = sprite_frames("death", 10.0, False, [f"death/frame-{i:02d}.png" for i in range(1, 14)], [10] * 13)
    for item in idle:
        source_image = load_image(item[1], f"idle frame {item[0]}")
        if source_image.size != (512, 512):
            raise ValueError("Idle frame размеры изменились")
    parity = verify_idle_parity(idle)
    manifest: dict[str, Any] = {
        "format": 1,
        "base_commit": BASE_COMMIT,
        "sources": sources,
        "operations": {
            "idle": "выбранные cadence validation кадры побайтно; композиция с #3f4b43 совпадает с preview.gif по RGBA",
            "buff": "5 кадров из buff-final/manifest.json; manifest base, порядок, длительности и SHA-256 входов проверены; RGBA nearest-neighbor x4",
            "death": "13 кадров из death-final/manifest.json; manifest base, порядок, длительности и SHA-256 входов проверены; RGBA nearest-neighbor x4",
            "still": "точная копия B1 inputs/ready.png; RGBA nearest-neighbor x4",
            "corpse": "копия масштабированного death кадра 13"
        },
        "timings_ms": {"idle": [200] * 12, "buff": list(BUFF_DURATIONS), "death": list(death_durations)},
        "idle_preview_rgba_parity": parity,
        "outputs": {name: sha256(data) for name, data in sorted(outputs.items())},
        "output_png_count": sum(1 for name in outputs if name.endswith(".png")),
    }
    outputs["manifest.json"] = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return outputs, manifest


def main() -> int:
    parser = argparse.ArgumentParser(description="Детерминированная сборка rogue animation trial assets")
    parser.add_argument("--check", action="store_true", help="проверить текущую сборку без записи файлов")
    args = parser.parse_args()
    outputs, _manifest = collect()
    if args.check:
        failures: list[str] = []
        for name, expected in outputs.items():
            path = PACKAGE / name
            if not path.is_file():
                failures.append(f"missing: {name}")
            elif read(path) != expected:
                failures.append(f"mismatch: {name}")
        if failures:
            print("FAIL: " + "; ".join(failures), file=sys.stderr)
            return 1
        print(f"PASS: {len(outputs)} files match deterministic build; {sum(n.endswith('.png') for n in outputs)} PNGs; idle preview RGBA parity 12/12")
        return 0
    for name, data in outputs.items():
        path = PACKAGE / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
    print(f"Built {len(outputs)} files ({sum(n.endswith('.png') for n in outputs)} PNGs) in {PACKAGE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
