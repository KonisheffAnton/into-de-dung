"""Assemble rare glints by selecting bright PixelLab pixels on a fixed source plate.

All changed pixels are copied unchanged from old PixelLab frames.  This is a
derived assembly, not a provider-returned animation or a generated new pose.
"""
from pathlib import Path
import hashlib
import json
import shutil
from PIL import Image, ImageDraw
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
RAW=ROOT/'docs/art/hazard-animations-20261104/pixellab/caltrops03-01/frames'
BASE=ROOT/'docs/art/hazard-animations-20261104/model/caltrops03/input-256.png'
EVENTS=[('glint-low-peak',2,(135,123,149,137)),
        ('glint-low-tail',3,(135,123,149,137)),
        ('glint-high-peak',5,(135,95,151,109)),
        ('glint-high-hold',6,(135,95,151,109))]
THRESHOLD=15.0

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    base=Image.open(BASE).convert('RGBA')
    shutil.copyfile(BASE,HERE/'rest.png')
    base_arr=np.array(base)
    raw0=np.array(Image.open(RAW/'frame-00.png').convert('RGBA'))
    contact=Image.new('RGBA',(5*256,2*280),(36,39,44,255));d=ImageDraw.Draw(contact)
    contact.alpha_composite(base,(0,24));d.text((5,5),'fixed source/rest',fill='white')
    evidence=[]
    for col,(name,idx,box) in enumerate(EVENTS,1):
        raw_path=RAW/f'frame-{idx:02}.png'
        raw=Image.open(raw_path).convert('RGBA');r=np.array(raw)
        x0,y0,x1,y1=box
        # Positive light difference inside an explicitly bounded original glint.
        delta=r[y0:y1,x0:x1,:3].astype(float).mean(2)-raw0[y0:y1,x0:x1,:3].astype(float).mean(2)
        mask=np.zeros((256,256),dtype=bool)
        mask[y0:y1,x0:x1]=delta>THRESHOLD
        assembled=base_arr.copy();assembled[mask]=r[mask]
        out=Image.fromarray(assembled,'RGBA');path=HERE/f'{name}.png';out.save(path)
        Image.fromarray((mask*255).astype('uint8'),'L').save(HERE/f'{name}-mask.png')
        contact.alpha_composite(out,(col*256,24)); contact.alpha_composite(raw,(col*256,304))
        d.text((col*256+5,5),name,fill='white');d.text((col*256+5,285),f'PixelLab raw {idx:02}',fill='white')
        assert np.array_equal(assembled[~mask],base_arr[~mask])
        assert np.array_equal(assembled[mask],r[mask])
        evidence.append({'pose':name,'raw_frame':idx,'raw_sha256':sha(raw_path),
                         'assembled_sha256':sha(path),'mask_pixels':int(mask.sum()),
                         'mask_bbox':box,'changed_outside_mask':0,
                         'changed_pixels':int(np.any(assembled!=base_arr,axis=2).sum())})
    contact.convert('RGB').save(HERE/'candidate-contact.png')
    close=Image.new('RGBA',(5*160,2*180),(36,39,44,255)); cd=ImageDraw.Draw(close)
    allposes=[('rest',BASE)]+[(name,HERE/f'{name}.png') for name,_,_ in EVENTS]
    for col,(name,path) in enumerate(allposes):
        image=Image.open(path).convert('RGBA')
        for row,box in enumerate(((133,120,153,140),(133,92,153,112))):
            crop=image.crop(box).resize((160,160),Image.Resampling.NEAREST)
            close.alpha_composite(crop,(col*160,row*180+20))
        cd.text((col*160+4,4),name,fill='white')
    close.convert('RGB').save(HERE/'glints-assembled-8x.png')
    schedule=[('rest',5000),('glint-low-peak',150),('glint-low-tail',150),('rest',5000),
              ('glint-high-peak',150),('glint-high-hold',150),('rest',5000)]
    (HERE/'candidate-metrics.json').write_text(json.dumps({'base_sha256':sha(BASE),
        'raw_frame00_vs_base_changed_pixels':int(np.any(raw0!=base_arr,axis=2).sum()),
        'raw_frame00_vs_base_max_channel_delta':int(np.max(np.abs(raw0.astype(int)-base_arr.astype(int)))),
        'light_delta_threshold':THRESHOLD,'poses':evidence,'schedule_ms':schedule},indent=2)+'\n',encoding='utf-8')

if __name__=='__main__':main()
