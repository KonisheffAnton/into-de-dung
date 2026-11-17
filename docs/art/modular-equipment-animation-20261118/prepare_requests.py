"""Готовит ограниченную серию PixelLab; сам не отправляет запросы."""
import argparse
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path('D:/Codex/home/generated_images/modular-equipment-animation-20261118')
SOURCE = REPO / 'assets/art_presets/approved/character_skins_v1/red_bastion/still.png'
OUTFITS = {
    'light': ('Лёгкий', 'olive padded sleeves, brown leather vest, small steel shoulder caps, brown boots'),
    'heavy': ('Тяжёлый', 'blue-grey steel breastplate, large plate pauldrons, bracers and greaves, short burgundy cape'),
}
WEAPONS = {
    'sword': ('Меч и щит', 'short broad iron sword and round wooden buckler',
              'Raises the sword for a short wind-up, delivers ONE crisp diagonal sword slash toward screen right while keeping the shield near the chest, then smoothly recovers to the starting ready pose.'),
    'axe': ('Топор и щит', 'one-handed iron battle axe and round wooden buckler',
            'Draws the axe back with a small torso twist, delivers ONE weighty downward axe chop toward screen right with a brief follow-through, then pulls the axe back to the starting ready pose. The shield stays on the other arm.'),
    'spear': ('Двуручное копьё', 'one wooden spear with a steel point held diagonally in BOTH hands, no sword and no shield',
              'Draws the spear slightly back in both hands, delivers ONE straight two-handed spear thrust toward screen right, then retracts the spear and smoothly recovers to the starting ready pose. Both hands remain attached to the same shaft.'),
}

def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')

def encoded(path):
    return {'base64': base64.b64encode(path.read_bytes()).decode('ascii')}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('phase', choices=['stills', 'animations'])
    args = parser.parse_args()
    plan_path = JOBS / 'plan.json'
    plan = json.loads(plan_path.read_text(encoding='utf-8')) if plan_path.exists() else []
    variants = []
    for oi, (outfit, (outfit_title, armor)) in enumerate(OUTFITS.items()):
        for wi, (weapon, (weapon_title, equipment, action)) in enumerate(WEAPONS.items()):
            ident = oi * 3 + wi + 1
            if outfit == 'heavy' and weapon != 'spear':
                equipment = equipment.replace('round wooden buckler', 'large red-and-steel kite shield')
            key = f'{outfit}-{weapon}'
            variants.append({'key':key,'outfit':outfit,'weapon':weapon,'title':f'{outfit_title} · {weapon_title}','still_id':ident})
            prompt = (f'Keep the SAME face, spiky auburn hair, red scarf, compact proportions, pixel style, scale and foot position. Face screen right. Change equipment to {armor}; {equipment}. Fully visible compact ready pose, entire weapon within the canvas. Transparent background. Preserve large clean pixel clusters.')
            assert len(prompt) <= 500
            if args.phase == 'stills':
                plan.append({'id':ident,'key':key,'kind':'still','endpoint':'/edit-image-pixen',
                    'source':str(SOURCE),'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
                    'request':{'image':encoded(SOURCE),'description':prompt,'width':256,'height':256,
                               'seed':181100+ident,'no_background':True}})
            else:
                source = JOBS / 'items' / f'{ident:03d}' / 'original.png'
                meta = json.loads((source.parent / 'result.json').read_text(encoding='utf-8'))
                assert meta['status'] == 'completed' and source.exists()
                for ki, kind in enumerate(('idle','attack')):
                    clip_id = 100 + ident*2 + ki
                    motion = ('One calm breathing cycle: chest and shoulders gently rise and fall, hands and equipment follow by a tiny amount, scarf settles softly. Feet remain planted. No stepping, no attacks, no turning. Return to the starting pose.' if kind == 'idle' else action + ' Use a compact action that keeps the entire weapon inside the frame. Keep both feet in the same area, retain facing, no full spin, no jumping, no extra attacks, no trails or effects.')
                    count = 16 if kind == 'idle' else 24
                    plan.append({'id':clip_id,'key':f'{key}-{kind}','variant':key,'kind':kind,
                        'title':f'{outfit_title} · {weapon_title}', 'source':str(source),
                        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                        'endpoint':'/animate-pixminimax','request':{
                            'first_frame':encoded(source),'last_frame':encoded(source),
                            'description':motion,'frame_count':count,'seed':181100+ident,
                            'no_background':True,'enhance_prompt':False,
                            'subject_description':f'Compact auburn-haired adventurer with red scarf, {armor}; {equipment}',
                            'initial_pose':'Standing in a compact combat-ready stance with equipment held securely and both feet planted',
                            'view':'low top-down','direction':'south-east'}})
    assert len({row['id'] for row in plan}) == len(plan), 'Refusing duplicate preparation'
    dump(plan_path,plan)
    dump(ROOT / 'variants.json',variants)
    dump(ROOT / 'requests.json',[{**{k:v for k,v in row.items() if k!='request'},
        'request':{k:v for k,v in row['request'].items() if k not in ('image','first_frame','last_frame')}} for row in plan])
    print(f'Prepared {len(plan)} requests; no API calls made')

if __name__ == '__main__':
    main()
