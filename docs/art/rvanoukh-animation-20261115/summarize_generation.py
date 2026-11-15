"""Summarize completed jobs and verify raw PNG provenance without copying payloads."""
from pathlib import Path
import base64
import hashlib
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('D:/Codex/home/generated_images/rvanoukh-animation-20261115')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main():
    rows = read(ROOT / 'requests.json')
    result, errors, verified = [], [], 0
    for row in rows:
        key = row['key']
        folder = JOBS / 'pixellab' / key
        admission, job = read(folder / 'admission.json'), read(folder / 'job-latest.json')
        if job.get('status') != 'completed' or job.get('id') != admission.get('background_job_id'):
            errors.append(f'{key}: incomplete or mismatched job')
            continue
        response = job['last_response']
        images = response['images']
        usage = response.get('billing_usage') or response.get('usage') or job.get('usage')
        if len(images) != row['expected_frames']:
            errors.append(f'{key}: unexpected count')
        hashes = []
        for index, image in enumerate(images):
            raw = base64.b64decode(image['base64'].split(',')[-1], validate=True)
            exported = ROOT / 'pixellab' / key / 'frames' / f'frame-{index:02d}.png'
            if not exported.is_file() or exported.read_bytes() != raw:
                errors.append(f'{key}:{index}: exported PNG differs from response')
            else:
                verified += 1
            hashes.append(hashlib.sha256(raw).hexdigest())
        result.append({'key':key, 'job_id':job['id'], 'status':job['status'], 'usage':usage,
                       'frames':len(images), 'response_png_sha256':hashes,
                       'submit':read(folder / 'submit-started.json')})
    generation_usage = sum(float(r['usage'].get('generations', 0)) for r in result if isinstance(r['usage'], dict))
    summary = {'pass':not errors, 'provider':'PixelLab', 'endpoint':'https://api.pixellab.ai/v2/animate-pixminimax',
               'expected_clips':len(rows), 'completed':len(result), 'raw_pngs_byte_verified':verified,
               'summed_job_generations':generation_usage, 'raw_jobs_directory':str(JOBS),
               'jobs':result, 'errors':errors, 'runtime_integration':False}
    (ROOT / 'generation.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k!='jobs'}, ensure_ascii=False))
    if errors:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
