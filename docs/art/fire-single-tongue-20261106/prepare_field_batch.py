"""Prepare each remaining distinct source stroke once; no provider calls here."""
import json
from pathlib import Path
from field_pipeline import ROOT, JOBS, prepare

inventory=json.loads((ROOT.parents[2]/'test_reports/fire-single-tongue-20261106/field-inputs.json').read_text())
complete=set()
for manifest in (ROOT/'results').glob('fire*-field*/manifest.json'):
    meta=json.loads((ROOT/'requests'/manifest.parent.name/'request-metadata.json').read_text())
    complete.add(meta['group']['key'])
styles={s:sorted((g for g in row['groups'] if g['key'] not in complete),key=lambda g:-g['core_pixels'])
        for s,row in inventory['styles'].items()}
keys=[]
for slot in range(max(map(len,styles.values()))):
    for style in ('24','29'):
        if slot>=len(styles[style]):continue
        group=styles[style][slot];key=group['key'].replace('-','-field')
        replacement=(JOBS/'pixellab'/key/'resolution.json').exists()
        if replacement:key+='r1'
        if not (ROOT/'requests'/key).exists():prepare(group['key'],32,replacement)
        assert not (JOBS/'pixellab'/key/'submit-started.json').exists(),f'{key} has already been attempted'
        keys.append(key)
plan={'purpose':'One generation for each remaining distinct prepared source stroke; no automatic retries.',
      'frames_requested_each':32,'max_active':3,'complete_source_groups_before_batch':sorted(complete),
      'order':'Alternate styles, larger bright/soft core groups first','keys':keys}
(ROOT/'field-batch-plan.json').write_text(json.dumps(plan,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'prepared_remaining':len(keys),'already_completed_groups':len(complete)}))
