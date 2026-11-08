"""Compose a color-edit comparison using unchanged A icons and the previous layout."""
import hashlib
import json
from pathlib import Path
import types
from PIL import Image, ImageDraw

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
PREVIOUS = ROOT / 'docs/art/status-hover-five-concepts-20261108'
source = PREVIOUS / 'build_preview.py'
layout = types.ModuleType('hover_concept_layout')
layout.__file__ = str(source)
exec(compile(source.read_text(encoding='utf-8'), str(source), 'exec'), layout.__dict__)
layout.OUT = OUT
NN = Image.Resampling.NEAREST


def build():
    # Keep the original next to the edit for byte-verifiable comparisons.
    (OUT / 'before.png').write_bytes((PREVIOUS / '04-bronze.png').read_bytes())
    sheet = Image.new('RGB',(1320,640),'#171b1c')
    draw=ImageDraw.Draw(sheet)
    layout.text(draw,(30,24),'№4 · ЦВЕТ И ЧИТАЕМОСТЬ',30,bold=True)
    layout.text(draw,(30,68),'Та же компактная форма · нейтральная середина · приглушённая бронза',21,'#a9b2b0')
    columns=[(440,1),(715,3),(1080,6)]
    for x,n in columns:
        layout.text(draw,(x-56,115),{1:'1 эффект',3:'3 эффекта',6:'6 эффектов'}[n],22,bold=True)
    battle=Image.open(layout.BATTLE).convert('RGBA')
    tile=battle.crop((730,276,842,318)).resize((448,168),NN)
    for row,(slug,title,subtitle) in enumerate([('before','БЫЛО','Зеленоватый фон'),('after','СТАЛО','Нейтральный серый')]):
        y=158+row*180
        draw.rounded_rectangle((20,y,1300,y+159),radius=5,fill='#202728')
        layout.text(draw,(38,y+39),title,26,'#d7b777',True)
        layout.text(draw,(38,y+79),subtitle,18,'#a9b2b0')
        for x,n in columns:
            panel,_=layout.sample(slug,n)
            display=panel.resize((panel.width*4,128),NN)
            field_width=display.width+8
            field=tile.crop(((448-field_width)//2,0,(448+field_width)//2,128)).copy()
            field.alpha_composite(display,(4,0))
            sheet.paste(field.convert('RGB'),(x-field_width//2,y+14))
    layout.text(draw,(30,532),'Значки A16 и числа10px прежние; нахлёст0/2/4px. Увеличение ×4 без сглаживания.',19,'#a9b2b0')
    layout.text(draw,(30,575),'Базовый размер:',18,'#a9b2b0')
    for x,slug in [(230,'before'),(520,'after')]:
        layout.text(draw,(x,575),'Было' if slug=='before' else 'Стало',18)
        panel,_=layout.sample(slug,6)
        sheet.paste(panel,(x+70,568),panel)
    layout.text(draw,(30,612),'Макет для выбора цвета, не новый кадр runtime.',16,'#85928f')
    sheet.save(OUT/'comparison.png')

    context=Image.new('RGB',(760,510),'#171b1c')
    draw=ImageDraw.Draw(context)
    layout.text(draw,(25,21),'№4 НАД ПЕРСОНАЖЕМ',25,bold=True)
    layout.text(draw,(25,60),'Макет поверх прежнего кадра · увеличение ×2',18,'#a9b2b0')
    for x,slug in [(70,'before'),(430,'after')]:
        field=battle.crop((575,297,705,467)).copy()
        panel,_=layout.sample(slug,6)
        field.alpha_composite(panel,((130-panel.width)//2,8))
        context.paste(field.resize((260,340),NN).convert('RGB'),(x,110))
        layout.text(draw,(x,465),'Было' if slug=='before' else 'Стало',22,bold=True)
    context.save(OUT/'character-comparison.png')

    icons=sorted(layout.ICONS.glob('*.png'))
    catalogue=Image.new('RGB',(1056,686),'#171b1c')
    draw=ImageDraw.Draw(catalogue)
    layout.text(draw,(24,20),'ПРОВЕРКА ВСЕХ 24 МОТИВОВ A',26,bold=True)
    layout.text(draw,(24,59),'Новый цвет подложки · значки 16px ×4 · без нахлёста и без счётчиков',18,'#a9b2b0')
    for index,icon in enumerate(icons):
        x=16+(index%6)*174
        y=100+(index//6)*144
        panel=layout.backing('after',40)
        panel.alpha_composite(Image.open(icon).convert('RGBA'),(12,8))
        catalogue.paste(panel.resize((160,128),NN),(x,y),panel.resize((160,128),NN))
        layout.text(draw,(x+3,y+120),icon.stem,15,'#dad9ce')
    catalogue.save(OUT/'all-icons.png')
    inputs=[PREVIOUS/'04-bronze.png',source,OUT/'after.png',layout.BATTLE]
    inputs += list(icons)+[ROOT/'assets/ui/combat_fonts/jersey20_numbers.ttf',ROOT/'assets/ui/combat_fonts/combat_letters.ttf']
    manifest=dict(kind='color proposal; runtime unchanged',source_hashes={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},
                  icon_size=16,counter_size=10,counts=[1,3,6],overlap=[0,2,4],widths=[40,68,100],native_sheet='comparison.png bottom row',catalogue_count=len(icons))
    (OUT/'layout.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Built comparison, character-comparison, all-icons and6 samples.')


if __name__=='__main__':
    build()
