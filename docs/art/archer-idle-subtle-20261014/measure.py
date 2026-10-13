"""Только измерение PNG. Области проверки не изменяют рисунки/alpha."""
from PIL import Image
from pathlib import Path
import json

root=Path(__file__).resolve().parent
base=Image.open(root/'pixellab/reference-128.png').convert('RGBA')
regions={
 'full_canvas':(0,0,128,128),
 'lower_legs_and_feet':(0,100,128,128),
 'left_foot':(24,104,53,119),
 'right_foot':(81,107,108,123),
 'bow_and_right_hand':(92,42,123,99),
 'head_and_ponytail':(43,10,93,51),
}
def compare(a,b):
 a=list(a.get_flattened_data());b=list(b.get_flattened_data())
 return {'rgba_changed':sum(x!=y for x,y in zip(a,b)),
         'visible_rgba_changed':sum(x!=y and (x[3]!=0 or y[3]!=0) for x,y in zip(a,b)),
         'alpha128_changed':sum((x[3]>=128)!=(y[3]>=128) for x,y in zip(a,b))}
frames=[]
for p in sorted((root/'pixellab').glob('frame-*.png')):
 im=Image.open(p).convert('RGBA')
 mask=im.getchannel('A').point(lambda a:255 if a>=128 else 0)
 frames.append({'file':p.name,'bbox_alpha128':mask.getbbox(),
                'regions_vs_reference':{name:compare(base.crop(box),im.crop(box)) for name,box in regions.items()}})
result={'basis':'Fixed, approximate rectangular regions in reference canvas, chosen before visual inspection of output. They include surrounding empty pixels/adjacent parts. Nonzero counts indicate a changed region, not a motion magnitude; zero is exact equality inside that box only.',
        'reference':'pixellab/reference-128.png','regions_xyxy':regions,'frames':frames}
(root/'motion-measurements.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps(result))
