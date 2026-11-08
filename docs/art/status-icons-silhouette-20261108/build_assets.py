"""Reproduce the16px proposal from immutable PixelLab PNGs; no recoloring/drawing."""
import hashlib
import json
from pathlib import Path
from PIL import Image

OUT=Path(__file__).resolve().parent
def build():
    receipts=json.loads((OUT/'receipts.json').read_text(encoding='utf-8'))
    for item in receipts:
        source=OUT/item['raw_file']
        assert hashlib.sha256(source.read_bytes()).hexdigest()==item['raw_sha256']
        im=Image.open(source).convert('RGBA')
        crop=im.crop(im.getbbox())
        scale=min(1.0,14/crop.width,14/crop.height)
        size=(max(1,round(crop.width*scale)),max(1,round(crop.height*scale)))
        result=Image.new('RGBA',(16,16))
        result.alpha_composite(crop.resize(size,Image.Resampling.NEAREST),((16-size[0])//2,(16-size[1])//2))
        target=OUT/'16'/(item['id']+'.png')
        result.save(target)
        assert hashlib.sha256(target.read_bytes()).hexdigest()==item['sha256']
    print(f'Reproduced {len(receipts)} icons, verified hashes.')

if __name__=='__main__': build()
