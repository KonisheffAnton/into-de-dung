"""Manual restoration of the source beard; no provider requests or motion edits."""
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
EXPRESSION = ROOT.parent / 'defender-death-expression-20261012'
ORIGINAL = ROOT.parent / 'defender-death-variants-20261012/03-last-knee/pixellab'
spec = importlib.util.spec_from_file_location('expression_preview', EXPRESSION / 'build-preview.py')
preview = importlib.util.module_from_spec(spec)
spec.loader.exec_module(preview)
manifest = json.loads((EXPRESSION / 'request-manifest.json').read_text(encoding='utf-8'))
entries = {entry['frame']: entry for entry in manifest['entries']}
sheet_mask = Image.open(EXPRESSION / 'sheet-mask.png').convert('L')
# Один ряд для сжатых зубов; подбородок и усы вокруг него возвращаются из оригинала.
MOUTH_X = {2: (68, 73), 3: (62, 67), 4: (61, 65), 5: (61, 65), 6: (61, 65),
           **{i: (60, 65) for i in range(7, 17)}, 17: (59, 64), 18: (59, 64), 19: (58, 63)}


def digest(data):
    return hashlib.sha256(data).hexdigest()


def beard_color(pixel):
    r, g, b, a = pixel
    return a == 255 and 40 < r < 170 and g < 110 and b < 85 and r > g * 1.25 and g > b * 1.15


frames_dir = ROOT / 'frames'
frames_dir.mkdir(exist_ok=True)
originals, previous, repaired, records = [], [], [], []
for number in range(1, 34):
    original_path = ORIGINAL / f'frame-{number:02}.png'
    previous_path = EXPRESSION / 'frames' / f'frame-{number:02}.png'
    original = Image.open(original_path).convert('RGBA')
    before = Image.open(previous_path).convert('RGBA')
    assert original.size == before.size == (128, 128)
    after = before.copy()
    restoration = []
    aperture = None
    if number in entries:
        entry = entries[number]
        left, top, right, bottom = entry['face_box']
        mouth_left, mouth_right = MOUTH_X[number]
        mouth_y = bottom - 3
        aperture = [mouth_left, mouth_y, mouth_right, mouth_y + 1]
        for y in range(top, bottom):
            for x in range(left, right):
                cell_x, cell_y = entry['cell']
                crop_x, crop_y = entry['crop'][:2]
                editable = sheet_mask.getpixel((cell_x + x - crop_x, cell_y + y - crop_y)) == 255
                mouth = mouth_y == y and mouth_left <= x < mouth_right
                if editable and beard_color(original.getpixel((x, y))) and not mouth:
                    after.putpixel((x, y), original.getpixel((x, y)))
                    restoration.append((x, y))
    restored_set = set(restoration)
    changed = []
    for y in range(128):
        for x in range(128):
            old_pixel, new_pixel = before.getpixel((x, y)), after.getpixel((x, y))
            assert old_pixel[3] == new_pixel[3] == original.getpixel((x, y))[3]
            if (x, y) in restored_set:
                assert new_pixel == original.getpixel((x, y))
            else:
                assert new_pixel == old_pixel
            if new_pixel != old_pixel:
                changed.append([x, y])
    output_path = frames_dir / previous_path.name
    if changed:
        after.save(output_path)
    else:
        shutil.copyfile(previous_path, output_path)
    assert Image.open(output_path).convert('RGBA').tobytes() == after.tobytes()
    originals.append(original)
    previous.append(before)
    repaired.append(after)
    records.append({'frame': number, 'source_sha256': digest(original_path.read_bytes()),
                    'previous_sha256': digest(previous_path.read_bytes()),
                    'output_sha256': digest(output_path.read_bytes()),
                    'restored_beard_pixels': len(restoration), 'changed_pixels': changed,
                    'mouth_aperture': aperture, 'alpha_unchanged': True,
                    'outside_restoration_unchanged': True})

assert all(record['changed_pixels'] for record in records[1:19])
gifs = {
    'preview.gif': preview._write_gif(ROOT / 'preview.gif', [preview._composite(f, 4) for f in repaired], loop=0),
    'native.gif': preview._write_gif(ROOT / 'native.gif', [preview._composite(f, 1) for f in repaired], loop=0),
    'before-after.gif': preview._write_gif(ROOT / 'before-after.gif', preview._before_after(previous, repaired), loop=0),
}
preview._filmstrip(ROOT / 'filmstrip.png', repaired)
comparison = Image.new('RGB', (1152, 460), (22, 33, 43))
draw = ImageDraw.Draw(comparison)
for group, number in enumerate([3, 7, 14, 17]):
    face_box = entries[number]['face_box']
    cx, cy = (face_box[0] + face_box[2]) // 2, (face_box[1] + face_box[3]) // 2
    crop = (cx - 12, cy - 12, cx + 12, cy + 12)
    base_x, base_y = group % 2 * 576, group // 2 * 230
    for column, (label, images) in enumerate([('ORIGINAL', originals), ('EXPRESSION', previous), ('BEARD FIX', repaired)]):
        x, y = base_x + column * 192, base_y
        face = images[number - 1].crop(crop).resize((192, 192), Image.Resampling.NEAREST)
        comparison.paste(face, (x, y + 25), face)
        draw.text((x + 4, y + 7), f'{label} {number:02}', fill=(238, 242, 246))
comparison.save(ROOT / 'face-comparison.png')
validation = {
    'method': 'Manual restoration from original PNG beard colors; preserve one-row mouth aperture and expression elsewhere.',
    'provider_requests': 0, 'source_frames': 33, 'frames': records,
    'restored_beard_pixels': sum(r['restored_beard_pixels'] for r in records),
    'total_changed_pixels': sum(len(r['changed_pixels']) for r in records), 'gifs': gifs,
}
(ROOT / 'validation.json').write_text(json.dumps(validation, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'changed_pixels': validation['total_changed_pixels'],
                  'restored_beard_pixels': validation['restored_beard_pixels'],
                  'gifs': {k: (v['frame_count'], v['total_ms']) for k, v in gifs.items()}}))
