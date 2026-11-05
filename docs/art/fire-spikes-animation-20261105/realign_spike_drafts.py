"""One-time correction to unsubmitted spike drafts; records original request hashes."""

from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

from prepare_requests import ROOT, ART, JOBS, frame, save_json, sha


def main() -> None:
    rows_path = ROOT / 'requests-prepared-15.json'
    rows = json.loads(rows_path.read_text(encoding='utf-8'))
    keys = {f'spike01-{i:02d}' for i in range(1, 4)}
    for key in keys:
        if (JOBS / 'pixellab' / key / 'submit-started.json').exists():
            raise SystemExit(f'Cannot change submitted spike request: {key}')
    model = ROOT / 'model' / 'spike01'
    old_hashes = {name: sha(model / f'{name}-input-256.png')
                  for name in ('retracted', 'extended')}
    old_requests = {key: sha(JOBS / 'pixellab' / key / 'request.json') for key in keys}
    # Full 768x1024 half images; pad at original resolution, then resize both
    # complete 1024x1024 canvases. Landmark x410+102 == (1129-768)+151.
    for name, offset in (('retracted', 102), ('extended', 151)):
        with Image.open(model / f'{name}-half.png') as half:
            canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
            canvas.paste(half, (offset, 0))
            canvas.resize((256, 256), Image.Resampling.LANCZOS).save(model / f'{name}-input-256.png')
    transform_path = model / 'transform.json'
    transform = json.loads(transform_path.read_text(encoding='utf-8'))
    transform.update({'common_scale': 0.25, 'full_canvas': [1024, 1024],
                      'retracted_paste_xy': [102, 0], 'extended_paste_xy': [151, 0],
                      'landmark_alignment': 'retracted global x410 +102 = extended local x361 +151 =512; same y',
                      'prior_unsubmitted_input_sha256': old_hashes,
                      'retracted_sha256': sha(model / 'retracted-input-256.png'),
                      'extended_sha256': sha(model / 'extended-input-256.png')})
    for obsolete in ('resized_half', 'canvas', 'paste_xy'):
        transform.pop(obsolete, None)
    save_json(transform_path, transform)
    for row in rows:
        if row['key'] not in keys:
            continue
        folder = JOBS / 'pixellab' / row['key']
        request_path = folder / 'request.json'
        request = json.loads(request_path.read_text(encoding='utf-8'))
        request['first_frame'] = frame(model / 'retracted-input-256.png')
        request['last_frame'] = frame(model / 'extended-input-256.png')
        request_path.write_text(json.dumps(request, separators=(',', ':')), encoding='utf-8')
        row['first_sha256'] = sha(model / 'retracted-input-256.png')
        row['last_sha256'] = sha(model / 'extended-input-256.png')
        row['request_sha256'] = sha(request_path)
    save_json(rows_path, rows)
    save_json(ROOT / 'spike-alignment-revision.json', {
        'reason': 'Align existing block centers in separate half paintings before PixelLab POST',
        'previous_unsubmitted_input_sha256': old_hashes,
        'previous_unsubmitted_request_sha256': old_requests,
        'revised_input_sha256': {name: sha(model / f'{name}-input-256.png')
                                 for name in ('retracted', 'extended')},
        'revised_request_sha256': {key: sha(JOBS / 'pixellab' / key / 'request.json')
                                   for key in sorted(keys)},
        'submitted_before_revision': False,
        'pixel_retouch': False,
    })
    print(json.dumps({'aligned_spike': 3, 'old_input_sha256': old_hashes,
                      'new_input_sha256': transform['retracted_sha256'][:12] + '/' + transform['extended_sha256'][:12],
                      'post': False}))


if __name__ == '__main__':
    main()
