"""Use two existing PixelLab poses as interpolation endpoints; no local tweening."""
from pathlib import Path
import json,base64,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106');key='fire24-interpolate01'
out=ROOT/'fire24'/'interpolate01';job=JOBS/'pixellab'/key
if job.exists():raise SystemExit('Immutable request exists')
out.mkdir(parents=True,exist_ok=True);crop=(64,40,192,168);inputs=[]
for name,frame in [('start',0),('end',7)]:
    src=ROOT/'fire24'/'layer02'/'raw'/f'frame-{frame:02d}.png';im=Image.open(src).convert('RGBA');bbox=im.getbbox();assert bbox[0]>=crop[0] and bbox[1]>=crop[1] and bbox[2]<=crop[2] and bbox[3]<=crop[3]
    dest=out/f'{name}.png';im.crop(crop).save(dest);inputs.append({'name':name,'source':str(src.relative_to(ROOT)),'source_sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'crop_xyxy':crop})
def enc(p):return {'image':{'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode()},'size':{'width':128,'height':128}}
req={'start_image':enc(out/'start.png'),'end_image':enc(out/'end.png'),'action':'Interpolate smoothly between these two almost identical low flame patterns. Gently bend the existing small curled tips in place, with fixed roots and stable brightness. Use the shortest motion between corresponding strokes. Keep the whole diamond stationary. Preserve transparency. No new shapes, loops, rising flames, flashes, jets, or camera movement.','image_size':{'width':128,'height':128},'seed':202611069024,'no_background':True}
job.mkdir(parents=True);(job/'request.json').write_text(json.dumps(req,indent=2)+'\n',encoding='utf-8');meta={'key':key,'endpoint':'interpolation-v2','request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'inputs':inputs,'motion_source':'Both endpoints are exact native-scale crops of PixelLab output; no locally drawn intermediate frames'};(out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8');print(json.dumps(meta))
