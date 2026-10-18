"""Preserve and verify PixelLab reference conversions; no network or image editing."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider-dir', type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    for source in sources:
        assert sha(ROOT / source['file']) == sha(REPO / source['source']) == source['sha256']
    plan = json.loads((ROOT / 'plan.json').read_text(encoding='utf-8'))
    actual = json.loads((args.provider_dir / 'plan.json').read_text(encoding='utf-8'))
    assert len(plan) == len(actual) == 2
    outputs, pending = [], []
    for item, sent in zip(plan, actual):
        assert item['id'] == sent['id'] and item['endpoint'] == sent['endpoint']
        assert json.loads((ROOT / 'requests' / f'{item["id"]:03d}.json').read_text(encoding='utf-8')) == item
        restored = json.loads(json.dumps(item['request']))
        ref = restored['image']
        assert sha(ROOT / ref['file']) == ref['sha256']
        restored['image'] = {'type': 'base64', 'format': 'png',
                             'base64': base64.b64encode((ROOT / ref['file']).read_bytes()).decode()}
        assert restored == sent['request']
        provider = args.provider_dir / 'items' / f'{item["id"]:03d}'
        if not (provider / 'result.json').exists():
            pending.append(item['id'])
            continue
        result = json.loads((provider / 'result.json').read_text(encoding='utf-8'))
        assert result['status'] == 'completed', result
        request = json.loads((provider / 'request.json').read_text(encoding='utf-8'))
        assert request == {'endpoint': item['endpoint'], 'body': restored}
        response = json.loads((provider / 'response.json').read_text(encoding='utf-8'))
        data = base64.b64decode(response['image']['base64'].split(',', 1)[-1], validate=True)
        assert data == (provider / 'original.png').read_bytes()
        digest = hashlib.sha256(data).hexdigest()
        assert digest == result['outputs'][0]['sha256']
        target = ROOT / 'outputs' / f'{item["label"]}.png'
        if target.exists():
            assert target.read_bytes() == data, target
        else:
            target.write_bytes(data)
        with Image.open(target) as image:
            image.load()
            assert image.size == (480, 270)
            alpha = image.convert('RGBA').getchannel('A').getextrema()
            output = {'label': item['label'], 'file': target.relative_to(ROOT).as_posix(),
                      'sha256': digest, 'size': list(image.size), 'alpha_extrema': list(alpha),
                      'nonopaque_pixel_count': sum(a < 255 for a in image.convert('RGBA').getchannel('A').get_flattened_data()),
                      'unique_rgb_colors': len(set(image.convert('RGB').get_flattened_data())),
                      'usage': result['usage']}
        outputs.append(output)
    selected = json.loads((ROOT / 'selected-animations.json').read_text(encoding='utf-8'))
    for clip in selected:
        assert sha(REPO / clip['path']) == clip['sha256']
    save(ROOT / 'manifest.json', {'provider': 'PixelLab API v2', 'preview_only': True,
                                'outputs': outputs, 'pending': pending,
                                'source_copies_verified': len(sources),
                                'selected_animation_hashes_verified': len(selected)})
    print(json.dumps({'packaged': len(outputs), 'pending': pending}))


if __name__ == '__main__':
    main()
