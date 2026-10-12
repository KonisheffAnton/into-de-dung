"""PixelLab creates the complete transition between two reviewed poses."""
import base64
import hashlib
import json
from pathlib import Path

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
first = ROOT / 'docs/art/rogue-buff-outline-20261012/reference-128.png'
last = OUT / 'death-end-pose/pixellab/frame-01.png'
request = {
    'first_frame': {'type': 'base64', 'format': 'png', 'base64': base64.b64encode(first.read_bytes()).decode()},
    'last_frame': {'type': 'base64', 'format': 'png', 'base64': base64.b64encode(last.read_bytes()).decode()},
    'frame_count': 12, 'seed': 2026101254, 'no_background': True, 'enhance_prompt': False,
    'action': 'One quick non-looping death from the supplied standing pose to the supplied final corpse. Begin losing balance immediately: one knee buckles, torso folds, then the rogue drops heavily onto his side with brief small settling. Finish EXACTLY in the supplied diagonal isometric floor pose, head lower-right, feet upper-left, viewed from above. No pause at the start, no long kneeling, slow-motion or extra rotation. Preserve the same physical body size, face, hood, palette, fixed camera and canvas registration throughout. Keep two original rigid daggers, same lengths, no duplicates. Both hands and daggers rest on the ground at the end. Keep whole body and weapons inside the canvas. Dead body remains fully visible and still; no recovery, rising, rolling away, fading, blood, trails, glow, background or painted shadows. Discrete crisp pixel-art key poses; no rubbery body, smooth smearing or black outlines.'
}
target = OUT / 'death-fast'
target.mkdir(exist_ok=True)
(target / 'request.json').write_text(json.dumps(request, indent=2)+'\n', encoding='utf-8')
(target / 'inputs.json').write_text(json.dumps([
    {'path': p.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
    for p in [first, last]
], indent=2)+'\n', encoding='utf-8')
print('Prepared complete death request with exact first/last pose references.')
