"""Selection sheet, native pixels enlarged x3 with no smoothing."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
sheet=Image.new('RGBA',(1100,395),(31,33,40,255))
draw=ImageDraw.Draw(sheet)
def text(point,value,size=20,color='#d8d6ce',bold=False):
    draw.text(point,value,font=ImageFont.truetype('C:/Windows/Fonts/segoeui'+('b' if bold else '')+'.ttf',size),fill=color)
text((25,18),'PixelLab · пять новых вариантов костей',29,bold=True)
text((25,62),'Разные силуэты и раскладка · без черепа и высокой костяной пластины',19,'#a3a5ad')
names=['Свободная россыпь','Длинные обломки','Дуга','Две кучки','Плотная кучка']
sources=['B1','B2-v2','B3-v2','B4-clean','B5-v2']
for i in range(1,6):
    im=Image.open(ROOT/sources[i-1]/'image.png').convert('RGBA')
    assert im.size==(64,64)
    large=im.resize((192,192),Image.Resampling.NEAREST)
    x=110+(i-1)*220
    text((x-28,109),f'PL{i+3}',24,bold=True)
    sheet.alpha_composite(large,(x-96,140))
    name=names[i-1];font=ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',18)
    width=draw.textlength(name,font=font)
    draw.text((x-width/2,343),name,font=font,fill='#bab8b1')
sheet.convert('RGB').save(ROOT/'five-bones.png')
print('Saved 5 variants at native x3')
