from pathlib import Path
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[4]
HERE=Path(__file__).resolve().parent
RAW=ROOT/'docs/art/hazard-animations-20261104/pixellab/caltrops03-01/frames'
BASE=ROOT/'docs/art/hazard-animations-20261104/model/caltrops03/input-256.png'
images=[('source',BASE)]+[(f'raw {i:02}',RAW/f'frame-{i:02}.png') for i in (0,1,2,3,4,5,6)]
contact=Image.new('RGBA',(4*256,2*282),(36,39,44,255)); d=ImageDraw.Draw(contact)
for i,(label,path) in enumerate(images):
    img=Image.open(path).convert('RGBA'); x=i%4*256;y=i//4*282
    contact.alpha_composite(img,(x,y+24));d.text((x+5,y+5),label,fill='white')
contact.convert('RGB').save(HERE/'source-raw-contact.png')
for n,box in enumerate(((129,89,154,114),(129,118,153,142))):
    out=Image.new('RGBA',(len(images)*160,190),(36,39,44,255));dd=ImageDraw.Draw(out)
    for i,(label,path) in enumerate(images):
        img=Image.open(path).convert('RGBA').crop(box).resize((150,150),Image.Resampling.NEAREST)
        out.alpha_composite(img,(i*160,25));dd.text((i*160+4,4),label,fill='white')
    out.convert('RGB').save(HERE/f'glint-{n+1}-source-raw-6x.png')
