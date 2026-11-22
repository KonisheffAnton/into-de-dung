"""Universal-remains concept requests. No automatic POST retries; no runtime edits."""
from pathlib import Path
import argparse, base64, json, os, urllib.request

ROOT = Path(__file__).resolve().parent
TOKEN = os.environ.pop('TASK_PIXELLAB_TOKEN')
BASE = 'https://api.pixellab.ai/v2'
COMMON = ('One small universal battlefield remains marker for a pixel art dungeon tactics game. '
          'A low flat pile of anonymous bone fragments, impossible to tell human or monster. '
          'NO skull, face, teeth, hands, feet, claws, horns, complete skeleton, clothing or equipment. '
          'Shallow three-quarter overhead view, 2:1 isometric floor perspective. '
          'Simple thick crisp pixel clusters, sparse detail, only 8-10 flat colors: muted dirty ivory, '
          'warm taupe shadow, gray-purple deep shadow, selective dark outlines. Light top left. '
          'Dry bare bones only. Compact footprint occupying about 44x28 pixels in 64x64. '
          'Transparent background, no tile, no floor, no ground debris, no soft shadow, no glow. ')
VARIANTS = {
    'PL-B1': 'Three short thick broken bones crossed loosely, with a small flat irregular fragment at their intersection. Sparse asymmetric criss-cross.',
    'PL-B2': 'Four short thick bone fragments and one plain curved fragment scattered loosely with clear gaps, compact diagonal arrangement.',
    'PL-B3': 'A low dense small heap of five chunky anonymous bone fragments, one curved piece at the back, rounded triangular silhouette. Not a rib cage.'
}
FRESH = ('Keep exactly this arrangement of anonymous bones and the same pixel style, scale and camera. '
         'Add small chunky patches of muted dark burgundy and brown-red meat clinging to the bones; '
         'leave bone ends visible. Universal fresh remains, not a creature body. '
         'No skull, face, organs, recognizable anatomy, clothing, equipment, big blood pool, floor, glow or background. '
         'Very simple crisp pixel clusters, no smoothing. Transparent background.')


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')


def request(method, endpoint, payload=None):
    raw = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + endpoint, data=raw, method=method,
        headers={'Authorization': 'Bearer ' + TOKEN, 'Content-Type': 'application/json'})
    with urllib.request.urlopen(req, timeout=180) as response:
        return json.load(response)


def decode(value, directory):
    result = value.get('last_response') or value
    images = result.get('images', [])
    if result.get('image'): images = [result['image']]
    paths = []
    for index, image in enumerate(images):
        data = image.get('base64', '') if isinstance(image, dict) else image
        if not data: continue
        path = directory / ('image.png' if index == 0 else f'image-{index}.png')
        path.write_bytes(base64.b64decode(data.split(',')[-1]))
        paths.append(path.name)
    return paths


def submit(identifier, endpoint, payload):
    directory = ROOT / identifier
    directory.mkdir(exist_ok=True)
    if (directory / 'response.json').exists():
        raise RuntimeError('Existing receipt: inspect it before any new POST for ' + identifier)
    save(directory / 'request.json', {'endpoint': endpoint, 'payload': payload})
    response = request('POST', endpoint, payload)
    save(directory / 'response.json', response)
    paths = decode(response, directory)
    print(json.dumps({'id': identifier, 'files': paths, 'job': response.get('background_job_id'), 'usage': response.get('usage')}, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['balance', 'bones', 'fresh', 'poll'])
    parser.add_argument('--id', default='all')
    args = parser.parse_args()
    if args.action == 'balance':
        data = request('GET', '/balance'); save(ROOT / 'balance.json', data); print(json.dumps(data)); return
    if args.action == 'bones':
        for index, (identifier, description) in enumerate(VARIANTS.items()):
            if args.id not in ('all', identifier): continue
            submit(identifier, '/create-image-pixen', {'description': COMMON + description,
                'image_size': {'width': 64, 'height': 64}, 'outline': 'selective outline',
                'detail': 'low detail', 'view': 'high top-down', 'no_background': True,
                'enhance_prompt': False, 'seed': 202611220 + index})
    elif args.action == 'fresh':
        assert len(FRESH) <= 500
        for index, bone in enumerate(VARIANTS):
            identifier = bone.replace('-B', '-F')
            if args.id not in ('all', identifier): continue
            data = base64.b64encode((ROOT / bone / 'image.png').read_bytes()).decode()
            submit(identifier, '/edit-image-pixen', {'image': {'type': 'base64', 'base64': data, 'format': 'png'},
                'description': FRESH, 'width': 64, 'height': 64, 'no_background': True, 'seed': 202611230 + index})
    else:
        for directory in sorted(ROOT.glob('PL-F*')):
            if args.id not in ('all', directory.name) or (directory / 'image.png').exists(): continue
            receipt = json.loads((directory / 'response.json').read_text())
            job = receipt['background_job_id']
            status = request('GET', '/background-jobs/' + job)
            save(directory / 'status.json', status)
            paths = decode(status, directory) if status.get('status') == 'completed' else []
            print(json.dumps({'id': directory.name, 'status': status.get('status'), 'files': paths,
                'usage': status.get('usage')}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
