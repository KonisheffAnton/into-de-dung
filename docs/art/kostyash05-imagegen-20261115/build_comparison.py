"""Собирает только презентационный лист; PNG генератора не изменяется."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (24, 33, 49, 255)
BASELINE = 544
HERO_HEIGHT = 456
KOSTYASH_HEIGHT = 304


def main():
    raw = ROOT / 'kostyash05-developed.png'
    before = hashlib.sha256(raw.read_bytes()).hexdigest()
    sheet = Image.new('RGBA', (1320, 648), BG)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 25)
    small = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 19)
    draw.text((28, 18), 'Костяш №5 · рост в 1,5 раза меньше героев', font=font, fill='#f4d18e')
    draw.text((28, 53), 'Герой : Костяш = 3 : 2  ·  одинаковая линия земли', font=small, fill='#c8d2dd')
    draw.line((28, BASELINE, 1292, BASELINE), fill='#4e6179', width=1)
    records = []
    specs = [('Воин', 'references/warrior11.png', HERO_HEIGHT, 220),
             ('Костяш №5', raw.name, KOSTYASH_HEIGHT, 660),
             ('Маг', 'references/mage02.png', HERO_HEIGHT, 1100)]
    for name, file, display_height, center in specs:
        image = Image.open(ROOT / file).convert('RGBA')
        # Едва видимый alpha1–7 шум вокруг крупной выдачи не задаёт рост тела.
        box = image.getchannel('A').point(lambda a: 255 if a >= 8 else 0).getbbox()
        padded = (max(0,box[0]-4),max(0,box[1]-4),min(image.width,box[2]+4),min(image.height,box[3]+4))
        crop = image.crop(padded)
        native_height = box[3]-box[1]
        preferred_height = round(crop.height * display_height/native_height)
        presentation = None
        for target_h in sorted(range(preferred_height-3,preferred_height+4), key=lambda h:abs(h-preferred_height)):
            target_w = round(crop.width * target_h/crop.height)
            candidate = crop.resize((target_w,target_h), Image.Resampling.NEAREST)
            visible = candidate.getchannel('A').point(lambda a: 255 if a >= 8 else 0).getbbox()
            if visible[3]-visible[1] == display_height:
                presentation = candidate
                break
        assert presentation is not None
        display_width = visible[2]-visible[0]
        x, y = center - (visible[0]+visible[2])//2, BASELINE-visible[3]
        assert 0 <= x and x + presentation.width < sheet.width and y + visible[1] >= 80
        sheet.alpha_composite(presentation, (x, y))
        draw.text((center, 570), name, font=font, fill='#f4d18e', anchor='mt')
        logical = '152 px эталона' if display_height == HERO_HEIGHT else '101⅓ px в масштабе эталона'
        draw.text((center, 606), logical, font=small, fill='#c8d2dd', anchor='mt')
        records.append(dict(name=name, file=file, native_bbox=list(box),
            visible_native_height=native_height, visible_alpha_threshold=8, display_width=display_width,
            display_height=display_height, display_top=y+visible[1], display_bottom=y+visible[3],
            scale=display_height/native_height))
    sheet.convert('RGB').save(ROOT / 'hero-scale-comparison.png')
    assert HERO_HEIGHT / KOSTYASH_HEIGHT == 1.5
    assert hashlib.sha256(raw.read_bytes()).hexdigest() == before
    report = dict(complete=True, ratio_hero_to_kostyash=1.5,
        hero_display_height=HERO_HEIGHT, kostyash_display_height=KOSTYASH_HEIGHT,
        logical_hero_height=152, logical_kostyash_height=152/1.5,
        same_baseline=BASELINE, nearest_neighbor_presentation_only=True,
        original_generated_png_unchanged=True, records=records,
        scope='Static comparison of canonical stills, not runtime ArtRoot or native sprite dimensions')
    (ROOT / 'scale-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
