"""Read-only PNG/source and motion measurements; never write image pixels."""
from pathlib import Path
import base64
import hashlib
import json
from PIL import Image

root=Path(__file__).resolve().parent
repo=root.parents[2]
regions={'far_boot':(35,75,57,90),'near_boot':(79,94,97,108),
         'bow_and_hand':(87,42,113,90),'head':(59,34,86,62),
         'chest':(54,52,84,72)}
ref=Image.open(root/'pixellab/reference-128.png').convert('RGBA')
job=json.loads((repo/'test_reports/archer-perspective-20261014/job-response.json').read_text(encoding='utf-8-sig'))
assert job['status']=='completed'
files=sorted((root/'pixellab').glob('frame-*.png'))
assert len(files)==len(job['last_response']['images'])

def compare(a,b):
    ap=list(a.getdata());bp=list(b.getdata())
    return {'visible_rgba_changed':sum(x!=y and (x[3]!=0 or y[3]!=0) for x,y in zip(ap,bp)),
            'alpha128_changed':sum((x[3]>=128)!=(y[3]>=128) for x,y in zip(ap,bp))}

records=[]
frames=[]
for file,encoded in zip(files,job['last_response']['images']):
    response_bytes=base64.b64decode(encoded['base64'].split(',')[-1])
    assert file.read_bytes()==response_bytes
    with Image.open(file) as source:
        assert source.mode=='RGBA' and source.size==(128,128)
        img=source.copy()
    alpha=img.getchannel('A');bbox=alpha.point(lambda v:255 if v>=128 else 0).getbbox()
    assert alpha.getextrema()==(0,255) and bbox and bbox[0]>0 and bbox[1]>0 and bbox[2]<128 and bbox[3]<128
    frames.append(img)
    records.append({'file':file.name,'sha256':hashlib.sha256(response_bytes).hexdigest(),'size':list(img.size),
        'bbox_alpha128':bbox,'partial_alpha_pixels':sum(0<a<255 for a in alpha.getdata()),
        'vs_reference':compare(ref,img),
        'regions_vs_reference':{name:compare(ref.crop(box),img.crop(box)) for name,box in regions.items()}})
result={'status':'PASS','provider_png_bytes_verified':len(records),'regions_xyxy':regions,'frames':records,
    'loop_seam':compare(frames[-1],frames[0]),
    'regions_loop_seam':{name:compare(frames[-1].crop(box),frames[0].crop(box)) for name,box in regions.items()},
    'playback_loop_13_to_02':compare(frames[-1],frames[1]),
    'basis':'Fixed approximate ROIs chosen on the reference before outputs. Counts indicate changed pixels, not displacement or exact segmentation. Technical PASS is not motion/art acceptance.'}
(root/'motion-measurements.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'status':'PASS','frames':len(records),'bboxes':[r['bbox_alpha128'] for r in records],
    'max_region_alpha_changes':{name:max(r['regions_vs_reference'][name]['alpha128_changed'] for r in records) for name in regions},
    'loop_seam':result['loop_seam']},ensure_ascii=False))
