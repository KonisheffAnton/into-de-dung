"""Статические детали и три слота; анимацию здесь не запекаем."""
from pathlib import Path
from PIL import Image
import json,hashlib
ROOT=Path(__file__).resolve().parent
OLD=ROOT.parent/'layered-character-rig-20261118'
def main():
    old=json.loads((OLD/'assets/manifest.json').read_text(encoding='utf-8'))
    specs={'head':(38,40,[.5,1]),'torso':(50,48,[.5,1]),'pelvis':(40,22,[.5,.5]),
           'upper_arm':(18,28,[.5,.10]),'forearm':(16,27,[.5,.10]),'hand':(13,14,[.5,.3]),
           'sword':(20,50,[.5,.86]),'axe':(28,50,[.22,.86])}
    parts={}
    (ROOT/'assets').mkdir(exist_ok=True)
    def save(key,im,w,h,pivot,origin,flip=False):
        dest=ROOT/'assets'/f'{key}.png';im.resize((w,h),Image.Resampling.NEAREST).save(dest)
        parts[key]={'file':f'assets/{key}.png','width':w,'height':h,'pivot':pivot,'flip_x':flip,
                    'sha256':hashlib.sha256(dest.read_bytes()).hexdigest(),'origin':origin}
    for key,(w,h,pivot) in specs.items():
        src=OLD/old['parts'][key]['file'];save(key,Image.open(src).convert('RGBA'),w,h,pivot,
          {'path':str(src.relative_to(ROOT.parent)),'sha256':hashlib.sha256(src.read_bytes()).hexdigest()},key=='head')
    atlas=Image.open(ROOT/'joints-helmet-atlas.png').convert('RGBA')
    new=[('thigh_far',20,28,[.5,.10]),('thigh_near',20,28,[.5,.10]),
         ('shin_far',15,29,[.5,.10]),('shin_near',15,29,[.5,.10]),
         ('boot_far',23,18,[.7,.2]),('boot_near',23,18,[.3,.2]),
         ('helmet',44,44,[.5,1]),('helmet_profile',42,44,[.5,1])]
    for i,(key,w,h,pivot) in enumerate(new):
        x,y=i%4,i//4;box=[round(x*atlas.width/4),round(y*atlas.height/2),round((x+1)*atlas.width/4),round((y+1)*atlas.height/2)]
        cell=atlas.crop(box);bbox=cell.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();assert bbox
        crop=[max(0,bbox[0]-2),max(0,bbox[1]-2),min(cell.width,bbox[2]+2),min(cell.height,bbox[3]+2)]
        save(key,cell.crop(crop),w,h,pivot,{'atlas':'joints-helmet-atlas.png','cell':box,'crop':crop})
    atlas=Image.open(ROOT/'full-suit-atlas.png').convert('RGBA')
    suit=[('light','torso',50,48,[.5,1]),('light','pelvis',42,23,[.5,.5]),
          ('light','upper_arm',22,28,[.5,.10]),('light','forearm',18,27,[.5,.10]),
          ('light','thigh',22,28,[.5,.10]),('light','shin',17,29,[.5,.10]),
          ('heavy','torso',50,48,[.5,1]),('heavy','pelvis',42,23,[.5,.5]),
          ('heavy','upper_arm',22,28,[.5,.10]),('heavy','forearm',18,27,[.5,.10]),
          ('heavy','thigh',22,28,[.5,.10]),('heavy','shin',17,29,[.5,.10])]
    for i,(kind,part,w,h,pivot) in enumerate(suit):
        x,y=i%4,i//4;box=[round(x*atlas.width/4),round(y*atlas.height/3),round((x+1)*atlas.width/4),round((y+1)*atlas.height/3)]
        cell=atlas.crop(box);bbox=cell.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox();assert bbox
        crop=[max(0,bbox[0]-2),max(0,bbox[1]-2),min(cell.width,bbox[2]+2),min(cell.height,bbox[3]+2)]
        save(f'armor_{kind}_{part}',cell.crop(crop),w,h,pivot,{'atlas':'full-suit-atlas.png','cell':box,'crop':crop})
    manifest={'parts':parts,'equipment_slots':['weapon','armor','helmet'],
              'armor_sets':{kind:[f'armor_{kind}_{p}' for p in ('torso','pelvis','upper_arm','forearm','thigh','shin')] for kind in ('light','heavy')},
              'provenance':{'static_new':'built-in image_gen','motion':'shared local projected2D rig','atlas_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in ('joints-helmet-atlas.png','full-suit-atlas.png')}}}
    (ROOT/'assets/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8',newline='\n')
    print(f'{len(parts)} static parts; armor is one complete torso/arms/legs set; only weapon/armor/helmet are equipment')
if __name__=='__main__':main()
