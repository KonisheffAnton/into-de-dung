"""Сохраняет неизменённые PNG завершённого PixelLab job; API не вызывает."""
from pathlib import Path
import argparse
import base64
import hashlib
import json

ROOT = Path(__file__).resolve().parent
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire29-growth-20261107')


def extract(key: str) -> None:
    response = EXTERNAL / 'pixellab' / key / 'job-latest.json'
    payload = response.read_bytes()
    state = json.loads(payload.decode('utf-8-sig'))
    assert state['status'] == 'completed', state['status']
    body = state['last_response']
    images = body.get('images') or [body['image']]
    out = ROOT / 'raw' / key
    out.mkdir(parents=True, exist_ok=True)
    records = []
    for index, item in enumerate(images):
        image = item.get('image', item)
        data = base64.b64decode(image['base64'].split(',', 1)[-1])
        path = out / f'{index:02d}.png'
        if path.exists():
            assert path.read_bytes() == data, path
        else:
            path.write_bytes(data)
        records.append({'file': path.name, 'sha256': hashlib.sha256(data).hexdigest()})
    metadata = {k: v for k, v in body.items() if k not in ('image', 'images', 'quantized_image')}
    metadata.update(job_id=state['id'], response_sha256=hashlib.sha256(payload).hexdigest(), images=records)
    (out / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
    print(f'{key}: {len(records)} unchanged raw PNG')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('key', choices=['growth-keypose01', 'growth-motion01', 'growth-motion02'])
    extract(parser.parse_args().key)
