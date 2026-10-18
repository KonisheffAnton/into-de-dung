"""Read-only asset checks and independent image-derived interaction fixtures."""
import ast
import base64
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
REPORT = REPO / 'test_reports/hub-diorama-layered-20261018'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        self.links += [v for k, v in attrs if k in ('href', 'src') and v and not v.startswith('#')]


def main():
    data = json.loads((ROOT / 'placement.json').read_text(encoding='utf-8'))
    js = (ROOT / 'scene-data.js').read_text(encoding='utf-8')
    baked = json.loads(js.removeprefix('window.DIORAMA_LAYER_DATA = ').strip().removesuffix(';'))
    assert len(data['backgrounds']) == 4 and len(data['actors']) == 4
    assert data['selection'] == {'crowd': 2, 'market': 5, 'smith_latest': 3}
    frames = {}
    checked = 0
    parser = Links()
    parser.feed((ROOT / 'gallery.html').read_text(encoding='utf-8'))
    references = set(parser.links)
    for bg in data['backgrounds']:
        assert sha(ROOT / bg['file']) == sha(REPO / bg['source']) == bg['sha256']
        base = np.array(Image.open(ROOT / bg['file']).convert('RGBA'))
        foreground = np.array(Image.open(ROOT / bg['foreground']).convert('RGBA'))
        assert base.shape == foreground.shape == (941, 1672, 4)
        assert np.array_equal(base[:, :, :3], foreground[:, :, :3])
        assert set(np.unique(foreground[:, :, 3])) == {0, 255}
        checked += 1
    for clip, packed in zip(data['clips'], baked['clips']):
        assert clip['id'] == packed['id'] and len(clip['frames']) == len(packed['masks']) == 9
        references.add(clip['gif'])
        frames[clip['id']] = []
        for record, mask in zip(clip['frames'], packed['masks']):
            assert sha(ROOT / record['file']) == sha(REPO / record['source']) == record['sha256']
            image = Image.open(ROOT / record['file']).convert('RGBA')
            assert image.size == (256, 256)
            expected = np.array(image)[:, :, 3] >= 24
            actual = np.unpackbits(np.frombuffer(base64.b64decode(mask), dtype=np.uint8), bitorder='little')
            assert np.array_equal(expected.flatten(), actual)
            frames[clip['id']].append(image)
            checked += 1
    for reference in references:
        assert (ROOT / reference).is_file(), reference
    for path in ROOT.glob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'))

    # Fixtures come from rendered alpha pixels, independently of JS hit-test math.
    foreground = Image.open(ROOT / data['backgrounds'][0]['foreground']).getchannel('A')
    solid_front = np.array(foreground.filter(ImageFilter.MinFilter(5))) == 255
    clear_front = np.array(foreground.filter(ImageFilter.MaxFilter(5))) == 0
    fixtures = []
    for index in range(9):
        for actor in data['actors']:
            sx, sy, sw, sh = actor['source']
            dx, dy, dw, dh = actor['destination']
            sprite = frames[actor['group']][index].crop((sx, sy, sx + sw, sy + sh))
            if actor['flipX']:
                sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            alpha = sprite.resize((dw, dh), Image.Resampling.NEAREST).getchannel('A')
            solid = np.array(alpha.filter(ImageFilter.MinFilter(5))) >= 24
            visible = solid.copy()
            if actor['z'] < data['foregroundZ']:
                visible &= clear_front[dy:dy+dh, dx:dx+dw]
            ys, xs = np.where(visible)
            assert len(xs), (actor['id'], index, 'no visible hit area')
            for sample in (0, len(xs)//2, len(xs)-1):
                fixtures.append({'frame': index, 'x': int(xs[sample]+dx)+0.5,
                                 'y': int(ys[sample]+dy)+0.5, 'expected': actor['id'], 'kind': 'visible'})
            fixtures.append({'frame': index, 'x': dx+0.5, 'y': dy+0.5,
                             'expected': None, 'kind': 'transparent padding'})
            if actor['id'] == 'merchant':
                hidden = solid & solid_front[dy:dy+dh, dx:dx+dw]
                ys, xs = np.where(hidden)
                assert len(xs), 'merchant must sit behind the stall'
                sample = len(xs)//2
                fixtures.append({'frame': index, 'x': int(xs[sample]+dx)+0.5,
                                 'y': int(ys[sample]+dy)+0.5, 'expected': None, 'kind': 'occluded merchant'})
    REPORT.mkdir(parents=True, exist_ok=True)
    (REPORT / 'hit-fixtures.json').write_text(json.dumps(fixtures), encoding='utf-8')
    result = {'status': 'PASS', 'source_hashes': checked, 'alpha_mask_pixels': 27*256*256,
              'foregrounds_exact_background_rgb': 4, 'local_links': len(references),
              'image_derived_hit_fixtures': len(fixtures), 'browser_tested': False}
    (REPORT / 'asset-validation.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
