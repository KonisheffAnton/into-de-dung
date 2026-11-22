"""Two independent ten-variant sheets. Packaging only, no local repainting."""
from pathlib import Path
import json
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parent
def text(d,xy,value,size=20,bold=False):
    d.text(xy,value,font=ImageFont.truetype('C:/Windows/Fonts/segoeui'+('b' if bold else '')+'.ttf',size),fill='#d8d6ce')
def build(provider):
    pl=provider=='pixellab'
    selection=json.loads((ROOT/'selection.json').read_text())
    sheet=Image.new('RGBA',(1400,740),(31,33,40,255)); d=ImageDraw.Draw(sheet)
    text(d,(24,16),'PixelLab · 10 самостоятельных вариантов' if pl else 'Мои · 10 новых вариантов',30,True)
    text(d,(24,63),'Мелкие кости разных форм · одна низкая кучка · варианты для выбора')
    for i in range(10):
        name=f'PL{i+19}' if pl else f'G{i+11}'
        path=ROOT/selection[name]
        im=Image.open(path).convert('RGBA')
        tile=Image.new('RGBA',(64,64))
        if pl:
            assert im.size==(64,64)
            tile.alpha_composite(im,(0,0))
        else:
            box=im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
            im=im.crop(box); im.thumbnail((48,32),Image.Resampling.NEAREST)
            tile.alpha_composite(im,((64-im.width)//2,(64-im.height)//2))
        cx=140+(i%5)*280; top=105+(i//5)*285
        text(d,(cx-32,top),name,26,True)
        sheet.alpha_composite(tile.resize((256,256),Image.Resampling.NEAREST),(cx-128,top+32))
    text(d,(24,704),'PixelLab 64×64 · увеличение ×4 · 8 цветов' if pl else 'Крупные imagegen-концепты · nearest-превью, не готовые игровые спрайты',18)
    sheet.convert('RGB').save(ROOT/(provider+'-ten.png'))
if __name__=='__main__':
    import sys
    for provider in sys.argv[1:] or ['imagegen','pixellab']: build(provider)
