"""Verify raw PixelLab provenance, exact ROI assemblies and all temporal joins."""
from pathlib import Path
import base64,hashlib,json,io
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def pixels(p):return np.array(Image.open(p).convert('RGBA'))
def main():
    rows=read(ROOT/'requests.json');result=[];usage=0
    for source in (24,29):
        model=ROOT/f'fire{source}'/'long01';base=pixels(model/'input-256.png');roi=pixels(model/'roi.png');mask=pixels(model/'mask-motion.png')[:,:,0]>0
        assert np.array_equal(base[67:131,96:160],roi)
        assert np.array_equal(np.array(Image.open(model/'source-original.png').resize((256,256),Image.Resampling.LANCZOS)),base)
        frames=[]
        starts=sorted(r['start_frame_index'] for r in rows if r['source']==source)
        for start in starts:
            key=f'fire{source}-long01-c{start:02d}';job=ROOT/'pixellab'/key
            row=next(r for r in rows if r['key']==key);req=read(job/'request.json');res=read(job/'response-raw.json')
            assert sha(job/'request.json')==row['request_sha256'];assert req['n_frames']==16 and req['start_frame_index']==start
            assert len(res['images'])==4;usage+=res['usage']['generations']
            for i in range(4):
                idx=start+i;raw=model/'raw'/f'frame-{idx:02d}.png';assembly=model/'assembled'/raw.name
                assert raw.read_bytes()==base64.b64decode(res['images'][i]['base64'])
                assert base64.b64decode(req['inpainting_images'][i]['base64'])==(model/'roi.png').read_bytes()
                which='mask-locked.png' if idx in (0,15) else 'mask-motion.png'
                assert base64.b64decode(req['mask_images'][i]['base64'])==(model/which).read_bytes()
                assert base64.b64decode(req['reference_image']['base64'])==(model/'flame-reference.png').read_bytes()
                init=model/'roi.png' if start==0 else model/'raw'/f'frame-{start-1:02d}.png'
                assert base64.b64decode(req['init_images'][i]['base64'])==init.read_bytes()
                a=pixels(raw);assert a.shape==(64,64,4)
                expected=base.copy();expected[67:131,96:160]=a;assert np.array_equal(pixels(assembly),expected)
                frames.append(a)
        closed=np.array_equal(frames[0],frames[-1])
        if len(frames)==16:assert closed
        assert all(np.array_equal(f[~mask],frames[0][~mask]) for f in frames)
        normalization=np.any(frames[0]!=roi,axis=2);assert np.all(roi[normalization,3]<=1)
        transitions=[]
        count=len(frames)
        for i in range(count if closed else count-1):
            d=np.abs(frames[(i+1)%count].astype(int)-frames[i].astype(int))
            transitions.append({'from':i,'to':(i+1)%count,'mean_rgb_delta':round(float(d[:,:,:3].mean()),4),'max_rgba_delta':int(d.max()),'pixels_gt20':int((d.max(2)>20).sum()),'chunk_join':i in (3,7,11)})
        result.append({'source':source,'raw_api_byte_matches':count,'exact_roi_assemblies':count,'same_first_last':closed,'complete_16_frame_cycle':count==16,'temporal_outside_mask_changes':0,'constant_source_normalized_alpha01_pixels':int(normalization.sum()),'transitions':transitions})
    out={'technical_provenance_pass':True,'usage_generations':usage,'art_acceptance':False,'art_status':'Rejected internally: texture changes and chunk jumps instead of coherent flame sway; fire29 stopped after 12 frames','clips':result}
    (ROOT/'validation.json').write_text(json.dumps(out,indent=2)+'\n',encoding='utf-8');print(json.dumps(out))
if __name__=='__main__':main()
