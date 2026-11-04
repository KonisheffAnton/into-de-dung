"""Подготовить шесть полных кадров и 30 запросов PixelLab без сетевых POST."""
from pathlib import Path
import base64
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104')
SOURCES = [
    ('fire29', '../fire-low-styles-20261104/fire-low-29.png', 'Низкий огонь 29', 'fire',
     'A fixed isometric stone tile with low orange fire covering the whole diamond top',
     'Low fire lies across the full diamond top; exposed stone sides remain fixed'),
    ('fire23', '../fire-low-styles-20261104/fire-low-23.png', 'Низкий огонь 23', 'fire',
     'A fixed isometric stone tile with low orange fire covering the whole diamond top',
     'Low fire lies across the full diamond top; exposed stone sides remain fixed'),
    ('fire24', '../fire-low-styles-20261104/fire-low-24.png', 'Низкий огонь 24', 'fire',
     'A fixed isometric stone tile with low orange fire covering the whole diamond top',
     'Low fire lies across the full diamond top; exposed stone sides remain fixed'),
    ('fire22', '../fire-low-styles-20261104/fire-low-22.png', 'Низкий огонь 22', 'fire',
     'A fixed isometric stone tile with low orange fire covering the whole diamond top',
     'Low fire lies across the full diamond top; exposed stone sides remain fixed'),
    ('acidfilm', '../hazard-variants-20261103/acid-01.png', 'Зелёная плёнка', 'acid',
     'A fixed isometric stone tile with a thin green acid film over the diamond top',
     'Thin flat green acid coats the top; exposed stone sides remain fixed'),
    ('caltrops03', '../hazard-variants-20261103/caltrops-03.png', 'Воронёные иглы', 'caltrops',
     'A fixed isometric stone tile with dark stationary steel caltrops on the diamond top',
     'Dark steel caltrops rest motionless on the top; stone and side faces stay fixed'),
]
MOTIONS = {
    'fire': [
        ('Тихое мерцание', 'Low flame tips flicker gently at staggered places across the entire top, with tiny rises and falls. Keep broad, low, continuous fire coverage.'),
        ('Медленное течение', 'The shallow fire flows slowly across the diamond in small overlapping currents, then eases back. Keep the flame height low and the full top covered.'),
        ('Пульс тепла', 'Short low tongues brighten and settle in alternating zones, a soft heat pulse moving across the full surface without lifting into tall flames.'),
        ('Неглубокие волны', 'A subtle ripple of low flames travels diagonally across the covered top and fades, followed by a gentler return wave. No tall jets or gaps.'),
        ('Переменный ритм', 'Small fire tongues dance with irregular but gentle timing across the full top, some briefly dimming as neighbours brighten. Maintain a flat low profile.'),
    ],
    'acid': [
        ('Мелкая рябь', 'Fine shallow ripples travel across the thin green acid film in staggered rings, then fade. Keep the film flat and continuous.'),
        ('Тихий блеск', 'Subtle highlights shimmer over the thin acid film in small shifting patches. No bubbling mound, foam, raised liquid or colour flash.'),
        ('Плавное течение', 'A slow gentle surface current moves across the flat green acid film and returns, with tiny ripples at its edge. The coating stays thin.'),
        ('Диагональная волна', 'A very shallow wave travels from the rear corner to the front through the thin film, settles, and repeats with a soft offset rhythm.'),
        ('Рассеянная рябь', 'Sparse small ripples appear in different areas of the green film, overlap softly and vanish. Keep the entire top evenly coated.'),
    ],
    'caltrops': [
        ('Редкие блики', 'A few tiny steel highlights glint briefly on separate caltrop tips, one after another, then return to their original shade.'),
        ('Медленный отблеск', 'A narrow soft steel glint crosses a few existing metal edges at a slow pace, then fades; the objects remain completely motionless.'),
        ('Чередование граней', 'Subtle brief highlights appear on alternating fixed steel facets, with long dim intervals and no global flash.'),
        ('Неровный ритм', 'Rare pinprick steel reflections shimmer at irregular intervals on existing caltrop tips, always returning to the initial appearance.'),
        ('Тихий проблеск', 'One small muted highlight at a time glows along the fixed metal edges and fades in a very restrained repeating rhythm.'),
    ],
}
GUARD = {
    'fire': 'Animate only the existing low fire. Stone, side faces, silhouette, position, scale and camera stay still. No high flames, smoke, sparks, dry gaps or spill beyond the tile. Preserve outside transparency. Seamless loop returning to the first frame.',
    'acid': 'Animate only the existing thin green film. Stone, side faces, silhouette, position, scale and camera stay still. No frothy pool, large bubbles, raised liquid, spill or new objects. Preserve outside transparency. Seamless loop returning to the first frame.',
    'caltrops': 'Animate only restrained steel reflections. Caltrops and stone remain fixed in silhouette, position, scale and camera. No rotation, jumping, extension, bending or new objects. Preserve outside transparency. Seamless loop returning to the first frame.',
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    existing = ROOT / 'requests.json'
    if existing.exists() and any((JOBS / 'pixellab' / row['key'] / 'submit-started.json').exists()
                                 for row in json.loads(existing.read_text(encoding='utf-8'))):
        raise SystemExit('Есть начатые POST; подготовленные запросы нельзя перезаписывать')
    rows = []
    for source_key, source_rel, label, kind, subject, pose in SOURCES:
        source = (ROOT / source_rel).resolve()
        model = ROOT / 'model' / source_key
        model.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, model / 'source-original.png')
        with Image.open(source) as image:
            assert image.format == 'PNG' and image.mode == 'RGBA' and image.size == (1254, 1254), source
            # Целый кадр, без кропа и ретуши; API ограничен 256×256.
            image.resize((256, 256), Image.Resampling.LANCZOS).save(model / 'input-256.png')
        transform = {'source': source_rel, 'source_sha256': sha(source),
                     'original_copy': f'model/{source_key}/source-original.png',
                     'input': f'model/{source_key}/input-256.png',
                     'input_sha256': sha(model / 'input-256.png'), 'source_size': [1254, 1254],
                     'input_size': [256, 256], 'crop': None, 'resize': 'Pillow LANCZOS, whole frame',
                     'pixel_retouch': False, 'integration': False}
        (model / 'transform.json').write_text(json.dumps(transform, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        frame = {'base64': base64.b64encode((model / 'input-256.png').read_bytes()).decode('ascii'), 'format': 'png'}
        captions = {'direction': 'south-east', 'view': 'low top-down',
                    'subject_description': subject, 'initial_pose': pose}
        for index, (name, motion) in enumerate(MOTIONS[source_key if source_key in MOTIONS else kind], 1):
            key = f'{source_key}-{index:02d}'
            prompt = f'{motion} {GUARD[kind]}'
            assert 0 < len(prompt) <= 1000 and len(subject) <= 300 and len(pose) <= 300
            folder = JOBS / 'pixellab' / key
            folder.mkdir(parents=True, exist_ok=True)
            request = {'first_frame': frame, 'last_frame': frame, 'description': prompt,
                       'frame_count': 32, 'seed': 20261104001 + len(rows),
                       'no_background': True, 'enhance_prompt': False, **captions}
            (folder / 'request.json').write_text(json.dumps(request), encoding='utf-8')
            (folder / 'prompt.txt').write_text(prompt, encoding='utf-8')
            rows.append({'key': key, 'source_key': source_key, 'group': label, 'kind': kind,
                         'variant': index, 'name': name, 'prompt': prompt, 'seed': request['seed'],
                         'frame_count': 32, 'expected_frames': 33, 'endpoint': 'animate-pixminimax',
                         'loop': True, 'return_to_first': True, 'input': transform['input'],
                         'source': source_rel, 'source_sha256': transform['source_sha256'],
                         'captions': captions, 'input_sha256': transform['input_sha256'],
                         'request_sha256': sha(folder / 'request.json'), 'integration': False})
    assert len(rows) == 30 and len({r['key'] for r in rows}) == 30
    (ROOT / 'requests.json').write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Prepared 30 requests from six whole-frame RGBA inputs; no POST')


if __name__ == '__main__':
    main()
