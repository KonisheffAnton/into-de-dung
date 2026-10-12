"""Keep PixelLab geometry; reuse the user's approved B1 colors-only correction."""
from pathlib import Path
import hashlib
import json
from PIL import Image

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
PREVIOUS = ROOT / 'docs/art/rogue-game-feedback-20261012'
TARGET = (33, 30, 33)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def luminance(rgb): return 2126*rgb[0]+7152*rgb[1]+722*rgb[2]
def relative(path): return path.relative_to(OUT).as_posix()

target_dir = OUT / 'buff-final'
target_dir.mkdir(exist_ok=True)
inputs = OUT / 'inputs'
inputs.mkdir(exist_ok=True)
previous = json.loads((PREVIOUS/'buff-final/manifest.json').read_text(encoding='utf-8'))
for name, source in [('ready.png', PREVIOUS/'inputs/ready.png'), ('cross.png', (PREVIOUS/previous['frames'][1]['source']).resolve()), ('settle.png', (PREVIOUS/previous['frames'][3]['source']).resolve()), ('peak.png', PREVIOUS/'buff-final/release.png')]:
    (inputs/name).write_bytes(source.read_bytes())
reference = Image.open(inputs/'ready.png').convert('RGBA')
palette = {p[:3] for p in reference.get_flattened_data() if p[3]}
assert TARGET in palette and luminance(TARGET) == min(map(luminance, palette))
records = []
for index, pose in [(1,'release-80'),(2,'release-94')]:
    source = OUT/f'buff-deceleration/pixellab/frame-{index:02d}.png'
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

sources = [inputs/'ready.png', inputs/'cross.png', target_dir/'release-80.png', target_dir/'release-94.png', inputs/'settle.png', inputs/'ready.png']
frames = [{'source':relative(p), 'sha256':sha(p), 'duration_ms':d} for p,d in zip(sources,[120,240,60,320,120,160])]
(target_dir/'manifest.json').write_text(json.dumps({'base':'c464c03d99f316dcebe231dc00794c984e84f197','frames':frames,'provider_job':'cfb5168d-7db7-4ca7-88e8-4ef8a5e5f8db','timing_ms':1020,'pixelOperations':'Only already authorized B1 dark-color mapping to reference #211e21; provider geometry/alpha unchanged.'},indent=2)+'\n',encoding='utf-8')
(OUT/'buff-palette-correction.json').write_text(json.dumps({'authorization':'Prior explicit user permission: correct only colors locally for B1 outline; no pose edits.', 'records':records},indent=2)+'\n',encoding='utf-8')
print(json.dumps({'frames':6,'duration_ms':1020,'changed_rgb':[r['changed_rgb_pixels'] for r in records],'alpha_mismatches':0}))
