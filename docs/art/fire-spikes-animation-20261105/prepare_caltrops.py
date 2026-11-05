"""Append three rare-glint PixMiniMax requests to the prepared fifteen."""

from __future__ import annotations

import base64
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image

from prepare_requests import ROOT, ART, JOBS, CALTROPS_ACTIONS, sha, save_json


def main() -> None:
    if (ROOT / 'requests.json').exists():
        raise SystemExit('Final manifest exists; immutable preparation')
    rows = json.loads((ROOT / 'requests-prepared-15.json').read_text(encoding='utf-8'))
    if len(rows) != 15:
        raise SystemExit('Expected exactly fifteen prepared rows')
    schema = json.loads((JOBS / 'openapi-prepared.json').read_text(encoding='utf-8'))
    contract = schema['components']['schemas']['AnimatePixminimaxRequest']
    fields = {'first_frame', 'last_frame', 'description', 'frame_count', 'seed',
              'no_background', 'enhance_prompt', 'direction', 'view',
              'subject_description', 'initial_pose'}
    if contract.get('additionalProperties') is not False or not fields <= set(contract['properties']):
        raise SystemExit('PixMiniMax API fields changed')
    source = ART / 'hazard-variants-20261103' / 'caltrops-03.png'
    model = ROOT / 'model' / 'caltrops03'
    model.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(source, model / 'source-original.png')
    with Image.open(source) as image:
        if image.mode != 'RGBA' or image.size != (1254, 1254):
            raise SystemExit('Unexpected caltrops source')
        image.resize((256, 256), Image.Resampling.LANCZOS).save(model / 'input-256.png')
    previous = ART / 'hazard-animations-20261104' / 'model' / 'caltrops03' / 'input-256.png'
    if sha(source) != '30a28973ec827f54756806dc00c9a3d447b154388f89de6a652e4262fe09ac8c' or sha(model / 'input-256.png') != sha(previous):
        raise SystemExit('Caltrops original/input mismatch')
    save_json(model / 'transform.json', {'source_sha256': sha(source), 'crop': None,
              'resize': 'whole RGBA frame Pillow LANCZOS 1254x1254 to 256x256',
              'input_sha256': sha(model / 'input-256.png'), 'prior_input_sha256': sha(previous),
              'pixel_retouch': False})
    first = {'base64': base64.b64encode((model / 'input-256.png').read_bytes()).decode('ascii'),
             'format': 'png'}
    captions = {'direction': 'south-east', 'view': 'low top-down',
                'subject_description': 'A finished isometric stone tile with stationary steel caltrops',
                'initial_pose': 'Every metal caltrop and stone surface is still; quiet steel with no active glint'}
    for variant, description in enumerate(CALTROPS_ACTIONS, 1):
        key = f'caltrops03-{variant:02d}'
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=False)
        request = {'first_frame': first, 'last_frame': first, 'description': description,
                   'frame_count': 32, 'seed': 20261105001 + len(rows),
                   'no_background': True, 'enhance_prompt': False, **captions}
        if set(request) != fields or len(description) > min(1000, contract['properties']['description']['maxLength']):
            raise SystemExit(f'Invalid caltrops payload: {key}')
        request_path = folder / 'request.json'
        request_path.write_text(json.dumps(request, separators=(',', ':')), encoding='utf-8')
        (folder / 'prompt.txt').write_text(description + '\n', encoding='utf-8')
        rows.append({'key': key, 'source_key': 'caltrops03', 'variant': variant,
                     'kind': 'caltrops', 'group': 'Редкие блики на иглах 03',
                     'name': f'Редкие блики {variant}', 'endpoint': 'animate-pixminimax',
                     'frame_count': 32, 'expected_frames': None, 'loop': True, 'one_way': False,
                     'first_input': 'model/caltrops03/input-256.png',
                     'last_input': 'model/caltrops03/input-256.png',
                     'first_sha256': sha(model / 'input-256.png'),
                     'last_sha256': sha(model / 'input-256.png'),
                     'source': 'hazard-variants-20261103/caltrops-03.png',
                     'source_sha256': sha(source), 'prompt': description,
                     'captions': captions, 'seed': request['seed'],
                     'request_sha256': sha(request_path), 'integration': False})
    if len(rows) != 18 or len({r['key'] for r in rows}) != 18:
        raise SystemExit('Expected exactly eighteen requests')
    save_json(ROOT / 'requests.json', rows)
    print(json.dumps({'prepared': 18, 'fire': 12, 'spike': 3, 'caltrops': 3,
                      'caltrops_source_sha256': sha(source),
                      'caltrops_input_sha256': sha(model / 'input-256.png'),
                      'post': False}))


if __name__ == '__main__':
    main()
