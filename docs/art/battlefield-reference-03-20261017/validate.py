"""Проверяет комплект и побайтную сохранность PNG; изображения не изменяет."""
import hashlib
import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
ratings = json.loads((ROOT / 'ratings.json').read_text(encoding='utf-8'))
gallery = (ROOT / 'gallery.html').read_text(encoding='utf-8')
assert len(manifest['items']) == len(ratings['items']) == 15
results = []
for item, rating in zip(manifest['items'], ratings['items']):
    code = item['id']
    data = (ROOT / f'{code}.png').read_bytes()
    assert data == Path(item['source']).read_bytes(), code
    assert data[:8] == b'\x89PNG\r\n\x1a\n', code
    width, height = struct.unpack('>II', data[16:24])
    assert width > 0 and height > 0
    assert rating['id'] == code and 1 <= rating['score'] <= 10
    assert f'id="{code}"' in gallery and f'{code}.png' in gallery
    for reference in item['request']['referenced_image_paths']:
        assert Path(reference).is_file()
    results.append(dict(id=code, width=width, height=height,
                        color_type=data[25], sha256=hashlib.sha256(data).hexdigest(),
                        source_byte_exact=True))
for link in re.findall(r'(?:src|href)="([^"]+)"', gallery):
    assert (ROOT / link).is_file(), link
ref = ROOT / 'reference.png'
assert ref.read_bytes() == Path('C:/Users/Aston/AppData/Local/Temp/codex-clipboard-d9eb99a1-22f2-4dbc-9f8d-4e6d15bc8ab2.png').read_bytes()
menu = ROOT.parents[2] / 'scenes/demo/main_menu.tscn'
assert hashlib.sha256(menu.read_bytes()).hexdigest() == 'a64c270256ebf2ea073081200be23028f792f42c3ca98f83a6499c1300a68668'
report = dict(status='PASS', final_count=15, pixellab_calls=0, imagegen_calls=16,
              reference_byte_exact=True, main_menu_unchanged=True, outputs=results,
              scope='PNG signature/dimensions, byte equality, input paths, gallery links and score coverage; not geometry or animation validation')
(ROOT / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('PASS: 15 originals, input reference, gallery links, ratings, main_menu hash')
