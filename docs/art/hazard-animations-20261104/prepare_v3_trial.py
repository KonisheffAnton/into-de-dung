"""Подготовить один ещё не отправленный fire22-01 для animate-with-text-v3."""
from pathlib import Path
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104')
KEY = 'fire22-01'
PROVENANCE = ROOT / 'prompt-revision-02-v3.json'
ACTION = (
    'Exactly the same 256x256 pixel positions in every frame. Keep the original diamond top and all masonry '
    'side faces perfectly fixed. Only cycle the brightness and nearby warm palette values of already existing '
    'orange surface pixels in place, in tiny staggered patches, then return to the original colours. '
    'This is a flat two-dimensional glowing ember texture on the top plane with no shape motion. '
    'Preserve the exact original tile silhouette and alpha envelope in every frame. No vertical expansion, '
    'rising tongues, flames, smoke, sparks, new orange shapes, liquid flow, redrawing, translation, '
    'camera movement or colour changes on stone sides. Start and end on the exact supplied image.'
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if PROVENANCE.exists():
        raise SystemExit('V3 revision already recorded')
    path = ROOT / 'requests.json'
    rows = json.loads(path.read_text(encoding='utf-8'))
    row = next(x for x in rows if x['key'] == KEY)
    folder = JOBS / 'pixellab' / KEY
    if (folder / 'submit-started.json').exists() or (folder / 'admission.json').exists():
        raise SystemExit('fire22-01 already attempted')
    request_path = folder / 'request.json'
    assert sha(request_path) == row['request_sha256']
    assert row['endpoint'] == 'animate-pixminimax' and row['frame_count'] == 32
    assert len(ACTION) <= 1000
    with urllib.request.urlopen('https://api.pixellab.ai/v2/openapi.json', timeout=30) as response:
        schema_bytes = response.read()
    schema_path = JOBS / 'openapi-v3-prepared.json'
    schema_path.write_bytes(schema_bytes)
    schema = json.loads(schema_bytes)
    endpoint = schema['paths']['/animate-with-text-v3']['post']
    name = endpoint['requestBody']['content']['application/json']['schema']['$ref'].split('/')[-1]
    request_schema = schema['components']['schemas'][name]
    props = request_schema['properties']
    fields = {'first_frame', 'last_frame', 'action', 'frame_count', 'seed',
              'no_background', 'drift_threshold', 'enhance_prompt'}
    assert fields <= set(props) and request_schema['additionalProperties'] is False
    assert props['action']['maxLength'] >= len(ACTION)
    assert props['frame_count']['minimum'] <= 8 <= props['frame_count']['maximum']
    assert 256 * 256 * 8 == 524288
    old = json.loads(request_path.read_text(encoding='utf-8'))
    request = {'first_frame': old['first_frame'], 'last_frame': old['last_frame'],
               'action': ACTION, 'frame_count': 8, 'seed': old['seed'],
               'no_background': True, 'drift_threshold': 0, 'enhance_prompt': False}
    assert set(request) == fields and request['first_frame'] == request['last_frame']
    before_row = row.copy()
    before_request_sha = sha(request_path)
    request_path.write_text(json.dumps(request), encoding='utf-8')
    (folder / 'prompt.txt').write_text(ACTION, encoding='utf-8')
    row.update({'name': 'Плоское мерцание v3', 'prompt': ACTION,
                'captions': None, 'endpoint': 'animate-with-text-v3',
                'frame_count': 8, 'expected_frames': None,
                'expected_frames_policy': 'Determine from completed provider response; no assumed 33-frame count',
                'request_sha256': sha(request_path)})
    before_manifest_sha = sha(path)
    path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    provenance = {'revision': 2, 'key': KEY, 'reason': 'PixMiniMax flat palette prompt still produced high flames',
                  'schema_snapshot': str(schema_path), 'before_requests_sha256': before_manifest_sha,
                  'after_requests_sha256': sha(path), 'before': before_row, 'before_request_sha256': before_request_sha,
                  'after': row, 'after_request_fields': sorted(request)}
    PROVENANCE.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'key': KEY, 'endpoint': row['endpoint'], 'frame_count': 8,
                      'expected_frames': None, 'action_length': len(ACTION), 'post_attempted': False}))


if __name__ == '__main__':
    main()
