"""Готовит 12 коротких V3-проб на четырёх исходных нарисованных тайлах, без POST."""

from pathlib import Path
import base64
import hashlib
import json
import shutil

from PIL import Image


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-painted-sway-20261105')
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29')
MOTIONS = (
    ('Левый плавный сдвиг', 'The already-painted orange contours shift sideways by at most one pixel to the left and return smoothly, slowly, as one quiet cycle.'),
    ('Направленная рябь контуров', 'A very slow one-pixel sideways waver passes across the already-painted orange contours in small delayed areas, then returns smoothly.'),
    ('Раздельное колыхание', 'Separate already-painted orange contour tips sway one pixel left or right at slightly offset times, easing back smoothly without changing their original locations.'),
)
GUARD = (
    'Animate the attached FINISHED PAINTED illustration, not a new fire scene. '
    'Move only contours already present in the input; keep their number, topology, '
    'position, maximum height, area coverage, shapes, palette and brightness essentially '
    'identical in every frame. Keep the original low flat top profile. The stone, side '
    'faces, outer alpha silhouette, tile edges, scale and camera stay fixed. No added '
    'flames, redrawing, upward flow, rising tongues, jets, particles, birth, growth, '
    'extinguishing, flare, flash, colour cycle or global light pulse. First and last '
    'frames match the supplied still image.'
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    schema_path = JOBS / 'openapi-prepared.json'
    schema = json.loads(schema_path.read_text(encoding='utf-8'))
    ref = schema['paths']['/animate-with-text-v3']['post']['requestBody']['content']['application/json']['schema']['$ref'].split('/')[-1]
    contract = schema['components']['schemas'][ref]
    fields = {'first_frame', 'last_frame', 'action', 'frame_count', 'seed', 'no_background', 'drift_threshold', 'enhance_prompt'}
    if contract.get('additionalProperties') is not False or not fields <= set(contract['properties']):
        raise SystemExit('Текущая V3-схема не совпала с ожидаемыми полями')
    count_schema = contract['properties']['frame_count']
    if not count_schema['minimum'] <= 8 <= count_schema['maximum'] or 256 * 256 * 8 != 524288:
        raise SystemExit('V3 не подтверждает 8 кадров 256²')
    manifest_path = ROOT / 'requests.json'
    if manifest_path.exists():
        raise SystemExit('Запросы уже подготовлены; не перезаписывать')
    rows = []
    for source_key in SOURCES:
        source = ROOT.parent / 'fire-low-styles-20261104' / f'fire-low-{source_key[4:]}.png'
        model = ROOT / 'model' / source_key
        model.mkdir(parents=True, exist_ok=False)
        shutil.copyfile(source, model / 'source-original.png')
        with Image.open(source) as image:
            if image.format != 'PNG' or image.mode != 'RGBA' or image.size != (1254, 1254):
                raise SystemExit(f'Неожиданный источник: {source}')
            image.resize((256, 256), Image.Resampling.LANCZOS).save(model / 'input-256.png')
        source_rel = f'../fire-low-styles-20261104/{source.name}'
        input_rel = f'model/{source_key}/input-256.png'
        transform = {'source': source_rel, 'source_sha256': sha(source),
                     'original_copy': f'model/{source_key}/source-original.png',
                     'input': input_rel, 'input_sha256': sha(model / 'input-256.png'),
                     'source_size': [1254, 1254], 'input_size': [256, 256],
                     'crop': None, 'resize': 'Pillow LANCZOS, whole frame',
                     'pixel_retouch': False, 'integration': False}
        (model / 'transform.json').write_text(json.dumps(transform, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        frame = {'base64': base64.b64encode((model / 'input-256.png').read_bytes()).decode('ascii'), 'format': 'png'}
        captions = {'direction': 'south-east', 'view': 'low top-down',
                    'subject_description': 'A fixed isometric stone tile with low painted orange contours on the whole diamond top',
                    'initial_pose': 'The finished painted marks and stone remain at the exact original positions and low height'}
        for variant, (name, motion) in enumerate(MOTIONS, 1):
            key = f'{source_key}-{variant:02d}'
            action = f'{motion} {GUARD}'
            if not 0 < len(action) <= min(1000, contract['properties']['action']['maxLength']):
                raise SystemExit(f'Слишком длинное action: {key}')
            folder = JOBS / 'pixellab' / key
            folder.mkdir(parents=True, exist_ok=False)
            request = {'first_frame': frame, 'last_frame': frame, 'action': action,
                       'frame_count': 8, 'seed': 20261106001 + len(rows),
                       'no_background': True, 'drift_threshold': 0,
                       'enhance_prompt': False}
            if set(request) != fields or request['first_frame'] != request['last_frame']:
                raise SystemExit(f'Некорректный запрос: {key}')
            request_path = folder / 'request.json'
            request_path.write_text(json.dumps(request), encoding='utf-8')
            (folder / 'prompt.txt').write_text(action, encoding='utf-8')
            rows.append({'key': key, 'source_key': source_key, 'group': f'Нарисованный низкий огонь {source_key[4:]}',
                         'kind': 'fire', 'variant': variant, 'name': name, 'prompt': action,
                         'captions_metadata_only': captions, 'caption_api_note': 'V3 additionalProperties=false; four caption fields are not accepted by this endpoint',
                         'seed': request['seed'], 'frame_count': 8, 'expected_frames': None,
                         'expected_frames_policy': 'Read count from admitted completed response; prior V3 returned 9 for frame_count 8',
                         'endpoint': 'animate-with-text-v3', 'loop': True, 'return_to_first': True,
                         'input': input_rel, 'input_sha256': transform['input_sha256'],
                         'source': source_rel, 'source_sha256': transform['source_sha256'],
                         'request_sha256': sha(request_path), 'integration': False})
    if len(rows) != 12 or len({row['seed'] for row in rows}) != 12:
        raise SystemExit('Нужно ровно 12 уникальных запросов')
    manifest_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'prepared': len(rows), 'source_keys': list(SOURCES),
                      'endpoint': 'animate-with-text-v3', 'frame_count': 8,
                      'action_lengths': [len(rows[i]['prompt']) for i in range(3)], 'post': False}))


if __name__ == '__main__':
    main()
