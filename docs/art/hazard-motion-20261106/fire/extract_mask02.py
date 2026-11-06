"""Decode masked provider poses and assemble the unchanged 64px ROI."""
from pathlib import Path
import json,base64,shutil,argparse
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=int,required=True);a=p.parse_args();key=f'fire{a.source}-mask02';model=ROOT/f'fire{a.source}'/'mask02';job=JOBS/'pixellab'/key
    res=json.loads((job/'response-raw.json').read_text(encoding='utf-8-sig'));archive=ROOT/'pixellab'/key;archive.mkdir(parents=True,exist_ok=True)
    for name in ('request.json','response-raw.json','response-summary.json','submit-started.json'):shutil.copyfile(job/name,archive/name)
    for sub in ('raw','assembled'):(model/sub).mkdir(exist_ok=True)
    source=Image.open(ROOT/f'fire{a.source}'/'long01'/'input-256.png').convert('RGBA');sheet=Image.new('RGBA',(512,288),(30,34,43,255));d=ImageDraw.Draw(sheet)
    for i,v in enumerate(res['images']):
        f=model/'raw'/f'frame-{i:02d}.png';f.write_bytes(base64.b64decode(v['base64']));im=Image.open(f).convert('RGBA');assert im.size==(64,64)
        tile=source.copy();tile.paste(im,(96,67));tile.save(model/'assembled'/f.name)
        sheet.alpha_composite(im.resize((128,128),Image.Resampling.NEAREST),(i*128,0));d.text((i*128+4,130),str(i),fill='white');sheet.alpha_composite(tile.resize((128,128),Image.Resampling.LANCZOS),(i*128,152))
    sheet.save(model/'contact.png');print(json.dumps({'key':key,'frames':len(res['images']),'usage':res['usage']}))
if __name__=='__main__':main()
