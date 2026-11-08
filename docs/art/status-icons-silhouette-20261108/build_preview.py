"""Mechanical previews of native PixelLab16 icons on the selected compact backing."""
import hashlib
import json
from pathlib import Path
import types
from PIL import Image, ImageDraw

OUT=Path(__file__).resolve().parent
ROOT=OUT.parents[2]
SOURCE_BUILDER=ROOT/'docs/art/status-hover-five-concepts-20261108/build_preview.py'
PANEL=ROOT/'docs/art/status-hover04-color-20261108/after.png'
OLD_ICONS=ROOT/'assets/art_presets/approved/status_icons_a_v1/16'
ITEMS=json.loads((OUT/'symbols.json').read_text(encoding='utf-8'))
layout=types.ModuleType('old_layout')
layout.__file__=str(SOURCE_BUILDER)
exec(compile(SOURCE_BUILDER.read_text(encoding='utf-8'),str(SOURCE_BUILDER),'exec'),layout.__dict__)
layout.OUT=OUT
NN=Image.Resampling.NEAREST


def icon_panel(icon_path):
    result=layout.backing('panel',40)
    result.alpha_composite(Image.open(icon_path).convert('RGBA'),(12,8))
    return result


def row(icon_root,count,counters,backing=True):
    overlap={1:0,3:2,6:4}[count]
    stride=16-overlap
    width=40+(count-1)*stride
    result=layout.backing('panel',width) if backing else Image.new('RGBA',(width,32))
    for index,(slug,_,_) in enumerate(layout.SAMPLES[:count]):
        result.alpha_composite(Image.open(icon_root/f'{slug}.png').convert('RGBA'),(12+index*stride,8))
    if counters:
        draw=ImageDraw.Draw(result)
        draw.fontmode='1'
        for index,(_,stacks,ticks) in enumerate(layout.SAMPLES[:count]):
            x=12+index*stride
            if stacks:
                draw.text((x+1,7),'×',font=layout.LETTERS,fill='#fff0be',stroke_width=1,stroke_fill='#171514')
                draw.text((x+1+round(layout.LETTERS.getlength('×')),7),str(stacks),font=layout.COUNTER,
                          fill='#fff0be',stroke_width=1,stroke_fill='#171514')
            value=str(ticks)
            draw.text((x+15-round(draw.textlength(value,font=layout.COUNTER)),16),value,
                      font=layout.COUNTER,fill='#f1eee4',stroke_width=1,stroke_fill='#171514')
    return result


