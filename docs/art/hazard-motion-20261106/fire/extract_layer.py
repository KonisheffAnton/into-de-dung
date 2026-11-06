"""Decode immutable PixelLab V3 outputs without changing their pixels."""
from pathlib import Path
import argparse,json,base64,shutil,hashlib
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')
def main():
    p=argparse.ArgumentParser();p.add_argument('--key',required=True);a=p.parse_args();source,attempt=a.key.split('-');model=ROOT/source/attempt;job=JOBS/'pixellab'/a.key
    res=json.loads((job/'job-latest.json').read_text(encoding='utf-8-sig'));assert res['status']=='completed'
    archive=ROOT/'pixellab'/a.key;archive.mkdir(parents=True,exist_ok=True);raw=model/'raw';raw.mkdir(exist_ok=True)
    for name in ('request.json','admission.json','submit-started.json','job-latest.json'):shutil.copyfile(job/name,archive/name)
    frames=res['last_response']['images'];sheet=Image.new('RGBA',(256*3,280*((len(frames)+2)//3)),(30,34,43,255));d=ImageDraw.Draw(sheet);hashes=[]
    for i,v in enumerate(frames):
        f=raw/f'frame-{i:02d}.png';f.write_bytes(base64.b64decode(v['base64']));im=Image.open(f).convert('RGBA');assert im.size==(256,256)
        x=i%3*256;y=i//3*280;sheet.alpha_composite(im,(x,y));d.text((x+10,y+256),str(i),fill='white');hashes.append({'frame':i,'sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'alpha_bbox':im.getbbox()})
    sheet.save(model/'contact.png');report={'frames':len(frames),'billing':res['last_response']['billing_usage'],'raw':hashes};(model/'raw-manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps(report))
if __name__=='__main__':main()
