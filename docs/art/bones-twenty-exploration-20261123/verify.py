"""Artifact/provenance verification. Selection map is explicit, not artistic auto-approval."""
from pathlib import Path
from PIL import Image
import json,hashlib,subprocess
ROOT=Path(__file__).resolve().parent; REPO=ROOT.parents[2]
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
mapping=json.loads((ROOT/'selection.json').read_text())
assert len(mapping)==20
rows=[]
for label,path in mapping.items():
    file=ROOT/path
    with Image.open(file) as im:
        assert im.mode=='RGBA',(label,im.mode)
        assert im.getchannel('A').getextrema()[0]==0,label
        if label.startswith('PL'): assert im.size in [(48,48),(64,64)]
        rgba=im.getdata()
        colors={px[:3] for px in rgba if px[3]>0}
        rows.append({'label':label,'file':path,'size':im.size,'alpha':im.getchannel('A').getextrema(),
            'visible_rgb_colors':len(colors),'sha256':sha(file)})
assert len({r['sha256'] for r in rows})==20
prior=json.loads((ROOT/'prior-png-hashes.json').read_text())
assert all(sha(REPO/p)==h for p,h in prior.items())
src=json.loads((ROOT/'imagegen-sources.json').read_text())
assert all(sha(Path(x['source']))==sha(ROOT/'imagegen'/(x['id']+'.png')) for x in src)
receipts=list((ROOT/'pixellab').glob('*/response.json'))
usage=sum(json.loads((p.parent/'status.json' if (p.parent/'status.json').exists() else p).read_text())['usage']['generations'] for p in receipts)
report={'base':subprocess.check_output(['git','rev-parse','HEAD'],cwd=REPO,text=True).strip(),
    'scope':'20 art proposals plus research; no runtime edits','images':rows,'prior_png_unchanged':len(prior),
    'imagegen_original_copies_identical':True,'imagegen_calls':10,'pixellab_post_count':len(receipts),
    'pixellab_generations':usage,'preview':'nearest only; G cropped/framed, PL native integer upscale',
    'limitations':['G are large raster concepts with soft alpha; not native production sprites',
        'Some concepts trade bone legibility for dense fragments; user acceptance pending',
        'No Godot, game field placement, gameplay or performance checks',
        'No third-party paid asset was purchased or integrated']}
(ROOT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'final_images':len(rows),'prior_unchanged':len(prior),'pixellab_generations':usage}))
