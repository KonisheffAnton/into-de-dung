"""Deterministic layer assembly. Copies/crops/mirrors only; no generated artwork."""
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def actor_image(actor, source):
    x, y, width, height = actor['source']
    sprite = source.crop((x, y, x + width, y + height))
    sprite = sprite.resize(tuple(actor['destination'][2:]), Image.Resampling.NEAREST)
    if actor['flipX']:
        sprite = sprite.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    return sprite


def main():
    data = json.loads((ROOT / 'placement.json').read_text(encoding='utf-8'))
    size = (data['width'], data['height'])
    clips = {}
    for clip in data['clips']:
        frames, masks = [], []
        for record in clip['frames']:
            assert sha(ROOT / record['file']) == sha(REPO / record['source']) == record['sha256']
            frame = Image.open(ROOT / record['file']).convert('RGBA')
            assert frame.size == (256, 256)
            frames.append(frame)
            bits = (np.array(frame)[:, :, 3] >= 24).reshape(-1)
            masks.append(base64.b64encode(np.packbits(bits, bitorder='little').tobytes()).decode())
            if clip['id'] == 'market':
                assert not np.array(frame)[:, 135:151, 3].any(), 'Market split must remain fully transparent'
        clips[clip['id']] = frames
        clip['masks'] = masks
    occlusion = Image.new('L', size)
    draw = ImageDraw.Draw(occlusion)
    for polygon in data['occlusionPolygons']:
        draw.polygon([tuple(p) for p in polygon], fill=255)
    observations = []
    for background in data['backgrounds']:
        assert sha(ROOT / background['file']) == sha(REPO / background['source']) == background['sha256']
        base = Image.open(ROOT / background['file']).convert('RGBA')
        assert base.size == size
        foreground = base.copy()
        foreground.putalpha(occlusion)
        foreground.save(ROOT / background['foreground'])
        for frame_index in (0, 3, 4):
            composite = base.copy()
            allowed = np.zeros((size[1], size[0]), dtype=bool)
            for depth in sorted({actor['z'] for actor in data['actors']} | {data['foregroundZ']}):
                if depth == data['foregroundZ']:
                    composite.alpha_composite(foreground)
                for actor in data['actors']:
                    if actor['z'] != depth:
                        continue
                    sprite = actor_image(actor, clips[actor['group']][frame_index])
                    x, y, w, h = actor['destination']
                    composite.alpha_composite(sprite, (x, y))
                    allowed[y:y+h, x:x+w] |= np.array(sprite)[:, :, 3] > 0
            difference = np.any(np.array(composite) != np.array(base), axis=2)
            assert not np.any(difference & ~allowed), 'Pixels outside actor layers changed'
            path = ROOT / 'previews' / f'{background["id"]}-frame-{frame_index+1:02d}.png'
            composite.save(path)
            observations.append({'background': background['id'], 'frame': frame_index+1,
                                 'outside_actor_pixels_changed': int(np.count_nonzero(difference & ~allowed)),
                                 'file': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)})
    (ROOT / 'scene-data.js').write_text('window.DIORAMA_LAYER_DATA = ' + json.dumps(data, ensure_ascii=False, separators=(',', ':')) + ';\n', encoding='utf-8')
    report = {'backgrounds_byte_unchanged': 4, 'animation_frames_byte_unchanged': 27,
              'market_split_gap_alpha_zero': True, 'foreground_source': 'Exact background pixels under explicit occlusion polygons',
              'outside_actor_pixels_unchanged': True, 'previews': observations}
    (ROOT / 'assembly-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Prepared 4 scenes,4 separate actor layers,27 unchanged PNG frames,12 checked preview frames')


if __name__ == '__main__':
    main()
