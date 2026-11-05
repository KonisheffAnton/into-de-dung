"""Export only completed admitted PixelLab PNG bytes, with measured endpoint evidence."""

from __future__ import annotations

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-spikes-animation-20261105')
KEYS = [f'{source}-{variant:02d}'
        for source in ('fire22', 'fire23', 'fire24', 'fire29', 'spike01', 'caltrops03')
        for variant in range(1, 4)]


def read(path: Path) -> object:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def difference(a: Image.Image, b: Image.Image) -> dict:
    aa, bb = np.asarray(a).astype(np.int16), np.asarray(b).astype(np.int16)
    delta = np.abs(aa - bb)
    visible = (aa[:, :, 3] > 0) | (bb[:, :, 3] > 0)
    return {'rgba_changed_pixels_gt8': int(np.count_nonzero(np.any(delta > 8, axis=2) & visible)),
            'alpha_changed_pixels_gt8': int(np.count_nonzero(delta[:, :, 3] > 8)),
            'visible_rgba_mae': float(delta[visible].mean()) if np.any(visible) else 0.0,
            'exact_rgba_equal': bool(np.array_equal(aa, bb))}


def image_from_png(raw: bytes, label: str) -> Image.Image:
    with Image.open(io.BytesIO(raw)) as image:
        image.load()
        if image.format != 'PNG' or image.mode != 'RGBA' or image.size != (256, 256):
            raise SystemExit(f'Expected RGBA 256x256 PNG: {label}')
        return image.copy()


