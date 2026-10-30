"""Пять контрольных поз на клип для визуальной проверки всей серии."""
from pathlib import Path
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parent
for id in ('02','05','11','12','17','18'):
    sheet=Image.new('RGB',(640,9*154),'#182131');draw=ImageDraw.Draw(sheet)
    for row,(kind,v) in enumerate((k,v) for k in ('idle','death','ability') for v in (1,2,3)):
        path=ROOT/'pixellab'/f'{id}-{kind}-{v}'/'filmstrip.png'
        draw.text((8,row*154+4),f'{id} / {kind} / {v}',fill='white')
        if path.exists():sheet.paste(Image.open(path).resize((640,128),Image.Resampling.NEAREST),(0,row*154+22))
        else:draw.text((8,row*154+55),'Pending',fill='#eac179')
    sheet.save(ROOT/f'contact-{id}.png')
print('Six contact sheets written')
ids=('02','05','11','12','17','18')
folders=[ROOT/'pixellab'/f'{id}-idle-1' for id in ids]
if all((p/'frames/frame-32.png').exists() for p in folders):
    frames=[]
    for i in range(33):
        sheet=Image.new('RGB',(768,564),'#182131');draw=ImageDraw.Draw(sheet)
        for index,(id,p) in enumerate(zip(ids,folders)):
            im=Image.open(p/'frames'/f'frame-{i:02}.png').convert('RGBA')
            x=(index%3)*256;y=(index//3)*282
            sheet.paste(im,(x,y),im);draw.text((x+12,y+258),id+' / idle 1',fill='white')
        frames.append(sheet)
    frames[0].save(ROOT/'idle-overview.gif',save_all=True,append_images=frames[1:],duration=90,loop=0,disposal=2)
    print('Six-warrior idle GIF written')
