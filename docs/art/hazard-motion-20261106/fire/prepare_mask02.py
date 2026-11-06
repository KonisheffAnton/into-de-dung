"""A bounded pilot without init-image copying; only existing flame strokes may move."""
from pathlib import Path
import json,base64,hashlib,argparse
import numpy as np
from PIL import Image,ImageFilter
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')
def enc(p):return {'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode()}
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=int,choices=(24,29),required=True);a=p.parse_args();key=f'fire{a.source}-mask02';out=ROOT/f'fire{a.source}'/'mask02';job=JOBS/'pixellab'/key
    if job.exists():raise SystemExit('Immutable request exists')
    out.mkdir(parents=True,exist_ok=True);im=Image.open(ROOT/f'fire{a.source}'/'long01'/'roi.png').convert('RGBA');im.save(out/'roi.png');v=np.array(im).astype(int);r,g,b=v[:,:,0],v[:,:,1],v[:,:,2]
    m=(r-b>95)&(r-g>22)&(v[:,:,3]>200);m=np.array(Image.fromarray((m*255).astype('uint8')).filter(ImageFilter.MaxFilter(3)))>0
    bounds=np.zeros((64,64),bool);bounds[3:61,3:61]=True;m&=bounds
    Image.fromarray((m*255).astype('uint8')).convert('RGB').save(out/'mask.png');ref=np.array(im);ref[:,:,3]=np.where((r-b>70)&(r-g>15),ref[:,:,3],0);Image.fromarray(ref).save(out/'reference.png')
    preview=np.array(im);preview[m]=(255,50,210,255);Image.fromarray(preview).resize((512,512),Image.Resampling.NEAREST).save(out/'mask-preview.png')
    req={'image_size':{'width':64,'height':64},'description':'Short low orange flame tongues burning across a floor, seen from a high angle.','action':'A quiet steady fire. The existing flame tips slowly sway sideways in place while their roots remain fixed. The tips bend by only one or two pixels and return. No increase in height. Keep the same little flames, steady brightness, dark floor fixed.','negative_description':'new flames, rising jets, explosions, flashes, sparks, moving stone, camera motion, rings, ribbons, changing brightness','reference_image':enc(out/'reference.png'),'inpainting_images':[enc(out/'roi.png')]*4,'mask_images':[enc(out/'mask.png')]*4,'n_frames':4,'start_frame_index':0,'view':'high top-down','direction':'south-east','image_guidance_scale':1.3,'text_guidance_scale':8,'seed':202611067000+a.source}
    job.mkdir(parents=True);(job/'request.json').write_text(json.dumps(req,indent=2)+'\n',encoding='utf-8')
    meta={'key':key,'request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'mask_pixels':int(m.sum()),'init_images_used':False,'reason':'Earlier init-image and chunk trial copied texture; this pilot allows full generation inside existing stroke masks','image_guidance_scale':1.3,'text_guidance_scale':8}
    (out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8');print(json.dumps(meta))
if __name__=='__main__':main()
