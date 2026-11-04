"""Добавить восемь запросов 02/03, не меняя уже отправленные 01."""

from pathlib import Path
import base64
import hashlib
import json


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-subtle-animation-20261105')
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29')
MOTIONS = {
    2: ('Ровное боковое течение', 'The existing small flames make a very gentle, slow, continuous sideways waver in one shared direction and return smoothly. Each existing tip shifts at most 1–2 pixels left or right in the 256-pixel frame.'),
    3: ('Раздельное тихое колыхание', 'The existing small flame tips sway slightly left and right at subtly offset timings across the surface. Each existing tip shifts at most 1–2 pixels sideways in the 256-pixel frame, with smooth continuous motion.'),
}
GUARD = (
    'Keep the fire steadily burning at exactly the original low height, overall intensity, '
    'coverage, density and palette in every frame. Animate only sideways motion of the '
    'flame tips that are already visible in the input. Preserve every original flame and '
    'the complete original top silhouette. Absolutely no flashes, flares, ignition, '
    'growth, rising tongues, new peaks, extinguishing, dimming, brightness pulse, colour '
    'cycling, smoke, sparks, gaps or detached particles. Keep the stone base, side faces, '
    'camera, tile edges, scale and outside transparency fixed. The first and last frames '
    'match; make a smooth seamless loop.'
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    manifest_path = ROOT / 'requests.json'
    initial = json.loads(manifest_path.read_text(encoding='utf-8'))
    initial_keys = [f'{source}-01' for source in SOURCES]
    if len(initial) != 4 or [row['key'] for row in initial] != initial_keys:
        raise SystemExit('Требуются ровно четыре первоначальных immutable-запроса')
    for row in initial:
        folder = JOBS / 'pixellab' / row['key']
        if not (folder / 'submit-started.json').is_file() or sha(folder / 'request.json') != row['request_sha256']:
            raise SystemExit(f'Нарушен барьер или SHA первого запроса: {row["key"]}')
    rows = []
    for row in initial:
        source = row['source_key']
        rows.append(row)
        model_input = ROOT / row['input']
        frame = {'base64': base64.b64encode(model_input.read_bytes()).decode('ascii'), 'format': 'png'}
        if sha(model_input) != row['input_sha256']:
            raise SystemExit(f'Изменился вход {source}')
        captions = {
            'direction': 'south-east', 'view': 'low top-down',
            'subject_description': 'A fixed isometric stone tile steadily covered by the same low fire as the input frame',
            'initial_pose': 'Original low flames hold constant height and intensity; only existing tips sway sideways',
        }
        for variant in (2, 3):
            name, motion = MOTIONS[variant]
            prompt = f'{motion} {GUARD}'
            if not 0 < len(prompt) <= 1000 or 'breathe' in prompt.lower():
                raise SystemExit(f'Некорректный prompt {source}-{variant:02d}')
            key = f'{source}-{variant:02d}'
            folder = JOBS / 'pixellab' / key
            if folder.exists():
                raise SystemExit(f'Запрос уже существует: {key}')
            folder.mkdir(parents=True)
            request = {
                'first_frame': frame, 'last_frame': frame, 'description': prompt,
                'frame_count': 32, 'seed': 20261105005 + len(rows) - 1,
                'no_background': True, 'enhance_prompt': False, **captions,
            }
            request_path = folder / 'request.json'
            request_path.write_text(json.dumps(request), encoding='utf-8')
            (folder / 'prompt.txt').write_text(prompt, encoding='utf-8')
            rows.append({
                'key': key, 'source_key': source, 'group': row['group'], 'kind': 'fire',
                'variant': variant, 'name': name, 'prompt': prompt, 'seed': request['seed'],
                'frame_count': 32, 'expected_frames': 33, 'endpoint': 'animate-pixminimax',
                'loop': True, 'return_to_first': True, 'input': row['input'], 'source': row['source'],
                'source_sha256': row['source_sha256'], 'captions': captions,
                'input_sha256': row['input_sha256'], 'request_sha256': sha(request_path),
                'integration': False,
            })
    if len(rows) != 12 or len({row['seed'] for row in rows}) != 12:
        raise SystemExit('Expected 12 distinct requests/seeds')
    (ROOT / 'user-steering-20261105.json').write_text(json.dumps({
        'instruction': 'Только постоянное горение: пламя слегка колыхается, без вспыхиваний; по три варианта для каждого из четырёх источников.',
        'immutable_initial_keys': initial_keys,
        'initial_request_sha256': {row['key']: row['request_sha256'] for row in initial},
        'added_keys': [row['key'] for row in rows if row['variant'] > 1],
        'additional_prompts': {row['key']: row['prompt'] for row in rows if row['variant'] > 1},
        'total_authorized_keys': 12,
        'integration': False,
    }, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    manifest_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared 8 additional requests, 12 total; prompt lengths {[len(rows[i]["prompt"]) for i in (1, 2)]}; no POST')


if __name__ == '__main__':
    main()
