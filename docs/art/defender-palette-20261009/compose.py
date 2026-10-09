"""Static comparison; provider originals are immutable inputs. Requires Pillow."""
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json, hashlib

OUT=Path(__file__).resolve().parent
PREV=OUT.parent/'projection-4x3-20261009'
FIRST=OUT.parent/'tiles-20261009'
CFG=json.loads((OUT/'geometry.json').read_text())
BG='#20272b';FG='#edf0e9';MUTED='#a6b0a7'
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
palette={tuple(bytes.fromhex(v)) for v in ['464B3E','4B6347','475643','3F3F3A','5B5141','473E34','354249']}
old_meta={v['id']:v for v in json.loads((FIRST/'checks.json').read_text())}
prev_meta={v['id']:v for v in json.loads((PREV/'checks.json').read_text())['tiles']}
layout=json.loads((FIRST/'mixed-A50-CDE-layout.json').read_text())['layout_rows_y_columns_x']
assert Counter(k for row in layout for k in row)=={'A':18,'C':6,'D':6,'E':6}
titles={'A':'Тихая земля','B':'Чистый газон','C':'Спокойная трава','D':'Лёгкая кромка','E':'Заметная трава','F':'Рассеянная трава','G':'Мой вариант: оливковая земля'}
tiles={};tile_checks=[]
for k in 'ABCDEFG':
    if k in 'ACDE':path=PREV/f'tile-{k}-original.png';box=prev_meta[k]['top_box'];provider='PixelLab'
    elif k in 'BF':path=FIRST/f'{k}-original.png';box=old_meta[k]['top_crop'];provider='PixelLab, первая серия'
    else:path=OUT/'tile-G-original.png';box=CFG['top_box_G'];provider='imagegen + PixelLab palette pass'
    raw=Image.open(path).convert('RGBA');pixels=[p for p in raw.get_flattened_data() if p[3]]
    off=sum(p[:3] not in palette for p in pixels);assert off==0,(k,off)
    sx,sy=128/(box[2]-box[0]),96/(box[3]-box[1])
    im=raw.resize((round(raw.width*sx),round(raw.height*sy)),Image.Resampling.NEAREST)
    ox,oy=round(box[0]*sx),round(box[1]*sy)
    alpha=im.getchannel('A');a=alpha.load()
    for py in range(im.height):
        for px in range(im.width):
            if py-oy>96-.75*abs(px-ox-64)+CFG['side_depth_limit']:a[px,py]=0
    im.putalpha(alpha);tiles[k]=(im,ox,oy)
    if k=='G':im.save(OUT/'tile-G-display.png')
    tile_checks.append({'id':k,'source':str(path.relative_to(OUT.parent)).replace('\\','/'),'provider':provider,'source_sha256':sha(path),'source_canvas':list(raw.size),'top_box':box,'scale_xy':[sx,sy],'off_palette_pixels':off})

char_path=OUT/'defender-4-original.png';char=Image.open(char_path).convert('RGBA')
assert char.size==(64,64)
bbox=char.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
assert bbox and all((bbox[0]>0,bbox[1]>0,bbox[2]<64,bbox[3]<64))
off=sum(p[3]>0 and p[:3] not in palette for p in char.get_flattened_data())
strict=Image.open(OUT/'defender-4-strict-original.png').convert('RGBA')
strict_off=sum(p[3]>0 and p[:3] not in palette for p in strict.get_flattened_data());assert strict_off==0
scale=CFG['character_visible_height']/(bbox[3]-bbox[1])
anchor=tuple(sum(p[axis] for p in CFG['character_foot_contacts'])/2 for axis in (0,1))
sprite=char.resize((round(64*scale),round(64*scale)),Image.Resampling.NEAREST)
cell=CFG['character_cell'];foot=(450+(cell[0]-cell[1])*64,183+(cell[0]+cell[1])*48)
origin=(foot[0]-round(anchor[0]*scale),foot[1]-round(anchor[1]*scale))
offset=[origin[i]+anchor[i]*scale-foot[i] for i in (0,1)];assert max(abs(e) for e in offset)<=.5

