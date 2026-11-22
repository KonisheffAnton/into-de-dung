"""Comparison layout only: originals are preserved, nearest-neighbour thumbnails."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import json

ROOT = Path(__file__).resolve().parent
BG = (31, 33, 40, 255)
FONT = 'C:/Windows/Fonts/segoeui.ttf'
BOLD = 'C:/Windows/Fonts/segoeuib.ttf'


def text(draw, point, value, size=21, fill='#d8d6ce', bold=False):
    draw.text(point, value, font=ImageFont.truetype(BOLD if bold else FONT, size), fill=fill)


def build(provider):
    sheet = Image.new('RGBA', (1000, 670), BG)
    draw = ImageDraw.Draw(sheet)
    text(draw, (28, 16), ('G · Imagegen' if provider == 'G' else 'PL · PixelLab') + ' — универсальные останки', 29, bold=True)
    text(draw, (28, 61), 'Без черепов и узнаваемой анатомии · три парных варианта', 19, '#a3a5ad')
    metrics = []
    for index, title in enumerate(['Перекрещенные', 'Россыпь', 'Кучка'], 1):
        x = 170 + (index - 1) * 330
        text(draw, (x - 116, 100), f'{provider}{index} · {title}', 22, bold=True)
        pair = []
        for kind in ['F', 'B']:
            path = ROOT / ('imagegen' if provider == 'G' else 'pixellab')
            path = path / (f'{provider}-{kind}{index}.png' if provider == 'G' else f'{provider}-{kind}{index}/image.png')
            pair.append(Image.open(path).convert('RGBA'))
        # Общий bbox пары сохраняет взаимное положение свежего и сухого состояния.
        # Почти невидимые alpha-следы генератора не должны уменьшать предмет в сравнении.
        # Порог определяет только рамку превью; RGBA оригиналов и вырезки не меняется.
        bounds = [im.getchannel('A').point(lambda value: 255 if value >= 128 else 0).getbbox() for im in pair]
        box = (min(b[0] for b in bounds), min(b[1] for b in bounds), max(b[2] for b in bounds), max(b[3] for b in bounds))
        ratio = min(54 / (box[2]-box[0]), 38 / (box[3]-box[1]))
        size = (max(1, round((box[2]-box[0])*ratio)), max(1, round((box[3]-box[1])*ratio)))
        for row, (kind, im) in enumerate(zip(['F', 'B'], pair)):
            stamp = im.crop(box).resize(size, Image.Resampling.NEAREST)
            canvas = Image.new('RGBA', (64, 64))
            canvas.alpha_composite(stamp, ((64-size[0])//2, (64-size[1])//2))
            baseline = 267 + row * 269
            preview = canvas.resize((256, 256), Image.Resampling.NEAREST)
            sheet.alpha_composite(preview, (x-128, baseline-128))
            label = 'Свежие · кости с мясом' if kind == 'F' else 'Голые кости'
            text(draw, (x-119, baseline+91), label, 19, '#c7a3a3' if kind == 'F' else '#c5c0b3')
            metrics.append({'id':f'{provider}-{kind}{index}', 'raw_size':list(im.size), 'alpha_extrema':list(im.getchannel('A').getextrema()),
                'raw_bounds':list(im.getchannel('A').getbbox()), 'display_size':list(size), 'display_only':True})
    sheet.convert('RGB').save(ROOT / f'{provider.lower()}-comparison.png')
    return metrics


if __name__ == '__main__':
    records = []
    for provider in ['G', 'PL']:
        if provider == 'PL' and not all((ROOT / 'pixellab' / f'PL-F{i}' / 'image.png').exists() for i in range(1,4)): continue
        records.extend(build(provider))
    (ROOT / 'image-check.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Previewed',len(records),'images; original PNGs unchanged')
