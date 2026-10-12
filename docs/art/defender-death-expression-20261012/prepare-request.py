"""Prepare one masked PixelLab edit; original animation remains read-only."""
import base64
import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'defender-death-variants-20261012/03-last-knee/pixellab'
CROP = (32, 24, 96, 88)
# Рамки видимой кожи исключают шлем, перчатки, одежду и скрытое после падения лицо.
FACE_BOXES = {
    2: (64, 40, 74, 50), 3: (57, 46, 68, 56), 4: (57, 51, 67, 61),
    5: (57, 52, 67, 62), 6: (57, 50, 67, 60),
    **{i: (56, 49, 67, 59) for i in range(7, 16)},
    16: (56, 51, 67, 61), 17: (56, 55, 66, 65),
    18: (56, 61, 66, 71), 19: (55, 78, 65, 86),
}
sheet = Image.new('RGBA', (384, 192), (0, 0, 0, 0))
mask = Image.new('L', sheet.size, 0)
entries = []
for index, (number, face_box) in enumerate(FACE_BOXES.items()):
    path = SOURCE / f'frame-{number:02}.png'
    original = Image.open(path).convert('RGBA')
    cell = (index % 6 * 64, index // 6 * 64)
    sheet.paste(original.crop(CROP), cell)
    count = 0
    for y in range(face_box[1], face_box[3]):
        for x in range(face_box[0], face_box[2]):
            r, g, b, a = original.getpixel((x, y))
            if a == 255 and r > 65 and r > g * 1.25 and g > b * 1.15:
                mask.putpixel((cell[0] + x - CROP[0], cell[1] + y - CROP[1]), 255)
                count += 1
    assert 60 <= count <= 90, (number, count)
    entries.append({'frame': number, 'cell': list(cell), 'crop': list(CROP),
                    'face_box': list(face_box), 'mask_pixels': count,
                    'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
sheet.save(ROOT / 'sheet-input.png')
mask.save(ROOT / 'sheet-mask.png')


def encoded(path):
    return {'image': {'type': 'base64', 'base64': base64.b64encode(path.read_bytes()).decode(), 'format': 'png'},
            'size': {'width': 384, 'height': 192}}


request = {
    'description': (
        'This image is a six-column, three-row sprite contact sheet showing 18 consecutive crops of the SAME '
        'helmeted defender dying. Edit ONLY the small masked exposed facial skin in every cell. '
        'Give him a clearly readable restrained grimace of PAIN AND EFFORT: eyes squeezed shut, '
        'brows tensed downward beneath the helmet, mouth tightly clenched into an asymmetric strained grimace '
        'with a tiny pale teeth line inside a dark mouth shape. The jaw is tense, never smiling. '
        'The face is only about ten pixels wide, so use a few LARGE simple pixel clusters; no added detail '
        'or tiny wrinkles. Preserve the existing skin palette and native pixel size exactly. '
        'Keep a coherent painful expression across the held kneeling poses, no mouth flicker or alternating expressions. '
        'Keep the identical head position, tilt, helmet, silhouette and all unmasked pixels of each cell. '
        'Do not move or rescale any frame or redraw the animation. No blood, tears, flashes, particles, '
        'text, added hair or new accessories. This is a serious death grimace, not a comic shouting face.'
    ),
    'inpainting_image': encoded(ROOT / 'sheet-input.png'),
    'mask_image': encoded(ROOT / 'sheet-mask.png'),
    'seed': 20261023, 'no_background': False, 'crop_to_mask': False,
}
assert len(request['description']) <= 2000
target = ROOT / 'pixellab'
target.mkdir(exist_ok=True)
payload = json.dumps(request, ensure_ascii=False, indent=2) + '\n'
request_path = target / 'request.json'
assert not request_path.exists() or request_path.read_text(encoding='utf-8') == payload
request_path.write_text(payload, encoding='utf-8', newline='\n')
manifest = {
    'endpoint': 'https://api.pixellab.ai/v2/inpaint-v3',
    'schema_verified': '2026-10-12 https://api.pixellab.ai/v2/openapi.json',
    'source_animation': '../defender-death-variants-20261012/03-last-knee/pixellab',
    'scope': 'Face-only expression revision of selected motion03; no integration into the game.',
    'request_sha256': hashlib.sha256(payload.encode()).hexdigest(),
    'sheet_size': list(sheet.size), 'entries': entries,
    'composition': 'Only provider RGB inside the saved skin mask; retain original alpha and every outside pixel.',
    'description': request['description'],
}
(ROOT / 'request-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'frames_to_edit': len(entries), 'masked_pixels': sum(e['mask_pixels'] for e in entries),
                  'size': list(sheet.size), 'description_length': len(request['description'])}))
