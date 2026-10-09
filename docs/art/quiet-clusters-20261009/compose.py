"""Rebuild static comparisons from preserved provider outputs. Requires Pillow."""
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json
import hashlib

OUT = Path(__file__).resolve().parent
OLD = OUT.parent / 'defender-palette-20261009'
FIRST = OUT.parent / 'tiles-20261009'
BG, FG, MUTED = '#20272b', '#edf0e9', '#a6b0a7'
font = lambda size: ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf', size)
sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
cfg = json.loads((OUT / 'geometry.json').read_text())
checks = {'preview_only': True, 'top_size': [128, 96], 'tiles': [], 'characters': {}, 'placements': []}

tiles = {}
for key in 'HIJ':
    path = OUT / cfg['tiles'][key]['file']
    raw = Image.open(path).convert('RGBA')
    box = cfg['tiles'][key]['top_box']
    sx, sy = 128 / (box[2] - box[0]), 96 / (box[3] - box[1])
    im = raw.resize((round(raw.width * sx), round(raw.height * sy)), Image.Resampling.NEAREST)
    ox, oy = round(box[0] * sx), round(box[1] * sy)
    alpha = im.getchannel('A')
    for y in range(im.height):
        for x in range(im.width):
            if y - oy > 96 - .75 * abs(x - ox - 64) + 8:
                alpha.putpixel((x, y), 0)
    im.putalpha(alpha)
    tiles[key] = (im, ox, oy)
    im.save(OUT / f'tile-{key}-display.png')
    checks['tiles'].append({'id': key, 'file': path.name, 'sha256': sha(path), 'size': raw.size, 'top_box': box, 'scale_xy': [sx, sy]})

characters = {}
for key, spec in cfg['characters'].items():
    path = OUT / spec['file']
    raw = Image.open(path).convert('RGBA')
    box = raw.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
    assert box and box[0] > 0 and box[1] > 0 and box[2] < raw.width and box[3] < raw.height
    scale = 72 / (box[3] - box[1])
    sprite = raw.resize((round(raw.width * scale), round(raw.height * scale)), Image.Resampling.NEAREST)
    # После округления размеров реальный коэффициент чуть отличается от расчётного.
    actual = (sprite.width / raw.width, sprite.height / raw.height)
    anchor = tuple(sum(p[axis] for p in spec['feet']) / 2 for axis in (0, 1))
    characters[key] = (raw, box, sprite, anchor, actual)
    checks['characters'][key] = {'source': spec['file'], 'sha256': sha(path), 'size': raw.size, 'bbox': box, 'target_height': 72, 'rendered_alpha_height': sprite.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()[3] - sprite.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()[1], 'anchor': anchor, 'actual_scale_xy': actual}

original_layout = json.loads((FIRST / 'mixed-A50-CDE-layout.json').read_text())['layout_rows_y_columns_x']
counter = 0
layout = []
for row in original_layout:
    new_row = []
    for item in row:
        if item == 'A': new_row.append('H')
        else:
            new_row.append('I' if counter % 2 == 0 else 'J')
            counter += 1
    layout.append(new_row)
assert Counter(k for row in layout for k in row) == {'H': 18, 'I': 9, 'J': 9}
checks['mixed_layout'] = layout
checks['mixed_counts'] = dict(Counter(k for row in layout for k in row))

