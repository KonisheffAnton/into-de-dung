"""Selection sheets only: source RGBA stays untouched; nearest-neighbour display."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent

def label(draw, xy, value, size=20, bold=False):
    font = ImageFont.truetype('C:/Windows/Fonts/segoeui' + ('b' if bold else '') + '.ttf', size)
    draw.text(xy, value, font=font, fill='#ded8c9')

def build(provider):
    pl = provider == 'pixellab'
    choices = json.loads((ROOT / 'selection.json').read_text())
    sheet = Image.new('RGBA', (1400, 740), '#202127')
    d = ImageDraw.Draw(sheet)
    label(d, (24, 16), 'PixelLab · ещё 10 вариантов' if pl else 'Мои · ещё 10 вариантов', 30, True)
    label(d, (24, 63), 'Короткие кости разных форм · низкие кучки · выбор перед внедрением')
    for i in range(10):
        name = f'PL{i+29}' if pl else f'G{i+21}'
        im = Image.open(ROOT / choices[name]).convert('RGBA')
        tile = Image.new('RGBA', (64, 64))
        if pl:
            assert im.size == (64, 64)
            tile.alpha_composite(im)
        else:
            box = im.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
            im = im.crop(box)
            im.thumbnail((48, 32), Image.Resampling.NEAREST)
            tile.alpha_composite(im, ((64-im.width)//2, (64-im.height)//2))
        cx, top = 140 + (i % 5)*280, 105 + (i // 5)*285
        label(d, (cx-32, top), name, 26, True)
        sheet.alpha_composite(tile.resize((256, 256), Image.Resampling.NEAREST), (cx-128, top+32))
    label(d, (24, 704), 'PixelLab 64×64 · увеличение ×4 · палитра до 8 цветов' if pl else
          'Крупные imagegen-концепты · nearest-превью, не готовые игровые спрайты', 18)
    sheet.convert('RGB').save(ROOT / (provider + '-ten.png'))

def candidates(folder='candidates'):
    paths = [ROOT/'pixellab'/folder/('image.png' if i == 0 else f'image-{i}.png') for i in range(16)]
    sheet = Image.new('RGBA', (960, 1000), '#202127')
    d = ImageDraw.Draw(sheet)
    for i, path in enumerate(paths):
        x, y = (i % 4)*240, (i // 4)*250
        label(d, (x+12, y+5), str(i), 23, True)
        im = Image.open(path).convert('RGBA')
        sheet.alpha_composite(im.resize((192, 192), Image.Resampling.NEAREST), (x+24, y+40))
    sheet.convert('RGB').save(ROOT/('pixellab-'+folder+'.png'))

if __name__ == '__main__':
    import sys
    for target in sys.argv[1:] or ['imagegen', 'pixellab']:
        candidates(target) if target in ('candidates', 'fragments') else build(target)
