"""Static comparisons with the user's measured Paint placement; Pillow required."""
from pathlib import Path
from collections import Counter
from PIL import Image,ImageDraw,ImageFont,ImageChops
import json,hashlib
OUT=Path(__file__).resolve().parent
ART=OUT.parent
BG,FG,MUTED='#20272b','#edf0e9','#a6b0a7'
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
measure=json.loads((OUT/'reference-measurements.json').read_text(encoding='utf-8'))
checks={'preview_only':True,'top':[128,96],'reference_sha256':sha(OUT/'user-reference.png'),'tiles':{},'fields':[]}
tiles={}
specs={}
for s in json.loads((ART/'tiles-20261009/checks.json').read_text(encoding='utf-8')):
 specs[s['id']]={'file':f"../tiles-20261009/{s['id']}-original.png",'top_box':s['top_crop'],'provider':s['provider'],'title':s['title'],'series':'very first A-F'}
recent=json.loads((ART/'terrain-fluffy-20261009/geometry.json').read_text(encoding='utf-8'))['tiles']
for k in 'KLM':
 s=recent[k].copy();s['file']='../terrain-fluffy-20261009/'+s['file'];s['title']={'K':'Низкий луг','L':'Земля и мох','M':'Спокойный луг'}[k];s['series']='latest K2/L2/M3';specs[k]=s
for k,s in specs.items():
 source=OUT/s['file'];raw=Image.open(source).convert('RGBA');box=s['top_box']
 sx,sy=128/(box[2]-box[0]),96/(box[3]-box[1])
 im=raw.resize((round(raw.width*sx),round(raw.height*sy)),Image.Resampling.NEAREST)
 ox,oy=round(box[0]*sx),round(box[1]*sy)
 alpha=im.getchannel('A')
 for y in range(im.height):
  for x in range(im.width):
   if y-oy>96-.75*abs(x-ox-64)+8:alpha.putpixel((x,y),0)
 im.putalpha(alpha);tiles[k]=(im,ox,oy)
 checks['tiles'][k]={**s,'sha256':sha(source),'scale_xy':[sx,sy]}

hero_path=ART/'quiet-clusters-20261009/defender-soft-original.png'
raw=Image.open(hero_path).convert('RGBA');b=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
scale=72/(b[3]-b[1]);full=raw.resize((round(raw.width*scale),round(raw.height*scale)),Image.Resampling.NEAREST)
crop=full.getchannel('A').getbbox();sprite=full.crop(crop)
assert sprite.tobytes()==Image.open(OUT/'paint-warrior.png').resize(sprite.size,Image.Resampling.NEAREST).tobytes()
offset=measure['cropped_warrior_origin_relative_to_cropped_tile_at_1x']
im,ox,oy=tiles['M'];mc=im.getchannel('A').getbbox()
# Экспорт M обрезан по alpha; переводим измеренную посадку в координаты верхней грани.
top_offset=(offset[0]+mc[0]-ox,offset[1]+mc[1]-oy)
assert top_offset==(19,-8)
cell_center=(450,375);cell_top_left=(386,327)
origin=tuple(round(cell_top_left[i]+top_offset[i]) for i in [0,1])
full_origin=tuple(origin[i]-crop[i] for i in [0,1])
actual=(full.width/raw.width,full.height/raw.height)
foot_mid=tuple(full_origin[i]+[658.75,1065][i]*actual[i] for i in [0,1])
checks['warrior']={'source':'../quiet-clusters-20261009/defender-soft-original.png','source_sha256':sha(hero_path),'height_alpha128':72,'cropped_size':sprite.size,'offset_from_tile_top_left':top_offset,'origin_in_field':origin,'uncropped_origin_in_field':full_origin,'foot_midpoint':foot_mid,'foot_midpoint_offset_from_cell_center':[foot_mid[i]-cell_center[i] for i in [0,1]],'placement_from_user_reference':True,'not_a_universal_anchor':True}

