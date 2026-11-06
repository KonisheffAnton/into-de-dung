"""Inspect unchanged poses over the unchanged source; no motion synthesis."""
from pathlib import Path
import argparse, json
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ROOT=Path(__file__).resolve().parent

def inspect(key):
    meta=json.loads((ROOT/'requests'/key/'request-metadata.json').read_text())
    source=Image.open(ROOT.parent/'fire-low-styles-20261104'/f'{key[:6].replace("fire", "fire-low-")}.png').convert('RGBA')
    roi=tuple(meta['group']['crop_xyxy']); orig=np.array(Image.open(ROOT/meta['input']).convert('RGBA'))
    support=orig[:,:,3]>127; dist=np.full(support.shape,256,dtype=np.uint16); dist[support]=0
    grown=Image.fromarray((support*255).astype('uint8'))
    for radius in range(1,257):
        grown=grown.filter(ImageFilter.MaxFilter(3)); newly=(np.array(grown)>0)&(dist==256); dist[newly]=radius
        if not (dist==256).any():break
    out=ROOT/'results'/key; pose_files=sorted((out/'raw').glob('frame-*.png'))
    rows=[]; size=meta['input_size'][0]; scale=2 if size==128 else 1
    sheet=Image.new('RGBA',(6*256,278),(30,34,43,255));draw=ImageDraw.Draw(sheet)
    sheet.alpha_composite(source.crop(roi).resize((256,256)),(0,0));draw.text((4,260),'original',fill='white')
    for i,path in enumerate(pose_files):
        im=Image.open(path).convert('RGBA');v=np.array(im);inside=v[:,:,3]>127
        rows.append({'frame':i,'max_alpha_chebyshev_distance_outside_input':int(dist[inside].max()),
            'alpha_pixels_over_3px_outside_input':int((inside&(dist>3)).sum())})
        if i in (0,3,8,12,16):
            tile=source.copy();tile.alpha_composite(im,roi[:2]);j=(0,3,8,12,16).index(i)+1
            sheet.alpha_composite(tile.crop(roi).resize((256,256),Image.Resampling.NEAREST),(j*256,0))
            draw.text((j*256+4,260),f'provider{i}',fill='white')
    sheet.save(out/'source-over-comparison.png')
    (out/'geometry.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'key':key,'geometry':rows}))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('keys',nargs='+');a=p.parse_args()
    for key in a.keys:inspect(key)
