"""Print bounded per-frame screening metrics for completed field clips."""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageFilter

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parent
ROOT=HERE.parents[3]

def rgba(path):return np.asarray(Image.open(path).convert('RGBA'),dtype=np.float32)

for req in sorted((PACKAGE/'requests').glob('fire*-field*/request-metadata.json')):
    key=req.parent.name
    manifest_path=PACKAGE/'results'/key/'manifest.json'
    if not manifest_path.exists():
        print(key,'pending');continue
    meta=json.loads(req.read_text(encoding='utf-8'));manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
    inp=rgba(ROOT/meta['group']['input_path']);core=np.asarray(Image.open(ROOT/meta['group']['core_mask_path']).convert('L'))>0
    source_mask=inp[:,:,3]>8
    dilation=np.asarray(Image.fromarray(source_mask.astype('uint8')*255).filter(ImageFilter.MaxFilter(9)))>0
    frames=[rgba(PACKAGE/'results'/key/'raw'/f'frame-{n:02}.png') for n in range(manifest['returned_frames'])]
    def light(x):return (x[:,:,:3]*np.array([.2126,.7152,.0722])[None,None,:]).sum(axis=2)*x[:,:,3]/255
    il=light(inp);den=il.sum()
    print('\n',key,len(frames),'inputalpha',source_mask.sum(),'core',core.sum())
    for i,f in enumerate(frames):
        m=f[:,:,3]>8; al=f[:,:,3]; lum=light(f)
        border=int(np.count_nonzero(np.r_[al[0,:],al[-1,:],al[:,0],al[:,-1]]>0))
        prev=frames[i-1] if i else f;pm=prev[:,:,3]>8
        print(f'{i:02}:core{(core&~m).sum():3} out4{(m&~dilation).sum():4} border{border:3} area{m.sum():5} axor{(m^source_mask).sum():4} adjxor{(m^pm).sum():4} light{lum.sum()/den:5.2f} max+{np.max(lum-il):5.0f}')
