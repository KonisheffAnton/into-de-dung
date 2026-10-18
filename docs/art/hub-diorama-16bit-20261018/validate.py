"""Read-only checks for art copies, selected GIFs, gallery links and provenance."""
import argparse
import ast
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.paths = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('src', 'href', 'data-source', 'data-output') and value:
                if not value.startswith(('http:', 'https:', 'data:', '#')):
                    self.paths.append(value)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    outputs = json.loads((ROOT / 'imagegen-manifest.json').read_text(encoding='utf-8'))['outputs']
    prompts = json.loads((ROOT / 'imagegen-prompts.json').read_text(encoding='utf-8'))
    assert prompts['tool'] == 'built-in image_gen' and not prompts['transparent_background']
    assert len(outputs) == len(sources) == len(prompts['variants']) == 2
    for source, result, prompt in zip(sources, outputs, prompts['variants']):
        assert source['label'] == result['label'] == prompt['label']
        assert sha(ROOT / source['file']) == sha(REPO / source['source']) == source['sha256']
        assert result['reference'] == source['file']
        assert sha(ROOT / result['file']) == sha(Path(result['original_output_path'])) == result['sha256']
        with Image.open(ROOT / result['file']) as image:
            image.load()
            assert list(image.size) == source['size'] == result['size'] == [1672, 941]
            assert image.convert('RGBA').getchannel('A').getextrema() == (255, 255)
    selected = json.loads((ROOT / 'selected-animations.json').read_text(encoding='utf-8'))
    assert [(item['role'], item['variant']) for item in selected] == [('crowd', 2), ('market', 5), ('smith', 3)]
    for item in selected:
        path = REPO / item['path']
        assert sha(path) == item['sha256']
        with Image.open(path) as image:
            assert image.n_frames > 1 and image.info.get('loop') == 0
            for frame in range(image.n_frames):
                image.seek(frame)
                image.load()
    previous = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    assert not previous['pending'] and len(previous['outputs']) == 2
    for item in previous['outputs']:
        assert sha(ROOT / item['file']) == item['sha256']
    links = Links()
    links.feed((ROOT / 'gallery.html').read_text(encoding='utf-8'))
    for link in links.paths:
        assert (ROOT / link).is_file(), link
    for path in ROOT.glob('*.py'):
        ast.parse(path.read_text(encoding='utf-8'))
    result = {'status': 'PASS', 'source_copies': 2, 'imagegen_output_copies': 2,
              'imagegen_prompts': 2, 'imagegen_size': [1672, 941], 'opaque_outputs': True,
              'selected_unchanged_animations': 'crowd02 / market05 / latest smith03',
              'gif_decodes': 3, 'previous_pixellab_outputs': 2,
              'gallery_local_links': len(links.paths), 'python_ast': 'PASS',
              'limits': 'Static provenance/file checks; not browser/Godot testing, measured pixel grid or final art acceptance.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
