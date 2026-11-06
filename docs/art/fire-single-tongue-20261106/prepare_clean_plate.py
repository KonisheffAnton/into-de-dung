"""Ask PixelLab for static floor beneath the isolated tongue; no local repaint."""
from pathlib import Path
import json,base64,hashlib,argparse
from PIL import Image,ImageDraw
parser=argparse.ArgumentParser();parser.add_argument('--wide',action='store_true');args=parser.parse_args()
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106');key='fire24-cleanplate04' if args.wide else 'fire24-cleanplate03'
job=JOBS/'pixellab'/key;out=ROOT/'requests'/key
if job.exists() or out.exists():raise SystemExit('Immutable request already exists')
def enc(p):return {'image':{'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode()},'size':{'width':128,'height':128}}
source=ROOT/'inputs/fire24-input-128.png';mask=ROOT/'inputs/fire24-motion-guide-mask-128.png'
if args.wide:
    out.mkdir(parents=True);mask=out/'wide-mask.png';m=Image.new('RGB',(128,128));ImageDraw.Draw(m).rectangle((25,45,105,82),fill='white');m.save(mask)
description='Continue the surrounding warm grey-brown stone floor texture seamlessly through the masked central patch. The patch contains only empty bare stone, with the same soft mineral mottling, faint grain and ambient warm illumination as its immediate unmasked edges. No object, symbol, orange stroke or bright shape lies on this patch. Keep the surrounding image unchanged.'
if args.wide:description='A continuous softly painted warm grey-brown stone floor background fills this whole rectangle. Match the flat mottled texture and lighting of the neighboring unmasked ground. This is only floor texture, with no object on it, no outlines, borders, frames, holes, emblems, orange marks, shadows of objects, or bright shapes. Keep the floor smooth and continuous across the entire masked area.'
req={'description':description,'inpainting_image':enc(source),'mask_image':enc(mask),'seed':202611063024,'no_background':False,'crop_to_mask':True}
job.mkdir(parents=True);out.mkdir(parents=True,exist_ok=True);payload=json.dumps(req,indent=2)+'\n'
for p in (job/'request.json',out/'request.json'):p.write_text(payload,encoding='utf-8',newline='\n')
meta={'key':key,'endpoint':'inpaint-v3','source_input_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'mask_sha256':hashlib.sha256(mask.read_bytes()).hexdigest(),'request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'purpose':'Static provider-generated clean floor under the existing animated tongue; no locally painted or moving pose'}
(out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps(meta))
