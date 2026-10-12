"""Build Rogue cloth masks on the shader's 128x128 grid without editing source PNGs.

Requires Pillow. --check verifies the committed masks and source hashes.
The color selection is authored for this exact set, not arbitrary future art.
"""
import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
SOURCES = ROOT / "assets/art_presets/trials/rogue_animations_v1"
DEST = ROOT / "assets/art_presets/trials/rogue_cloth_v1"
CELL = 128
COLS = 10


def sources():
    yield "still", 0, SOURCES / "still.png"
    for clip, count in (("idle", 12), ("buff", 6), ("death", 13)):
        for frame in range(count):
            yield clip, frame, SOURCES / clip / f"frame-{frame + 1:02}.png"


def native_pixels(path):
    with Image.open(path) as original:
        assert original.mode == "RGBA" and original.size == (512, 512), path
        # Точно повторяем центры native_sprite, включая субпиксельные фазы idle.
        result = Image.new("RGBA", (CELL, CELL))
        result.putdata([original.getpixel((x * 4 + 2, y * 4 + 2))
                        for y in range(CELL) for x in range(CELL)])
    return result


def cloth(color):
    r, g, b, a = color
    # Оливковая ткань отделена от рыжей кожи/ремней и нейтрального металла.
    # Тёмный контур исключён: его оттенок не должен меняться вместе с тканью.
    return a >= 128 and r > 25 and .86 * r <= g <= 1.22 * r and b < .76 * min(r, g)


def build():
    rows, paths = [], []
    for slot, (clip, frame, source) in enumerate(sources()):
        pixels = native_pixels(source)
        selected = {(x, y) for y in range(CELL) for x in range(CELL)
                    if cloth(pixels.getpixel((x, y)))}
        assert 100 < len(selected) < 2000, f"Unexpected cloth coverage: {source}: {len(selected)}"
        ox, oy = slot % COLS * CELL, slot // COLS * CELL
        for y in range(CELL):
            xs = sorted(x for x, py in selected if py == y)
            while xs:
                start = end = xs.pop(0)
                while xs and xs[0] == end + 1:
                    end = xs.pop(0)
                length = end - start + 1
                paths.append(f"M{ox + start} {oy + y}h{length}v1h-{length}z")
        rows.append({"slot": slot, "clip": clip, "frame": frame,
                     "source": source.relative_to(ROOT).as_posix(),
                     "sha256": hashlib.sha256(source.read_bytes()).hexdigest(),
                     "native_size": [CELL, CELL], "source_size": [512, 512],
                     "cloth_pixels": len(selected)})
    assert len(rows) == 32
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280" viewBox="0 0 1280 1280">\n'
           '<rect width="1280" height="1280" fill="black"/>\n'
           '<path fill="white" d="' + " ".join(paths) + '"/>\n</svg>\n')
    manifest = {"format": 1, "cell_size": CELL, "columns": COLS,
                "selection": "olive cloth only; current authored 32-frame source set",
                "sampling": "full512; centers x*4+2,y*4+2; native128", "frames": rows}
    return {"cloth_masks.svg": svg, "mask_sources.json": json.dumps(manifest, indent=2) + "\n"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for name, content in build().items():
        path = DEST / name
        if args.check:
            assert path.read_text(encoding="utf-8") == content, f"Stale mask data: {path}"
        else:
            DEST.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    print(f"Rogue cloth masks: 32 source frames {'verified' if args.check else 'built'}")


if __name__ == "__main__":
    main()
