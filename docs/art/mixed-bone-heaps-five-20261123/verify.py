"""Art integrity/provenance checks only; no runtime or artistic acceptance claim."""
from pathlib import Path
from PIL import Image
import hashlib, json, subprocess

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
mapping = {f'G{i}':f'imagegen/G{i}.png' for i in range(1,6)}
mapping.update({f'PL{i}':f'pixellab/PL{i}/image.png' for i in range(9,14)})
mapping['PL11'] = 'pixellab/PL11-clean/image.png'
rows = []
for label, relative in mapping.items():
    path = ROOT/relative
    with Image.open(path) as im:
        assert im.mode == 'RGBA', (label, im.mode)
        alpha = im.getchannel('A')
        assert alpha.getextrema()[0] == 0 and alpha.getextrema()[1] > 128
        if label.startswith('PL'): assert im.size == (64,64)
        rows.append({'label':label,'file':relative,'size':im.size,'alpha':alpha.getextrema(),
            'visible_bbox_alpha128':alpha.point(lambda a:255 if a>=128 else 0).getbbox(),
            'sha256':sha(path)})
prior = json.loads((ROOT/'prior-png-hashes.json').read_text())
assert all(sha(REPO/path) == digest for path,digest in prior.items())
receipts = list((ROOT/'pixellab').glob('*/response.json'))
usage = sum(json.loads((path.parent/'status.json' if (path.parent/'status.json').exists() else path).read_text())['usage']['generations'] for path in receipts)
sources = json.loads((ROOT/'imagegen-sources.json').read_text())
assert all(sha(Path(row['source'])) == sha(ROOT/'imagegen'/(row['id']+'.png')) for row in sources)
report = {'scope':'art concepts only; no runtime integration',
    'base_at_verification':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
    'final_images':rows,'prior_png_unchanged':len(prior),'imagegen_original_copies_identical':True,
    'pixellab_post_count':len(receipts),'pixellab_generations':usage,'imagegen_calls':5,
    'preview_scaling':'nearest only; G framing/thumbnail, native PL x4',
    'limitations':['G originals are large raster concepts, not native64',
        'G1/G2/G5 faint alpha halo; provider cleanup needed if selected',
        'No gameplay, field placement or user acceptance tested']}
before = Image.open(ROOT/'pixellab/PL11-v4/image.png').convert('RGBA')
after = Image.open(ROOT/'pixellab/PL11-clean/image.png').convert('RGBA')
mask = Image.open(ROOT/'PL11-clean-mask.png').convert('L')
protected = [xy for xy in ((x,y) for y in range(64) for x in range(64)) if mask.getpixel(xy)==0]
assert all(before.getpixel(xy)==after.getpixel(xy) for xy in protected)
report['PL11_masked_cleanup_preserved_pixels'] = len(protected)
(ROOT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'final_png':len(rows),'prior_unchanged':len(prior),'pl_usage':usage}))
