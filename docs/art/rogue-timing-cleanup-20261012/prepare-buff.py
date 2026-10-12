"""Prepare two PixelLab in-between poses; source images remain untouched."""
from pathlib import Path
import base64
import hashlib
import json

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
OLD = ROOT / 'docs/art/rogue-game-feedback-20261012'
peak = OLD / 'buff-final/release.png'
cross = OLD / 'inputs/cross.png'
job = OUT / 'buff-deceleration'
job.mkdir(exist_ok=True)

def picture(p):
    return {'image': {'type':'base64','format':'png','base64':base64.b64encode(p.read_bytes()).decode()},'width':128,'height':128}

description = '''Create TWO ordered in-between poses for this rogue opening his crossed daggers with explosive force then DECELERATING as his arms reach maximum spread. Both edit inputs are the EXACT final wide-open endpoint; the reference is the crossed starting pose. Do NOT change either character design. Output image 1: already 80 percent of the distance from the crossed pose to the wide-open endpoint, both forearms thrust outward, hands still clearly closer together than the supplied endpoint. Output image 2: 94 percent of that distance, almost the full supplied spread, only a small outward movement remains. These are two DIFFERENT progressively wider poses, not duplicate endpoints and not a return to idle. Motion starts with a sudden metallic snap out of the cross, loses speed near full extension, then comes to rest at the supplied wide-open pose. Preserve the endpoint's exact planted boots, leg positions, torso/hood/face size and camera registration in BOTH outputs; only elbows, forearms, hands and their TWO daggers should move. Keep shoulders stable. Keep both original rigid daggers the SAME length and width in every pose, exactly one blade per fist, no four blades, double tips, shrinking, smears or trails. Preserve original olive cloth/brown leather/muted steel colors, clean large flat pixel clusters, original dark-gray #211e21 contour, NO black outline, noisy speckle, dithering, blur or gradients. Fixed elevated isometric camera, fixed 128x128 transparent canvas, same character location. No background, floor, shadow, effects, objects or text.'''
assert len(description) <= 2000
request = {'method':'edit_with_reference','edit_images':[picture(peak),picture(peak)],
    'reference_image':picture(cross),'image_size':{'width':128,'height':128},
    'no_background':True,'seed':2026101261,'description':description}
(job/'request.json').write_bytes((json.dumps(request,indent=2)+'\n').encode())
(job/'inputs.json').write_bytes((json.dumps([{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in [peak,cross]],indent=2)+'\n').encode())
print('Prepared 2 in-between poses; no source pixel edits.')
