"""Change only requested frame count on the problematic native stroke."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parent;EXT=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
p=argparse.ArgumentParser();p.add_argument('--source-key',default='fire24-field29');p.add_argument('--key',default='fire24-short01');a=p.parse_args()
assert (a.source_key,a.key) in [('fire24-field29','fire24-short01'),('fire24-field10','fire24-short02'),('fire29-field12','fire29-short01')]
base=a.source_key;key=a.key
request=json.loads((ROOT/'requests'/base/'request.json').read_text());meta=json.loads((ROOT/'requests'/base/'request-metadata.json').read_text())
assert request['frame_count']==32;request['frame_count']=16
out=ROOT/'requests'/key;job=EXT/'pixellab'/key
assert not out.exists() and not job.exists();out.mkdir();job.mkdir()
(out/'request.json').write_text(json.dumps(request,indent=2)+'\n',encoding='utf-8');(job/'request.json').write_bytes((out/'request.json').read_bytes())
meta.update(key=key,requested_frames=16,controlled_comparison_to=base,
            control_variable='Only requested frame_count32→16; same input pixels, seed, descriptions, drift0, and alpha.',
            request_sha256=hashlib.sha256((job/'request.json').read_bytes()).hexdigest())
(out/'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'prepared':key,'only_changed':'frame_count','frames':16}))