def field(name, title, grid, hero='soft'):
    canvas = Image.new('RGBA', (1100, 850), BG)
    d = ImageDraw.Draw(canvas)
    d.text((38, 24), title, font=font(29), fill=FG)
    d.text((38, 70), 'Ракурс 4:3  •  спокойные пятна  •  №4 в центре клетки', font=font(19), fill=MUTED)
    for x, y in sorted(((x, y) for x in range(6) for y in range(6)), key=sum):
        im, ox, oy = tiles[grid[y][x]]
        canvas.alpha_composite(im, (450 + (x-y)*64 - 64 - ox, 135 + (x+y)*48 - oy))
    raw, box, sprite, anchor, scale = characters[hero]
    foot = (450, 375)
    origin = tuple(round(foot[i] - anchor[i] * scale[i]) for i in (0, 1))
    error = [origin[i] + anchor[i] * scale[i] - foot[i] for i in (0, 1)]
    assert max(abs(v) for v in error) <= .5
    before = canvas.copy()
    layer = Image.new('RGBA', canvas.size)
    layer.alpha_composite(sprite, origin)
    canvas.alpha_composite(layer)
    diff = ImageChops.difference(before.convert('RGB'), canvas.convert('RGB'))
    outside = Image.new('RGB', canvas.size)
    outside.paste(diff, (0, 0), layer.getchannel('A').point(lambda a: 0 if a else 255))
    assert outside.getbbox() is None
    checks['placements'].append({'field': name, 'character': hero, 'cell': [2, 2], 'foot_canvas': foot, 'origin': origin, 'center_error': error, 'background_changes_outside_character': 0})
    # Справа отдельные крупные планы; они не подменяют проверку размера на поле.
    for n, k in enumerate('HIJ'):
        im = tiles[k][0]; crop = im.crop(im.getbbox())
        crop.thumbnail((110, 95), Image.Resampling.NEAREST)
        canvas.alpha_composite(crop, (907, 155 + n*127))
        d.text((1022, 174 + n*127), k, font=font(22), fill=FG)
    large = raw.crop(box)
    s = min(170 / large.width, 170 / large.height)
    large = large.resize((round(large.width*s), round(large.height*s)), Image.Resampling.NEAREST)
    canvas.alpha_composite(large, (890, 565))
    d.text((38, 771), 'Поле 6 × 6. Фигура около 72 px, одинаковая посадка по опорам ног.', font=font(18), fill=FG)
    note = {'soft': '№4: крупные плоскости / image_gen', 'clean': '№4: PixelLab 96 × 96 / упрощение', 'old': '№4: прежняя шумная версия / контроль'}[hero]
    d.text((38, 807), note + '   •   Справа — увеличение для деталей.', font=font(17), fill=MUTED)
    canvas.convert('RGB').save(OUT / f'{name}.png')
    return canvas

for key, title in [('H', 'Тихая земля'), ('I', 'Два пучка'), ('J', 'Трава у края')]:
    field(f'field-{key}', key + '  /  ' + title, [[key]*6 for _ in range(6)])
field('mixed-soft', 'Новая смесь  /  H + I + J', layout)
field('mixed-pixellab', 'Та же смесь  /  PixelLab 96 × 96', layout, 'clean')
field('mixed-old', 'Та же смесь  /  прежний солдат', layout, 'old')
overview = Image.new('RGB', (2200, 1700), BG)
for n, name in enumerate(['field-H', 'field-I', 'field-J', 'mixed-soft']):
    overview.paste(Image.open(OUT / f'{name}.png'), ((n%2)*1100, (n//2)*850))
overview.save(OUT / 'all-fields.png')

compare = Image.new('RGB', (1200, 650), BG); d = ImageDraw.Draw(compare)
d.text((35, 20), '№4  /  меньше дробных деталей, яснее основные формы', font=font(28), fill=FG)
for n, (key, title) in enumerate([('old', 'Прежде / 64 × 64'), ('clean', 'PixelLab / 96 × 96'), ('soft', 'Крупные плоскости / image_gen')]):
    raw, box, sprite, anchor, scale = characters[key]
    im = raw.crop(box); s = min(320/im.width, 340/im.height)
    im = im.resize((round(im.width*s), round(im.height*s)), Image.Resampling.NEAREST)
    compare.paste(im, (n*400 + (400-im.width)//2, 95), im)
    d.text((n*400+20, 458), title, font=font(21), fill=FG)
    # Одинаковая видимая высота и отдельная полоса игрового масштаба.
    bb = sprite.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
    small = sprite.crop(bb)
    compare.paste(small, (n*400 + (400-small.width)//2, 510), small)
d.text((35, 614), 'Нижний ряд — около 72 px: сравнивать читаемость здесь, а не только в увеличении.', font=font(18), fill=MUTED)
compare.save(OUT / 'soldier-comparison.png')

audit = Image.open(OUT / 'mixed-soft.png'); d = ImageDraw.Draw(audit)
d.line([(450,327),(514,375),(450,423),(386,375),(450,327)], fill='#d7c382', width=1)
d.line((446,375,454,375), fill='#fff1a2'); d.line((450,371,450,379), fill='#fff1a2')
audit.save(OUT / 'placement-check.png')
(OUT / 'checks.json').write_text(json.dumps(checks, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print('Built quiet fields, mixed layout, three-character comparison and placement check.')
