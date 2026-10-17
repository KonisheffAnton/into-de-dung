"""Проверяет комплект PNG и происхождение; не редактирует изображения."""
import hashlib
import json
import re
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent
manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
ratings = json.loads((ROOT / 'ratings.json').read_text(encoding='utf-8'))
gallery = (ROOT / 'gallery.html').read_text(encoding='utf-8')
expected = [f'G{i:02d}' for i in range(1, 11)] + ['M01', 'M02']
assert [x['id'] for x in manifest['items']] == expected
assert [x['id'] for x in ratings['items']] == expected
outputs, inputs = [], {}
for item, rating in zip(manifest['items'], ratings['items']):
    code = item['id']
    data = (ROOT / f'{code}.png').read_bytes()
    assert data == Path(item['source']).read_bytes(), code
    assert data[:8] == b'\x89PNG\r\n\x1a\n', code
    width, height = struct.unpack('>II', data[16:24])
    assert width > 0 and height > 0
    pos = 8
    while pos < len(data):
        length = struct.unpack('>I', data[pos:pos + 4])[0]
        chunk = data[pos + 4:pos + 8 + length]
        crc = struct.unpack('>I', data[pos + 8 + length:pos + 12 + length])[0]
        assert zlib.crc32(chunk) & 0xffffffff == crc, code
        pos += length + 12
    assert pos == len(data)
    assert 1 <= rating['score'] <= 10 and rating['reason']
    assert f'{code}.png' in gallery
    for ref in item['request']['referenced_image_paths']:
        snapshot = item.get('input_snapshots', {}).get(ref, ref)
        inputs[snapshot] = hashlib.sha256(Path(snapshot).read_bytes()).hexdigest()
    outputs.append(dict(id=code, width=width, height=height, color_type=data[25],
                        sha256=hashlib.sha256(data).hexdigest(), source_byte_exact=True))
for link in re.findall(r'(?:src|href)="([^"]+)"', gallery):
    assert (ROOT / link).is_file(), link
assert (ROOT / 'reference.png').read_bytes() == Path('C:/Users/Aston/AppData/Local/Temp/codex-clipboard-1f1cdd9f-9afa-48c2-b9b8-8218b90ab515.png').read_bytes()
assert (ROOT / 'monster-reference.png').read_bytes() == Path('C:/Users/Aston/AppData/Local/Temp/codex-clipboard-df447b29-a9ab-4f8d-b23b-c5e7346898ac.png').read_bytes()
assert hashlib.sha256((ROOT.parents[2] / 'scenes/demo/main_menu.tscn').read_bytes()).hexdigest() == 'a64c270256ebf2ea073081200be23028f792f42c3ca98f83a6499c1300a68668'
report = dict(status='PASS', output_count=12, imagegen_calls=20, pixellab_calls=0,
              references_byte_exact=True, main_menu_unchanged=True, inputs=inputs, outputs=outputs,
              scope='PNG dimensions/chunk CRC/SHA/source bytes, reference bytes, gallery links, rating coverage; excludes geometry, anchors and animation tests')
(ROOT / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('PASS: 12 PNGs, source bytes, reference bytes, links, ratings and main_menu hash')
