"""Select original PixelLab spike pixels over the byte-exact retracted plate.

This creates an assembly preview, not raw provider frames. No pose is drawn or
interpolated; each selected pixel is copied unchanged from an existing frame.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RAW = ROOT / 'docs/art/fire-spikes-animation-20261105/pixellab/spike01-01/frames'
BASE = ROOT / 'docs/art/fire-spikes-animation-20261105/model/spike01/retracted-input-256.png'
CENTERS = [(128,54),(105,72),(151,72),(83,91),(128,91),(174,91),(105,110),(151,110),(128,129)]
POSES = [(0,'closed',0),(3,'half',8),(8,'extended',16)]

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def make_mask(height):
    m=Image.new('L',(256,256),0)
    if not height:return m
    d=ImageDraw.Draw(m)
    for x,y in CENTERS:
        # Narrow copy region follows the existing vertical metal pixels and
        # intentionally excludes the socket rim and surrounding stone.
        d.polygon([(x-1,y-height),(x+1,y-height),(x+3,y-2),(x+3,y+1),
                   (x-3,y+1),(x-3,y-2)],fill=255)
    return m

def main():
    base=Image.open(BASE).convert('RGBA')
    evidence=[]
    contact=Image.new('RGBA',(3*256,2*282),(34,37,43,255))
    draw=ImageDraw.Draw(contact)
    for col,(idx,name,height) in enumerate(POSES):
        raw_path=RAW/f'frame-{idx:02}.png'
        raw=Image.open(raw_path).convert('RGBA')
        mask=make_mask(height)
        out=Image.composite(raw,base,mask)
        out_path=HERE/f'{name}.png'
        out.save(out_path)
        mask.save(HERE/f'{name}-mask.png')
        contact.alpha_composite(out,(col*256,24))
        contact.alpha_composite(raw,(col*256,306))
        draw.text((col*256+5,4),f'assembled {name}',fill='white')
        draw.text((col*256+5,286),f'PixelLab raw {idx:02}',fill='white')
        a=np.array(out); b=np.array(base); r=np.array(raw); m=np.array(mask)>0
        assert np.array_equal(a[~m],b[~m]) and np.array_equal(a[m],r[m])
        evidence.append({'pose':name,'raw_frame':idx,'raw_sha256':sha(raw_path),
                         'assembled_sha256':sha(out_path),'mask_pixels':int(m.sum()),
                         'changed_outside_mask':int(np.any(a[~m]!=b[~m],axis=-1).sum()),
                         'changed_pixels':int(np.any(a!=b,axis=-1).sum())})
    contact.convert('RGB').save(HERE/'candidate-contact.png')
    detail=Image.new('RGBA',(3*240,3*215),(34,37,43,255));dd=ImageDraw.Draw(detail)
    for row,(cx,cy) in enumerate((CENTERS[0],CENTERS[3],CENTERS[8])):
        for col,(_,name,_) in enumerate(POSES):
            img=Image.open(HERE/f'{name}.png').convert('RGBA')
            crop=img.crop((cx-12,cy-13,cx+12,cy+8)).resize((240,210),Image.Resampling.NEAREST)
            detail.alpha_composite(crop,(col*240,row*215+5))
            dd.text((col*240+5,row*215+5),name,fill='yellow')
    detail.convert('RGB').save(HERE/'socket-assembled-10x.png')
    (HERE/'candidate-metrics.json').write_text(json.dumps({'base_sha256':sha(BASE),'poses':evidence},indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
