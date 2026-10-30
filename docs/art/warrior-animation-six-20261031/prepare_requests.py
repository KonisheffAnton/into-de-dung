"""Фиксирует54 разных запроса; сетевых вызовов и секретов здесь нет."""
from pathlib import Path
import json,base64
ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/warrior-animation-six-20261031')
ABILITIES={
 '02':('Удар щитом','Brace legs, draw shield back slightly then deliver one short forceful shield bash forward; sword stays guarded; recoil softly and return to starting stance.'),
 '05':('Тяжёлый удар сверху','Raise the greatsword with both hands, wind up, deliver one heavy overhead chop, follow through and recover to exact starting guard. Keep both hands on hilt.'),
 '11':('Воодушевление','Lift the sword in one assertive rally salute, open chest and give a silent battle cry, scarf follows late, then lower sword and return to starting stance.'),
 '12':('Защитная стойка','Raise blue heraldic shield across chest, bend knees to firmly brace against an unseen impact, settle and return to original guard. Keep sword in the other hand.'),
 '17':('Провокация щитом','Raise wooden shield slightly and strike its rim once with sword in a confident taunt, chest rises; let shield recoil slightly then return to starting stance.'),
 '18':('Широкий удар мечом','Wind the sword back with both hands, perform one broad diagonal sweeping sword cut across front, follow through then smoothly recover to starting stance.'),
}
IDLES=[
 'Very quiet breathing loop, like a smoothly articulated cutout rig. Feet and pelvis locked. Chest rises only1-2 pixels; shoulders, head, forearms and cloth follow with tiny staggered phase delays, then settle. No hopping, no whole-body scaling or bobbing. Slow organic inhale/exhale, exact return to first pose.',
 'Calm alert idle loop. Tiny weight transfer through torso only, shoulders subtly counterbalance. Both soles stay planted. One small glance with head, no turn of body, no stepping or weapon attack. Ease in and out and return to first pose.',
 'Calm ready idle loop. Subtle breath, a tiny delayed scarf/cape-tip sway and gentle grip adjustment. Boots fixed, blade angle stable. No bouncing, stepping or flourish. Return smoothly to first pose.'
]
DEATHS=[
 'One death: knees buckle, body sinks briefly then tips onto its near side by original feet. Keep weapons attached. End fully lying on side and completely still. Do not get up or loop.',
 'One death: small backward recoil, knees buckle, torso tips back and lands on back beside original feet. End fully supine, motionless. No standing recovery or loop.',
 'One death: shoulders sag, knees give way, body collapses forward and lands prone near original feet. End fully lying face down, completely still. No kneeling endpoint or recovery.'
]
COMMON='Animate the EXACT reference warrior, preserving face or helmet, hair, costume, equipment, proportions, pixel clusters and palette. Fixed camera and facing; no zoom, turn, redesign, extra limbs, duplicate weapons, VFX, gore, ground or shadow. Transparent256x256 canvas; starting soles near(128,200). Keep entire body and weapons within x8..248,y8..248. '

def main():
 rows=[]
 for n,(id,(title,ability)) in enumerate(ABILITIES.items()):
  frame={'base64':base64.b64encode((ROOT/'models'/('warrior-'+id)/'input-256.png').read_bytes()).decode(),'format':'png'}
  for kind in ('idle','death','ability'):
   for v in range(1,4):
    key=f'{id}-{kind}-{v}';folder=JOBS/'pixellab'/key;folder.mkdir(parents=True,exist_ok=True)
    if (folder/'submit-started.json').exists(): raise RuntimeError('Already attempted '+key)
    motion=(IDLES if kind=='idle' else DEATHS)[v-1] if kind!='ability' else ability+[' Controlled compact motion, clear anticipation and soft recovery.',' Stronger anticipation, decisive action, delayed cloth follow-through.',' Quicker action with short held emphasis, gentle settle and recovery.'][v-1]
    action=COMMON+motion;assert len(action)<=1000
    req={'first_frame':frame,'description':action,'frame_count':32,'seed':2026103100+n*20+('idle','death','ability').index(kind)*3+v,'no_background':True,'enhance_prompt':False}
    if kind!='death': req['last_frame']=frame
    (folder/'request.json').write_text(json.dumps(req),encoding='utf-8')
    (folder/'prompt.txt').write_text(action,encoding='utf-8')
    rows.append({'key':key,'id':id,'kind':kind,'variant':v,'ability_title':title,'prompt':action,'seed':req['seed'],'frame_count':32,'endpoint':'animate-pixminimax','loop':kind=='idle','return_to_first':kind!='death','input':f'models/warrior-{id}/input-256.png'})
 (ROOT/'requests.json').write_text(json.dumps(rows,ensure_ascii=False,indent=2),encoding='utf-8')
 print('Prepared',len(rows),'requests; no submissions.')

if __name__=='__main__':main()
