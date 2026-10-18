"""Read-only artifact/provenance checks, not a Godot or art acceptance test."""
import argparse
import base64
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.local = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value and not value.startswith(('#', 'http', 'data:')):
                self.local.append(value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    for source in sources:
        assert sha(ROOT / source['source']) == source['source_sha256']
        assert sha(Path(source['attachment'])) == source['source_sha256']
        if 'input' in source:
            assert sha(ROOT / source['input']) == source['input_sha256']
    plan = json.loads((ROOT / 'plan.json').read_text(encoding='utf-8'))
    actual_plan = json.loads((args.provider_dir / 'plan.json').read_text(encoding='utf-8'))
    assert len(plan) == len(actual_plan) == 17
    for item, sent in zip(plan, actual_plan):
        assert item['id'] == sent['id'] and item['endpoint'] == sent['endpoint']
        restored = json.loads(json.dumps(item['request']))
        for key in ('image', 'first_frame', 'last_frame'):
            if key in restored:
                ref = restored[key]
                assert sha(ROOT / ref['file']) == ref['sha256']
                restored[key] = {'type': 'base64', 'base64': base64.b64encode((ROOT / ref['file']).read_bytes()).decode(), 'format': 'png'}
        assert restored == sent['request'], f'Request differs: {item["id"]}'
        saved = json.loads((args.provider_dir / 'items' / f'{item["id"]:03d}' / 'request.json').read_text(encoding='utf-8'))
        assert saved == {'endpoint': item['endpoint'], 'body': restored}
    manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    assert not manifest['pending'], manifest['pending']
    assert len(manifest['outputs']) == 17
    pngs, observations, dynamic_links = 0, [], []
    for output in manifest['outputs']:
        assert len(output['frames']) == (1 if output['kind'] == 'diorama' else 9)
        bounds = []
        for frame in output['frames']:
            path = ROOT / frame['file']
            assert sha(path) == frame['sha256']
            with Image.open(path) as im:
                im.load()
                assert list(im.size) == frame['size']
                alpha = im.convert('RGBA').getchannel('A')
                assert list(alpha.getextrema()) == frame['alpha_extrema']
                bounds.append(alpha.point(lambda x: 255 if x >= 128 else 0).getbbox())
                if output['kind'] == 'animation':
                    assert im.size == (256, 256) and alpha.getextrema()[0] == 0
            pngs += 1
            dynamic_links.append(frame['file'])
        if output['kind'] == 'animation':
            assert output['unique_frames'] > 1
            folder = Path(output['frames'][0]['file']).parent
            for filename in ('contact.png', 'spritesheet.png', 'loop.gif'):
                with Image.open(ROOT / folder / filename) as im:
                    im.load()
                    if filename == 'loop.gif':
                        assert im.info.get('loop') == 0
                        assert im.n_frames >= 2
                dynamic_links.append((folder / filename).as_posix())
        observations.append({'id': output['id'], 'label': output['label'],
                             'variant': output.get('variant'), 'alpha128_bounds': bounds,
                             'edge_contact_frames': [i + 1 for i, b in enumerate(bounds) if b and (b[0] == 0 or b[1] == 0 or b[2] == 256 or b[3] == 256)] if output['kind'] == 'animation' else []})
    links = Links()
    links.feed((ROOT / 'gallery.html').read_text(encoding='utf-8'))
    for path in links.local + dynamic_links:
        assert (ROOT / path).is_file(), path
    result = {'status': 'PASS', 'source_copies': 5, 'request_provenance': 17,
              'provider_pngs': pngs, 'dioramas': 2, 'animations': 15,
              'requested_frames': 8, 'returned_frames_per_animation': 9, 'local_links_checked': len(links.local + dynamic_links),
              'observations': observations,
              'limits': 'Static file checks only. Not browser playback, runtime integration or final art acceptance.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in result.items() if k != 'observations'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
