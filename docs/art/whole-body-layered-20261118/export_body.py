"""Копирует цельные кадры провайдера и собирает общий трек двух предметов.

Тело никогда не разрезается, не деформируется и не собирается из фрагментов.
Изображения тела в assets побайтно совпадают с выбранными PNG PixelLab.
"""
from pathlib import Path
from PIL import Image
import hashlib
import json

ROOT = Path(__file__).resolve().parent
RAW = Path('D:/Codex/home/generated_images/whole-body-layered-20261118')
PREVIOUS = ROOT.parent / 'natural-layered-character-20261118' / 'assets'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def head_socket(im):
    # Ищем связную область кожи лица; ремни ниже головы не должны двигать шлем.
    candidates = set()
    for y in range(20, 115):
        for x in range(55, 210):
            r, g, b, a = im.getpixel((x, y))
            if a > 128 and r > 170 and g > 110 and g > r * .63 and b < g * .85:
                candidates.add((x, y))
    components = []
    while candidates:
        seed = candidates.pop()
        group, queue = [seed], [seed]
        while queue:
            x, y = queue.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)):
                point = (x + dx, y + dy)
                if point in candidates:
                    candidates.remove(point)
                    group.append(point)
                    queue.append(point)
        components.append(group)
    face = max(components, key=len)
    if len(face) < 40:
        raise ValueError('Лицо не распознано: требуется ручная привязка, не угадывание')
    xs, ys = [x for x, y in face], [y for x, y in face]
    return [round((min(xs) + max(xs)) / 2 - 5), max(ys) + 11], 'profile' if max(xs) - min(xs) < 19 else 'front'


def foot_anchor(im):
    bounds = im.getchannel('A').crop((0, 180, 256, 256)).point(lambda a: 255 if a > 128 else 0).getbbox()
    if bounds is None:
        raise ValueError('Нет опоры ног в нижней части кадра')
    return [(bounds[0] + bounds[2]) / 2, bounds[3] + 180]


def main():
    selection = json.loads((ROOT / 'selected_frames.json').read_text(encoding='utf-8'))
    plan = {r['id']: r for r in json.loads((RAW / 'plan.json').read_text(encoding='utf-8'))}
    used = {ref[0] for clips in selection['bodies'].values() for refs in clips.values() for ref in refs}
    jobs = {}
    for ident in used:
        folder = RAW / 'items' / f'{ident:03d}'
        result = json.loads((folder / 'result.json').read_text(encoding='utf-8'))
        saved_request = json.loads((folder / 'request.json').read_text(encoding='utf-8'))
        if result['status'] != 'completed' or saved_request != {'endpoint': plan[ident]['endpoint'], 'body': plan[ident]['request']}:
            raise ValueError(f'Не завершён или подменён запрос {ident}')
        jobs[ident] = result
    bodies, origins, files, clips = {}, {}, {}, {}
    first_body = next(iter(selection['bodies']))
    anchor = None
    for body, sequences in selection['bodies'].items():
        bodies[body] = {}
        for clip, refs in sequences.items():
            spec = selection['clips'][clip]
            if len(refs) != len(spec['durations']) or len(refs) != len(spec['hands']):
                raise ValueError(f'Несовпадение кадров/треков {body}/{clip}')
            bodies[body][clip] = []
            sockets = []
            for index, (ident, original_index) in enumerate(refs):
                output = jobs[ident]['outputs'][original_index]
                src = RAW / 'items' / f'{ident:03d}' / Path(output['path']).name
                if digest(src) != output['sha256']:
                    raise ValueError(f'Изменён PNG провайдера {ident}/{original_index}')
                im = Image.open(src).convert('RGBA')
                if im.size != (256, 256):
                    raise ValueError('Кадр тела должен быть 256×256')
                relative = f'assets/body/{body}/{clip}/{index:03d}.png'
                target = ROOT / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(src.read_bytes())
                files[relative] = digest(target)
                origins[relative] = {'job_id': jobs[ident]['job_id'], 'request_id': ident, 'provider_frame': original_index, 'sha256': files[relative], 'whole_provider_png_unchanged': True}
                bodies[body][clip].append(relative)
                if body == first_body:
                    foot = foot_anchor(im)
                    if anchor is None:
                        # Оставляем справа место для целого оружия в вытянутой руке.
                        anchor = [foot[0] - 12, foot[1]]
                    root = [round(anchor[0] - foot[0]), round(anchor[1] - foot[1])]
                    head, variant = head_socket(im)
                    hand = spec['hands'][index]
                    sockets.append({'hand': hand[:2], 'weaponAngle': hand[2], 'head': head,
                                    'headAngle': 0, 'headScale': 1, 'helmetVariant': variant,
                                    'weaponBehind': False, 'gripRadius': 5, 'root': root})
            if body == first_body:
                clips[clip] = {'durations': spec['durations'], 'sockets': sockets}
    equipment = {}
    for key, old, width, height, pivot in [
        ('sword', 'sword', 26, 65, [.5, .86]),
        ('axe', 'axe', 36, 64, [.22, .86]),
        ('helmet_front', 'helmet', 62, 62, [.5, 1]),
        ('helmet_profile', 'helmet_profile', 60, 62, [.5, 1]),
    ]:
        relative = f'assets/{key}.png'
        src = PREVIOUS / (old + '.png')
        Image.open(src).resize((width, height), Image.Resampling.NEAREST).save(ROOT / relative)
        equipment[key] = {'file': relative, 'width': width, 'height': height, 'pivot': pivot}
        files[relative] = digest(ROOT / relative)
        origins[relative] = {'source': str(src.relative_to(ROOT.parent)), 'source_sha256': digest(src), 'operation': f'nearest export {width}x{height}'}
    manifest = {'canvas': 256, 'slots': ['body', 'weapon', 'helmet'], 'bodies': bodies,
                'clips': clips, 'equipment': equipment, 'files_sha256': files}
    (ROOT / 'assets/manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8', newline='\n')
    (ROOT / 'origins.json').write_text(json.dumps(origins, ensure_ascii=False, indent=2), encoding='utf-8', newline='\n')
    print(f'{len(files)} images; whole body PNGs unchanged; shared timeline + root + hand/head sockets')


if __name__ == '__main__':
    main()
