"""Preserve PixelLab PNG bytes and measure the actual crop animation."""
from pathlib import Path
import json,base64,hashlib,argparse
from PIL import Image,ImageDraw
import numpy as np
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
def main():
 p=argparse.ArgumentParser();p.add_argument('--key',default='fire24-single01');a=p.parse_args();job=JOBS/'pixellab'/a.key;meta=json.loads((ROOT/'requests'/a.key/'request-metadata.json').read_text());outer=json.loads((job/'job-latest.json').read_text(encoding='utf-8-sig'));assert outer['status']=='completed'
 res=outer['last_response'];out=ROOT/'results'/a.key;raw=out/'raw';raw.mkdir(parents=True,exist_ok=True);items=res['images'];records=[];arrays=[];source=np.array(Image.open(ROOT/meta['input']).convert('RGBA'));mask=np.array(Image.open(ROOT/'inputs/fire24-motion-guide-mask-128.png').convert('L'))>0
 contact=Image.new('RGBA',(512,152*((len(items)+3)//4)),(32,36,44,255));draw=ImageDraw.Draw(contact)
 detail=Image.new('RGBA',(512,144*((len(items)+3)//4)),(32,36,44,255));dd=ImageDraw.Draw(detail)
 for i,item in enumerate(items):
  path=raw/f'frame-{i:02d}.png';path.write_bytes(base64.b64decode(item['base64']));im=Image.open(path).convert('RGBA');v=np.array(im);arrays.append(v);assert im.size==tuple(meta['input_size'])
  delta=np.abs(v.astype(int)-source.astype(int));changed=np.any(delta>0,axis=2)
  premul=v[:,:,:3].astype(float)*v[:,:,3,None]/255;source_premul=source[:,:,:3].astype(float)*source[:,:,3,None]/255;visible_delta=np.abs(premul-source_premul);weights=v[:,:,3].astype(float);yy,xx=np.indices(weights.shape);total=weights.sum()
  records.append({'frame':i,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'changed_pixels':int(changed.sum()),'outside_guide_changed':int(changed[~mask].sum()),'mean_rgb_delta':float(delta[:,:,:3].mean()),'outside_guide_mean_rgb_delta':float(delta[~mask,:3].mean()),'mean_premultiplied_rgb_delta':float(visible_delta.mean()),'alpha_bbox':im.getbbox(),'alpha_weighted_centroid':[float((xx*weights).sum()/total),float((yy*weights).sum()/total)] if total else None})
  x=(i%4)*128;y=(i//4)*152;contact.alpha_composite(im,(x,y));draw.text((x+4,y+130),str(i),fill='white')
  y=(i//4)*144;detail.alpha_composite(im.crop((32,32,96,96)).resize((128,128),Image.Resampling.NEAREST),(x,y));dd.text((x+4,y+129),str(i),fill='white')
 contact.save(out/'contact-native.png');detail.save(out/'central-detail-2x.png')
 report={'key':a.key,'returned_frames':len(items),'requested_frames':meta['requested_frames'],'response_sha256':hashlib.sha256((job/'job-latest.json').read_bytes()).hexdigest(),'response_external':str(job/'job-latest.json'),'billing_usage':res.get('billing_usage'),'first_last_rgba_equal':bool(np.array_equal(arrays[0],arrays[-1])),'frames':records,'art_acceptance':False,'raw_pixels_modified':False}
 (out/'manifest.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps({k:v for k,v in report.items() if k!='frames'}))
if __name__=='__main__':main()
