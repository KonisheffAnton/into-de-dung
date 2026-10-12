"""Разрешённая U замена только новых слишком тёмных цветов, без изменения геометрии."""
from pathlib import Path
from collections import Counter
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent
BASE = '6bca61de324fd07da7cfe06d8576d37b21c627ad'
TARGET = (33, 30, 33)
def luminance(rgb):
    return 2126 * rgb[0] + 7152 * rgb[1] + 722 * rgb[2]
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

reference = Image.open(ROOT / 'reference-128.png').convert('RGBA')
reference_colors = {p[:3] for p in reference.getdata() if p[3]}
assert TARGET in reference_colors
assert luminance(TARGET) == min(map(luminance, reference_colors))
target_dir = ROOT / 'final' / 'frames'
target_dir.mkdir(parents=True, exist_ok=True)
records = []
for index, pose in enumerate(('cross', 'release', 'settle'), 1):
    source_path = ROOT / 'inputs' / f'{pose}.png'
    original = Image.open(source_path).convert('RGBA')
    assert original.size == (128, 128)
    before = list(original.getdata())
    replacements = {p[:3]: TARGET for p in before if p[3] and p[:3] not in reference_colors and luminance(p[:3]) < luminance(TARGET)}
    after = [(*replacements.get(p[:3], p[:3]), p[3]) if p[3] else p for p in before]
    corrected = original.copy()
    corrected.putdata(after)
    assert corrected.getchannel('A').tobytes() == original.getchannel('A').tobytes()
    assert all(a == b or (a[3] == b[3] and a[:3] in replacements and b[:3] == TARGET) for a, b in zip(before, after))
    assert all(luminance(p[:3]) >= luminance(TARGET) for p in after if p[3])
    output = target_dir / f'frame-{index:02}.png'
    corrected.save(output)
    assert Image.open(output).convert('RGBA').tobytes() == corrected.tobytes()
    counts = Counter(p[:3] for p in before if p[3])
    records.append({'pose': pose, 'source': str(source_path.relative_to(ROOT)), 'source_sha256': digest(source_path), 'output': str(output.relative_to(ROOT)), 'output_sha256': digest(output), 'replacement_colors': [{'from': list(color), 'to': list(TARGET), 'pixels': counts[color]} for color in sorted(replacements)], 'changed_color_pixels': sum(a != b for a, b in zip(before, after)), 'alpha_mismatches': 0, 'unchanged_other_pixels': True, 'bounding_box': list(original.getchannel('A').getbbox())})
manifest_sources = ['reference-128.png', 'final/frames/frame-01.png', 'final/frames/frame-02.png', 'final/frames/frame-03.png', 'reference-128.png']
durations = [200, 350, 60, 120, 240]
phases = ['ready', 'cross-hold', 'forceful-release', 'deceleration', 'exact-ready-end']
manifest = {'base': BASE, 'previous': '../rogue-buff-release-20261012/final/manifest.json', 'frames': [{'source': source, 'sha256': digest(ROOT / source), 'duration_ms': duration, 'provenance': phase} for source, duration, phase in zip(manifest_sources, durations, phases)], 'pixelOperations': 'User explicitly authorized local colors-only correction. Only new colors darker than the reference minimum are replaced by #211e21. Original pose coordinates/alpha/all other RGBA and timing preserved.', 'timing': 'Identical to prior B1: 5 frames,970ms'}
(ROOT / 'final' / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
(ROOT / 'palette-correction.json').write_text(json.dumps({'authorization': 'U: Да, исправь только цвета локально', 'target_rgb': TARGET, 'rule': 'Visible non-reference RGB with integer Rec709 luminance below reference minimum -> reference #211e21; all remaining pixels exactly unchanged', 'records': records}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'frames': 3, 'changed_pixels': [r['changed_color_pixels'] for r in records], 'alpha_mismatches': 0}))
