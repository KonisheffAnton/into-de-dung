"""Provenance, prior-art preservation and native selected-pose constraints."""
import argparse
import ast
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[2]
REPORT = REPO/'test_reports/fire-readable-sway-20261106'
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire-readable-sway-20261106')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--partial',action='store_true');args=parser.parse_args()
    preserved={}
    for name,entries in read(REPORT/'baseline.json')['groups'].items():
        for item in entries: assert sha(REPO/item['path'])==item['sha256'],item['path']
        preserved[name]=len(entries)
    assert (REPORT/'previous-handoff.bytes').read_bytes()==(REPO/'docs/CODEX_HANDOFF.history-20261106-3.md').read_bytes()
    jobs=[];pending=[]
    for meta_path in sorted((PACKAGE/'requests').glob('*/request-metadata.json')):
        meta=read(meta_path);key=meta['key'];job=EXTERNAL/'pixellab'/key
        request=meta_path.parent/'request.json'
        assert sha(request)==meta['request_sha256']==sha(job/'request.json')
        payload=read(request);old=REPO/'docs/art/fire-single-tongue-20261106/requests'/meta['controlled_comparison_to']/'request.json'
        assert sha(old)==meta['old_request_sha256']
        before=read(old);assert [k for k in payload if payload[k]!=before[k]]==['description']
        assert base64.b64decode(payload['first_frame']['base64'])==(PACKAGE/meta['input']).read_bytes()
        assert payload['first_frame']==payload['last_frame'] and payload['frame_count']==16
        last=job/'job-latest.json'
        if not last.exists() or read(last)['status']!='completed': pending.append(key);continue
        response=read(last);assert response['id']==read(job/'admission.json')['background_job_id']
        manifest=read(PACKAGE/'results'/key/'manifest.json');assert manifest['response_sha256']==sha(last)
        images=response['last_response']['images'];assert len(images)==manifest['returned_frames']==17
        for i,(image,row) in enumerate(zip(images,manifest['frames'])):
            png=PACKAGE/'results'/key/'raw'/f'frame-{i:02}.png'
            assert png.read_bytes()==base64.b64decode(image['base64']) and sha(png)==row['sha256']
        jobs.append({'key':key,'raw_count':17,'provider_usage':response['last_response']['billing_usage']})
    assert args.partial or not pending,pending
    selected=[]
    if (PACKAGE/'selection.json').exists():
        selection=read(PACKAGE/'selection.json')
        old=read(REPO/'docs/art/fire-single-tongue-20261106/field-preview/manifest.json')
        old_groups={g['group_key']:g for s in old['styles'] for g in s['groups']}
        assert len(selection['clips'])==len({r['group_key'] for r in selection['clips']})==56
        for row in selection['clips']:
            for key in ('source','input','core_mask'): assert sha(REPO/row[key])==row[key+'_sha256']
            inp=np.array(Image.open(REPO/row['input']).convert('RGBA'));core=np.array(Image.open(REPO/row['core_mask']).convert('L'))>0
            allowed=np.array(Image.fromarray(((inp[:,:,3]>8)*255).astype('uint8')).filter(ImageFilter.MaxFilter(2*row['dilation_native_px']+1)))>0
            exposed=[]
            for frame in row['raw_frames']:
                path=REPO/frame['path'];assert sha(path)==frame['sha256']
                arr=np.array(Image.open(path).convert('RGBA'));mask=arr[:,:,3]>8
                assert not np.any(mask & ~allowed)
                assert not np.any(np.r_[arr[0,:,3],arr[-1,:,3],arr[:,0,3],arr[:,-1,3]])
                exposed.append(int(np.count_nonzero(core & ~mask)))
            assert max(exposed)<=row['max_exposed_source_core_px']
            assert row['order'][0]==row['order'][-1] and 0 not in row['order']
            assert set(row['order'])=={f['index'] for f in row['raw_frames']}
            assert len(row['order'])*old_groups[row['group_key']]['passes_in_common_cycle']<=96
            selected.append({'key':row['key'],'poses':len(row['raw_frames']),'max_exposed_source_core_px':max(exposed),'native_envelope_bound':row['dilation_native_px']})
    parsed=[]
    for path in PACKAGE.rglob('*.py'):
        ast.parse(path.read_text(encoding='utf-8-sig'));parsed.append(path.relative_to(PACKAGE).as_posix())
    result={'pass':True,'partial':args.partial,'preserved':preserved,'preserved_total':sum(preserved.values()),'archive_byte_exact':True,
            'new_jobs':jobs,'new_raw_count':sum(j['raw_count'] for j in jobs),'pending_jobs':pending,'selected':selected,'python_parsed':parsed,
            'runtime_integrated':False,'godot_run':False,'old_core_zero_gate_claimed_for_new_pilots':False}
    (REPORT/'validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'pass':True,'preserved':result['preserved_total'],'new_raw':result['new_raw_count'],'pending':pending,'selected':len(selected)}))

if __name__=='__main__':main()
