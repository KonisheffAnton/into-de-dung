"""Происхождение новых PNG, отбор и сохранность прежних файлов этапа."""
import ast
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

PACKAGE=Path(__file__).resolve().parent
REPO=PACKAGE.parents[2]
REPORT=REPO/'test_reports/fire29-spikes-20261106'
EXTERNAL=Path('C:/Users/Aston/.codex/generated_images/fire29-readable-20261106')
MUTABLE={
    'scripts/demo/battle_environment_visual.gd','scripts/demo/battle_demo_board.gd',
    'scenes/demo/visuals/hazards/floor_trap.tscn','scenes/demo/visuals/hazards/caltrops_03.tscn',
    'tests/test_hazards_ui.gd','tests/test_acid_tile_animation.gd','tests/test_environment_visual_contract.gd',
}

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    preserved={};changed=[]
    for name,items in read(REPORT/'baseline.json')['groups'].items():
        count=0
        for item in items:
            p=item['path']
            if p in MUTABLE:
                if sha(REPO/p)!=item['sha256']:changed.append(p)
                continue
            assert sha(REPO/p)==item['sha256'],p
            count+=1
        preserved[name]=count
    assert set(changed)==MUTABLE
    assert (REPORT/'previous-handoff.bytes').read_bytes()==(REPO/'docs/CODEX_HANDOFF.history-20261106-4.md').read_bytes()
    jobs=[]
    for path in sorted((PACKAGE/'requests').glob('*/request-metadata.json')):
        meta=read(path);key=meta['key'];job=EXTERNAL/'pixellab'/key
        request=read(path.parent/'request.json')
        assert sha(path.parent/'request.json')==sha(job/'request.json')==meta['request_sha256']
        old_path=REPO/'docs/art/fire-single-tongue-20261106/requests'/meta['controlled_comparison_to']/'request.json'
        before=read(old_path);assert sha(old_path)==meta['old_request_sha256']
        assert [k for k in request if request[k]!=before[k]]==meta['changed_payload_fields']
        assert base64.b64decode(request['first_frame']['base64'])==(PACKAGE/meta['input']).read_bytes()
        assert request['first_frame']==request['last_frame'] and request['frame_count']==16
        result=read(job/'job-latest.json');assert result['status']=='completed'
        assert result['id']==read(job/'admission.json')['background_job_id']
        manifest=read(PACKAGE/'results'/key/'manifest.json')
        assert manifest['response_sha256']==sha(job/'job-latest.json')
        images=result['last_response']['images'];assert len(images)==17
        for i,img in enumerate(images):
            png=PACKAGE/'results'/key/'raw'/f'frame-{i:02}.png'
            assert png.read_bytes()==base64.b64decode(img['base64'])
            assert sha(png)==manifest['frames'][i]['sha256']
        jobs.append({'key':key,'job_id':result['id'],'frames':17,'usage':result['last_response']['billing_usage']})
    assert len(jobs)==3
    selection=read(PACKAGE/'selection.json');assert len(selection['clips'])==26
    old=read(REPO/'docs/art/fire-readable-sway-20261106/preview/manifest.json')
    old_groups={g['group_key']:g for s in old['styles'] for g in s['groups']}
    raw_count=0
    for row in selection['clips']:
        for key in ['source','input','core_mask']:assert sha(REPO/row[key])==row[key+'_sha256']
        inp=np.array(Image.open(REPO/row['input']).convert('RGBA'))
        core=np.array(Image.open(REPO/row['core_mask']).convert('L'))>0
        radius=row['dilation_native_px']
        allowed=np.array(Image.fromarray(((inp[:,:,3]>8)*255).astype('uint8')).filter(ImageFilter.MaxFilter(2*radius+1)))>0
        for frame in row['raw_frames']:
            p=REPO/frame['path'];assert sha(p)==frame['sha256']
            arr=np.array(Image.open(p).convert('RGBA'));shape=arr[:,:,3]>8
            assert not np.any(shape & ~allowed)
            assert np.count_nonzero(core & ~shape)<=row['max_exposed_source_core_px']
            assert not np.any(np.r_[arr[0,:,3],arr[-1,:,3],arr[:,0,3],arr[:,-1,3]])
            raw_count+=1
        order=row['order'];assert order==order[::-1] and 0 not in order
        assert set(order)=={f['index'] for f in row['raw_frames']}
        assert len(order)*old_groups[row['group_key']]['passes_in_common_cycle']<=96
    for p in PACKAGE.rglob('*.py'):ast.parse(p.read_text(encoding='utf-8-sig'))
    result={'pass':True,'preserved':preserved,'preserved_total':sum(preserved.values()),
            'authorized_changed_baseline_files':sorted(changed),'archive_byte_exact':True,
            'new_jobs':jobs,'new_raw':51,'pending_jobs':[],'selected_raw':raw_count,'selected_groups':26,
            'fire24_unchanged':True,'new_fire29_runtime_integrated':False,'spikes_runtime_integrated':True,
            'strict_old_fire_gates_claimed':False}
    (REPORT/'validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({k:result[k] for k in ['pass','preserved_total','new_raw','selected_raw','selected_groups']}))

if __name__=='__main__':main()
