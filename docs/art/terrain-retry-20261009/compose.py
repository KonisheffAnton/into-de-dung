"""Reproducible static art comparisons. Requires Pillow and Windows Segoe UI."""
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont, ImageChops
import json, hashlib, random
OUT=Path(__file__).resolve().parent
BG,FG,MUTED='#20272b','#edf0e9','#a6b0a7'
font=lambda n:ImageFont.truetype('C:/Windows/Fonts/segoeui.ttf',n)
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
cfg=json.loads((OUT/'geometry.json').read_text())
checks={'preview_only':True,'top_size':[128,96],'tiles':[],'placements':[]}
tiles={}
for k,spec in cfg['tiles'].items():
 p=OUT/spec['file'];raw=Image.open(p).convert('RGBA');box=spec['top_box']
 sx,sy=128/(box[2]-box[0]),96/(box[3]-box[1]);im=raw.resize((round(raw.width*sx),round(raw.height*sy)),Image.Resampling.NEAREST)
 ox,oy=round(box[0]*sx),round(box[1]*sy);alpha=im.getchannel('A')
 for y in range(im.height):
  for x in range(im.width):
   if y-oy>96-.75*abs(x-ox-64)+8:alpha.putpixel((x,y),0)
 im.putalpha(alpha);tiles[k]=(im,ox,oy);im.save(OUT/f'tile-{k}-display.png')
 checks['tiles'].append({'id':k,'source':spec['file'],'provider':spec['provider'],'sha256':sha(p),'size':raw.size,'top_box':box,'scale_xy':[sx,sy]})
hero_path=OUT/'../quiet-clusters-20261009/defender-soft-original.png'
raw=Image.open(hero_path).convert('RGBA');bbox=raw.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();s=72/(bbox[3]-bbox[1])
sprite=raw.resize((round(raw.width*s),round(raw.height*s)),Image.Resampling.NEAREST)
actual=(sprite.width/raw.width,sprite.height/raw.height);anchor=(658.75,1065);foot=(450,375)
origin=tuple(round(foot[i]-anchor[i]*actual[i]) for i in (0,1));error=[origin[i]+anchor[i]*actual[i]-foot[i] for i in (0,1)]
assert max(abs(v) for v in error)<=.5
sb=sprite.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();assert sb[3]-sb[1]==72
checks['defender']={'source':str(hero_path.relative_to(OUT)).replace('\\','/'),'sha256':sha(hero_path),'unchanged':True,'user_accepted_static':True,'visible_height':72,'feet':[[411.5,988],[906,1142]],'anchor':anchor,'actual_scale_xy':actual,'center_error_px':error}
oldlayout=json.loads((OUT.parent/'tiles-20261009/mixed-A50-CDE-layout.json').read_text())['layout_rows_y_columns_x']
def mixture(pair):
 n=0;grid=[]
 for row in oldlayout:
  r=[]
  for k in row:
   if k=='A':r.append('A')
   else:r.append(pair[n%len(pair)]);n+=1
  grid.append(r)
 return grid

