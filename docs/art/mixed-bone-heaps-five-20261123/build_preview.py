"""Package provider images only; no repainting. Native PL x4, G concept thumbnails."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
BG = (31,33,40,255)
def label(draw, point, value, size=23, color='#d8d6ce', bold=False):
    draw.text(point, value, font=ImageFont.truetype('C:/Windows/Fonts/segoeui'+('b' if bold else '')+'.ttf',size),fill=color)

def build(provider):
    sheet = Image.new('RGBA',(1400,420),BG)
    draw = ImageDraw.Draw(sheet)
    is_pl = provider == 'pixellab'
    label(draw,(24,17),'PixelLab · PL9–PL13' if is_pl else 'Мои варианты · G1–G5',30,bold=True)
    label(draw,(24,64),'Разные формы костей внутри одной кучки',22,color='#b7b5ad')
    label(draw,(24,386),'64×64 · увеличение ×4 без сглаживания' if is_pl else 'Концепты imagegen · уменьшенные превью, увеличение без сглаживания',18,color='#989ba5')
    for i in range(5):
        identifier = f'PL{i+9}' if is_pl else f'G{i+1}'
        source_id = 'PL11-clean' if identifier == 'PL11' else identifier
        source = ROOT/'pixellab'/source_id/'image.png' if is_pl else ROOT/'imagegen'/(identifier+'.png')
        im = Image.open(source).convert('RGBA')
        if not is_pl:
            # Alpha threshold only finds framing bounds; original RGB/alpha are preserved.
            box = im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
            tile = Image.new('RGBA',(64,64))
            crop = im.crop(box)
            crop.thumbnail((54,39),Image.Resampling.NEAREST)
            tile.alpha_composite(crop,((64-crop.width)//2,(64-crop.height)//2))
            im = tile
        assert im.size == (64,64)
        cx = 140 + 280*i
        label(draw,(cx-32,107),identifier,26,bold=True)
        sheet.alpha_composite(im.resize((256,256),Image.Resampling.NEAREST),(cx-128,133))
    sheet.convert('RGB').save(ROOT/(provider+'-five.png'))

if __name__ == '__main__':
    build('pixellab')
    build('imagegen')
