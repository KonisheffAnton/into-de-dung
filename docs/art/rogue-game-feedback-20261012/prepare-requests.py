"""Prepare explicit PixelLab edits; never reads credentials or paints source pixels."""
import base64
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
OLD = ROOT / 'docs/art/rogue-buff-outline-20261012'


def image(path):
    return {'type': 'base64', 'format': 'png', 'base64': base64.b64encode(path.read_bytes()).decode()}


def write(name, request, sources):
    directory = OUT / name
    directory.mkdir(exist_ok=True)
    (directory / 'request.json').write_text(json.dumps(request, indent=2) + '\n', encoding='utf-8')
    provenance = [{'path': p.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in sources]
    (directory / 'inputs.json').write_text(json.dumps(provenance, indent=2) + '\n', encoding='utf-8')


manifest = json.loads((OLD / 'final/manifest.json').read_text(encoding='utf-8'))
buff_sources = [(OLD / manifest['frames'][i]['source']).resolve() for i in [2, 3]]
reference = OLD / 'reference-128.png'
buff = {
    'method': 'edit_with_reference',
    'edit_images': [{'image': image(p), 'width': 128, 'height': 128} for p in buff_sources],
    'reference_image': {'image': image(reference), 'width': 128, 'height': 128},
    'image_size': {'width': 128, 'height': 128}, 'no_background': True, 'seed': 2026101251,
    'description': 'Make this rogue dagger-opening gesture slightly wider and more aggressive, while keeping the same character, body size, feet and camera. The separate reference gives exact identity, palette and dagger size. Image 1 is the explosive peak immediately after uncrossing the blades: pull BOTH forearms decisively farther OUT to opposite sides, roughly 20 percent wider fist-to-fist span than now, with elbows flared and shoulders driving a strong muscular outward rip. Keep hands around waist level, not a horizontal T-pose. Chest opens with effort, small forward crouch, grounded feet. Image 2 is the short settling follow-through: retain most of that wider arm span, a little recoil in elbows, visibly smaller movement than the initial burst. Do not return all the way to neutral yet. Exactly TWO rigid single-ended steel daggers, one per fist; keep each blade approximately 20 native pixels guard-to-tip and 4 pixels wide, same grips as reference, no shrinking, lengthening, duplicate blades, smears or trails. Maintain hood and face attached to torso, same face and expression. Preserve original olive cloth, brown leather and muted steel palette; retain soft dark-gray #211e21 edge colors, DO NOT add a black outline. Keep boots in their current fixed positions and preserve overall body/canvas position. Transparent 128x128 crisp pixel art. No glow, effects, extra objects, blur or antialiasing.'
}
write('buff-wide', buff, buff_sources + [reference])

death_sources = [ROOT / f'docs/art/rogue-buff-death-variants-20261012/death-03-side/pixellab/frame-{i:02d}.png' for i in range(1, 14)]
death = {
    'frames': [{'image': image(p), 'size': {'width': 128, 'height': 128}} for p in death_sources],
    'image_size': {'width': 128, 'height': 128}, 'no_background': True, 'seed': 2026101252,
    'description': 'Correct the landing perspective of this existing 13-frame rogue death animation for an ISOMETRIC tactical board viewed from above, with a 4:3 diamond tile. Preserve the same side-fall action, identity, olive hood, face, leather armor, two original daggers, body size and canvas registration. Frames 1-4 retain the standing start and initial loss of balance. As he drops, turn his body naturally onto the floor plane so the final corpse lies ALONG the tile diagonal, from feet at the UPPER LEFT to head at the LOWER RIGHT of the image. The projected head-to-feet axis must slope DOWN RIGHT about 35-37 degrees, not lie horizontally across the screen. Show the top planes of the hood, shoulder and back from the same elevated three-quarter camera as the standing rogue. The torso, bent legs and arms all rest on that one flat ground plane, with plausible foreshortening; not a side-view cutout rotated in the image. Final head near (93,103), boots near (41,65), body centered near (69,87); keep all pixels inside the 128x128 canvas. Through frames 5-11, progressively reach this corrected diagonal landing without a sudden last-frame rotation; frames 12-13 settle motionless on his side. Keep dagger count exactly two, consistent reference blade lengths and grips, both lying naturally with the hands. No camera change, perspective grid, tile, painted shadow, new objects, blood, glow or trails. Preserve muted reference colors and dark-gray outline, no added thick black border. Crisp transparent pixel art with no smoothing. Return the same ordered 13 poses.'
}
write('death-isometric', death, death_sources)
end_pose = {
    'method': 'edit_with_reference',
    'edit_images': [{'image': image(death_sources[-1]), 'width': 128, 'height': 128}],
    'reference_image': {'image': image(reference), 'width': 128, 'height': 128},
    'image_size': {'width': 128, 'height': 128}, 'no_background': True, 'seed': 2026101253,
    'description': 'Correct this final fallen rogue pose to the floor perspective of an ISOMETRIC tactical board. The reference is the standing SAME character and gives the elevated three-quarter camera, identity, equipment and muted pixel palette. Keep him DEAD LYING ON HIS SIDE, do not stand him up. Reproject his whole fallen body onto one flat ground plane so the feet are at UPPER LEFT and hooded head at LOWER RIGHT; the body axis slopes DOWN RIGHT about 35-37 degrees along an isometric diamond tile edge. The existing horizontal side-view corpse is wrong. Show the TOP planes of hood, back and shoulder, with natural depth foreshortening. This is not a flat side-view cutout just rotated. Compact bent legs at upper-left near (42,63), head resting on lower-right near (91,102), torso midway near (65,80), whole character within canvas and close to the original physical size. Arms and two unchanged daggers rest naturally on the same ground; no raised weapon pointing vertically, no extra hands or blades. Preserve olive hood, brown leather, same face, large simple pixel clusters, original steel daggers and soft dark-gray edge #211e21; no new black outline. Transparent 128x128 pixel art; no tile, floor, grid, shadow, gore, effects or background. Return only the corrected final lying pose.'
}
write('death-end-pose', end_pose, [death_sources[-1], reference])
print('Prepared requests and input provenance without changing source pixels.')
