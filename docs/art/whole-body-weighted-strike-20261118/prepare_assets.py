"""Собирает цельные PNG PixelLab и размеченные привязки двух предметов."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
RAW = Path('D:/Codex/home/generated_images/whole-body-weighted-strike-20261118')
PREVIOUS = ROOT.parent / 'whole-body-layered-20261118'


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n',
                    encoding='utf-8', newline='\n')


def main() -> None:
    selection = json.loads((ROOT / 'selected_frames.json').read_text(encoding='utf-8'))
    plan = {row['id']: row for row in json.loads((RAW / 'plan.json').read_text(encoding='utf-8'))}
    clips, body, files, origins = {}, {}, {}, {}
    for clip, spec in selection['clips'].items():
        job = spec['job']
        folder = RAW / 'items' / f'{job:03d}'
        result = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
        request = json.loads((folder / 'request.json').read_text(encoding='utf-8'))
        if result['status'] != 'completed' or request != {
                'endpoint': plan[job]['endpoint'], 'body': plan[job]['request']}:
            raise ValueError(f'Незавершённый или изменённый источник {job}')
        frames, durations, sockets = spec['frames'], spec['durations'], spec['sockets']
        if not (len(frames) == len(durations) == len(sockets)):
            raise ValueError(f'Количество кадров, длительностей и привязок различается: {clip}')
        if any(not isinstance(ms, int) or ms <= 0 or ms % 10 for ms in durations):
            raise ValueError('Длительности GIF должны быть положительными кратными10мс')
        paths = []
        for index, frame in enumerate(frames):
            override = spec.get('overrides', {}).get(str(frame))
            source_job, source_frame = (override['job'], override['frame']) if override else (job, frame)
            source_folder = RAW / 'items' / f'{source_job:03d}'
            active_result = result
            if override:
                active_result = json.loads((source_folder / 'result.json').read_text(encoding='utf-8'))
                active_request = json.loads((source_folder / 'request.json').read_text(encoding='utf-8'))
                if active_result['status'] != 'completed' or active_request != {
                        'endpoint': plan[source_job]['endpoint'], 'body': plan[source_job]['request']}:
                    raise ValueError(f'Некорректный источник замены {source_job}')
            output = active_result['outputs'][source_frame]
            source = source_folder / Path(output['path']).name
            if digest(source) != output['sha256']:
                raise ValueError(f'Изменены пиксели провайдера: {job}/{frame}')
            with Image.open(source) as image:
                if image.size != (256, 256) or 'A' not in image.getbands():
                    raise ValueError('Ожидается цельный прозрачный PNG256×256')
            relative = f'assets/body/light/{clip}/{index:03d}.png'
            destination = ROOT / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            destination.write_bytes(source.read_bytes())
            paths.append(relative)
            files[relative] = digest(destination)
            origins[relative] = {
                'job_id': active_result['job_id'], 'request_id': source_job, 'provider_frame': source_frame,
                'sha256': files[relative], 'whole_provider_png_unchanged': True,
            }
        body[clip] = paths
        clips[clip] = {'durations': durations, 'sockets': sockets}

    previous = json.loads((PREVIOUS / 'assets/manifest.json').read_text(encoding='utf-8'))
    equipment = previous['equipment']
    for definition in equipment.values():
        relative = definition['file']
        source, destination = PREVIOUS / relative, ROOT / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(source.read_bytes())
        files[relative] = digest(destination)
        origins[relative] = {'source': source.relative_to(ROOT.parent).as_posix(),
                             'sha256': files[relative], 'unchanged': True}
    manifest = {'canvas': 256, 'slots': ['body', 'weapon', 'helmet'],
                'bodies': {'light': body}, 'clips': clips,
                'equipment': equipment, 'files_sha256': files}
    write_json(ROOT / 'assets/manifest.json', manifest)
    write_json(ROOT / 'origins.json', origins)
    print(f'{len(files)} images; complete provider PNGs unchanged; shared timeline/sockets')


if __name__ == '__main__':
    main()
