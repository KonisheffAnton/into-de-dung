"""Two controlled provider tests; no moving pose is edited locally."""
import base64, hashlib, json
from pathlib import Path
from PIL import Image
import numpy as np

ROOT=Path(__file__).resolve().parent
EXT=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
source_key='fire24-field29'
request=json.loads((ROOT/'requests'/source_key/'request.json').read_text())
meta=json.loads((ROOT/'requests'/source_key/'request-metadata.json').read_text())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def save(key,payload,metadata):
    out=ROOT/'requests'/key;job=EXT/'pixellab'/key
    assert not out.exists() and not job.exists()
    out.mkdir();job.mkdir()
    (out/'request.json').write_text(json.dumps(payload,indent=2)+'\n',encoding='utf-8')
    (job/'request.json').write_bytes((out/'request.json').read_bytes())
    metadata.update(key=key,request_sha256=sha(job/'request.json'),controlled_comparison_to=source_key)
    (out/'request-metadata.json').write_text(json.dumps(metadata,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'prepared':key,'variable':metadata['control_variable']}))

disabled=json.loads(json.dumps(request));disabled['drift_threshold']=100000
m=json.loads(json.dumps(meta));m['control_variable']='Only drift_threshold changes from0 to100000, so provider color correction should rarely/never trigger. Same visible image, seed, caption and32 requested frames.'
save('fire24-drift01',disabled,m)

image=Image.open(ROOT/meta['input']).convert('RGBA');a=np.array(image);b=a.copy();b[b[:,:,3]==0,:3]=0
assert np.array_equal(a[a[:,:,3]>0],b[a[:,:,3]>0]) and np.array_equal(a[:,:,3],b[:,:,3])
zero_path=ROOT/'inputs/fire24-field29-zero-hidden.png';Image.fromarray(b).save(zero_path)
clean=json.loads(json.dumps(request));blob={'type':'base64','format':'png','base64':base64.b64encode(zero_path.read_bytes()).decode('ascii')};clean['first_frame']=blob;clean['last_frame']=blob
m=json.loads(json.dumps(meta));m['input']=zero_path.relative_to(ROOT).as_posix();m['input_sha256']=sha(zero_path)
m['control_variable']='Only hidden RGB under alpha0 is zeroed on static input. Visible RGB and all alpha bytes exact; drift0, seed, caption and32 frames unchanged.'
m['visible_input_rgba_unchanged']=True
save('fire24-alpha01',clean,m)
