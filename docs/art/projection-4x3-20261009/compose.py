"""Rebuild static 4:3 art comparisons from retained provider originals (Pillow)."""
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json, hashlib

OUT=Path(__file__).resolve().parent
OLD=OUT.parent/'tiles-20261009'
OLDCHARS=OUT.parent/'defender-20261009'
BG='#20272b'; FG='#edf0e9'; MUTED='#a6b0a7'
FONT='C:/Windows/Fonts/segoeui.ttf'
font=lambda n:ImageFont.truetype(FONT,n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
layout=json.loads((OLD/'mixed-A50-CDE-layout.json').read_text())['layout_rows_y_columns_x']
counts=Counter(k for row in layout for k in row)
assert counts=={'A':18,'C':6,'D':6,'E':6}
config=json.loads((OUT/'geometry.json').read_text())
colors={tuple(bytes.fromhex(h)) for h in ['464B3E','4B6347','475643','3F3F3A','5B5141','473E34','354249']}
tile_meta=[]; tiles={}
for k in 'ACDE':
    path=OUT/f'tile-{k}-original.png';raw=Image.open(path).convert('RGBA')
    box=config['top_boxes'][k]
    sx,sy=128/(box[2]-box[0]),96/(box[3]-box[1])
    im=raw.resize((round(raw.width*sx),round(raw.height*sy)),Image.Resampling.NEAREST)
    ox,oy=round(box[0]*sx),round(box[1]*sy)
    # В макете все поверхности лежат на одном уровне: лишняя толщина блоков скрыта.
    alpha=im.getchannel('A');a=alpha.load();clipped=0
    for py in range(im.height):
        for px in range(im.width):
            bottom=96-0.75*abs(px-ox-64)+config['max_preview_side_depth']
            if py-oy>bottom and a[px,py]: a[px,py]=0;clipped+=1
    im.putalpha(alpha)
    im.save(OUT/f'tile-{k}-display.png')
    tiles[k]=(im,ox,oy)
    off=sum(p[3]>0 and p[:3] not in colors for p in raw.get_flattened_data())
    assert off==0,(k,off)
    tile_meta.append({'id':k,'provider':'PixelLab Pixflux','file':path.name,'sha256':sha(path),'canvas':list(raw.size),'top_box':box,'preview_top':[128,96],'scale_xy':[sx,sy],'off_palette_pixels':off,'side_pixels_clipped_for_flat_preview':clipped,'source_request':f'tile-{k}-'+('guided' if k=='A' else 'free')+'-request.json'})

titles={'A':'Тихая земля','C':'Спокойная трава','D':'Лёгкая кромка','E':'Заметная трава'}
def field(title,subtitle,grid=layout):
    c=Image.new('RGBA',(1100,850),BG);d=ImageDraw.Draw(c)
    d.text((38,24),title,font=font(29),fill=FG)
    d.text((38,67),subtitle,font=font(18),fill=MUTED)
    for x,y in sorted(((x,y) for x in range(6) for y in range(6)),key=sum):
        im,ox,oy=tiles[grid[y][x]]
        c.alpha_composite(im,(450+(x-y)*64-64-ox,135+(x+y)*48-oy))
    for n,k in enumerate('ACDE'):
        raw=Image.open(OUT/f'tile-{k}-display.png').convert('RGBA')
        box=raw.getbbox();raw=raw.crop(box)
        scale=min(128/raw.width,125/raw.height)
        c.alpha_composite(raw.resize((round(raw.width*scale),round(raw.height*scale)),Image.Resampling.NEAREST),(890,137+n*145))
        d.text((1028,179+n*145),k,font=font(23),fill=FG)
    d.text((38,775),'Верх клетки 128 × 96  •  A: 18, C/D/E: по 6 в смешанном поле',font=font(18),fill=FG)
    d.text((38,810),'Палитра из Into the Breach; статическая проба, nearest.',font=font(16),fill=MUTED)
    return c

base=field('Смешанное поле  /  ракурс 4:3','Новые тайлы PixelLab  •  прежняя раскладка A + C + D + E')
base.convert('RGB').save(OUT/'mixed-field.png')
for k in 'ACDE':
    c=field(f'{k}  /  {titles[k]}','Новая генерация PixelLab  •  36 одинаковых тайлов',[[k]*6 for _ in range(6)])
    c.convert('RGB').save(OUT/f'tile-{k}-field.png')

variants=[('1','Массивный','PixelLab',(1,1)),('2','Страж','PixelLab',(4,1)),('3','Вид сверху','PixelLab',(1,4)),('4','Мой вариант','imagegen',(4,4))]
char_meta=[]
def place(c,label,cell,badge=True,old=False):
    path=(OLDCHARS if old else OUT)/f'defender-{label}-original.png'
    raw=Image.open(path).convert('RGBA')
    box=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
    assert box and 0<box[0]<box[2]<raw.width and 0<box[1]<box[3]<raw.height,(label,box)
    scale=config['defender_target_visible_height']/(box[3]-box[1])
    sprite=raw.resize((round(raw.width*scale),round(raw.height*scale)),Image.Resampling.NEAREST)
    contacts=config['defender_foot_contacts'][label]
    anchor=tuple(sum(p[axis] for p in contacts)/2 for axis in (0,1))
    foot=(450+(cell[0]-cell[1])*64,183+(cell[0]+cell[1])*48)
    origin=(foot[0]-round(anchor[0]*scale),foot[1]-round(anchor[1]*scale))
    assert origin[0]>=0 and origin[1]>=0 and origin[0]+sprite.width<=c.width and origin[1]+sprite.height<=c.height
    overlay=Image.new('RGBA',c.size);overlay.alpha_composite(sprite,origin)
    if badge:
        d=ImageDraw.Draw(overlay);x,y=foot[0]+33,foot[1]-79
        d.rounded_rectangle((x,y,x+25,y+27),radius=5,fill='#e5e4cc')
        d.text((x+7,y+2),label,font=font(17),fill=BG)
    before=c.copy();c.alpha_composite(overlay)
    change=ImageChops.difference(before.convert('RGB'),c.convert('RGB'))
    change.putalpha(255)
    outside=Image.new('RGBA',c.size);outside.paste(change,(0,0),overlay.getchannel('A').point(lambda a:0 if a else 255))
    assert not any(p[:3]!=(0,0,0) for p in outside.get_flattened_data())
    midpoint=tuple(origin[axis]+anchor[axis]*scale for axis in (0,1))
    error=tuple(midpoint[axis]-foot[axis] for axis in (0,1))
    assert max(abs(e) for e in error)<=0.5
    return {'id':label,'file':path.name,'sha256':sha(path),'canvas':list(raw.size),'bbox_alpha_128':box,'scale':scale,'target_visible_height':config['defender_target_visible_height'],'cell':cell,'foot_canvas':foot,'source_foot_contacts':contacts,'source_anchor':anchor,'origin_canvas':origin,'contact_midpoint_offset_px':error,'background_changes_outside_overlay':0}

board=base.copy();d=ImageDraw.Draw(board)
d.rectangle((0,0,1099,109),fill=BG)
d.text((38,24),'Защитники на поле  /  новый ракурс 4:3',font=font(29),fill=FG)
d.text((38,67),'1–3: PixelLab  •  4: imagegen  •  уменьшены; опоры в центрах клеток',font=font(18),fill=MUTED)
for label,title,provider,cell in variants:
    m=place(board,label,cell);m.update(title=title,provider=provider);char_meta.append(m)
    single=base.copy();sd=ImageDraw.Draw(single);sd.rectangle((0,0,1099,109),fill=BG)
    sd.text((38,24),f'{label}  /  {title}  /  {provider}',font=font(30),fill=FG)
    sd.text((38,67),'Новый ракурс; одинаковая клетка и способ привязки для сравнения',font=font(18),fill=MUTED)
    place(single,label,(2,2),False)
    single.convert('RGB').save(OUT/f'defender-{label}-field.png')
board.convert('RGB').save(OUT/'defenders-on-board.png')
audit=board.copy();ad=ImageDraw.Draw(audit)
for m in char_meta:
    cx,cy=m['foot_canvas'];ad.line([(cx,cy-48),(cx+64,cy),(cx,cy+48),(cx-64,cy),(cx,cy-48)],fill='#cfbf7b',width=1)
    ad.line((cx-5,cy,cx+5,cy),fill='#fff1a2',width=1);ad.line((cx,cy-5,cx,cy+5),fill='#fff1a2',width=1)
audit.convert('RGB').save(OUT/'placement-check.png')
comparison=Image.new('RGB',(1100,1170),BG);comparison.paste(board,(0,0));d=ImageDraw.Draw(comparison)
d.line((38,862,1062,862),fill='#46524e',width=2)
for n,(label,title,provider,cell) in enumerate(variants):
    raw=Image.open(OUT/f'defender-{label}-original.png').convert('RGBA')
    box=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();crop=raw.crop(box)
    scale=min(220/crop.width,208/crop.height)
    big=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST)
    comparison.paste(big,(n*275+(275-big.width)//2,888+(208-big.height)//2),big)
    d.text((n*275+22,1102),f'{label}. {title}',font=font(21),fill=FG)
    d.text((n*275+22,1134),provider,font=font(16),fill=MUTED)
comparison.save(OUT/'comparison.png')

# Сравнение наклона не смешивает новый рисунок с изменением геометрии.
angles=Image.new('RGB',(2000,870),BG)
for n,h in enumerate((64,96)):
    c=Image.open(OUT/f'previous-art-{h}.png').convert('RGBA')
    raw=Image.open(OLDCHARS/'defender-4-original.png').convert('RGBA')
    box=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();scale=72/(box[3]-box[1])
    sprite=raw.resize((round(raw.width*scale),round(raw.height*scale)),Image.Resampling.NEAREST)
    foot=(500,135+(576-h*6)//2+h//2+4*h//2)
    anchor=(663,1065)
    c.alpha_composite(sprite,(foot[0]-round(anchor[0]*scale),foot[1]-round(anchor[1]*scale)))
    angles.paste(c,(n*1000,0))
ImageDraw.Draw(angles).text((38,828),'Тот же персонаж №4 в обоих полях: рисунок и размер сохранены.',font=font(22),fill=FG)
angles.save(OUT/'angle-comparison.png')

overview=Image.new('RGB',(1320,1020),BG)
for n,k in enumerate('ACDE'):
    im=Image.open(OUT/f'tile-{k}-field.png').resize((660,510),Image.Resampling.NEAREST)
    overview.paste(im,((n%2)*660,(n//2)*510))
overview.save(OUT/'tile-comparison.png')
report={'preview_only':True,'projection':'4:3; 128x96 top','grid_steps':[[64,48],[-64,48]],'counts':dict(counts),'layout_rows_y_columns_x':layout,'tiles':tile_meta,'defenders':char_meta,'provider_generation_count':{'PixelLab':12,'image_gen':1},'rejected_local':['tile-A.png (rounded silhouette)','tile-C-guided.png','tile-D-guided.png','tile-E-guided.png','tile-C-grass.png (insufficient grass differentiation with init guide)'],'original_game_art_sent_to_providers':False,'game_code_changed':False,'filter':'nearest','limits':['Exact 4:3 grid in montage; generated character camera is judged visually, not measured 3D.','Tile top boxes are normalized to the common grid; excessive side depth is clipped to 8 screen pixels in the preview. Originals unchanged.','Imagegen character is a large pixel-styled raster, not a native 64x64 sprite.','Boot contacts estimated visually; their midpoint is placed at the cell center within half a screen pixel.']}
(OUT/'checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Built all tile fields, mixed field, four individual defender fields, both comparisons; palette/alpha/placements verified.')
