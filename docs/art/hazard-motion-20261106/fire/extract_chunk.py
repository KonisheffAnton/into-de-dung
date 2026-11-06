"""Archive provider bytes and insert unchanged ROI pixels into the fixed source."""
from pathlib import Path
import argparse,base64,hashlib,json,shutil
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=int,required=True);p.add_argument('--start',type=int,required=True);a=p.parse_args()
    key=f'fire{a.source}-long01-c{a.start:02d}';job=JOBS/'pixellab'/key;model=ROOT/f'fire{a.source}'/'long01'
    result=json.loads((job/'response-raw.json').read_text(encoding='utf-8-sig'));frames=result['images'];assert len(frames)==4
    archive=ROOT/'pixellab'/key;archive.mkdir(parents=True,exist_ok=True)
    for name in ('request.json','response-raw.json','response-summary.json','submit-started.json'):
        shutil.copyfile(job/name,archive/name)
    for sub in ('raw','assembled'): (model/sub).mkdir(exist_ok=True)
    source=Image.open(model/'input-256.png').convert('RGBA');original=np.array(Image.open(model/'roi.png').convert('RGBA'))
    mask=np.array(Image.open(model/'mask-motion.png').convert('L'))>0
    rows=[]
    for i,frame in enumerate(frames):
        idx=a.start+i;raw=model/'raw'/f'frame-{idx:02d}.png';raw.write_bytes(base64.b64decode(frame['base64']))
        roi=Image.open(raw).convert('RGBA');assert roi.size==(64,64)
        delta=np.abs(np.array(roi).astype(int)-original.astype(int));allowed=mask if idx not in (0,15) else np.zeros_like(mask)
        tile=source.copy();tile.paste(roi,(96,67));tile.save(model/'assembled'/raw.name)
        rows.append({'index':idx,'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'changed_pixels':int(np.any(delta,axis=2).sum()),'outside_mask_changed':int(np.any(delta[~allowed],axis=1).sum()),'max_delta':int(delta.max())})
    (archive/'metrics.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
    allframes=sorted((model/'raw').glob('frame-*.png'));sheet=Image.new('RGBA',(512,((len(allframes)+3)//4)*144),(35,38,45,255));d=ImageDraw.Draw(sheet)
    for i,f in enumerate(allframes):
        x=(i%4)*128;y=(i//4)*144;sheet.alpha_composite(Image.open(f).convert('RGBA').resize((128,128),Image.Resampling.NEAREST),(x,y));d.text((x+4,y+128),f.stem,fill='white')
    sheet.save(model/'contact-2x.png');print(json.dumps(rows))
if __name__=='__main__':main()
