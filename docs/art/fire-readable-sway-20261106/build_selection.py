"""Keep 48 old loops; widen five old ranges and insert three reviewed provider pilots."""
from pathlib import Path
import copy
import hashlib
import json

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
OLD = ROOT.parent / 'fire-single-tongue-20261106'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    previous = read(OLD/'field-selection/selection.json')
    report = read(REPO/'test_reports/fire-readable-sway-20261106/selection-analysis.json')
    proposals = {r['key']: r['proposal'] for r in report['clips'] if 'proposal' in r}
    clips = copy.deepcopy(previous['clips'])
    changed = []
    for row in clips:
        row['dilation_native_px'] = 4
        row['max_exposed_source_core_px'] = 0
        if row['key'] not in proposals:
            continue
        p = proposals[row['key']]
        row['order'] = p['order']
        row['raw_frames'] = [{'index': int(i), **entry} for i,entry in p['raw_paths_sha256'].items()]
        row['dilation_native_px'] = 6
        row['metrics'] = p
        row['timeline_report'] = 'test_reports/fire-readable-sway-20261106/selection-analysis.json'
        changed.append(row['key'])
    for old_key, new_key, forward, dilation, exposed, report_name in [
            ('fire24-short01','fire24-strong01',[8,1,2],6,13,'controls-analysis.json'),
            ('fire29-field02r1','fire29-strong01',[1,3,4,5],12,27,'controls-analysis.json'),
            ('fire24-short02','fire24-strong02',[1,2,3],4,1,'extra24-analysis.json')]:
        row = next(c for c in clips if c['key'] == old_key)
        meta = read(ROOT/'requests'/new_key/'request-metadata.json')
        assert row['group_key'] == meta['group']['key']
        row['previous_key'] = old_key
        row['key'] = new_key
        row['order'] = forward + forward[-2::-1]
        row['dilation_native_px'] = dilation
        row['max_exposed_source_core_px'] = exposed
        row['raw_frames'] = []
        for i in forward:
            path = ROOT/'results'/new_key/'raw'/f'frame-{i:02}.png'
            row['raw_frames'].append({'index':i,'path':path.relative_to(REPO).as_posix(),'sha256':sha(path)})
        row['metrics'] = {'status':'bounded pilot; old core0/4px/180alpha gates are not claimed',
                          'exposed_source_core_max_px':exposed,'native_envelope_px':dilation,
                          'selected_forward':forward,'art_accepted':False}
        row['timeline_report'] = 'test_reports/fire-readable-sway-20261106/' + report_name
        changed.append(new_key)
    assert len(clips)==56 and len({c['group_key'] for c in clips})==56 and len(changed)==8
    selection = {'schema':'fire-field-selection-v1','path_base':'repository_root',
                 'purpose':'Slightly more readable sway, fixed previous cadence and phases; user selection pending.',
                 'previous_selection_sha256':sha(OLD/'field-selection/selection.json'),
                 'changed_clips':changed,'clips':clips,'art_accepted':False}
    (ROOT/'selection.json').write_text(json.dumps(selection,indent=2)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'changed':changed,'groups':len(clips)}))

if __name__=='__main__':
    main()