def build():
    (OUT/'panel.png').write_bytes(PANEL.read_bytes())
    sheet=Image.new('RGB',(1120,1020),'#171b1c')
    draw=ImageDraw.Draw(sheet)
    layout.text(draw,(26,20),'24 ПРОСТЫХ ЗНАКА',30,bold=True)
    layout.text(draw,(26,63),'Один главный мотив · 1–2 плоских цвета · размер16px · подложка №4',20,'#a9b2b0')
    for index,item in enumerate(ITEMS):
        x=12+(index%6)*184
        y=105+(index//6)*218
        draw.rounded_rectangle((x,y,x+176,y+208),radius=4,fill='#202728')
        words=item['title'].split(' ')
        if len(item['title'])>16:
            title=words[0]+'\n'+' '.join(words[1:])
        else: title=item['title']
        layout.text(draw,(x+8,y+9),title,16,bold=True)
        old=icon_panel(OLD_ICONS/(item['id']+'.png'))
        new=icon_panel(OUT/'16'/(item['id']+'.png'))
        for bx,im,label in [(x+5,old,'Было'),(x+91,new,'Силуэт')]:
            big=im.resize((80,64),NN)
            sheet.paste(big,(bx,y+55),big)
            layout.text(draw,(bx+17,y+122),label,13,'#a9b2b0')
        sheet.paste(new,(x+100,y+158),new)
        layout.text(draw,(x+12,y+165),'Размер16px',13,'#a9b2b0')
    layout.text(draw,(26,992),'Пробы для оценки узнаваемости. В игру ещё не подключены.',17,'#85928f')
    sheet.save(OUT/'catalogue.png')

    compare=Image.new('RGB',(1320,924),'#171b1c')
    draw=ImageDraw.Draw(compare)
    layout.text(draw,(28,22),'ЧИТАЕМОСТЬ В РЯДУ ЭФФЕКТОВ',28,bold=True)
    layout.text(draw,(28,63),'Та же подложка №4, тот же нахлёст0/2/4px. Увеличение ×4.',20,'#a9b2b0')
    columns=[(440,1),(715,3),(1080,6)]
    for x,n in columns:
        layout.text(draw,(x-55,110),{1:'1 эффект',3:'3 эффекта',6:'6 эффектов'}[n],21,bold=True)
    battle=Image.open(layout.BATTLE).convert('RGBA')
    tile=battle.crop((730,276,842,318)).resize((448,168),NN)
    cases=[('old',OLD_ICONS,False,True,'Было','Без чисел'),('simple',OUT/'16',False,True,'Силуэты','Без чисел'),
           ('counters',OUT/'16',True,True,'С числами','Прежние10px'),('idle',OUT/'16',True,False,'Без фона','Вне наведения')]
    for index,(slug,root,counters,backing,title,sub) in enumerate(cases):
        y=150+index*174
        draw.rounded_rectangle((20,y,1300,y+158),radius=5,fill='#202728')
        layout.text(draw,(35,y+32),title,25,'#d7b777',True)
        layout.text(draw,(35,y+72),sub,18,'#a9b2b0')
        for x,count in columns:
            panel=row(root,count,counters,backing)
            panel.save(OUT/f'{slug}-{count}.png')
            display=panel.resize((panel.width*4,128),NN)
            fw=display.width+8
            field=tile.crop(((448-fw)//2,0,(448+fw)//2,128)).copy()
            field.alpha_composite(display,(4,0))
            compare.paste(field.convert('RGB'),(x-fw//2,y+14))
    layout.text(draw,(28,863),'Базовый размер:',18,'#a9b2b0')
    for x,root,counters in [(230,OLD_ICONS,False),(440,OUT/'16',False),(650,OUT/'16',True)]:
        panel=row(root,6,counters)
        compare.paste(panel,(x,856),panel)
    layout.text(draw,(28,897),'Шесть эффектов — условный пример. Числа всё ещё могут перекрывать часть рисунка.',17,'#85928f')
    compare.save(OUT/'row-comparison.png')

    context=Image.new('RGB',(760,510),'#171b1c')
    draw=ImageDraw.Draw(context)
    layout.text(draw,(24,20),'МАКЕТ НАД ПЕРСОНАЖЕМ',25,bold=True)
    layout.text(draw,(24,59),'Прежний кадр боя · одинаковая подложка · увеличение ×2',17,'#a9b2b0')
    for x,root,title in [(70,OLD_ICONS,'Было'),(430,OUT/'16','Простые силуэты')]:
        field=battle.crop((575,297,705,467)).copy()
        panel=row(root,6,True)
        field.alpha_composite(panel,((130-panel.width)//2,8))
        context.paste(field.resize((260,340),NN).convert('RGB'),(x,110))
        layout.text(draw,(x,466),title,21,bold=True)
    context.save(OUT/'character-comparison.png')
    sources=[PANEL,SOURCE_BUILDER,layout.BATTLE,ROOT/'assets/ui/combat_fonts/jersey20_numbers.ttf',ROOT/'assets/ui/combat_fonts/combat_letters.ttf']
    sources += [OLD_ICONS/(x['id']+'.png') for x in ITEMS]+[OUT/'16'/(x['id']+'.png') for x in ITEMS]
    manifest=dict(kind='art proposal, no runtime changes',icon_size=16,counts=[1,3,6],overlap=[0,2,4],widths=[40,68,100],counter_size=10,
                  sources={p.relative_to(ROOT).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
    (OUT/'layout.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
    print('Built24-icon comparison, row comparison, character mockup and12 native rows.')


if __name__=='__main__': build()
