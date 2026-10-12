"""Build deterministic cloth selection data; never modify the approved source PNGs.

Run with Pillow installed. --check validates committed masks against all sources.
The masks use the native shader sampling grid, including the 77x72 still.
"""
import argparse
from collections import deque
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / "assets/art_presets/trials/defender_cloth_v1"
CELL = 128
COLS = 10


def sources():
    yield "still", 0, "defender_field_v1/defender_new.png"
    for clip, folder, count in (("vertical", "defender_idle_v1/vertical", 12),
                               ("sway", "defender_idle_v1/sway", 12),
                               ("buff", "defender_buff_v1", 33),
                               ("death", "defender_death_v1", 33)):
        for frame in range(count):
            yield clip, frame, f"{folder}/frame-{frame + 1:02}.png"


def native_pixels(path, still):
    source = Image.open(path).convert("RGBA")
    if not still:
        assert source.size == (128, 128), path
        return source
    result = Image.new("RGBA", (77, 72))
    for y in range(72):
        for x in range(77):
            result.putpixel((x, y), source.getpixel((int(89 + (x + .5) * 1034 / 77),
                                                    int(206 + (y + .5) * 966 / 72))))
    return result


def olive(color):
    r, g, b, a = color
    return a >= 128 and r > 25 and .86 * r <= g <= 1.22 * r and b < .76 * min(r, g)


def components(points):
    remaining = set(points)
    result = []
    while remaining:
        seed = min(remaining)
        remaining.remove(seed)
        queue = deque([seed])
        part = {seed}
        while queue:
            x, y = queue.popleft()
            for p in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                if p in remaining:
                    remaining.remove(p)
                    queue.append(p)
                    part.add(p)
        result.append(part)
    return result


def hull(points):
    def cross(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    ordered = sorted(points)
    halves = []
    for sequence in (ordered, ordered[::-1]):
        half = []
        for p in sequence:
            while len(half) >= 2 and cross(half[-2], half[-1], p) <= 0:
                half.pop()
            half.append(p)
        halves.append(half[:-1])
    return halves[0] + halves[1]


def inside(p, polygon):
    return all((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0]) >= 0
               for a, b in zip(polygon, polygon[1:] + polygon[:1]))


def cloth_selection(pixels):
    candidates = {(x, y) for y in range(pixels.height) for x in range(pixels.width)
                  if olive(pixels.getpixel((x, y)))}
    parts = components(candidates)
    shield = max(parts, key=len)
    center_x = sum(x for x, _ in shield) / len(shield)
    assert center_x > pixels.width * .55, "Source no longer matches the approved shield layout"
    # Щит использует те же цвета. Его контур включает островки, разделённые мечом/искрами.
    margin = 10 * pixels.width / 128
    shield_parts = set().union(*(part for part in parts
                                if sum(x for x, _ in part) / len(part) > center_x - margin))
    polygon = hull(shield_parts)
    selected = {p for p in candidates if not inside(p, polygon)}
    assert selected, "Missing cloth; inspect the source before regenerating"
    return selected, polygon


def build():
    rows = []
    paths = []
    for slot, (clip, frame, relative) in enumerate(sources()):
        source = ROOT / "assets/art_presets/trials" / relative
        pixels = native_pixels(source, clip == "still")
        selected, shield = cloth_selection(pixels)
        ox, oy = slot % COLS * CELL, slot // COLS * CELL
        for y in range(pixels.height):
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
                     "native_size": list(pixels.size), "cloth_pixels": len(selected),
                     "shield_exclusion": shield})
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="1280" viewBox="0 0 1280 1280">\n'
           '<rect width="1280" height="1280" fill="black"/>\n'
           '<path fill="white" d="' + " ".join(paths) + '"/>\n</svg>\n')
    manifest = {"format": 1, "cell_size": CELL, "columns": COLS, "frames": rows}
    return {"cloth_masks.svg": svg, "mask_sources.json": json.dumps(manifest, indent=2) + "\n"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    results = build()
    for name, content in results.items():
        path = DEST / name
        if args.check:
            assert path.read_text(encoding="utf-8") == content, f"Stale mask data: {path}"
        else:
            DEST.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
    print(f"Defender cloth masks: 91 source frames {'verified' if args.check else 'built'}")


if __name__ == "__main__":
    main()
