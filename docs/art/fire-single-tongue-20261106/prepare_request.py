"""Prepare one native-crop PixelLab pilot without drawing any motion poses."""
from pathlib import Path
import argparse,base64,hashlib,json
from PIL import Image
ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
def main():
    p=argparse.ArgumentParser();p.add_argument('--source',type=int,choices=(24,29),required=True);p.add_argument('--input',required=True);p.add_argument('--cutout',action='store_true');a=p.parse_args()
    input_path=(ROOT/a.input).resolve();assert input_path.is_relative_to(ROOT/'inputs') and input_path.suffix=='.png'
    with Image.open(input_path) as im:
        assert im.format=='PNG' and im.size in ((128,128),(256,256));size=list(im.size);alpha_range=im.convert('RGBA').getchannel('A').getextrema();assert alpha_range[1]>=250 and (alpha_range[0]==0 if a.cutout else alpha_range[0]>=250)
    key=f'fire{a.source}-'+('cutout02' if a.cutout else 'single01');job=JOBS/'pixellab'/key;out=ROOT/'requests'/key
    if job.exists() or out.exists():raise SystemExit('Immutable pilot already prepared')
    blob={'type':'base64','format':'png','base64':base64.b64encode(input_path.read_bytes()).decode('ascii')}
    description='Only the small orange flame at the CENTER gently flexes sideways and returns. Its base stays in exactly the same position; only its existing curled tip shifts a few pixels. One quiet continuous cycle of steady burning. Keep its original low height and constant light. All surrounding stone and other painted orange strokes remain perfectly still. No upward growth, extra flames, sparks, flashes or camera motion.'
    request={'first_frame':blob,'last_frame':blob,'description':description,'frame_count':16,'seed':202611061000+a.source,'no_background':False,'drift_threshold':0,'enhance_prompt':False,'direction':'east','view':'high top-down','subject_description':'A close-up of one existing low painted orange flame tongue on a grey stone surface','initial_pose':'A short curled flame tip lying close to the stone, with a fixed broad base'}
    if a.cutout:
        request.update(description='The right curled end of this single painted shape softly bends a few pixels left, then right, then returns. Its left base stays pinned in exactly the same position. The whole shape keeps its original flattened height and horizontal footprint. One smooth restrained sway. Maintain constant color, light and opacity. Nothing grows, appears, breaks away or disappears. Fixed camera and transparent background.',no_background=True,seed=202611062000+a.source,subject_description='One small flattened orange and yellow curved brushstroke on transparency',initial_pose='A low horizontal curved silhouette with its broad left base anchored and a slightly raised right tip')
    job.mkdir(parents=True);out.mkdir(parents=True);payload=json.dumps(request,indent=2)+'\n';(job/'request.json').write_text(payload,encoding='utf-8',newline='\n');(out/'request.json').write_text(payload,encoding='utf-8',newline='\n')
    meta={'key':key,'endpoint':'animate-pixminimax','input':input_path.relative_to(ROOT).as_posix(),'input_sha256':hashlib.sha256(input_path.read_bytes()).hexdigest(),'input_size':size,'source_alpha_range':alpha_range,'request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),'requested_frames':16,'native_crop_no_resize':True,'local_motion_generation':False,'hypothesis':('Isolated existing shape with contour-only action, without combustion semantics' if a.cutout else 'A whole single tongue at native source scale is a recognizable object instead of tiny tiled texture')}
    (out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps(meta))
if __name__=='__main__':main()
