"""Собирает целые исходные и промежуточные PNG, не изменяя их пиксели."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / 'whole-body-weighted-strike-20261118'
RAW = Path('D:/Codex/home/generated_images/whole-body-smooth-strike-20261119')


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def save(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def main() -> None:
    selection = json.loads((ROOT / 'selected_frames.json').read_text(encoding='utf-8'))
    previous = json.loads((PREVIOUS / 'assets/manifest.json').read_text(encoding='utf-8'))
    old_origins = json.loads((PREVIOUS / 'origins.json').read_text(encoding='utf-8'))
    plan = {item['id']: item for item in json.loads((RAW / 'plan.json').read_text(encoding='utf-8'))}
    jobs = {}
    clips, bodies, files, origins = {}, {}, {}, {}
    for clip_name, spec in selection['clips'].items():
        frames, durations, sockets = spec['frames'], spec['durations'], spec['sockets']
        if not frames or not (len(frames) == len(durations) == len(sockets)):
            raise ValueError(f'Несовпадение кадров/тайминга/привязок: {clip_name}')
        if any(type(ms) is not int or ms < 20 or ms % 10 for ms in durations):
            raise ValueError('Основные GIF требуют интервалов от20мс, кратных10мс')
        paths = []
        for index, ref in enumerate(frames):
            if ref['source'] == 'previous':
                old_path = ref['path']
                source = (PREVIOUS / old_path).resolve()
                if not source.is_relative_to((PREVIOUS / 'assets/body').resolve()):
                    raise ValueError('Источник тела вне предыдущего каталога assets/body')
                expected = previous['files_sha256'][old_path]
                origin = {'source_package': PREVIOUS.name, 'source_path': old_path,
                          'source_origin': old_origins[old_path]}
            elif ref['source'] == 'pixellab':
                job, frame = ref['job'], ref['frame']
                if type(frame) is not int or frame < 0:
                    raise ValueError('Некорректный индекс кадра провайдера')
                folder = RAW / 'items' / f'{job:03d}'
                if job not in jobs:
                    result = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
                    request = json.loads((folder / 'request.json').read_text(encoding='utf-8'))
                    if result['status'] != 'completed' or request != {
                            'endpoint': plan[job]['endpoint'], 'body': plan[job]['request']}:
                        raise ValueError(f'Незавершённый или изменённый запрос: {job}')
                    jobs[job] = result
                output = jobs[job]['outputs'][frame]
                source = folder / Path(output['path']).name
                expected = output['sha256']
                origin = {'job_id': jobs[job]['job_id'], 'request_id': job, 'provider_frame': frame}
            else:
                raise ValueError('Неизвестный тип источника')
            if digest(source) != expected:
                raise ValueError(f'Изменён исходный PNG: {source.name}')
            with Image.open(source) as image:
                if image.size != (256, 256) or 'A' not in image.getbands():
                    raise ValueError('Ожидается цельный прозрачный PNG256×256')
            relative = f'assets/body/light/{clip_name}/{index:03d}.png'
            target = ROOT / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())
            paths.append(relative)
            files[relative] = expected
            origins[relative] = {**origin, 'sha256': expected, 'whole_provider_png_unchanged': True}
        bodies[clip_name] = paths
        clips[clip_name] = {'durations': durations, 'sockets': sockets}

    equipment = previous['equipment']
    for definition in equipment.values():
        relative = definition['file']
        source, target = PREVIOUS / relative, ROOT / relative
        expected = previous['files_sha256'][relative]
        if digest(source) != expected:
            raise ValueError('Изменён исходный предмет')
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(source.read_bytes())
        files[relative] = expected
        origins[relative] = {'source_package': PREVIOUS.name, 'source_path': relative,
                             'sha256': expected, 'unchanged': True}
    save(ROOT / 'assets/manifest.json', {
        'canvas': 256, 'slots': ['body', 'weapon', 'helmet'], 'bodies': {'light': bodies},
        'clips': clips, 'equipment': equipment, 'files_sha256': files,
    })
    save(ROOT / 'origins.json', origins)
    print(f'{sum(len(v) for v in bodies.values())} whole body PNGs, {len(files)} manifest images')


if __name__ == '__main__':
    main()
