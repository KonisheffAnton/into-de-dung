"""Record observed 404s without changing or resubmitting the original requests."""
from pathlib import Path
from datetime import datetime, timezone
import json, hashlib
ROOT=Path(__file__).resolve().parent
EXTERNAL=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
rows=[]
for key in ('fire24-field02','fire24-field04','fire29-field02'):
    job=EXTERNAL/'pixellab'/key
    admission=json.loads((job/'admission.json').read_text(encoding='utf-8-sig'))
    error=json.loads((job/'rejected-response.json').read_text(encoding='utf-8-sig'))
    assert error['detail']=='Job not found'
    old=json.loads((job/'job-latest.json').read_text(encoding='utf-8-sig'))
    assert old['id']==admission['background_job_id'] and old['status']=='processing'
    row={'key':key,'kind':'unavailable_after_404','job_id':admission['background_job_id'],
         'http_status':404,'observed_utc':datetime.now(timezone.utc).isoformat(),
         'last_saved_status':old['status'],'raw_frames_received':0,
         'request_sha256':hashlib.sha256((job/'request.json').read_bytes()).hexdigest(),
         'error_sha256':hashlib.sha256((job/'rejected-response.json').read_bytes()).hexdigest(),
         'explanation':'Confirmed admission, then GET 404 Job not found. No terminal success payload was saved. Official Jobs schema says completed jobs are automatically cleaned up; no recovery/list endpoint for standalone PixMiniMax images is documented. Exact cause and completion status are unverified. Original POST barrier remains; any new generation needs a new recorded attempt.'}
    target=job/'resolution.json'
    if target.exists(): row=json.loads(target.read_text())
    else: target.write_text(json.dumps(row,indent=2)+'\n',encoding='utf-8')
    rows.append(row)
report={'jobs':rows,'balance_after_five_saved_field_jobs':4527,'balance_after_unavailable_jobs':4512,
        'balance_delta_for_three_unavailable_jobs':15,'provider_usage_response_for_unavailable_jobs':None,
        'recovery_change':'Poll every 5 seconds (official recommendation 5-10), archive every successful GET before parsing; never repeat original POST keys.'}
(ROOT.parents[2]/'test_reports/fire-single-tongue-20261106/provider-recovery.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'unavailable_jobs':len(rows),'saved_frames':0,'balance_delta':15}))
