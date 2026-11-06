"""Render unchanged provider RGBA poses over a provider-cleaned static plate."""
from pathlib import Path
import json,base64,hashlib,argparse
import numpy as np
from PIL import Image,ImageDraw
parser=argparse.ArgumentParser();parser.add_argument('--plate',choices=('03','04'),default='03');parser.add_argument('--body-only',action='store_true');args=parser.parse_args()
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106');key='fire24-cleanplate'+args.plate
job=JOBS/'pixellab'/key;out=ROOT/'results'/key;out.mkdir(parents=True,exist_ok=True)
outer=json.loads((job/'job-latest.json').read_text(encoding='utf-8-sig'));assert outer['status']=='completed';res=outer['last_response'];raw=out/'raw.png';raw.write_bytes(base64.b64decode(res['image']['base64']));im=Image.open(raw).convert('RGBA');assert im.size==(128,128)
crop=np.array(Image.open(ROOT/'inputs/fire24-input-128.png').convert('RGBA'));generated=np.array(im);guard=np.array(Image.open(ROOT/'inputs/fire24-motion-guide-mask-128.png').convert('L'))>0;mask=(np.array(Image.open(ROOT/'inputs/fire24-tongue-reference-128.png'))[:,:,3]>0) if args.body_only else guard
proof=ROOT/(f'layer-proof-body{args.plate}' if args.body_only else 'layer-proof');proof.mkdir(exist_ok=True);rows=[];tiles=[];details=[]
clean=crop.copy();clean[mask]=generated[mask];Image.fromarray(clean).save(proof/'plate-crop.png')
source=Image.open(ROOT.parent/'fire-low-styles-20261104/fire-low-24.png').convert('RGBA');plate=source.copy();plate.paste(Image.fromarray(clean),(664,436));plate.save(proof/'plate-full.png')
for i in range(17):
    f=ROOT/'results/fire24-cutout02/raw'/f'frame-{i:02d}.png';pose=Image.open(f).convert('RGBA');tile=plate.copy();tile.alpha_composite(pose,(664,436))
    if not args.body_only or i in (0,3,8):tile.save(proof/f'frame-{i:02d}-full.png')
    tile.resize((256,256),Image.Resampling.LANCZOS).save(proof/f'frame-{i:02d}-view256.png')
    region=np.array(tile)[436:564,664:792];changed=np.any(region!=clean,axis=2);visible=np.array(pose)[:,:,3]>0
    rows.append({'frame':i,'provider_png_sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'alpha_support_outside_guide':int(visible[~guard].sum()),'render_changes_outside_guide':int(changed[~guard].sum())})
    if i in (0,3,8):tiles.append(tile.resize((256,256),Image.Resampling.LANCZOS));details.append(tile.crop((664,436,792,564)).resize((384,384),Image.Resampling.NEAREST))
sheet=Image.new('RGBA',(1024,280),(30,34,43,255));draw=ImageDraw.Draw(sheet);sheet.alpha_composite(source.resize((256,256),Image.Resampling.LANCZOS),(0,0));draw.text((8,258),'source',fill='white')
for i,(tile,label) in enumerate(zip(tiles,['provider0','provider3','provider8']),1):sheet.alpha_composite(tile,(i*256,0));draw.text((i*256+8,258),label,fill='white')
sheet.save(proof/'full-comparison.png');sheet=Image.new('RGBA',(384*4,410),(30,34,43,255));draw=ImageDraw.Draw(sheet);sheet.alpha_composite(Image.fromarray(crop).resize((384,384),Image.Resampling.NEAREST),(0,0));draw.text((8,386),'source',fill='white')
for i,(tile,label) in enumerate(zip(details,['provider0','provider3','provider8']),1):sheet.alpha_composite(tile,(i*384,0));draw.text((i*384+8,386),label,fill='white')
sheet.save(proof/'detail-comparison.png')
meta={'clean_plate_key':key,'clean_raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),'clean_response_sha256':hashlib.sha256((job/'job-latest.json').read_bytes()).hexdigest(),'billing_usage':res['billing_usage'],'static_mask_pixels':int(mask.sum()),'static_plate_sha256':hashlib.sha256((proof/'plate-full.png').read_bytes()).hexdigest(),'plate_variant':'original support' if args.body_only else 'whole guide region','crop_placement_xy':[664,436],'source_size':list(source.size),'render_operation':'Standard RGBA source-over of unchanged PixelLab pose at a constant position; no warping, tweening or frame recolor','local_motion_generation':False,'frames':rows,'art_acceptance':False}
(proof/'manifest.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps({k:v for k,v in meta.items() if k!='frames'}))
