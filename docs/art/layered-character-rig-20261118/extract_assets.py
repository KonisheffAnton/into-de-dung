"""Извлекает статические детали из атласа; позы и движение здесь не создаются."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent
PARTS = [
    ('head',42,44,[.5,1]), ('torso',48,62,[.5,1]),
    ('pelvis',34,22,[.5,.5]), ('upper_arm',16,32,[.5,0]),
    ('forearm',14,28,[.5,0]), ('hand',12,14,[.5,.2]),
    ('leg_left',16,38,[.5,0]), ('leg_right',16,38,[.5,0]),
    ('armor_light',48,62,[.5,1]), ('armor_heavy',48,62,[.5,1]),
    ('shoulder_light',22,22,[.5,.2]), ('shoulder_heavy',22,22,[.5,.2]),
    ('sword',20,52,[.5,.86]), ('axe',28,52,[.22,.86]),
    ('bracer_light',16,24,[.5,0]), ('bracer_heavy',16,24,[.5,0]),
]

def main():
    source=ROOT/'parts-atlas-original.png'
    atlas=Image.open(source).convert('RGBA')
    manifest={'parts':{},'provenance':{'provider':'built-in image_gen','source':source.name,
        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
        'processing':'Equal4x4 cells, alpha>=128 content bbox +2px border, nearest resize; no generated motion, no retouching',
        'animation':'Local shared hierarchical transforms, explicitly requested by user2026-11-18'}}
    for i,(name,w,h,pivot) in enumerate(PARTS):
        x,y=i%4,i//4
        bounds=[round(x*atlas.width/4),round(y*atlas.height/4),round((x+1)*atlas.width/4),round((y+1)*atlas.height/4)]
        cell=atlas.crop(bounds)
        # Слабая alpha-пыль генератора не должна задавать размер самой детали.
        bbox=cell.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        assert bbox, name
        crop=[max(0,bbox[0]-2),max(0,bbox[1]-2),min(cell.width,bbox[2]+2),min(cell.height,bbox[3]+2)]
        piece=cell.crop(crop).resize((w,h),Image.Resampling.NEAREST)
        path=ROOT/'assets'/f'{name}.png';piece.save(path)
        manifest['parts'][name]={'file':f'assets/{name}.png','width':w,'height':h,'pivot':pivot,
            'flip_x':name=='head','source_cell':bounds,'source_crop':crop,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    (ROOT/'assets/manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Extracted16 static RGBA layers; motion not baked')

if __name__=='__main__':main()
