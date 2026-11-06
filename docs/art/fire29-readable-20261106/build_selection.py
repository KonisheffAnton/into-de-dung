"""Усиливает четыре низких мазка29 из неизменённых поз PixelLab."""
from pathlib import Path
import copy
import hashlib
import json

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[2]
PREVIOUS=ROOT.parent/'fire-readable-sway-20261106'
RAW_OLD=ROOT.parent/'fire-single-tongue-20261106'

def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    prior=read(PREVIOUS/'selection.json')
    clips=copy.deepcopy([c for c in prior['clips'] if c['group_key'].startswith('fire29-')])
    replacements=[
        ('fire29-field14','fire29-visible02',[1,2,3,14],6,26,ROOT),
        ('fire29-field13','fire29-field13',[1,4,5,6,7],6,17,RAW_OLD),
        ('fire29-field25','fire29-field25',[1,4,5,6,7,8,9],4,1,RAW_OLD),
        ('fire29-field22','fire29-field22',[7,9,11,17,18],4,0,RAW_OLD),
    ]
    for old_key,key,forward,dilation,core_bound,raw_root in replacements:
        row=next(c for c in clips if c['key']==old_key)
        row.update({'key':key,'previous_key':old_key,'order':forward+forward[-2::-1],
                    'dilation_native_px':dilation,'max_exposed_source_core_px':core_bound})
        manifest=read(raw_root/'results'/key/'manifest.json')
        row['raw_frames']=[]
        for index in forward:
            p=raw_root/'results'/key/'raw'/f'frame-{index:02}.png'
            assert sha(p)==manifest['frames'][index]['sha256']
            row['raw_frames'].append({'index':index,'path':p.relative_to(REPO).as_posix(),'sha256':sha(p)})
        row['metrics']={'individual_visual_review':'GO for fixed composite pilot; user acceptance pending',
                        'old_strict_gates_not_claimed':True,'selected_forward':forward,
                        'core_exposure_bound_px':core_bound,'contour_bound_px':dilation}
        row['timeline_report']='test_reports/fire29-spikes-20261106/fire29/selection-review.json'
    assert len(clips)==26 and len({c['group_key'] for c in clips})==26
    result={'schema':'fire-field-selection-v1','path_base':'repository_root',
            'previous_selection_sha256':sha(PREVIOUS/'selection.json'),
            'changed_clips':[x[1] for x in replacements],'clips':clips,'art_accepted':False}
    (ROOT/'selection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'groups':26,'changed':result['changed_clips']}))

if __name__=='__main__':main()
