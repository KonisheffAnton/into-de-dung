"""Comparison packaging only, nearest scaling, no local repainting."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parent
def text(draw,point,value,size=22,bold=False):
    draw.text(point,value,font=ImageFont.truetype('C:/Windows/Fonts/segoeui'+('b' if bold else '')+'.ttf',size),fill='#d8d6ce')
def build(provider):
    pl=provider=='pixellab'
    sheet=Image.new('RGBA',(1400,420),(31,33,40,255))
    draw=ImageDraw.Draw(sheet)
    text(draw,(24,17),'PixelLab · PL14–PL18' if pl else 'Мои варианты · G6–G10',30,True)
    text(draw,(24,64),'Более мелкие кости внутри кучки')
    for i in range(5):
        name=f'PL{i+14}' if pl else f'G{i+6}'
        path=ROOT/'pixellab'/(name+'-adapt')/'image.png' if pl else ROOT/'imagegen'/(name+'.png')
        im=Image.open(path).convert('RGBA')
        if not pl:
            box=im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
            crop=im.crop(box)
            crop.thumbnail((54,39),Image.Resampling.NEAREST)
            im=Image.new('RGBA',(64,64))
            im.alpha_composite(crop,((64-crop.width)//2,(64-crop.height)//2))
            (ROOT/'provider-inputs').mkdir(exist_ok=True)
            im.save(ROOT/'provider-inputs'/(name+'.png'))
        assert im.size==(64,64)
        cx=140+i*280
        text(draw,(cx-32,107),name,26,True)
        sheet.alpha_composite(im.resize((256,256),Image.Resampling.NEAREST),(cx-128,133))
    text(draw,(24,386),'64×64 · увеличение ×4 без сглаживания' if pl else 'Концепты imagegen · превью в прежнем масштабе, без сглаживания',18)
    sheet.convert('RGB').save(ROOT/(provider+'-five.png'))
if __name__=='__main__':
    import sys
    for provider in sys.argv[1:] or ['imagegen','pixellab']: build(provider)