clean=Image.new('RGBA',measure['reference_size'],(0,0,0,0))
for name in ['tile','warrior']:
 clean.alpha_composite(Image.open(OUT/f'paint-{name}.png').convert('RGBA'),tuple(measure['placements'][name]['origin']))
clean.save(OUT/'clean-reconstruction-transparent.png')
white=Image.new('RGBA',clean.size,'white');white.alpha_composite(clean);white.convert('RGB').save(OUT/'clean-reconstruction.png')
comparison=Image.new('RGB',(1370,620),BG);d=ImageDraw.Draw(comparison)
d.text((24,20),'Твой пример',font=font(28),fill=FG);d.text((710,20),'Восстановлено из чистых PNG',font=font(28),fill=FG)
comparison.paste(Image.open(OUT/'user-reference.png').convert('RGB'),(14,82));comparison.paste(white.convert('RGB'),(699,82))
comparison.save(OUT/'reference-comparison.png')

def field(name,title,grid,legend):
 canvas=Image.new('RGBA',(1100,850),BG);d=ImageDraw.Draw(canvas)
 d.text((38,24),title,font=font(29),fill=FG)
 d.text((38,70),'Посадка из твоего примера  •  тот же воин 72 px  •  ракурс 4:3',font=font(19),fill=MUTED)
 for x,y in sorted(((x,y) for x in range(6) for y in range(6)),key=sum):
  im,ox,oy=tiles[grid[y][x]];canvas.alpha_composite(im,(450+(x-y)*64-64-ox,135+(x+y)*48-oy))
 before=canvas.copy();layer=Image.new('RGBA',canvas.size);layer.alpha_composite(sprite,origin);canvas.alpha_composite(layer)
 diff=ImageChops.difference(before.convert('RGB'),canvas.convert('RGB'));outside=Image.new('RGB',canvas.size);outside.paste(diff,(0,0),layer.getchannel('A').point(lambda a:0 if a else 255));assert outside.getbbox() is None
 for n,k in enumerate(legend):
  im=tiles[k][0];im=im.crop(im.getbbox());im.thumbnail((110,110),Image.Resampling.NEAREST);canvas.alpha_composite(im,(897,130+n*110));d.text((1034,155+n*110),k,font=font(20),fill=FG)
 big=sprite.resize((156,146),Image.Resampling.NEAREST);canvas.alpha_composite(big,(897,582))
 d.text((38,772),'Фигура и тайлы сохранены; изменилась только сборка композиции.',font=font(18),fill=FG)
 d.text((38,808),'Ранние A–F приведены к нынешнему ракурсу 4:3. Справа — увеличения.',font=font(17),fill=MUTED)
 canvas.convert('RGB').save(OUT/f'{name}.png')
 checks['fields'].append({'name':name,'cell':[2,2],'origin':origin,'counts':dict(Counter(k for row in grid for k in row)),'background_changes_outside_hero':0})
for k in specs:
 field('field-'+k,k+' / '+specs[k]['title'],[[k]*6 for _ in range(6)],[k])
early=json.loads((ART/'tiles-20261009/mixed-A50-CDE-layout.json').read_text(encoding='utf-8'))['layout_rows_y_columns_x']
current=json.loads((ART/'terrain-fluffy-20261009/checks.json').read_text(encoding='utf-8'))['new_mixed_layout']
field('mixed-early','Ранние тайлы / A + C + D + E',early,list('ACDE'))
field('mixed-current','Нынешние тайлы / K + L + M',current,list('KLM'))
for name,items in [('early-fields',list('ABCDEF')),('current-fields',list('KLM')+['mixed-current'])]:
 sheet=Image.new('RGB',(2200,850*((len(items)+1)//2)),BG)
 for n,k in enumerate(items):sheet.paste(Image.open(OUT/(('field-'+k if len(k)==1 else k)+'.png')),((n%2)*1100,(n//2)*850))
 sheet.save(OUT/(name+'.png'))
(OUT/'checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Built clean user-reference reconstruction and11 fields from immutable A-F/KLM and72px warrior. No generations.')
