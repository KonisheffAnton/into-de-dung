"""Extract the final accepted PixelLab result without resubmission."""
import base64
import hashlib
import io
import json
import sys
from pathlib import Path

from PIL import Image

root = Path(__file__).resolve().parent
target = root / 'pixellab'
accepted = json.loads((target / 'response.json').read_text(encoding='utf-8-sig'))
job = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8-sig'))
assert job['id'] == accepted['background_job_id'], 'Wrong job'
assert job['status'] == 'completed', 'Not completed'
result = job['last_response']
records = {}
for key, name in [('image', 'result.png'), ('quantized_image', 'result-quantized.png')]:
    encoded = result[key]['base64'].split(',')[-1]
    data = base64.b64decode(encoded, validate=True)
    assert data.startswith(b'\x89PNG\r\n\x1a\n')
    with Image.open(io.BytesIO(data)) as image:
        assert image.size == (384, 192)
        image.load()
    path = target / name
    assert not path.exists() or path.read_bytes() == data, 'Refuse changed result'
    if not path.exists():
        path.write_bytes(data)
    records[key] = {'file': name, 'sha256': hashlib.sha256(data).hexdigest()}
metadata = {k: v for k, v in result.items() if k not in ['image', 'quantized_image']}
metadata.update({'job_id': job['id'], 'status': job['status'], 'images': records,
                 'composition_source': 'image (result.png)'})
(target / 'result.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'status': job['status'], 'images': records, 'billing_usage': metadata['billing_usage']}))
