"""Проверяет реальные ответы PixelLab, выбор из20 кандидатов и полный расход."""
import base64
import hashlib
import json
from pathlib import Path
from run_pixellab import extract_pngs

ROOT = Path(__file__).resolve().parent
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/kostyash-feral-small-five-20261115')
def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(data):
    return hashlib.sha256(data).hexdigest()
def actual_usage(response):
    last = response.get('last_response') or response
    return last.get('billing_usage', last.get('usage', response.get('usage')))
def main():
    sources = read(ROOT/'sources.json')
    assert sources['complete'] and len(sources['variants']) == 5
    selections = {r['id']:r for r in read(ROOT/'selection.json')['variants']}
    cleanups = {r['id']:r for r in read(ROOT/'cleanup.json')['variants']}
    results=[]
    for row in sources['variants']:
        i=row['id']; choice=selections[i]
        folder=EXTERNAL/'feral-generation/items'/f'{i:03d}'
        result=read(folder/'result.json');response=read(folder/'response.json')
        images=extract_pngs(response)
        assert len(images)==len(result['outputs'])==4
        for index,data in enumerate(images):
            assert data==(ROOT/f'candidates/{i:02d}/{index+1:02d}.png').read_bytes()
            assert sha(data)==result['outputs'][index]['sha256']
        generated=images[choice['output_index']]
        assert generated==(ROOT/row['generated_file']).read_bytes()
        assert sha(generated)==choice['sha256']==row['generated_sha256']
        assert response['status']=='completed' and response['id']==row['job_id']==result['job_id']
        body=read(folder/'request.json')['body']
        assert base64.b64decode(body['reference_images'][0]['image']['base64'])==(ROOT/row['source_file']).read_bytes()
        assert base64.b64decode(body['style_image']['image']['base64'])==(ROOT/'references/warrior11.png').read_bytes()
        usage=actual_usage(response)
        assert usage==row['usage']==result['usage']
        cleanup_usage=None
        final=generated
        if i in cleanups:
            c=cleanups[i]; cf=Path(c['external_dir']);cr=read(cf/'response.json');cb=read(cf/'request.json')['body']
            assert base64.b64decode(cb['image']['base64'])==generated
            pngs=extract_pngs(cr);assert len(pngs)==1
            final=pngs[0];cleanup_usage=actual_usage(cr)
            assert sha(final)==c['output_sha256'] and cleanup_usage==c['usage']==read(cf/'result.json')['usage']
        assert final==(ROOT/row['file']).read_bytes()
        results.append(dict(id=i,job_id=row['job_id'],output_index=choice['output_index'],sha256=sha(final),usage=usage,cleanup_usage=cleanup_usage))
    trial_usage=[]
    pilot=read(EXTERNAL/'items/001/result.json')
    assert extract_pngs(read(EXTERNAL/'items/001/response.json'))==[(ROOT/'trials/pilot-256.png').read_bytes()]
    trial_usage.append(pilot['usage'])
    for row in read(ROOT/'trials/edit-224/results.json')['variants']:
        folder=EXTERNAL/'trial-224/items'/f"{row['id']:03d}"
        assert extract_pngs(read(folder/'response.json'))==[(ROOT/row['file']).read_bytes()]
        assert row['usage']==read(folder/'result.json')['usage']
        trial_usage.append(row['usage'])
    bg=read(EXTERNAL/'background-cleanup/items/003/response.json')
    assert extract_pngs(bg)==[(ROOT/'trials/background-first-03.png').read_bytes()]
    trial_usage.append(actual_usage(bg))
    selected_cost=sum(r['usage']['generations']+(r['cleanup_usage'] or {}).get('generations',0) for r in results)
    trial_cost=sum(u['generations'] for u in trial_usage)
    before=read(EXTERNAL/'balance-before.json');after=read(EXTERNAL/'background-cleanup-selected/balance-latest.json')
    delta=before['subscription']['generations']-after['subscription']['generations']
    report=dict(complete=True,selected=results,provider_candidates=20,selected_generation_units=selected_cost,unselected_generation_units=trial_cost,total_generation_units=selected_cost+trial_cost,balance_before=before,balance_after=after,balance_delta=delta,native_outputs_unmodified=True,matching_submitted_source_bytes=True,scope='Actual API payload/output provenance and usage; geometry and artistic acceptance are separate')
    (ROOT/'request-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(dict(complete=True,selected=5,provider_candidates=20,total_generation_units=selected_cost+trial_cost,balance_delta=delta)))
if __name__=='__main__':
    main()