def decode(item: dict) -> bytes:
    encoded = item['base64']
    if encoded.startswith('data:'):
        encoded = encoded.split(',', 1)[1]
    return base64.b64decode(encoded, validate=True)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = read(ROOT / 'requests.json')
    if [row['key'] for row in rows] != KEYS:
        raise SystemExit('Expected exactly eighteen keys in fixed order')
    if args.completed_only:
        selected = [row for row in rows if (JOBS / 'pixellab' / row['key'] / 'job-latest.json').exists()
                    and read(JOBS / 'pixellab' / row['key'] / 'job-latest.json').get('status') == 'completed']
    else:
        selected = rows
    results = []
    for row in selected:
        key = row['key']
        external = JOBS / 'pixellab' / key
        if not (external / 'submit-started.json').exists():
            raise SystemExit(f'No POST barrier: {key}')
        admission = read(external / 'admission.json')
        job = read(external / 'job-latest.json')
        if job.get('status') != 'completed' or job.get('id') != admission.get('background_job_id'):
            raise SystemExit(f'No matching completed admitted ID: {key}')
        request_path = external / 'request.json'
        if sha(request_path.read_bytes()) != row['request_sha256']:
            raise SystemExit(f'Request SHA changed: {key}')
        request = read(request_path)
        if request['frame_count'] != row['frame_count'] or request['seed'] != row['seed']:
            raise SystemExit(f'Request metadata mismatch: {key}')
        first_path, last_path = ROOT / row['first_input'], ROOT / row['last_input']
        if sha(first_path.read_bytes()) != row['first_sha256'] or sha(last_path.read_bytes()) != row['last_sha256']:
            raise SystemExit(f'Input SHA changed: {key}')
        if decode(request['first_frame']) != first_path.read_bytes() or decode(request['last_frame']) != last_path.read_bytes():
            raise SystemExit(f'Input payload mismatch: {key}')
        response = job['last_response']
        images = response.get('images', [])
        count = len(images)
        if row['endpoint'] == 'animate-with-text-v3':
            if not row['frame_count'] <= count <= 16:
                raise SystemExit(f'Unexpected V3 frame count {count}: {key}')
        elif row['endpoint'] == 'animate-pixminimax':
            if not 32 <= count <= 64:
                raise SystemExit(f'Unexpected PixMiniMax frame count {count}: {key}')
        else:
            raise SystemExit(f'Unexpected endpoint: {key}')
        output = ROOT / 'pixellab' / key
        frame_dir = output / 'frames'
        frame_dir.mkdir(parents=True, exist_ok=True)
        frames, hashes, boxes = [], [], []
        for index, item in enumerate(images):
            raw = decode(item)
            image = image_from_png(raw, f'{key}:{index}')
            path = frame_dir / f'frame-{index:02d}.png'
            if path.exists() and path.read_bytes() != raw:
                raise SystemExit(f'Existing frame changed: {path}')
            path.write_bytes(raw)
            frames.append(image)
            hashes.append(sha(raw))
            boxes.append(image.getchannel('A').getbbox())
        with Image.open(first_path) as first_still, Image.open(last_path) as last_still:
            first_still.load(); last_still.load()
            first_difference = difference(frames[0], first_still)
            final_difference = difference(frames[-1], last_still)
            seam_difference = difference(frames[-1], frames[0])
            neighbor_start = difference(frames[0], frames[1])
            neighbor_end = difference(frames[-2], frames[-1])
        fps = 3 if row['kind'] == 'caltrops' else 2 if row['kind'] == 'fire' else 4
        durations = [round(1000 / fps)] * count
        sheet = Image.new('RGBA', (8 * 256, ((count + 7) // 8) * 256), (0, 0, 0, 0))
        for index, image in enumerate(frames):
            sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
        sheet.save(output / 'sheet.png')
        # Preview derivatives may use an opaque stage; the raw frame PNGs remain byte-exact.
        gif_frames = []
        for image in frames:
            stage = Image.new('RGBA', (256, 256), '#182131')
            stage.alpha_composite(image)
            gif_frames.append(stage.convert('RGB').resize((512, 512), Image.Resampling.NEAREST))
        gif_frames[0].save(output / 'preview.gif', save_all=True,
                           append_images=gif_frames[1:], duration=durations,
                           disposal=2, optimize=False,
                           **({'loop': 0} if row['loop'] else {}))
        filmstrip = Image.new('RGB', (5 * 256, 256), '#182131')
        for column, index in enumerate([round((count - 1) * j / 4) for j in range(5)]):
            filmstrip.paste(frames[index], (column * 256, 0), frames[index])
        filmstrip.save(output / 'filmstrip.png')
        clip = {**row, 'job_id': job['id'], 'actual_frames': count,
                'usage': response.get('billing_usage') or response.get('usage') or job.get('usage'),
                'frame_sha256': hashes, 'alpha_bboxes': boxes,
                'edge_frames': [i for i, box in enumerate(boxes) if box and
                                (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
                'margin_violation_frames': [i for i, box in enumerate(boxes) if box and
                                            (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
                'fps_preview': fps, 'durations_ms': durations,
                'first_vs_input': first_difference, 'last_vs_target': final_difference,
                'loop_seam_last_to_first': seam_difference if row['loop'] else None,
                'neighbor_first_to_second': neighbor_start,
                'neighbor_penultimate_to_last': neighbor_end,
                'endpoint_policy': 'one-way transition' if row['one_way'] else 'loop candidate; actual seam metrics recorded',
                'artifact_sha256': {name: sha((output / name).read_bytes())
                                    for name in ('sheet.png', 'preview.gif', 'filmstrip.png')},
                'artistic_acceptance': 'open', 'integration': False}
        (output / 'clip.json').write_text(json.dumps(clip, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        results.append(clip)
    summary = {'expected': 18, 'completed': len(results), 'complete': len(results) == 18,
               'raw_png_frames': sum(row['actual_frames'] for row in results),
               'clips': results, 'artistic_acceptance': 'open', 'integration': False}
    output = ROOT / ('pixellab-validation-partial.json' if args.completed_only else 'pixellab-validation.json')
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'completed': len(results), 'expected': 18,
                      'raw_png_frames': summary['raw_png_frames'],
                      'keys': [row['key'] for row in results]}))


if __name__ == '__main__':
    main()
