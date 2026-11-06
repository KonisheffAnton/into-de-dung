"""Read-only pair metrics for selecting unchanged PixelLab poses."""
from pathlib import Path
import numpy as np
from PIL import Image

PACKAGE = Path(__file__).resolve().parents[1]

def load(key, frame):
    path = PACKAGE / 'results' / key / 'raw' / f'frame-{frame:02}.png'
    return np.asarray(Image.open(path).convert('RGBA')).astype(np.int16)

def pair(a, b):
    aa=a[:,:,3]; ba=b[:,:,3]
    ap=a[:,:,:3]*aa[:,:,None]/255.0
    bp=b[:,:,:3]*ba[:,:,None]/255.0
    d=np.max(np.abs(ap-bp),axis=2)
    return {'alpha_xor':int(np.logical_xor(aa>8,ba>8).sum()),
            'premul_gt8':int((d>8).sum()),
            'premul_sum':round(float(d.sum())),
            'alpha_sum':int(np.abs(aa-ba).sum())}

if __name__=='__main__':
    for key,ids in [('fire24-field07',[1,2,3,15,16]),('fire29-field01',list(range(1,17)))]:
        frames={i:load(key,i) for i in ids}
        print('\n'+key)
        for i in ids:
            row=[]
            for j in ids:
                m=pair(frames[i],frames[j]); row.append(f"{m['alpha_xor']}/{m['premul_gt8']}")
            print(f'{i:02} '+ ' '.join(row))
