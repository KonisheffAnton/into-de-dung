"""Validate preserved concept inputs and PNGs without altering image pixels."""
from pathlib import Path
from hashlib import sha256
import json
import re
from PIL import Image

root = Path(__file__).resolve().parent
brief = json.loads((root / 'brief.json').read_text(encoding='utf-8'))
assert brief['integration'] is False
rows = []
for hero in brief['characters']:
    prompt_path = root / 'prompts' / (hero['id'] + '.txt')
    prompt = prompt_path.read_text(encoding='utf-8')
    assert prompt == brief['common_prompt'] + '\n\n' + hero['prompt']
    assert len(prompt) <= 2000
    for provider in ['imagegen', 'pixellab']:
        path = root / provider / (hero['id'] + '.png')
        assert path.is_file(), path
        with Image.open(path) as im:
            im.load()
            assert im.format == 'PNG', path
            assert 'A' in im.getbands(), path
            alpha = im.getchannel('A')
            bbox = alpha.getbbox()
            assert bbox and alpha.getextrema()[0] == 0, path
            visible_bbox = alpha.point(lambda value: 255 if value > 8 else 0).getbbox()
            assert visible_bbox and visible_bbox[0] > 0 and visible_bbox[1] > 0 and visible_bbox[2] < im.width and visible_bbox[3] < im.height, (path, visible_bbox)
            border_alpha = max(alpha.crop(box).getextrema()[1] for box in [(0, 0, im.width, 1), (0, im.height - 1, im.width, im.height), (0, 0, 1, im.height), (im.width - 1, 0, im.width, im.height)])
            assert border_alpha <= 8, (path, border_alpha)
            rows.append({'provider': provider, 'character': hero['id'], 'file': path.relative_to(root).as_posix(), 'width': im.width, 'height': im.height, 'mode': im.mode, 'alpha_bbox': bbox, 'visible_alpha_gt8_bbox': visible_bbox, 'border_max_alpha': border_alpha, 'sha256': sha256(path.read_bytes()).hexdigest(), 'prompt_sha256': sha256(prompt_path.read_bytes()).hexdigest()})
refs = []
for path in sorted((root / 'references').glob('*.png')):
    with Image.open(path) as im:
        im.verify()
    refs.append({'file': path.relative_to(root).as_posix(), 'sha256': sha256(path.read_bytes()).hexdigest()})
html = (root / 'gallery.html').read_text(encoding='utf-8')
for link in re.findall(r'(?:href|src)="([^"#]+)"', html):
    if '${' in link or re.match(r'[a-z]+:', link):
        continue
    assert (root / link).is_file(), link
result = {'status': 'PASS', 'integration': False, 'image_count': len(rows), 'reference_count': len(refs), 'outputs': rows, 'references': refs, 'limits': ['Static file validation only; not animation/runtime acceptance.', 'Visible silhouette clipping check uses alpha>8; original faint alpha fringe is preserved and separately reported.', 'Visual comparison and provider consistency require human review.']}
(root / 'validation.json').write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
print(json.dumps({'status': result['status'], 'images': len(rows), 'references': len(refs), 'outputs': [{k:v for k,v in row.items() if k in ['provider','character','width','height','alpha_bbox']} for row in rows]}, ensure_ascii=False))
