"""Help PixelLab identify flame shapes; prepare one immutable four-frame window."""
from pathlib import Path
import argparse,base64,hashlib,json,shutil
import numpy as np
from PIL import Image,ImageFilter

ROOT=Path(__file__).resolve().parent
ART=ROOT.parents[1]
JOBS=Path('C:/Users/Aston/.codex/generated_images/hazard-motion-20261106')

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def enc(p): return {'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode('ascii')}
def write(p,v): p.write_text(json.dumps(v,ensure_ascii=False,indent=2)+'\n',encoding='utf-8',newline='\n')

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--source',type=int,choices=(24,29),required=True);parser.add_argument('--start',type=int,choices=(0,4,8,12),required=True);args=parser.parse_args()
    key=f'fire{args.source}-long01-c{args.start:02d}'
    folder=JOBS/'pixellab'/key
    if folder.exists(): raise SystemExit('Existing request directory; no overwrite')
    model=ROOT/f'fire{args.source}'/'long01';model.mkdir(parents=True,exist_ok=True)
    source=ART/'fire-low-styles-20261104'/f'fire-low-{args.source}.png'
    working=ART/'fire-painted-sway-20261105'/'model'/f'fire{args.source}'/'input-256.png'
    box=(96,67,160,131)
    if not (model/'roi.png').exists():
        shutil.copyfile(source,model/'source-original.png');shutil.copyfile(working,model/'input-256.png')
        roi=Image.open(working).convert('RGBA').crop(box);roi.save(model/'roi.png')
        a=np.asarray(roi).astype(float);r,g,b,alpha=[a[:,:,i] for i in range(4)]
        warm=(r>115)&(r-b>55)&(r>g*1.01)&(alpha>200)
        # Input preparation only: remove cool stone from the semantic reference.
        ref=a.copy();ref[:,:,3]=np.rint(alpha*np.clip((r-b-25)/60,0,1));Image.fromarray(ref.astype('uint8')).save(model/'flame-reference.png')
        m=np.asarray(Image.fromarray(warm.astype('uint8')*255).filter(ImageFilter.MaxFilter(3)))>0
        expanded=m.copy();expanded[:,1:]|=m[:,:-1];expanded[:,:-1]|=m[:,1:]
        bounds=np.zeros((64,64),bool);bounds[4:60,4:60]=True;expanded&=bounds&(alpha>200)
        Image.fromarray(expanded.astype('uint8')*255).convert('RGB').save(model/'mask-motion.png')
        Image.new('RGB',(64,64),'black').save(model/'mask-locked.png')
        preview=a.astype('uint8').copy();preview[expanded]=(255,50,210,255);Image.fromarray(preview).resize((512,512),Image.Resampling.NEAREST).save(model/'mask-preview-8x.png')
        Image.open(model/'flame-reference.png').resize((512,512),Image.Resampling.NEAREST).save(model/'reference-preview-8x.png')
        write(model/'preparation.json',{'source_sha256':sha(source),'working_sha256':sha(working),'roi_xyxy':list(box),'scale':1,'reference':'OriginalRGB with chroma-derived alpha to identify warm flames; not a motion pose','mask_pixels':int(expanded.sum()),'mask':'Whole warm tongues plus2horizontal/1verticalpixels, boundedinsideROI and opaque top','motion_frames_generated_locally':False})
    roi=model/'roi.png'
    if args.start:
        prev=ROOT/f'fire{args.source}'/'long01'/'raw'/f'frame-{args.start-1:02d}.png'
        if not prev.exists(): raise SystemExit('Prior generated frame required before next window')
        init=prev
    else: init=roi
    masks=[model/('mask-locked.png' if args.start+i in (0,15) else 'mask-motion.png') for i in range(4)]
    phase={0:'Begin still, then lean the existing tips slightly left.',4:'Ease the gently left-leaning tips back toward their original positions.',8:'Lean the same existing tips slightly right.',12:'Ease the right-leaning tips back to the exact original still pose.'}[args.start]
    action=f'One calm16-frame left-right sway of the ALREADY PAINTED low flame tongues. This window is frames{args.start} through{args.start+3}. {phase} Bend only the upper parts sideways about2pixels, with fixed roots. Keep original height, shape count, orange palette and steady brightness. Smooth continuous motion, no flares or new tongues.'
    request={'image_size':{'width':64,'height':64},'description':'Existing orange painted flame tongues on a fixed isometric stone surface; transparent reference isolates only these tongues.',
             'action':action,'negative_description':'new flames, jets, sparks, growth, explosions, flashes, global brightness pulse, moving stone, camera movement',
             'reference_image':enc(model/'flame-reference.png'),'inpainting_images':[enc(roi)]*4,'mask_images':[enc(p) for p in masks],
             'init_images':[enc(init)]*4,'init_image_strength':300,'n_frames':16,'start_frame_index':args.start,'view':'high top-down','direction':'south-east',
             'image_guidance_scale':2.5,'text_guidance_scale':7,'seed':2026110600+args.source}
    folder.mkdir(parents=True);write(folder/'request.json',request)
    manifest=ROOT/'requests.json';rows=json.loads(manifest.read_text(encoding='utf-8')) if manifest.exists() else []
    rows.append({'key':key,'endpoint':'animate-with-text','source':args.source,'start_frame_index':args.start,'n_frames':16,'expected_chunk_frames':4,'roi_xyxy':list(box),
                 'reference_sha256':sha(model/'flame-reference.png'),'mask_sha256':[sha(p) for p in masks],'init_sha256':sha(init),'request_sha256':sha(folder/'request.json'),
                 'image_guidance_scale':2.5,'text_guidance_scale':7,'action':action,'provenance':'Only input segmentation/masks prepared locally; output poses remain PixelLab raw frames'})
    write(manifest,rows);print(json.dumps({'key':key,'mask_pixels':json.loads((model/'preparation.json').read_text())['mask_pixels'],'request_sha256':rows[-1]['request_sha256']}))

if __name__=='__main__':main()
