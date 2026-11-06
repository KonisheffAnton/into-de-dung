"""Test whether the unchanged painted tile can retain the static surrounding glow."""
from pathlib import Path
import json,hashlib
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;source=Image.open(ROOT.parent/'fire-low-styles-20261104/fire-low-24.png').convert('RGBA');crop=np.array(source.crop((664,436,792,564)));support=np.array(Image.open(ROOT/'inputs/fire24-tongue-reference-128.png'))[:,:,3]>0;guard=np.array(Image.open(ROOT/'inputs/fire24-motion-guide-mask-128.png').convert('L'))>0
core=support&(crop[:,:,0]>235)&(crop[:,:,1]>160)&(crop[:,:,2]<150);out=ROOT/'overlay-proof';out.mkdir(exist_ok=True);rows=[];details=[];tiles=[]
for i in range(17):
 f=ROOT/'results/fire24-cutout02/raw'/f'frame-{i:02d}.png';pose=Image.open(f).convert('RGBA');a=np.array(pose);tile=source.copy();tile.alpha_composite(pose,(664,436));render=np.array(tile.crop((664,436,792,564)));changed=np.any(render!=crop,axis=2)
 if i in (0,3,8):tile.save(out/f'frame-{i:02d}-full.png');details.append(tile.crop((664,436,792,564)).resize((384,384),Image.Resampling.NEAREST));tiles.append(tile.resize((256,256),Image.Resampling.LANCZOS))
 tile.resize((256,256),Image.Resampling.LANCZOS).save(out/f'frame-{i:02d}-view256.png')
 hot=guard&(render[:,:,0]>235)&(render[:,:,1]>160)&(render[:,:,2]<150);yy,xx=np.where(hot)
 rows.append({'frame':i,'raw_png_sha256':hashlib.sha256(f.read_bytes()).hexdigest(),'uncovered_original_hot_core_pixels':int((core&(a[:,:,3]==0)).sum()),'changed_outside_guide':int(changed[~guard].sum()),'rendered_hot_core_pixels':int(hot.sum()),'rendered_hot_core_centroid':[float(xx.mean()),float(yy.mean())]})
sheet=Image.new('RGBA',(1536,410),(30,34,43,255));d=ImageDraw.Draw(sheet);sheet.alpha_composite(Image.fromarray(crop).resize((384,384),Image.Resampling.NEAREST),(0,0));d.text((8,386),'source',fill='white')
for j,(im,label) in enumerate(zip(details,['provider0','provider3','provider8']),1):sheet.alpha_composite(im,(384*j,0));d.text((384*j+8,386),label,fill='white')
sheet.save(out/'detail-comparison.png');sheet=Image.new('RGBA',(1024,280),(30,34,43,255));d=ImageDraw.Draw(sheet);sheet.alpha_composite(source.resize((256,256),Image.Resampling.LANCZOS),(0,0));d.text((8,258),'source',fill='white')
for j,(im,label) in enumerate(zip(tiles,['provider0','provider3','provider8']),1):sheet.alpha_composite(im,(256*j,0));d.text((256*j+8,258),label,fill='white')
sheet.save(out/'full-comparison.png');report={'mode':'Unchanged full source tile as static base/glow; unchanged provider RGBA source-over at constant native placement (664,436). No clean-plate pixels, no manual motion or color edit.','source_hot_core_pixels':int(core.sum()),'frames':rows,'art_acceptance':False};(out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps({'hot_core':int(core.sum()),'max_uncovered_core':max(r['uncovered_original_hot_core_pixels'] for r in rows),'max_changed_outside':max(r['changed_outside_guide'] for r in rows)}))
