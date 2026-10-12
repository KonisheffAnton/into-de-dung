"""Save original PNGs only from the three matching completed PixelLab jobs."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent


def extract(variant: dict, report: Path) -> dict:
    slug = variant['id']
    assert slug in ['01-forward-shield', '02-backward', '03-last-knee']
    target = ROOT / slug / 'pixellab'
    accepted = json.loads((target / 'response.json').read_text(encoding='utf-8-sig'))
    raw_path = report / (slug + '-job-latest.json')
    if not raw_path.exists():
        return {'variant': slug, 'status': 'not_polled'}
    job = json.loads(raw_path.read_text(encoding='utf-8-sig'))
    assert accepted.get('background_job_id') and job.get('id') == accepted['background_job_id'], 'Wrong job: ' + slug
    if job.get('status') != 'completed':
        return {'variant': slug, 'status': job.get('status')}
    result = job['last_response']
    entries = result['images']
    assert len(entries) == variant['frame_count'] + 1, 'Unexpected output frame count: ' + slug
    decoded = []
    records = []
    for index, entry in enumerate(entries):
        encoded = entry['base64']
        if encoded.startswith('data:'):
            encoded = encoded.split(',', 1)[1]
        data = base64.b64decode(encoded, validate=True)
        assert data.startswith(b'\x89PNG\r\n\x1a\n'), 'Not PNG'
        with Image.open(io.BytesIO(data)) as image:
            assert image.size == (128, 128), 'Unexpected dimensions'
            image.load()
        name = f'frame-{index + 1:02}.png'
        decoded.append((name, data))
        records.append({'file': name, 'sha256': hashlib.sha256(data).hexdigest()})
    expected = {name for name, _ in decoded}
    assert not {path.name for path in target.glob('frame-*.png')} - expected, 'Unexpected existing frames'
    # Проверяем весь пакет до записи, чтобы повторное чтение не подменило сохранённый вариант.
    for name, data in decoded:
        path = target / name
        assert not path.exists() or path.read_bytes() == data, 'Refusing changed frame: ' + str(path)
    for name, data in decoded:
        path = target / name
        if not path.exists():
            path.write_bytes(data)
    metadata = {key: value for key, value in result.items() if key not in ['images', 'image']}
    metadata.update({'job_id': job['id'], 'status': job['status'], 'frame_count': len(entries), 'files': records})
    (target / 'result.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    summary = {key: value for key, value in job.items() if key != 'last_response'}
    summary['last_response'] = {key: value for key, value in metadata.items() if key != 'files'}
    (target / 'job-status.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return {'variant': slug, 'status': 'completed', 'frames': len(entries), 'billing_usage': metadata.get('billing_usage')}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('report_directory', type=Path, help='Raw accepted job responses, outside Git')
    report = parser.parse_args().report_directory.resolve()
    manifest = json.loads((ROOT / 'request-manifest.json').read_text(encoding='utf-8'))
    print(json.dumps([extract(variant, report) for variant in manifest['variants']], ensure_ascii=False))


if __name__ == '__main__':
    main()
