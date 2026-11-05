"""Prepare the thirteen remaining masked probes; never sends a request."""

from pathlib import Path
import json
import shutil

import numpy as np
from PIL import Image

from prepare_pilots import ROOT, ART, JOBS, encoded, sha, save_json, save_mask


def playback(row: dict) -> dict:
    row = dict(row)
    row.pop('post_attempted', None)
    row['prepared_before_post'] = True
    row['variant'] = int(row['key'][-2:])
    row['source_key'] = row['key'].rsplit('-', 1)[0]
    row['kind'] = 'fire' if row['key'].startswith('fire') else 'caltrops'
    if row['kind'] == 'fire':
        row['playback_order'] = [0, 1, 2, 3]
        row['durations_ms'] = [350, 350, 350, 350]
    elif row['variant'] == 3:
        row['playback_order'] = [0, 1, 0, 2, 0, 1, 3]
        row['durations_ms'] = [4000, 160, 4000, 160, 4000, 160, 4000]
    else:
        hold = 4000 if row['variant'] == 1 else 5000
        row['playback_order'] = [0, 1, 0, 2, 3]
        row['durations_ms'] = [hold, 160, hold, 160, hold]
    return row


def main() -> None:
    destination = ROOT / 'requests.json'
    if destination.exists():
        raise SystemExit('Final manifest already exists; no overwrite')
    pilots = json.loads((ROOT / 'pilots.json').read_text(encoding='utf-8'))
    existing = {r['key']: playback(r) for r in pilots}
    base_requests = {k: json.loads((JOBS / 'pixellab' / k / 'request.json').read_text(encoding='utf-8')) for k in existing}
    schema = json.loads((JOBS / 'openapi-prepared.json').read_text(encoding='utf-8-sig'))
    allowed = set(schema['components']['schemas']['AnimateWithTextRequest']['properties'])
    keys = [f'fire{source}-{variant:02d}' for source in (22, 23, 24, 29) for variant in (1, 2, 3)]
    keys += [f'caltrops03-{variant:02d}' for variant in (1, 2, 3)]
    rows = []
    for index, key in enumerate(keys):
        if key in existing:
            rows.append(existing[key])
            continue
        variant = int(key[-2:])
        fire = key.startswith('fire')
        model = ROOT / 'model' / key
        model.mkdir(parents=True, exist_ok=False)
        if fire:
            number = key[4:6]
            source = ART / 'fire-low-styles-20261104' / f'fire-low-{number}.png'
            prior_input = ART / 'fire-painted-sway-20261105' / 'model' / f'fire{number}' / 'input-256.png'
            box = (96, 67, 160, 131)
        else:
            source = ART / 'hazard-variants-20261103' / 'caltrops-03.png'
            prior_input = ART / 'hazard-animations-20261104' / 'model' / 'caltrops03' / 'input-256.png'
            box = (94, 70, 158, 134)
        shutil.copyfile(source, model / 'source-original.png')
        shutil.copyfile(prior_input, model / 'input-256.png')
        full = Image.open(prior_input).convert('RGBA')
        assert np.array_equal(np.asarray(Image.open(source).resize((256, 256), Image.Resampling.LANCZOS)), np.asarray(full))
        roi = full.crop(box)
        roi.save(model / 'roi-static.png')
        blank = np.zeros((64, 64), dtype=bool)
        save_mask(model / 'mask-0.png', blank)
        save_mask(model / 'mask-3.png', blank)
        if fire:
            a = np.asarray(roi).astype(np.int16)
            warm = (a[:, :, 0] > 105) & (a[:, :, 0] > a[:, :, 1] + 35) & (a[:, :, 1] > a[:, :, 2] + 5)
            selected = blank.copy()
            boxes = {1: ((15, 12, 35, 23), (32, 26, 53, 38)),
                     2: ((8, 23, 29, 37), (27, 41, 53, 54)),
                     3: ((8, 8, 56, 56),)}[variant]
            for x0, y0, x1, y1 in boxes:
                selected[y0:y1, x0:x1] = warm[y0:y1, x0:x1]
            left = blank.copy(); left[:, 1:] = warm[:, :-1]
            right = blank.copy(); right[:, :-1] = warm[:, 1:]
            selected &= (~left | ~right)
            expanded = selected.copy()
            expanded[:, 1:] |= selected[:, :-1]
            expanded[:, :-1] |= selected[:, 1:]
            expanded &= a[:, :, 3] > 200
            assert expanded.any()
            for frame in (1, 2):
                save_mask(model / f'mask-{frame}.png', expanded)
            reference = model / 'roi-static.png'
            request = dict(base_requests['fire23-01'])
            request['action'] = ('Only the masked edges of the existing orange painted strokes gently sway one pixel horizontally, then return. '
                                 'Preserve the original low flat shape, height, palette and brightness. Everything outside these small contours stays still.')
            note = f'Original warm horizontal contours in {len(boxes)} area(s), plus one horizontal pixel; no new vertical growth zone.'
        else:
            ref_number = 2 if variant == 2 else 10
            old = ART / 'hazard-animations-20261104' / 'pixellab' / 'caltrops03-01' / 'frames' / f'frame-{ref_number:02d}.png'
            shutil.copyfile(old, model / f'accepted-glint-frame-{ref_number:02d}-original.png')
            reference = model / 'accepted-glint-reference-64.png'
            Image.open(old).crop(box).save(reference)
            # Locations correspond to bright glints in the accepted original sequence.
            centers = ((47, 59), (48, 31)) if variant == 2 else ((12, 31), (24, 16))
            radius = 2 if variant == 2 else 3
            for frame, (x, y) in enumerate(centers, 1):
                mask = blank.copy()
                mask[y, x-radius:x+radius+1] = True
                mask[y-radius:y+radius+1, x] = True
                assert np.asarray(roi)[:, :, 3][mask].min() > 200
                save_mask(model / f'mask-{frame}.png', mask)
            request = dict(base_requests['caltrops03-01'])
            request['action'] = ('In each middle frame show one small pale silver specular twinkle only on the masked existing metal point, '
                                 'matching the accepted glint reference. Preserve the original metal shape. Calm first and last frames; all stone and unmasked pixels remain still.')
            request['text_guidance_scale'] = 4
            note = f'Two cross masks of width {2*radius+1}px centered at prior accepted glint locations; all-black endpoints.'
        request.update(reference_image=encoded(reference), inpainting_images=[encoded(model / 'roi-static.png') for _ in range(4)],
                       mask_images=[encoded(model / f'mask-{i}.png') for i in range(4)], seed=20261105100 + index)
        assert set(request) <= allowed and request['image_size'] == {'width': 64, 'height': 64}
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=False)
        request_path = folder / 'request.json'
        request_path.write_text(json.dumps(request, separators=(',', ':')), encoding='utf-8', newline='\n')
        (folder / 'prompt.txt').write_text(request['action'] + '\n', encoding='utf-8', newline='\n')
        row = {'key': key, 'endpoint': 'animate-with-text', 'source': str(source.relative_to(ART)).replace('\\', '/'),
               'source_sha256': sha(source), 'input_sha256': sha(prior_input), 'roi_xyxy': list(box),
               'roi_sha256': sha(model / 'roi-static.png'), 'reference_sha256': sha(reference),
               'mask_sha256': [sha(model / f'mask-{i}.png') for i in range(4)],
               'mask_white_pixels': [int(np.count_nonzero(np.asarray(Image.open(model / f'mask-{i}.png'))[:, :, 0])) for i in range(4)],
               'mask_note': note, 'description': request['description'], 'action': request['action'],
               'negative_description': request['negative_description'], 'image_guidance_scale': request['image_guidance_scale'],
               'text_guidance_scale': request['text_guidance_scale'], 'seed': request['seed'], 'request_sha256': sha(request_path),
               'raw_api_canvas': [64, 64], 'derived_canvas': [256, 256], 'assembly': 'Integer ROI placement only; no scale/pixel retouch'}
        rows.append(playback(row))
    assert len(rows) == 15 and len({r['key'] for r in rows}) == 15
    save_json(destination, rows)
    print(json.dumps({'prepared_total': len(rows), 'new_requests': len(rows)-len(pilots),
                      'mask_counts': {r['key']: r['mask_white_pixels'] for r in rows}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
