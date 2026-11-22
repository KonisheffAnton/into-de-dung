"""Verify provenance and PNG integrity, not automatic artistic acceptance."""
from pathlib import Path
from PIL import Image
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
rows=[]
for i in range(5):
    for label,relative in [(f'G{i+6}',f'imagegen/G{i+6}.png'),(f'PL{i+14}',f'pixellab/PL{i+14}-adapt/image.png')]:
        path=ROOT/relative
        with Image.open(path) as im:
            assert im.mode=='RGBA'
            assert im.getchannel('A').getextrema()[0]==0
            if label.startswith('PL'): assert im.size==(64,64)
            rows.append({'label':label,'file':relative,'size':im.size,'alpha':im.getchannel('A').getextrema(),'sha256':sha(path)})
prior=json.loads((ROOT/'prior-png-hashes.json').read_text())
assert all(sha(REPO/p)==h for p,h in prior.items())
sources=json.loads((ROOT/'imagegen-sources.json').read_text())
assert all(sha(Path(x['source']))==sha(ROOT/'imagegen'/(x['id']+'.png')) for x in sources)
receipts=list((ROOT/'pixellab').glob('*/response.json'))
usage=sum(json.loads((p.parent/'status.json' if (p.parent/'status.json').exists() else p).read_text())['usage']['generations'] for p in receipts)
result={'base':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
    'scope':'art proposals only, smaller individual bones; no runtime edits','final_images':rows,
    'prior_png_unchanged':len(prior),'original_imagegen_copies_identical':True,
    'imagegen_calls':5,'pixellab_posts':len(receipts),'pixellab_generations':usage,
    'presentation':'G same 54x39 max thumbnail on64 canvas as prior, nearest; PL native64 x4',
    'limits':['G remains high-resolution concept with partial alpha/soft edging',
        'PL final adapts new G concepts; not an independent composition family',
        'Requested half-size/piece count not an exact measured guarantee',
        'No game field placement or Godot checks; selection pending']}
(ROOT/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'final_png':len(rows),'prior_unchanged':len(prior),'pixellab_posts':len(receipts),'pixellab_generations':usage}))