def field(key,title,grid,legend_key,previous_char=False,strict_char=False):
    c=Image.new('RGBA',(1100,850),BG);d=ImageDraw.Draw(c)
    d.text((38,24),title,font=font(29),fill=FG)
    d.text((38,68),'Выбранный ракурс 4:3  •  128 × 96  •  солдат №4 в центре клетки',font=font(18),fill=MUTED)
    for x,y in sorted(((x,y) for x in range(6) for y in range(6)),key=sum):
        im,ox,oy=tiles[grid[y][x]];c.alpha_composite(im,(450+(x-y)*64-64-ox,135+(x+y)*48-oy))
    # Отдельный слой позволяет проверить неизменность поверхности вне персонажа.
    before=c.copy();layer=Image.new('RGBA',c.size)
    shown=sprite;where=origin
    if strict_char:
        sb=strict.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();ss=72/(sb[3]-sb[1])
        shown=strict.resize((round(strict.width*ss),round(strict.height*ss)),Image.Resampling.NEAREST)
        where=(foot[0]-round(34.25*ss),foot[1]-round(54*ss))
    if previous_char:
        old=Image.open(PREV/'defender-4-original.png').convert('RGBA')
        bb=old.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();s=72/(bb[3]-bb[1])
        shown=old.resize((round(old.width*s),round(old.height*s)),Image.Resampling.NEAREST)
        old_anchor=(661,1041.5);where=(foot[0]-round(old_anchor[0]*s),foot[1]-round(old_anchor[1]*s))
    layer.alpha_composite(shown,where);c.alpha_composite(layer)
    diff=ImageChops.difference(before.convert('RGB'),c.convert('RGB'))
    outside=Image.new('RGB',c.size);outside.paste(diff,(0,0),layer.getchannel('A').point(lambda a:0 if a else 255))
    assert outside.getbbox() is None
    t=tiles[legend_key][0];bb=t.getbbox();crop=t.crop(bb);ts=min(145/crop.width,145/crop.height)
    crop=crop.resize((round(crop.width*ts),round(crop.height*ts)),Image.Resampling.NEAREST)
    c.alpha_composite(crop,(906,153));d.text((900,315),'Тайл '+legend_key,font=font(20),fill=FG)
    large_char=Image.open(PREV/'defender-4-original.png').convert('RGBA') if previous_char else (strict if strict_char else char)
    bb=large_char.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();crop=large_char.crop(bb)
    s=min(176/crop.width,176/crop.height);crop=crop.resize((round(crop.width*s),round(crop.height*s)),Image.Resampling.NEAREST)
    c.alpha_composite(crop,(892+(176-crop.width)//2,393))
    d.text((883,590),'№4 — крупнее',font=font(19),fill=FG)
    d.text((38,771),'На поле: 72 px по высоте, опора по середине подошв, nearest.',font=font(18),fill=FG)
    note='Прежние цвета солдата — контроль сравнения.' if previous_char else ('Контроль: солдат строго в семи цветах тайлов.' if strict_char else 'Родственная палитра: оливковые/землистые тона и читаемые светлые акценты.')
    d.text((38,809),note,font=font(16),fill=MUTED)
    c.convert('RGB').save(OUT/f'{key}-field.png')
    return c

fields=[]
for k in 'ABCDEFG':
    field(k,k+'  /  '+titles[k],[[k]*6 for _ in range(6)],k);fields.append((k,36))
field('mixed-ACDE','Смешанное поле  /  A + C + D + E',layout,'E')
mixed_ag=[['A' if k=='A' else 'G' for k in row] for row in layout]
field('mixed-AG','Новая смесь  /  A + мой G',mixed_ag,'G')
assert Counter(k for row in mixed_ag for k in row)=={'A':18,'G':18}
field('before','№4  /  прежние цвета',layout,'E',True)
field('strict','№4  /  строгие 7 цветов — контроль',layout,'E',strict_char=True)
audit=Image.open(OUT/'mixed-AG-field.png').convert('RGB');d=ImageDraw.Draw(audit);cx,cy=foot
d.line([(cx,cy-48),(cx+64,cy),(cx,cy+48),(cx-64,cy),(cx,cy-48)],fill='#cfbf7b',width=1)
d.line((cx-4,cy,cx+4,cy),fill='#fff1a2');d.line((cx,cy-4,cx,cy+4),fill='#fff1a2');audit.save(OUT/'placement-check.png')

overview=Image.new('RGB',(1980,1530),BG)
for n,k in enumerate(list('ABCDEFG')+['mixed-ACDE','mixed-AG']):
    im=Image.open(OUT/f'{k}-field.png').resize((660,510),Image.Resampling.NEAREST)
    overview.paste(im,((n%3)*660,(n//3)*510))
overview.save(OUT/'all-fields.png')
compare=Image.new('RGB',(2200,850),BG)
for n,k in enumerate(['before','mixed-ACDE']):compare.paste(Image.open(OUT/f'{k}-field.png'),(n*1100,0))
compare.save(OUT/'palette-before-after.png')
hero=Image.new('RGB',(1100,560),BG);d=ImageDraw.Draw(hero)
d.text((38,24),'№4  /  палитра тайлов и явная пиксельная сетка',font=font(29),fill=FG)
for n,(path,title) in enumerate([(PREV/'defender-4-original.png','Прежний цвет'),(OUT/'defender-4-strict-original.png','Строгие 7 цветов'),(char_path,'Итог: близкая гамма / 64 × 64')]):
    raw=Image.open(path).convert('RGBA');bb=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();im=raw.crop(bb)
    s=min(280/im.width,330/im.height);im=im.resize((round(im.width*s),round(im.height*s)),Image.Resampling.NEAREST)
    hero.paste(im,(n*366+(366-im.width)//2,100+(330-im.height)//2),im)
    d.text((n*366+18,463),title,font=font(19),fill=FG)
d.text((38,521),'По уточнению пользователя: общая цветовая гамма, без жёсткого ограничения RGB.',font=font(18),fill=MUTED)
hero.save(OUT/'soldier-comparison.png')

report={'preview_only':True,'angle_accepted_by_user':'4:3','top_size':[128,96],'grid_steps':[[64,48],[-64,48]],'tiles':tile_checks,'defender':{'file':char_path.name,'sha256':sha(char_path),'source_size':[64,64],'bbox_alpha_128':bbox,'colors_outside_terrain_palette_expected':off,'palette_requirement':'Related muted hues, not exact RGB after user clarification','strict_control_off_palette_pixels':strict_off,'visible_height':72,'scale':scale,'foot_contacts_source':CFG['character_foot_contacts'],'anchor_source':anchor,'cell':cell,'foot_canvas':foot,'origin_canvas':origin,'center_rounding_error_px':offset},'single_fields':list('ABCDEFG'),'mixed_ACDE_counts':dict(Counter(k for row in layout for k in row)),'mixed_AG_counts':dict(Counter(k for row in mixed_ag for k in row)),'background_changes_outside_character':0,'imagegen_calls':2,'pixellab_charged_calls':5,'game_changed':False,'limits':['Strict terrain palette control reduces contrast; final character uses related hues and readable accents as requested.','4:3 is exact in montage; native source top geometry is normalized.','Foot contacts estimated visually and verified against source pixels; no measured3D.']}
(OUT/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Built A-G and both mixed fields with the same #4; palette and placement PASS.')
