"""Сохраняет полные исходники и отдельные нормализованные входы анимации."""
from pathlib import Path
from PIL import Image, ImageDraw
import json, hashlib, shutil

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
GEN = Path('C:/Users/Aston/.codex/generated_images/01a18ed7-afd8-70f0-8c54-3750bf04d380')
SOURCES = {
    '02': GEN/'exec-bbec7624-c4a0-4eb4-ae16-6986242d2ae4.png',
    '05': GEN/'exec-26d1ab91-0bb3-4cd6-bc50-0f481170edbf.png',
    '11': REPO/'assets/art_presets/trials/warrior_classes_v1/fighter-11.png',
    '12': GEN/'exec-fc729a46-aabb-4fa6-a912-e08839034995.png',
    '17': REPO/'assets/art_presets/trials/warrior_classes_v1/shieldbearer-17.png',
    '18': GEN/'exec-461315dc-292e-4fd0-b024-8028f12149f1.png',
}
PROMPT = 'Use case: background-extraction. Extract ONLY the complete warrior from the reference concept into a large full-resolution transparent PNG. Remove the entire stone tile, floor, cast shadow and dark blue background. Preserve precisely the character identity, compact proportions, original pose and camera angle, face/hair or helmet, armor, scarf/cape, sword and shield if present, original pixel-art rendering and colors. Do not redesign or simplify. Single full-body character enlarged to fill the canvas with modest transparent margins, entire blade, hands and boots visible. Actual alpha transparency, no halo, outline, extra objects or labels. This is the source model for game sprite animation.'

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    records=[]
    sheet=Image.new('RGB',(768,564),'#182131')
    draw=ImageDraw.Draw(sheet)
    for index,(id,src) in enumerate(SOURCES.items()):
        folder=ROOT/'models'/('warrior-'+id)
        folder.mkdir(parents=True,exist_ok=True)
        raw=folder/'source-full.png'
        if not raw.exists(): shutil.copy2(src,raw)
        if src.exists():
            assert sha(raw)==sha(src)
        else:
            # В новом checkout полные исходники уже в Git, внешний кэш не обязателен.
            assert sha(raw)==json.loads((folder/'model.json').read_text(encoding='utf-8'))['source_sha256']
        im=Image.open(raw).convert('RGBA'); a=im.getchannel('A')
        assert a.getextrema()==(0,255)
        # Едва видимые пиксели ImageGen по всему холсту не задают размер фигуры.
        solid=a.point(lambda v:255 if v>=128 else 0).getbbox()
        bbox=(max(0,solid[0]-2),max(0,solid[1]-2),min(im.width,solid[2]+2),min(im.height,solid[3]+2))
        crop=im.crop(bbox)
        # Полный рисунок, включая оружие, помещается в152px; исходник неизменен.
        scale=min(152/crop.height,180/crop.width)
        size=(round(crop.width*scale),round(crop.height*scale))
        sprite=crop.resize(size,Image.Resampling.NEAREST)
        # Опора определяется по середине двух сапог в нижней полосе, без кончика меча.
        import numpy as np
        arr=np.array(sprite); h,w=arr.shape[:2]
        brown=(arr[:,:,0]>arr[:,:,2]*1.35)&(arr[:,:,0]>arr[:,:,1]*1.1)&(arr[:,:,3]>128)
        brown[:int(h*.88)]=False
        ys,xs=np.where(brown)
        foot_x=(int(xs.min())+int(xs.max()))/2 if len(xs) else w/2
        foot_y=int(ys.max())+1 if len(ys) else h
        offset=(round(128-foot_x),200-foot_y)
        canvas=Image.new('RGBA',(256,256));canvas.paste(sprite,offset)
        canvas.save(folder/'input-256.png')
        box=canvas.getbbox();assert box and min(box[:2])>0 and max(box[2:])<256
        record={'id':id,'source':str(src),'source_sha256':sha(raw),'source_size':im.size,'source_bbox':bbox,'input_sha256':sha(folder/'input-256.png'),'canvas':[256,256],'anchor':[128,200],'bbox':box,'scale_from_source':scale,'resampling':'nearest','offset':offset,'integration':False,'prompt':None if id in ('11','17') else PROMPT+f' Character variant {id}.','provider':'existing-project-imagegen' if id in ('11','17') else 'built-in-imagegen'}
        (folder/'model.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf-8')
        records.append(record)
        x=(index%3)*256;y=(index//3)*282
        sheet.paste(canvas,(x,y),canvas);draw.text((x+12,y+258),id,fill='white')
    sheet.save(ROOT/'models-contact.png')
    (ROOT/'models.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps([{'id':r['id'],'bbox':r['bbox']} for r in records]))

if __name__=='__main__': main()
