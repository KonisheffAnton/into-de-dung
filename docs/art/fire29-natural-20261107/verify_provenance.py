"""Audit actual PixelLab responses and byte-exact raw images, without API calls."""
from pathlib import Path
import base64
import hashlib
import json

PACKAGE = Path(__file__).resolve().parent
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire29-natural-20261107')
sha = lambda data: hashlib.sha256(data).hexdigest()
records = []
total_usage = 0.0
total_png = 0
pending = []
for directory in sorted((PACKAGE / 'requests').iterdir()):
    key = directory.name
    metadata = json.loads((directory / 'metadata.json').read_bytes())
    request = (directory / 'request.json').read_bytes()
    external = EXTERNAL / 'pixellab' / key
    actual_request = (external / 'request.json').read_bytes()
    assert sha(actual_request) == metadata['request_sha256'], key
    if metadata.get('continuation_external'):
        assert sha(request) == metadata['public_request_sha256'], key
        actual = json.loads(actual_request)
        assert sha(actual['conversation'].encode()) == metadata['continuation_sha256'], key
        actual['conversation'] = '<continuation stored outside repository>'
        assert actual == json.loads(request), key
    else:
        assert request == actual_request, key
    latest = external / 'job-latest.json'
    row = {'key': key, 'endpoint': metadata['endpoint'], 'request_sha256': sha(request)}
    synchronous = False
    if not latest.exists():
        direct = external / 'response-raw.json'
        direct_state = json.loads(direct.read_bytes()) if direct.exists() and direct.stat().st_size else {}
        if direct_state.get('images') or direct_state.get('image'):
            latest = direct
            synchronous = True
        elif (external / 'admission.json').exists():
            admitted = json.loads((external / 'admission.json').read_bytes())
            row.update(status='admitted_not_yet_polled', job_id=admitted['background_job_id'])
            pending.append(key)
            records.append(row)
            continue
        else:
            transport = external / 'transport-failure.json'
            if transport.exists():
                failure = json.loads(transport.read_bytes())
                assert not (external / 'admission.json').exists(), key
                assert failure['connection_established'] is False, key
                row.update(status='transport_failed_before_connection', raw_png=0,
                           evidence_sha256=sha(transport.read_bytes()))
                records.append(row)
                continue
            rejected = external / 'rejected-response.json'
            assert rejected.exists() and not (external / 'admission.json').exists(), key
            error = json.loads(rejected.read_bytes())
            row.update(status='request_rejected', detail=error.get('detail'), raw_png=0)
            records.append(row)
            continue
    payload = latest.read_bytes()
    state = json.loads(payload)
    job_id = None if synchronous else state['id']
    status = 'completed' if synchronous else state['status']
    row.update(status=status, job_id=job_id, response_sha256=sha(payload),
               delivery='synchronous' if synchronous else 'background_job')
    if status != 'completed':
        pending.append(key)
        records.append(row)
        continue
    body = state if synchronous else state['last_response']
    if metadata['endpoint'] == 'vfx':
        from PIL import Image
        manifest = json.loads((PACKAGE / 'raw' / key / 'metadata.json').read_bytes())
        assert manifest['response_sha256'] == sha(payload) and manifest['job_id'] == job_id, key
        assert len(manifest['downloads']) == len(body['files']), key
        assert {item['name'] for item in manifest['downloads']} == set(body['files']), key
        for item in manifest['downloads']:
            assert item['url'] == body['files'][item['name']]
            assert sha((PACKAGE / 'raw' / key / item['name']).read_bytes()) == item['sha256']
        frames = json.loads((PACKAGE / 'raw' / key / 'frames.json').read_bytes())
        png_names = [name for name in body['files'] if name.endswith('.png')]
        layout_names = [name for name in body['files'] if name.endswith('.json')]
        assert len(png_names) == len(layout_names) == 1, key
        assert frames['source'] == png_names[0], key
        layout = json.loads((PACKAGE / 'raw' / key / layout_names[0]).read_bytes())
        assert len(frames['frames']) == len(layout['frames']) == body['frames'], key
        atlas = Image.open(PACKAGE / 'raw' / key / frames['source']).convert('RGBA')
        for index, frame in enumerate(frames['frames']):
            original = layout['frames'][index]
            assert not original['rotated'] and not original['trimmed'], key
            assert frame['file'] == f'frame-{index:02d}.png', key
            assert frame['atlas_rect'] == original['frame'], key
            assert frame['duration_ms'] == original['duration'], key
            r = frame['atlas_rect']
            pixels = atlas.crop((r['x'], r['y'], r['x'] + r['w'], r['y'] + r['h'])).tobytes()
            assert pixels == Image.open(PACKAGE / 'raw' / key / frame['file']).convert('RGBA').tobytes()
            assert sha(pixels) == frame['rgba_sha256']
        usage = state['usage']
        assert usage['type'] == 'generations'
        total_usage += usage['generations']
        row.update(atlas_frames=len(frames['frames']), usage_generations=usage['generations'])
        records.append(row)
        continue
    images = body.get('images') or [body['image']]
    manifest = json.loads((PACKAGE / 'raw' / key / 'metadata.json').read_bytes())
    assert manifest['response_sha256'] == sha(payload) and manifest['job_id'] == job_id, key
    assert len(manifest['images']) == len(images), key
    for index, item in enumerate(images):
        value = item.get('image', item)
        data = base64.b64decode(value['base64'].split(',', 1)[-1])
        assert data == (PACKAGE / 'raw' / key / f'{index:02d}.png').read_bytes(), (key, index)
        assert sha(data) == manifest['images'][index]['sha256'], (key, index)
    usage = state['usage']
    assert usage['type'] == 'generations', (key, usage)
    total_usage += usage['generations']
    total_png += len(images)
    row.update(raw_png=len(images), usage_generations=usage['generations'])
    records.append(row)
result = {'status': 'PENDING' if pending else 'PASS', 'requests': records,
          'pending': pending, 'raw_png': total_png, 'usage_generations': total_usage,
          'completed_non_vfx_png_bytes_equal_response': True,
          'completed_vfx_download_hashes_and_slice_rgba_verified': True,
          'vfx_slice_png_encoding_is_not_provider_original': True,
          'requires_external_response_archive': str(EXTERNAL),
          'runtime_integration': False}
(PACKAGE / 'provider-ledger.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
print(result['status'], 'raw:', total_png, 'usage:', total_usage, 'pending:', pending)
