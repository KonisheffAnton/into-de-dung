"""Ask PixelLab to draw a constrained extreme pose before interpolation."""
from pathlib import Path
import json,base64,hashlib
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106');key='fire24-keypose02'
out=ROOT/'fire24'/'keypose02';job=JOBS/'pixellab'/key
if job.exists():raise SystemExit('Immutable request exists')
out.mkdir(parents=True,exist_ok=True);source=ROOT/'fire24'/'long01'/'input-256.png';im=Image.open(source).convert('RGBA');im.save(out/'source.png')
mask=Image.new('RGB',(256,256));d=ImageDraw.Draw(mask)
# Small regions cover only tips of selected existing strokes, leaving roots fixed.
rects=[(140,69,147,79),(128,80,135,88),(118,92,125,101),(139,105,146,114),(146,117,153,127),(111,119,118,129),(102,100,109,109),(105,72,112,83),(133,130,140,141)]
for rect in rects:d.rectangle(rect,fill='white')
mask.save(out/'mask.png');preview=im.copy();overlay=Image.new('RGBA',im.size);od=ImageDraw.Draw(overlay)
for rect in rects:od.rectangle(rect,fill=(255,25,210,140))
preview.alpha_composite(overlay);preview.resize((768,768),Image.Resampling.NEAREST).save(out/'mask-preview.png')
def enc(p):return {'image':{'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode()},'size':{'width':256,'height':256}}
req={'description':'Edit the existing orange-yellow flame tips in the white areas into a slightly right-leaning pose for a quiet animation. Each tip curls two pixels to the right, while its connected root stays exactly in place. Preserve the current small low flame shapes, palette, steady brightness, and painterly style. These are existing tiny flame tips, not new fires or objects. Match the surrounding picture at every mask edge. The dark stone and all unmasked pixels remain exactly unchanged.','inpainting_image':enc(out/'source.png'),'mask_image':enc(out/'mask.png'),'seed':202611068024,'no_background':False,'crop_to_mask':True}
job.mkdir(parents=True);(job/'request.json').write_text(json.dumps(req,indent=2)+'\n',encoding='utf-8')
meta={'key':key,'endpoint':'inpaint-v3','request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'rectangles_xyxy':rects,'purpose':'PixelLab-generated extreme pose; no locally drawn motion'};(out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8');print(json.dumps(meta))