def field(name,title,grid,legend):
 c=Image.new('RGBA',(1100,850),BG);d=ImageDraw.Draw(c)
 d.text((38,24),title,font=font(29),fill=FG);d.text((38,70),'Ракурс 4:3  •  тот же одобренный №4  •  6 × 6 клеток',font=font(19),fill=MUTED)
 for x,y in sorted(((x,y) for x in range(6) for y in range(6)),key=sum):
  im,ox,oy=tiles[grid[y][x]];c.alpha_composite(im,(450+(x-y)*64-64-ox,135+(x+y)*48-oy))
 before=c.copy();layer=Image.new('RGBA',c.size);layer.alpha_composite(sprite,origin);c.alpha_composite(layer)
 diff=ImageChops.difference(before.convert('RGB'),c.convert('RGB'));outside=Image.new('RGB',c.size);outside.paste(diff,(0,0),layer.getchannel('A').point(lambda a:0 if a else 255));assert outside.getbbox() is None
 for n,k in enumerate(legend):
  size=110 if len(legend)>3 else 145;step=110 if len(legend)>3 else 153
  im=tiles[k][0];im=im.crop(im.getbbox());im.thumbnail((size,size),Image.Resampling.NEAREST);c.alpha_composite(im,(892,130+n*step));d.text((1035,155+n*step),k,font=font(20),fill=FG)
 big=raw.crop(bbox);bs=min(165/big.width,165/big.height);big=big.resize((round(big.width*bs),round(big.height*bs)),Image.Resampling.NEAREST);c.alpha_composite(big,(894,576))
 d.text((38,772),'Фигура 72 px, опора в центре клетки. Справа — увеличения для деталей.',font=font(18),fill=FG)
 d.text((38,808),'Оригинальные цвета; без случайных поворотов и подкраски. Сравнение арта.',font=font(17),fill=MUTED)
 c.convert('RGB').save(OUT/f'{name}.png');checks['placements'].append({'field':name,'cell':[2,2],'origin':origin,'center':foot,'error':error,'background_changes_outside_character':0,'counts':dict(Counter(k for row in grid for k in row))})
 return c
names={'K':'Мой / низкий луг','L':'Мой / земля и мох','M':'PixelLab / низкий луг','N':'PixelLab / земля и мох'}
for k in 'KLM':
 field(f'field-{k}',k+'  /  '+names[k],[[k]*6 for _ in range(6)],[k])
 field(f'mixed-A{k}','A + '+k+'  /  половина — прежняя земля',mixture(k),['A',k])
for pair,label in [('KLM','Общая смесь')]:
 grid=mixture(pair);assert Counter(k for row in grid for k in row)=={'A':18,'K':6,'L':6,'M':6}
 field('mixed-A'+pair,label+'  /  A + K + L + M',grid,list('A'+pair))
pool=list('KLM')*12;random.Random(20261009).shuffle(pool);puremix=[pool[y*6:y*6+6] for y in range(6)]
assert Counter(pool)=={'K':12,'L':12,'M':12}
field('mixed-KLM','Новые тайлы вперемешку  /  K + L + M',puremix,list('KLM'))
checks['new_mixed_layout']=puremix
for mode,prefix in [('all-fields','field-'),('all-mixed','mixed-A')]:
 sheet=Image.new('RGB',(2200,1700),BG)
 for n,k in enumerate('KLM'):sheet.paste(Image.open(OUT/f'{prefix}{k}.png'),((n%2)*1100,(n//2)*850))
 sheet.paste(Image.open(OUT/('mixed-KLM.png' if mode=='all-fields' else 'mixed-AKLM.png')),(1100,850))
 sheet.save(OUT/f'{mode}.png')
close=Image.new('RGB',(1400,950),BG);d=ImageDraw.Draw(close)
for n,k in enumerate('KLM'):
 x,y=(n%2)*700,(n//2)*475;d.text((x+30,y+20),k+' / '+names[k],font=font(27),fill=FG)
 im=tiles[k][0];im=im.crop(im.getbbox());sc=min(480/im.width,355/im.height);im=im.resize((round(im.width*sc),round(im.height*sc)),Image.Resampling.NEAREST);close.paste(im,(x+85,y+80),im)
d.text((750,520),'Солдат №4 оставлен без изменений',font=font(25),fill=FG)
hr=raw.crop(bbox);hs=min(260/hr.width,285/hr.height);hr=hr.resize((round(hr.width*hs),round(hr.height*hs)),Image.Resampling.NEAREST);close.paste(hr,(900,585),hr)
close.save(OUT/'tiles-closeup.png')
audit=Image.open(OUT/'mixed-AKLM.png');d=ImageDraw.Draw(audit);d.line([(450,327),(514,375),(450,423),(386,375),(450,327)],fill='#d7c382');d.line((446,375,454,375),fill='#fff1a2');d.line((450,371,450,379),fill='#fff1a2');audit.save(OUT/'placement-check.png')
checks['mix_base_layout']=oldlayout
(OUT/'checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Built selected K/L/M fields and mixtures with unchanged approved #4; alpha/placement/background assertions PASS.')
