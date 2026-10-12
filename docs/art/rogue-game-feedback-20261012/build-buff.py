"""Keep PixelLab geometry; reuse the user's approved B1 colors-only correction."""
from pathlib import Path
import hashlib
import json
from PIL import Image

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
PREVIOUS = ROOT / 'docs/art/rogue-buff-outline-20261012'
TARGET = (33, 30, 33)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def luminance(rgb): return 2126*rgb[0]+7152*rgb[1]+722*rgb[2]
def relative(path): return path.relative_to(OUT).as_posix()

target_dir = OUT / 'buff-final'
target_dir.mkdir(exist_ok=True)
inputs = OUT / 'inputs'
inputs.mkdir(exist_ok=True)
previous = json.loads((PREVIOUS/'final/manifest.json').read_text(encoding='utf-8'))
for name, source in [('ready.png', PREVIOUS/'reference-128.png'), ('cross.png', (PREVIOUS/previous['frames'][1]['source']).resolve()), ('settle.png', (PREVIOUS/previous['frames'][3]['source']).resolve())]:
    (inputs/name).write_bytes(source.read_bytes())
reference = Image.open(inputs/'ready.png').convert('RGBA')
palette = {p[:3] for p in reference.get_flattened_data() if p[3]}
assert TARGET in palette and luminance(TARGET) == min(map(luminance, palette))
records = []
for index, pose in [(1,'release')]:
    source = OUT/f'buff-wide/pixellab/frame-{index:02d}.png'
    original = Image.open(source).convert('RGBA')
    before = list(original.get_flattened_data())
    changes = {p[:3]:TARGET for p in before if p[3] and p[:3] not in palette and luminance(p[:3]) < luminance(TARGET)}
    after = [(*changes.get(p[:3],p[:3]),p[3]) if p[3] else p for p in before]
    corrected = original.copy()
    corrected.putdata(after)
    assert original.getchannel('A').tobytes() == corrected.getchannel('A').tobytes()
    assert all(a == b or (a[3] == b[3] and a[:3] in changes and b[:3] == TARGET) for a,b in zip(before,after))
    destination=target_dir/f'{pose}.png'
    corrected.save(destination)
    records.append({'pose':pose, 'source':relative(source),'source_sha256':sha(source),'output':relative(destination),'output_sha256':sha(destination),'changed_rgb_pixels':sum(a!=b for a,b in zip(before,after)), 'alpha_mismatches':0,'unchanged_other_rgba':True,'replacement_colors': [{'from':k,'to':v} for k,v in sorted(changes.items())]})

sources = [inputs/'ready.png', inputs/'cross.png', target_dir/'release.png', inputs/'settle.png', inputs/'ready.png']
frames = [{'source':relative(p), 'sha256':sha(p), 'duration_ms':d} for p,d in zip(sources,[200,350,60,120,240])]
(target_dir/'manifest.json').write_text(json.dumps({'base':'d16bd004a5ab91a44e33965fc8515f16106f388b','frames':frames,'provider_job':'855fd0e5-3d5e-485d-b85e-41ec919780b7','timing_ms':970,'pixelOperations':'Only already authorized B1 dark-color mapping to reference #211e21; provider geometry/alpha unchanged.'},indent=2)+'\n',encoding='utf-8')
(OUT/'buff-palette-correction.json').write_text(json.dumps({'authorization':'Prior explicit user permission: correct only colors locally for B1 outline; no pose edits.', 'records':records},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'frames':5,'duration_ms':970,'changed_rgb':[r['changed_rgb_pixels'] for r in records],'alpha_mismatches':0}))
