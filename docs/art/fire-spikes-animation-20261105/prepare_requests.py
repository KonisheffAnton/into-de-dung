"""Prepare eighteen immutable PixelLab requests. Never submits a job."""

from __future__ import annotations

import base64
import hashlib
import json
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parent
ART = ROOT.parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-spikes-animation-20261105')
FIRE = ('22', '23', '24', '29')
FIELDS = {'first_frame', 'last_frame', 'action', 'frame_count', 'seed',
          'no_background', 'drift_threshold', 'enhance_prompt'}
FIRE_ACTIONS = (
    'The finished 2D painting stays nearly still. Orange painted surface texture on the top diamond gently shifts sideways within its plane by one pixel and returns. The entire stone block, top plane, flat profile, original shapes, colors and brightness stay immobile and unchanged. Match the supplied first and last picture.',
    'In this finished flat tile painting, move only existing orange brush marks one pixel sideways and back, slowly and smoothly inside the top diamond. Keep every mark at its original height. The stone block and top plane remain perfectly fixed, with the same outline, colors and light throughout. Match both supplied endpoint pictures.',
    'A tiny horizontal one-pixel sway runs through the already painted orange marks on the flat top surface, then returns to their original positions. The finished stone tile and top diamond do not move. Keep the painted silhouette, height, coverage, palette and brightness steady. The supplied first and last pictures define the exact tile.',
)
SPIKE_ACTIONS = (
    'Animate this finished painted stone trap from the supplied retracted first picture to the supplied extended last picture. The existing metal spikes rise smoothly out of their existing sockets to exactly the shown final height. Keep every socket, stone block, viewpoint, scale, colors and lighting fixed. Finish at the supplied extended state.',
    'A quiet one-way extension of the already painted metal spikes: start at the supplied retracted stone trap and end at the supplied extended stone trap. Each spike stays centered in its own socket as it rises smoothly. The stone, sockets, camera, silhouette, colors and brightness remain fixed. Match both supplied endpoints.',
    'From the supplied retracted picture, slowly extend the existing spikes vertically within their fixed sockets until they exactly match the supplied extended picture. Preserve the finished painted stone block, socket positions, shape, palette, light and framing throughout. This is one transition, ending in the extended state.',
)
CALTROPS_ACTIONS = (
    'The finished steel caltrops tile is almost perfectly still. Exactly two tiny isolated steel glints appear briefly on separate existing tips, each lasting only one or two frames, with long completely still intervals. Begin and end in the same quiet state. Keep every caltrop, stone, camera, colors and transparent background fixed.',
    'Hold the finished painted caltrops and stone completely still. Across the long loop, show exactly two rare, small, separate metal glints, each for only one or two frames, with long unchanged pauses between them. The start and end match the supplied quiet picture. Keep all geometry, palette and background fixed.',
    'An almost static finished caltrops painting, with exactly three tiny steel highlights on separate existing tips at widely spaced moments. Each lasts only one or two frames; all other frames remain quiet and still. Return to the supplied first picture at the end. Preserve fixed objects, stone, framing, colors and transparency.',
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def frame(path: Path) -> dict:
    return {'base64': base64.b64encode(path.read_bytes()).decode('ascii'), 'format': 'png'}


def save_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def main() -> None:
    if (ROOT / 'requests.json').exists():
        raise SystemExit('Existing request manifest; immutable preparation')
    schema = json.loads((JOBS / 'openapi-prepared.json').read_text(encoding='utf-8'))
    contracts = {}
    for endpoint in ('animate-with-text-v3', 'animate-pixminimax'):
        ref = schema['paths']['/' + endpoint]['post']['requestBody']['content']['application/json']['schema']['$ref'].split('/')[-1]
        contracts[endpoint] = schema['components']['schemas'][ref]
    v3 = contracts['animate-with-text-v3']
    if v3.get('additionalProperties') is not False or not FIELDS <= set(v3['properties']):
        raise SystemExit('V3 fields changed')
    for count in (4, 8):
        spec = v3['properties']['frame_count']
        if not spec['minimum'] <= count <= spec['maximum']:
            raise SystemExit('V3 frame count changed')
    pix = contracts['animate-pixminimax']
    print('PIX_FIELDS', sorted(pix['properties']))
    rows = []

    def append(source_key: str, variant: int, kind: str, group: str,
               first: Path, last: Path, source: Path, action: str,
               endpoint: str, count: int, loop: bool, name: str) -> None:
        key = f'{source_key}-{variant:02d}'
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=False)
        if len(action) > min(1000, contracts[endpoint]['properties']['action']['maxLength']):
            raise SystemExit(f'Action too long: {key}')
        request = {'first_frame': frame(first), 'last_frame': frame(last), 'action': action,
                   'frame_count': count, 'seed': 20261105001 + len(rows),
                   'no_background': True, 'drift_threshold': 0, 'enhance_prompt': False}
        if endpoint == 'animate-pixminimax':
            raise SystemExit('PixMiniMax request mapping not yet confirmed')
        if set(request) != FIELDS:
            raise SystemExit('Bad request fields')
        request_path = folder / 'request.json'
        request_path.write_text(json.dumps(request, separators=(',', ':')), encoding='utf-8')
        (folder / 'prompt.txt').write_text(action + '\n', encoding='utf-8')
        rows.append({'key': key, 'source_key': source_key, 'variant': variant,
                     'kind': kind, 'group': group, 'name': name, 'endpoint': endpoint,
                     'frame_count': count, 'expected_frames': None,
                     'loop': loop, 'one_way': not loop,
                     'first_input': str(first.relative_to(ROOT)).replace('\\', '/'),
                     'last_input': str(last.relative_to(ROOT)).replace('\\', '/'),
                     'first_sha256': sha(first), 'last_sha256': sha(last),
                     'source': str(source.relative_to(ART)).replace('\\', '/'),
                     'source_sha256': sha(source), 'prompt': action,
                     'seed': request['seed'], 'request_sha256': sha(request_path),
                     'integration': False})

    for suffix in FIRE:
        key = 'fire' + suffix
        source = ART / 'fire-low-styles-20261104' / f'fire-low-{suffix}.png'
        model = ROOT / 'model' / key
        model.mkdir(parents=True, exist_ok=False)
        shutil.copyfile(source, model / 'source-original.png')
        with Image.open(source) as image:
            if image.mode != 'RGBA' or image.size != (1254, 1254):
                raise SystemExit(f'Unexpected fire source: {source}')
            image.resize((256, 256), Image.Resampling.LANCZOS).save(model / 'input-256.png')
        previous = ART / 'fire-painted-sway-20261105' / 'model' / key / 'input-256.png'
        if sha(previous) != sha(model / 'input-256.png'):
            raise SystemExit(f'Fire source no longer matches prior original: {key}')
        save_json(model / 'transform.json', {'source': str(source), 'source_sha256': sha(source),
                  'crop': None, 'resize': 'whole RGBA frame Pillow LANCZOS 1254x1254 to 256x256',
                  'input_sha256': sha(model / 'input-256.png'), 'prior_input_sha256': sha(previous),
                  'pixel_retouch': False})
        for variant, action in enumerate(FIRE_ACTIONS, 1):
            append(key, variant, 'fire', f'Огонь {suffix}', model / 'input-256.png',
                   model / 'input-256.png', source, action, 'animate-with-text-v3', 4,
                   True, f'Плоский сдвиг {variant}')

    source = ART / 'retractable-spike-traps-20261104' / 'spike-trap-01-pair.png'
    model = ROOT / 'model' / 'spike01'
    model.mkdir(parents=True, exist_ok=False)
    shutil.copyfile(source, model / 'source-pair-original.png')
    with Image.open(source) as image:
        if image.mode != 'RGBA' or image.size != (1536, 1024):
            raise SystemExit('Unexpected spike pair geometry')
        for name, box in (('retracted', (0, 0, 768, 1024)),
                          ('extended', (768, 0, 1536, 1024))):
            half = image.crop(box)
            half.save(model / f'{name}-half.png')
            resized = half.resize((192, 256), Image.Resampling.LANCZOS)
            canvas = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
            canvas.paste(resized, (32, 0))
            canvas.save(model / f'{name}-input-256.png')
    save_json(model / 'transform.json', {'source_sha256': sha(source),
              'pair_size': [1536, 1024], 'left_retracted_crop': [0, 0, 768, 1024],
              'right_extended_crop': [768, 0, 1536, 1024],
              'common_scale': 0.25, 'resized_half': [192, 256],
              'canvas': [256, 256], 'paste_xy': [32, 0],
              'resampler': 'Pillow LANCZOS', 'alpha_bbox_crop': False,
              'pixel_retouch': False, 'retracted_sha256': sha(model / 'retracted-input-256.png'),
              'extended_sha256': sha(model / 'extended-input-256.png')})
    for variant, action in enumerate(SPIKE_ACTIONS, 1):
        append('spike01', variant, 'spike_transition', 'Выдвижные шипы 01',
               model / 'retracted-input-256.png', model / 'extended-input-256.png',
               source, action, 'animate-with-text-v3', 8, False, f'Выдвижение {variant}')

    # Caltrops are prepared separately after the PixelLab PixMiniMax schema is inspected.
    save_json(ROOT / 'requests-prepared-15.json', rows)
    print(json.dumps({'prepared': len(rows), 'fire': 12, 'spike': 3,
                      'post': False, 'source_shas': {r['source_key']: r['source_sha256']
                                                   for r in rows}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
