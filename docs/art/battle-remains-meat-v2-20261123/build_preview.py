"""Native PixelLab pixels, before/after at integer x4; source PNGs untouched."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / 'battle-remains-variants-20261122' / 'pixellab'
sheet = Image.new('RGBA', (1000, 750), (31,33,40,255))
draw = ImageDraw.Draw(sheet)


def label(position, value, size=22, color='#d8d6ce', bold=False):
    draw.text(position, value, fill=color,
        font=ImageFont.truetype('C:/Windows/Fonts/segoeui' + ('b' if bold else '') + '.ttf', size))


label((28,16), 'PixelLab · чуть больше мяса', 30, bold=True)
label((28,61), 'Универсальные свежие останки · исходные пиксели ×4', 19, '#a3a5ad')
for index in range(1,4):
    center = 170 + (index-1)*330
    label((center-31,101), f'PL{index}', 24, bold=True)
    old = Image.open(PREVIOUS / f'PL-F{index}' / 'image.png').convert('RGBA')
    new = Image.open(ROOT / f'PL-F{index}' / 'image.png').convert('RGBA')
    assert old.size == new.size == (64,64)
    bounds = [im.getchannel('A').getbbox() for im in (old,new)]
    box = (min(b[0] for b in bounds), min(b[1] for b in bounds),max(b[2] for b in bounds),max(b[3] for b in bounds))
    for row, im in enumerate((old,new)):
        part = im.crop(box)
        part = part.resize((part.width*4,part.height*4),Image.Resampling.NEAREST)
        y = 255 + row*310
        sheet.alpha_composite(part,(center-part.width//2,y-part.height//2))
        label((center-105,y+128),'Было' if row==0 else 'Стало · больше мяса',20,'#a7a7ae' if row==0 else '#d2b0ad')
sheet.convert('RGB').save(ROOT/'before-after.png')
print('Saved native x4 before/after comparison')
