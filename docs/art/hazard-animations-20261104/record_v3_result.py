"""Зафиксировать фактические 9 кадров admitted v3 без изменения запроса."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/pixellab')
KEY = 'fire22-01'
PROVENANCE = ROOT / 'prompt-revision-03-v3-result.json'


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if PROVENANCE.exists():
        raise SystemExit('V3 result already recorded')
    folder = JOBS / KEY
    job = json.loads((folder / 'job-latest.json').read_text(encoding='utf-8-sig'))
    admission = json.loads((folder / 'admission.json').read_text(encoding='utf-8-sig'))
    assert job['status'] == 'completed' and job['id'] == admission['background_job_id']
    actual = len(job['last_response']['images'])
    assert actual == 9, f'Unexpected v3 frame count: {actual}'
    path = ROOT / 'requests.json'
    rows = json.loads(path.read_text(encoding='utf-8'))
    row = next(x for x in rows if x['key'] == KEY)
    assert row['endpoint'] == 'animate-with-text-v3' and row['frame_count'] == 8 and row['expected_frames'] is None
    assert sha(folder / 'request.json') == row['request_sha256']
    before = row.copy()
    before_sha = sha(path)
    row['expected_frames'] = actual
    row['expected_frames_policy'] = 'Observed completed v3 response: 9 PNG frames for requested frame_count=8'
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    provenance = {'revision': 3, 'key': KEY, 'job_id': job['id'], 'requested_frame_count': 8,
                  'returned_frame_count': actual, 'billing_usage': job['last_response'].get('billing_usage'),
                  'before_requests_sha256': before_sha, 'after_requests_sha256': sha(path),
                  'before': before, 'after': row, 'request_sha256_unchanged': row['request_sha256']}
    PROVENANCE.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'key': KEY, 'requested_frames': 8, 'returned_frames': actual, 'job_id': job['id']}))


if __name__ == '__main__':
    main()
