"""Проверить подготовленный пакет без обращения к платному API."""
from pathlib import Path
import base64
import copy
import hashlib
import io
import json
import os
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104')
REPORT = ROOT.parents[2] / 'test_reports' / 'hazard-animations-20261104' / 'prepared-validation.json'
SOURCES = ('fire29', 'fire23', 'fire24', 'fire22', 'acidfilm', 'caltrops03')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    rows = json.loads((ROOT / 'requests.json').read_text(encoding='utf-8'))
    expected = [f'{source}-{i:02d}' for source in SOURCES for i in range(1, 6)]
    assert [row['key'] for row in rows] == expected
    assert all(len({row['prompt'] for row in rows if row['source_key'] == source}) == 5 for source in SOURCES)
    assert len({row['seed'] for row in rows}) == 30
    schema = json.loads((JOBS / 'openapi-20261104.json').read_text(encoding='utf-8'))
    endpoint = schema['paths']['/animate-pixminimax']['post']
    name = endpoint['requestBody']['content']['application/json']['schema']['$ref'].split('/')[-1]
    request_schema = schema['components']['schemas'][name]
    properties = request_schema['properties']
    assert request_schema['additionalProperties'] is False
    assert properties['description']['maxLength'] >= 1000
    assert 'first_frame' in request_schema['required'] and 'description' in request_schema['required']
    v3_schema = json.loads((JOBS / 'openapi-v3-prepared.json').read_text(encoding='utf-8'))
    v3_endpoint = v3_schema['paths']['/animate-with-text-v3']['post']
    v3_name = v3_endpoint['requestBody']['content']['application/json']['schema']['$ref'].split('/')[-1]
    v3_properties = v3_schema['components']['schemas'][v3_name]['properties']
    for source in SOURCES:
        transform = json.loads((ROOT / 'model' / source / 'transform.json').read_text(encoding='utf-8'))
        original = ROOT / transform['original_copy']
        initial = ROOT / transform['input']
        assert sha(original) == transform['source_sha256'] == sha((ROOT / transform['source']).resolve())
        assert sha(initial) == transform['input_sha256']
        with Image.open(original) as image:
            assert image.format == 'PNG' and image.mode == 'RGBA' and image.size == (1254, 1254)
            resized = image.resize((256, 256), Image.Resampling.LANCZOS)
        with Image.open(initial) as image:
            assert image.format == 'PNG' and image.mode == 'RGBA' and image.size == (256, 256)
            assert resized.tobytes() == image.tobytes()
    submitted = 0
    admitted_ids = []
    for row in rows:
        folder = JOBS / 'pixellab' / row['key']
        attempted = (folder / 'submit-started.json').exists()
        admission_file = folder / 'admission.json'
        assert attempted == admission_file.exists(), f'Uncertain POST: {row["key"]}'
        if attempted:
            admitted_id = json.loads(admission_file.read_text(encoding='utf-8-sig')).get('background_job_id')
            assert admitted_id
            admitted_ids.append(admitted_id)
            submitted += 1
        request_path = folder / 'request.json'
        request = json.loads(request_path.read_text(encoding='utf-8'))
        if row['endpoint'] == 'animate-with-text-v3':
            assert row['key'] == 'fire22-01' and row['frame_count'] == 8 and row['expected_frames'] == 9
            assert set(request) <= set(v3_properties) and len(request) == 8
            assert request['action'] == row['prompt'] and 0 < len(row['prompt']) <= v3_properties['action']['maxLength']
            assert request['frame_count'] == 8 and request['drift_threshold'] == 0
            assert row['captions'] is None
        else:
            assert row['endpoint'] == 'animate-pixminimax'
            assert set(request) <= set(properties)
            assert request['description'] == row['prompt'] and 0 < len(row['prompt']) <= 1000
            assert request['frame_count'] == 32
            for field in ('direction', 'view', 'subject_description', 'initial_pose'):
                assert request[field] == row['captions'][field]
        assert request['seed'] == row['seed']
        assert request['no_background'] is True and request['enhance_prompt'] is False
        assert request['first_frame'] == request['last_frame']
        assert sha(request_path) == row['request_sha256']
        data = base64.b64decode(request['first_frame']['base64'], validate=True)
        assert data == (ROOT / row['input']).read_bytes()
        with Image.open(io.BytesIO(data)) as image:
            assert image.format == 'PNG' and image.mode == 'RGBA' and image.size == (256, 256)
    revision = json.loads((ROOT / 'prompt-revision-01.json').read_text(encoding='utf-8'))
    revision2 = json.loads((ROOT / 'prompt-revision-02-v3.json').read_text(encoding='utf-8'))
    revision3 = json.loads((ROOT / 'prompt-revision-03-v3-result.json').read_text(encoding='utf-8'))
    assert len(revision['changed']) == 14
    reconstructed = copy.deepcopy(rows)
    index = next(i for i, row in enumerate(reconstructed) if row['key'] == revision2['key'])
    assert reconstructed[index] == revision3['after']
    reconstructed[index] = revision3['before']
    pre_result_bytes = (json.dumps(reconstructed, ensure_ascii=False, indent=2) + '\n').replace('\n', os.linesep).encode('utf-8')
    assert hashlib.sha256(pre_result_bytes).hexdigest() == revision3['before_requests_sha256'] == revision2['after_requests_sha256']
    assert reconstructed[index] == revision2['after']
    reconstructed[index] = revision2['before']
    assert all(item['after']['request_sha256'] == next(row['request_sha256'] for row in reconstructed if row['key'] == item['before']['key'])
               for item in revision['changed'])
    pre_v3_bytes = (json.dumps(reconstructed, ensure_ascii=False, indent=2) + '\n').replace('\n', os.linesep).encode('utf-8')
    assert hashlib.sha256(pre_v3_bytes).hexdigest() == revision2['before_requests_sha256'] == revision['revised_requests_sha256']
    for change in revision['changed']:
        original = next(row for row in reconstructed if row['key'] == change['before']['key'])
        for field in ('name', 'prompt', 'captions', 'request_sha256'):
            original[field] = change['before'][field]
    original_bytes = (json.dumps(reconstructed, ensure_ascii=False, indent=2) + '\n').replace('\n', os.linesep).encode('utf-8')
    assert hashlib.sha256(original_bytes).hexdigest() == revision['original_requests_sha256']
    assert sha(ROOT / 'requests.json') == revision3['after_requests_sha256']
    assert len(admitted_ids) == len(set(admitted_ids))
    result = {'status': 'PASS', 'sources': 6, 'requests': 30, 'max_prompt_length': max(len(row['prompt']) for row in rows),
              'schema': str(JOBS / 'openapi-20261104.json'), 'endpoints': ['/v2/animate-pixminimax', '/v2/animate-with-text-v3'],
              'post_attempts': submitted, 'ambiguous_post_attempts': 0, 'revision': 3, 'integration': False}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
