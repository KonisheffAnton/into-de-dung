"""Подготовка четырёх новых проб низкого огня без сетевых запросов."""

from pathlib import Path
import base64
import hashlib
import json
import shutil
from PIL import Image


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-subtle-animation-20261105')
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29')
ACTION = (
    'Barely moving low fire: only the tips of the existing tiny flames breathe and sway '
    'very slowly, gently left and right by no more than one or two pixels in this 256-pixel '
    'frame, easing back to the exact starting shape. Preserve the original flame positions, '
    'density, coverage, palette and overall silhouette. Keep every flame tip at or below '
    'its original maximum height. The entire top remains continuously covered by the same '
    'small low flames. The stone base, side faces, outer tile edges, camera, scale and '
    'transparent surroundings are absolutely fixed in every frame. No new flames, no '
    'larger tongues, no rising peaks, no vertical growth, no smoke, sparks, detached '
    'particles, gaps, spill, colour pulse or global brightness cycling. Slow subtle '
    'geometric sway of existing flame tips only. Seamless loop returning to the first frame.'
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if len(ACTION) > 1000:
        raise SystemExit('Prompt > 1000 characters')
    manifest_path = ROOT / 'requests.json'
    if manifest_path.exists() and any((JOBS / 'pixellab' / row['key'] / 'submit-started.json').exists()
                                      for row in json.loads(manifest_path.read_text(encoding='utf-8'))):
        raise SystemExit('Started POST exists: requests are immutable')
    rows = []
    for index, source_key in enumerate(SOURCES):
        source = ROOT.parent / 'fire-low-styles-20261104' / f'fire-low-{source_key[4:]}.png'
        model = ROOT / 'model' / source_key
        model.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, model / 'source-original.png')
        with Image.open(source) as image:
            if image.format != 'PNG' or image.mode != 'RGBA' or image.size != (1254, 1254):
                raise SystemExit(f'Unexpected source: {source}')
            image.resize((256, 256), Image.Resampling.LANCZOS).save(model / 'input-256.png')
        input_path = model / 'input-256.png'
        transform = {
            'source': source.relative_to(ROOT).as_posix() if source.is_relative_to(ROOT) else '../fire-low-styles-20261104/' + source.name,
            'source_sha256': sha(source), 'original_copy': f'model/{source_key}/source-original.png',
            'input': f'model/{source_key}/input-256.png', 'input_sha256': sha(input_path),
            'source_size': [1254, 1254], 'input_size': [256, 256], 'crop': None,
            'resize': 'Pillow LANCZOS, whole frame', 'pixel_retouch': False, 'integration': False,
        }
        (model / 'transform.json').write_text(json.dumps(transform, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        key = f'{source_key}-01'
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=True)
        frame = {'base64': base64.b64encode(input_path.read_bytes()).decode('ascii'), 'format': 'png'}
        captions = {
            'direction': 'south-east', 'view': 'low top-down',
            'subject_description': 'A fixed isometric stone tile with the original tiny low flames covering the whole diamond top',
            'initial_pose': 'Tiny existing flames cover the whole top; stone sides and outer silhouette remain fixed',
        }
        request = {
            'first_frame': frame, 'last_frame': frame, 'description': ACTION,
            'frame_count': 32, 'seed': 20261105001 + index,
            'no_background': True, 'enhance_prompt': False, **captions,
        }
        request_path = folder / 'request.json'
        request_path.write_text(json.dumps(request), encoding='utf-8')
        (folder / 'prompt.txt').write_text(ACTION, encoding='utf-8')
        rows.append({
            'key': key, 'source_key': source_key, 'group': f'Низкий огонь {source_key[4:]}',
            'kind': 'fire', 'variant': 1, 'name': 'Едва заметное покачивание',
            'prompt': ACTION, 'seed': request['seed'], 'frame_count': 32,
            'expected_frames': 33, 'endpoint': 'animate-pixminimax', 'loop': True,
            'return_to_first': True, 'input': transform['input'], 'source': transform['source'],
            'source_sha256': transform['source_sha256'], 'captions': captions,
            'input_sha256': transform['input_sha256'], 'request_sha256': sha(request_path),
            'integration': False,
        })
    manifest_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'Prepared {len(rows)} whole-frame requests; prompt {len(ACTION)} chars; no POST')


if __name__ == '__main__':
    main()
