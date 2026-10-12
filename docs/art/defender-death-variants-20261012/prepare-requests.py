"""Prepare three distinct PixelLab death motions. No network or game edits."""
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'defender-shield-taunt-fluid-20261011/pixellab/reference-128.png'
source = SOURCE.read_bytes()
reference = ROOT / 'reference-128.png'
assert not reference.exists() or reference.read_bytes() == source
reference.write_bytes(source)
image = {'type': 'base64', 'base64': base64.b64encode(source).decode('ascii'), 'format': 'png'}
common = (
    'One continuous grounded death, no loop. Clear weight, anticipation and connected limb motion. '
    'Keep the body and both weapons fully inside the canvas, near the original ground position. '
    'Same armor, helmet, sword and shield throughout. No spinning, leaping, flying weapons, '
    'blood, particles, dust, flashes, trails, text, fading or camera movement. '
    'Finish completely motionless on the ground and stay dead; never stand up or return to the starting pose.'
)
motions = [
    ('01-forward-shield', 'Вперёд на щит',
     'The defender reels briefly, his knees buckle and he drops his shield edge to the ground in front. '
     'He tries to support his weight on the shield, but his arms give out. He pitches forward heavily '
     'over the falling shield and settles face-down with his torso on the flat shield, helmet low, '
     'knees and boots behind. The sword hand falls beside his body; the sword remains close. '
     'A small natural settling movement ends the fall. '),
    ('02-backward', 'Тяжёлое падение назад',
     'The defender takes an invisible fatal hit to the chest. His chest recoils, knees give way '
     'and he loses balance backward without jumping. Hips descend first, then his upper back and '
     'helmet settle on the ground behind his original feet. End lying fully on his back, legs '
     'relaxed toward the front, shield lowered beside his torso and short sword beside the right hand. '
     'One short heavy impact and minimal settling; no repeated bouncing. '),
    ('03-last-knee', 'Последняя опора на меч',
     'The wounded defender sinks onto one knee and plants the sword tip on the ground to support himself. '
     'He holds this failing kneel for a brief beat, head bowed, shield drooping. His sword arm gives way, '
     'his torso tilts toward his shield side on screen-right and he collapses sideways into a compact '
     'curled body lying on its side, helmet and shoulder resting on the ground, shield beside the chest. '
     'The sword tilts down with the hand and stays close. Finish with a small heavy settling motion. '),
]
variants = []
for index, (slug, title, motion) in enumerate(motions):
    request = {
        'first_frame': image, 'description': motion + common, 'frame_count': 32,
        'seed': 20261020 + index, 'no_background': True, 'enhance_prompt': False,
        'direction': 'south-east', 'view': 'high top-down',
        'subject_description': 'A compact helmeted human defender in simple steel armor and olive cloth, a short sword in his right hand on screen-left and a broad olive shield in his left hand on screen-right; chunky quiet pixel clusters with minimal detail.',
        'initial_pose': 'Standing in a wide braced stance with bent knees, sword lowered diagonally on screen-left, shield raised on screen-right, leaning slightly forward and facing lower-right. Full body on a transparent 128 by 128 canvas.',
    }
    assert len(request['description']) <= 1000, (slug, len(request['description']))
    assert all(len(request[field]) <= 300 for field in ['subject_description', 'initial_pose'])
    target = ROOT / slug / 'pixellab'
    target.mkdir(parents=True, exist_ok=True)
    path = target / 'request.json'
    encoded = json.dumps(request, ensure_ascii=False, indent=2) + '\n'
    assert not path.exists() or path.read_text(encoding='utf-8') == encoded, 'Refuse to replace a request'
    path.write_text(encoded, encoding='utf-8', newline='\n')
    variants.append({'id': slug, 'title': title, 'request_sha256': hashlib.sha256(encoded.encode()).hexdigest(),
                     **{key: value for key, value in request.items() if key != 'first_frame'}})
manifest = {
    'scope': 'Three offline death-animation alternatives requested by U2026-10-12; user selection and integration pending.',
    'endpoint': 'https://api.pixellab.ai/v2/animate-pixminimax',
    'schema_verified': '2026-10-12 https://api.pixellab.ai/v2/openapi.json',
    'reference': str(SOURCE.relative_to(ROOT.parent)).replace('\\', '/'),
    'reference_sha256': hashlib.sha256(source).hexdigest(),
    'last_frame_omitted': 'A death must end on the ground, not return to its living start pose.',
    'variants': variants,
}
(ROOT / 'request-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'variants': len(variants), 'description_lengths': [len(v['description']) for v in variants], 'frames_requested_each': 32}))
