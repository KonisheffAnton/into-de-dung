"""Prepare exactly five non-attack ability candidates; never overwrite attempted jobs."""
from pathlib import Path
import base64
import hashlib
import json
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'rvanoukh-animation-20261115'
JOBS = Path('D:/Codex/home/generated_images/rvanoukh-abilities-five-20261115')
CAPTIONS = {
    'direction': 'south-east', 'view': 'low top-down',
    'subject_description': 'A small pale grey beastlike hunched goblin with a massive brow, torn pointed ears, short bent legs, long clawed arms, three yellow blisters on its hump, a ragged brown loincloth with holes, and one short iron-headed club in its right hand',
    'initial_pose': 'Deeply crouched facing screen right, huge head low ahead of its hump, both clawed feet planted, free clawed hand near the ground, other hand holding the short club diagonally across the belly',
}
MOTIONS = [
    ('Рык', 'One non-contact intimidation roar. Sink slightly lower, inhale with a broad shoulder expansion, draw the muzzle back a little, then open the jaw in one strong rasping roar. The low head pushes only a few pixels forward; shoulders shudder once and ears lag behind. Hold the open-mouth silhouette briefly, close the jaw and slowly settle into the exact original crouch. The club hand stays down across the belly throughout. No weapon swing, strike, bite, projectile or magic effect.'),
    ('Прикрыться', 'One defensive bracing gesture. Lower the head behind the heavy brow and compact the hump. Lift the free forearm slowly from the ground to shield the side of the face, claws curled inward, while tucking the club close against the belly without swinging. Hold a low compact protective silhouette, then lower the free palm back onto the original spot and relax to the exact original crouch. No strike, weapon wind-up, push, lunge, contact, projectile or magic effect.'),
    ('Взять след', 'One deliberate scent-tracking ability gesture, larger and clearer than quiet idle sniffing. Lower the broad muzzle almost to the ground, sweep it slowly from near the planted free claw toward screen right, pause for two clear short sniffs, then tilt one torn ear as if locating a smell. Draw the muzzle back and settle into the exact original crouch. The torso follows in a low compact arc; the club stays tucked across the belly. No bite, strike, weapon swing, target, projectile or magic effect.'),
    ('Чутьё земли', 'One ground-listening gesture. Slowly spread the free claws and gently flatten that palm on the ground directly beneath its current position. Sink the low head and lean the ear toward the planted palm as if listening through the earth. Pause in this weighted listening pose; the shoulder and hump give one small responsive tremor. Ease the weight back, curl the fingers and return to the exact original crouch. The club remains low across the belly. No ground slam, hit, forceful impact, weapon swing, projectile or magic effect.'),
    ('Стряхнуть', 'One beastlike shake-off gesture. Tense the shoulders in a deeper crouch, then give one short controlled left-right body shiver that travels from the heavy head through the hump. The loose torn ears and ragged cloth lag and flap once; the claws flex. Keep the muzzle low and the club tucked firmly against the belly. Let the wobble settle and return to the exact original crouch and hand placement. No weapon swing, strike, biting, stomping, leap, target, projectile or magic effect.'),
]
COMMON = ' Keep both short feet planted at the same spot and the spine deeply hunched, never stand taller or turn around. Preserve the small body size, simple pixel clusters and torn clothing. Fixed camera and scale, transparent background, whole figure and club within the canvas with empty edge margins.'

def main():
    keys = [f'ability-{i}' for i in range(1, 6)]
    for key in keys:
        if (JOBS / 'pixellab' / key / 'submit-started.json').exists():
            raise SystemExit(f'Already attempted {key}; requests are immutable')
    schema = json.load(urllib.request.urlopen('https://api.pixellab.ai/v2/openapi.json'))
    endpoint = schema['paths']['/animate-pixminimax']['post']
    model = schema['components']['schemas']['AnimatePixminimaxRequest']
    (ROOT / 'endpoint-schema.json').write_text(json.dumps({'source': 'https://api.pixellab.ai/v2/openapi.json', 'endpoint': endpoint, 'request_schema': model}, indent=2) + '\n', encoding='utf-8')
    (ROOT / 'model').mkdir(exist_ok=True)
    for filename in ('input-256.png', 'source-full.png', 'input-manifest.json'):
        shutil.copyfile(SOURCE / 'model' / filename, ROOT / 'model' / filename)
    source = (ROOT / 'model/input-256.png').read_bytes()
    frame = {'base64': base64.b64encode(source).decode('ascii'), 'format': 'png'}
    rows = []
    for i, (name, motion) in enumerate(MOTIONS, 1):
        prompt = motion + COMMON
        assert 1 <= len(prompt) <= 1000, (name, len(prompt))
        request = {'first_frame': frame, 'last_frame': frame, 'description': prompt,
                   'frame_count': 32, 'seed': 2026111550 + i,
                   'no_background': True, 'enhance_prompt': False, **CAPTIONS}
        assert set(request).issubset(model['properties'])
        assert all(len(CAPTIONS[k]) <= 300 for k in ('initial_pose', 'subject_description'))
        folder = JOBS / 'pixellab' / f'ability-{i}'
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'request.json').write_text(json.dumps(request), encoding='utf-8')
        row = {'key': f'ability-{i}', 'kind': 'ability', 'variant': i, 'name': name, 'title': name,
               'prompt': prompt, 'seed': request['seed'], 'frame_count': 32, 'expected_frames': 33,
               'endpoint': 'animate-pixminimax', 'loop': False, 'return_to_first': True,
               'input': 'model/input-256.png', 'input_sha256': hashlib.sha256(source).hexdigest(),
               'captions': CAPTIONS, 'attack': False, 'gameplay_mechanic_defined': False}
        rows.append(row)
    (ROOT / 'requests.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    shutil.copyfile(ROOT / 'invoke-pixellab.ps1', JOBS / 'invoke-pixellab.ps1')
    print('Prepared exactly five non-attack requests; no submissions')

if __name__ == '__main__':
    main()
