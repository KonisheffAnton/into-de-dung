"""Validate provider provenance, task boundaries and the byte-exact handoff archive."""
from pathlib import Path
import argparse, base64, hashlib, json
from PIL import Image

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[2]
REPORT=REPO/'test_reports/fire-single-tongue-20261106'
EXTERNAL=Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')

def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    p=argparse.ArgumentParser();p.add_argument('--partial',action='store_true');a=p.parse_args()
    rows=[];png_count=0;usage=0;incomplete=[];unavailable=[]
    for metadata in sorted((ROOT/'requests').glob('*/request-metadata.json')):
        meta=read(metadata);key=meta['key'];job=EXTERNAL/'pixellab'/key
        request_path=metadata.parent/'request.json';request=read(request_path)
        assert sha(request_path)==meta['request_sha256']==sha(job/'request.json'),key
        if 'input' in meta:
            inp=ROOT/meta['input'];assert sha(inp)==meta['input_sha256']
            assert base64.b64decode(request['first_frame']['base64'])==inp.read_bytes()
            assert request['first_frame']==request['last_frame']
        if not (job/'admission.json').exists():
            incomplete.append(key);continue
        admission=read(job/'admission.json');latest=job/'job-latest.json'
        if not latest.exists() or read(latest).get('status')!='completed':
            if (job/'resolution.json').exists():
                resolution=read(job/'resolution.json')
                assert resolution['job_id']==admission['background_job_id']
                assert resolution['kind']=='unavailable_after_404' and resolution['http_status']==404
                assert resolution['raw_frames_received']==0 and resolution['request_sha256']==sha(request_path)
                unavailable.append(key);rows.append({'key':key,'result':'unavailable_after_404','raw_count':0})
            else:incomplete.append(key)
            continue
        outer=read(latest);assert outer['id']==admission['background_job_id'];response=outer['last_response']
        items=response.get('images') or [response['image']]
        files=([ROOT/'results'/key/'raw.png'] if meta['endpoint']=='inpaint-v3'
               else sorted((ROOT/'results'/key/'raw').glob('frame-*.png')))
        assert len(items)==len(files),key
        for item,path in zip(items,files):
            assert path.read_bytes()==base64.b64decode(item['base64']),path
            with Image.open(path) as im:assert im.format=='PNG' and im.mode=='RGBA'
        if (ROOT/'results'/key/'manifest.json').exists():
            manifest=read(ROOT/'results'/key/'manifest.json')
            assert manifest['response_sha256']==sha(latest)
            for frame,path in zip(manifest['frames'],files):assert frame['sha256']==sha(path)
        billed=response['billing_usage']['generations'];usage+=billed;png_count+=len(files)
        rows.append({'key':key,'result':'completed_and_png_bytes_verified','job_id':admission['background_job_id'],
                     'raw_count':len(files),'usage_generations':billed,'response_sha256':sha(latest)})
    assert a.partial or not incomplete,f'Incomplete jobs: {incomplete}'
    preserved={}
    for name,entries in read(REPORT/'baseline.json').items():
        if not isinstance(entries,list):continue
        for entry in entries:assert sha(REPO/entry['path'])==entry['sha256'],entry['path']
        preserved[name]=len(entries)
    assert (REPORT/'previous-handoff.bytes').read_bytes()==(REPO/'docs/CODEX_HANDOFF.history-20261106-2.md').read_bytes()
    result={'pass':True,'partial':a.partial,'raw_png_byte_matches':png_count,'confirmed_provider_usage_generations':usage,
        'unavailable_jobs':unavailable,'unavailable_balance_delta':15 if unavailable else 0,
        'unavailable_usage_from_provider':None,'pending_jobs':incomplete,'jobs':rows,
        'preserved_groups':preserved,'archive_byte_exact':True,'runtime_integrated':False,'godot_run':False}
    (REPORT/'package-validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:result[k] for k in ['pass','partial','raw_png_byte_matches','confirmed_provider_usage_generations','unavailable_jobs','pending_jobs','preserved_groups']}))

if __name__=='__main__':main()
