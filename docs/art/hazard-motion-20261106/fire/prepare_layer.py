"""Create static semantic input separating existing warm strokes from cool stone."""
from pathlib import Path
import json,hashlib,base64,argparse
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent;JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=int,choices=(24,29),required=True);p.add_argument('--attempt',default='layer02');p.add_argument('--frames',type=int,default=8);a=p.parse_args();key=f'fire{a.source}-{a.attempt}'
    out=ROOT/f'fire{a.source}'/a.attempt;out.mkdir(parents=True,exist_ok=True);job=JOBS/'pixellab'/key
    if job.exists():raise SystemExit('Immutable request already exists')
    source=ROOT.parents[1]/'fire-painted-sway-20261105'/'model'/f'fire{a.source}'/'input-256.png';im=Image.open(source).convert('RGBA');arr=np.array(im);f=arr.astype(float);r,g,b=[f[:,:,i] for i in range(3)]
    top=Image.new('L',(256,256));ImageDraw.Draw(top).polygon([(128,49),(195,101),(128,148),(60,102)],fill=255)
    # Only static input alpha is segmented; RGB stays byte-for-byte the source RGB.
    alpha=np.minimum(np.clip((r-b-45)/35,0,1),np.clip((r-g-10)/25,0,1))*np.array(top)/255*f[:,:,3]
    arr[:,:,3]=np.rint(alpha).astype('uint8');layer=Image.fromarray(arr);layer.save(out/'flames-input.png');top.save(out/'top-region.png')
    check=Image.new('RGBA',(256,256),(30,34,43,255));check.alpha_composite(layer);check.resize((768,768),Image.Resampling.NEAREST).save(out/'input-preview-3x.png')
    im.save(out/'source-256.png');blob={'type':'base64','format':'png','base64':base64.b64encode((out/'flames-input.png').read_bytes()).decode('ascii')}
    action='The existing small orange and yellow painted strokes gently bend sideways like soft ribbons pinned at their bases. Move their already curled tips left by two pixels, then right by two pixels, then return to this exact arrangement. One calm continuous loop. Keep the same short horizontal strokes, same count, same roots, same total area and constant color and brightness. Absolutely no upward growth, new shapes, jets, sparks, flashes, or camera movement. Preserve the empty transparent spaces between the strokes. Only the tips softly sway; the overall diamond arrangement stays fixed.'
    request={'first_frame':blob,'last_frame':blob,'action':action,'frame_count':a.frames,'seed':202611062400+a.source,'no_background':True,'drift_threshold':0,'enhance_prompt':False}
    job.mkdir(parents=True);(job/'request.json').write_text(json.dumps(request,indent=2)+'\n',encoding='utf-8')
    meta={'key':key,'endpoint':'animate-with-text-v3','request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'input_sha256':hashlib.sha256((out/'flames-input.png').read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'frame_count':a.frames,'static_input_preparation':'Source RGB unchanged; alpha selects warm painted strokes only; no generated motion poses locally','action':action}
    (out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8');print(json.dumps(meta))
if __name__=='__main__':main()
