"""Prepare exactly two unsubmitted 64x64 masked legacy PixelLab pilots."""

from __future__ import annotations

import base64
import hashlib
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
ART = ROOT.parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-masked-retry-20261105')
PILOTS = ('fire23-01', 'caltrops03-01')
BOXES = {'fire23-01': (96, 67, 160, 131),
         'caltrops03-01': (94, 70, 158, 134)}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def encoded(path: Path) -> dict:
    return {'type': 'base64', 'base64': base64.b64encode(path.read_bytes()).decode('ascii'),
            'format': 'png'}


def save_json(path: Path, data: object) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def save_mask(path: Path, selected: np.ndarray) -> None:
    Image.fromarray(np.uint8(selected) * 255, mode='L').convert('RGB').save(path)


def main() -> None:
    if (ROOT / 'pilots.json').exists():
        raise SystemExit('Pilot payloads already prepared; do not overwrite')
    schema = json.loads((JOBS / 'openapi-prepared.json').read_text(encoding='utf-8'))
    contract = schema['components']['schemas']['AnimateWithTextRequest']
    size = schema['components']['schemas']['app__endpoints__external__v2__animate_with_text__ImageSize']
    base64_image = schema['components']['schemas']['Base64Image']
    fields = {'image_size', 'description', 'action', 'negative_description',
              'reference_image', 'inpainting_images', 'mask_images', 'n_frames',
              'start_frame_index', 'view', 'direction', 'image_guidance_scale',
              'text_guidance_scale', 'seed'}
    if contract.get('additionalProperties') is not False or not fields <= set(contract['properties']):
        raise SystemExit('Legacy mask API fields changed')
    if size['properties']['width']['minimum'] != 64 or size['properties']['width']['maximum'] != 64:
        raise SystemExit('Legacy size is no longer fixed 64')
    if base64_image.get('additionalProperties') is not False:
        raise SystemExit('Base64Image schema changed')
    if not 1 <= 2 <= 20 or not 1 <= 8 <= 20:
        raise SystemExit('Guidance out of schema range')
    rows = []
    for key in PILOTS:
        model = ROOT / 'model' / key
        model.mkdir(parents=True, exist_ok=False)
        if key.startswith('fire'):
            source = ART / 'fire-low-styles-20261104' / 'fire-low-23.png'
            prior_input = ART / 'fire-painted-sway-20261105' / 'model' / 'fire23' / 'input-256.png'
        else:
            source = ART / 'hazard-variants-20261103' / 'caltrops-03.png'
            prior_input = ART / 'hazard-animations-20261104' / 'model' / 'caltrops03' / 'input-256.png'
        shutil.copyfile(source, model / 'source-original.png')
        shutil.copyfile(prior_input, model / 'input-256.png')
        with Image.open(source) as image:
            if image.mode != 'RGBA' or image.size != (1254, 1254):
                raise SystemExit(f'Unexpected source: {source}')
            if not np.array_equal(np.asarray(image.resize((256, 256), Image.Resampling.LANCZOS)),
                                  np.asarray(Image.open(model / 'input-256.png'))):
                raise SystemExit(f'Original input does not reconstruct: {key}')
        box = BOXES[key]
        with Image.open(model / 'input-256.png') as image:
            roi = image.crop(box)
            if roi.mode != 'RGBA' or roi.size != (64, 64):
                raise SystemExit(f'Bad ROI: {key}')
            roi.save(model / 'roi-static.png')
        blank = np.zeros((64, 64), dtype=bool)
        save_mask(model / 'mask-0.png', blank)
        save_mask(model / 'mask-3.png', blank)
        if key.startswith('fire'):
            rgb = np.asarray(roi)[:, :, :3].astype(np.int16)
            warm = (rgb[:, :, 0] > 105) & (rgb[:, :, 0] > rgb[:, :, 1] + 35) & (rgb[:, :, 1] > rgb[:, :, 2] + 5)
            selected = np.zeros((64, 64), dtype=bool)
            for x0, y0, x1, y1 in ((15, 12, 35, 23), (32, 26, 53, 38)):
                selected[y0:y1, x0:x1] = warm[y0:y1, x0:x1]
            # Only narrow horizontal boundaries of the existing painted strokes may move.
            left = np.zeros_like(warm); left[:, 1:] = warm[:, :-1]
            right = np.zeros_like(warm); right[:, :-1] = warm[:, 1:]
            selected &= (~left | ~right)
            shifted = selected.copy()
            shifted[:, 1:] |= selected[:, :-1]
            shifted[:, :-1] |= selected[:, 1:]
            selected = shifted
            save_mask(model / 'mask-1.png', selected)
            save_mask(model / 'mask-2.png', selected)
            reference = model / 'roi-static.png'
            description = 'Finished close-up of the existing flat orange painted surface texture on an isometric stone tile.'
            action = ('Only the two masked existing orange brush-stroke areas sway horizontally by one pixel and return. '
                      'Keep their original height, flat shape, color and brightness. The unmasked painted surface stays still.')
            negative = 'new flames, rising shapes, sparks, stone movement, color pulse, camera movement'
            mask_note = 'Horizontal boundaries in two existing warm stroke patches, selected by original RGB and expanded one horizontal pixel; no side face.'
        else:
            old_frame = ART / 'hazard-animations-20261104' / 'pixellab' / 'caltrops03-01' / 'frames' / 'frame-10.png'
            shutil.copyfile(old_frame, model / 'accepted-glint-frame-10-original.png')
            with Image.open(old_frame) as image:
                image.crop(box).save(model / 'accepted-glint-reference-64.png')
            reference = model / 'accepted-glint-reference-64.png'
            first = np.zeros((64, 64), dtype=bool)
            second = np.zeros((64, 64), dtype=bool)
            first[13:16, 33:36] = True
            second[43:46, 42:45] = True
            save_mask(model / 'mask-1.png', first)
            save_mask(model / 'mask-2.png', second)
            description = 'Finished close-up of dark stationary steel caltrops on a stone top, matching the accepted rare-glint reference.'
            action = ('Keep every existing steel point and all stone completely still. '
                      'Only one tiny glint appears briefly at the first masked metal tip, then one at the second masked metal tip. '
                      'The first and last pictures stay calm and identical.')
            negative = 'moving caltrops, growing spikes, broad stars, stone shimmer, camera movement'
            mask_note = 'Two separate 3x3 boxes on existing metal tips; first/last masks fully black.'
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=False)
        masks = [encoded(model / f'mask-{i}.png') for i in range(4)]
        request = {'image_size': {'width': 64, 'height': 64},
                   'description': description, 'action': action,
                   'negative_description': negative,
                   'reference_image': encoded(reference),
                   'inpainting_images': [encoded(model / 'roi-static.png') for _ in range(4)],
                   'mask_images': masks, 'n_frames': 4, 'start_frame_index': 0,
                   'view': 'high top-down', 'direction': 'south-east',
                   'image_guidance_scale': 8, 'text_guidance_scale': 2,
                   'seed': 20261105051 + len(rows)}
        if set(request) != fields:
            raise SystemExit('Unexpected payload fields')
        request_path = folder / 'request.json'
        request_path.write_text(json.dumps(request, separators=(',', ':')), encoding='utf-8')
        (folder / 'prompt.txt').write_text(action + '\n', encoding='utf-8')
        mask_counts = [int(np.count_nonzero(np.asarray(Image.open(model / f'mask-{i}.png'))[:, :, 0])) for i in range(4)]
        if mask_counts[0] or mask_counts[3] or not mask_counts[1] or not mask_counts[2]:
            raise SystemExit(f'Mask endpoint/area error: {key}')
        row = {'key': key, 'endpoint': 'animate-with-text', 'source': str(source.relative_to(ART)).replace('\\', '/'),
               'source_sha256': sha(source), 'input_sha256': sha(model / 'input-256.png'),
               'roi_xyxy': list(box), 'roi_sha256': sha(model / 'roi-static.png'),
               'reference_sha256': sha(reference), 'mask_sha256': [sha(model / f'mask-{i}.png') for i in range(4)],
               'mask_white_pixels': mask_counts, 'mask_note': mask_note,
               'description': description, 'action': action, 'negative_description': negative,
               'image_guidance_scale': 8, 'text_guidance_scale': 2,
               'seed': request['seed'], 'request_sha256': sha(request_path),
               'raw_api_canvas': [64, 64], 'derived_canvas': [256, 256],
               'assembly': 'Integer ROI placement only; no scale/pixel retouch',
               'prepared_before_post': True}
        rows.append(row)
    save_json(ROOT / 'pilots.json', rows)
    print(json.dumps({'prepared': len(rows), 'post': False,
                      'mask_white_pixels': {r['key']: r['mask_white_pixels'] for r in rows}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
