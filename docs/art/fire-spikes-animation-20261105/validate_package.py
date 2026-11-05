"""Verify eighteen raw PNG clips, exact payload provenance, sheets and seam metrics."""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from export_pixellab import KEYS, JOBS, ROOT, decode, difference


def read(path: Path) -> object:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        image.load()
        if image.format != 'PNG' or image.mode != 'RGBA':
            raise AssertionError(f'Expected RGBA PNG: {path}')
        return np.asarray(image).copy()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-raw', action='store_true')
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = read(ROOT / 'requests.json')
    assert [row['key'] for row in rows] == KEYS
    assert len({row['seed'] for row in rows}) == 18
    manifest = read(ROOT / ('pixellab-validation-partial.json' if args.completed_only
                            else 'pixellab-validation.json'))
    selected = [row for row in rows if (ROOT / 'pixellab' / row['key'] / 'clip.json').exists()] if args.completed_only else rows
    assert manifest['expected'] == 18 and manifest['completed'] == len(selected)
    if not args.completed_only:
        assert manifest['complete'] and len(selected) == 18
    details = []
    raw_matches = frame_count = 0
    for row in selected:
        key = row['key']
        assert row['frame_count'] == (32 if row['kind'] == 'caltrops' else 8 if row['kind'] == 'spike_transition' else 4)
        assert row['endpoint'] == ('animate-pixminimax' if row['kind'] == 'caltrops' else 'animate-with-text-v3')
        assert row['loop'] != row['one_way']
        first_path, last_path = ROOT / row['first_input'], ROOT / row['last_input']
        source_path = ROOT.parent / row['source']
        assert sha(first_path) == row['first_sha256'] and sha(last_path) == row['last_sha256']
        assert sha(source_path) == row['source_sha256']
        model = ROOT / 'model' / row['source_key']
        source_copy = model / ('source-pair-original.png' if row['kind'] == 'spike_transition' else 'source-original.png')
        assert sha(source_copy) == sha(source_path)
        transform = read(model / 'transform.json')
        assert transform['pixel_retouch'] is False
        if row['kind'] == 'spike_transition':
            pair = Image.open(source_copy)
            assert pair.size == (1536, 1024) and pair.mode == 'RGBA'
            for name, crop, offset in (('retracted', (0, 0, 768, 1024), 102),
                                       ('extended', (768, 0, 1536, 1024), 151)):
                half = pair.crop(crop)
                assert np.array_equal(np.asarray(half), rgba(model / f'{name}-half.png'))
                canvas = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
                canvas.paste(half, (offset, 0))
                reconstructed = canvas.resize((256, 256), Image.Resampling.LANCZOS)
                assert np.array_equal(np.asarray(reconstructed), rgba(model / f'{name}-input-256.png'))
        else:
            with Image.open(source_copy) as original:
                reconstructed = original.resize((256, 256), Image.Resampling.LANCZOS)
                assert np.array_equal(np.asarray(reconstructed), rgba(first_path))
        external = JOBS / 'pixellab' / key
        request_path = external / 'request.json'
        assert (external / 'submit-started.json').exists() and sha(request_path) == row['request_sha256']
        request = read(request_path)
        assert decode(request['first_frame']) == first_path.read_bytes()
        assert decode(request['last_frame']) == last_path.read_bytes()
        assert request['frame_count'] == row['frame_count'] and request['seed'] == row['seed']
        assert request['no_background'] is True and request['enhance_prompt'] is False
        if row['endpoint'] == 'animate-with-text-v3':
            assert request['action'] == row['prompt'] and request['drift_threshold'] == 0
        else:
            assert request['description'] == row['prompt']
        admission, job = read(external / 'admission.json'), read(external / 'job-latest.json')
        assert job['status'] == 'completed' and job['id'] == admission['background_job_id']
        clip_dir = ROOT / 'pixellab' / key
        clip = read(clip_dir / 'clip.json')
        assert clip['job_id'] == job['id'] and clip['request_sha256'] == row['request_sha256']
        count = clip['actual_frames']
        assert len(job['last_response']['images']) == count == len(clip['frame_sha256'])
        frames = []
        for index in range(count):
            path = clip_dir / 'frames' / f'frame-{index:02d}.png'
            assert path.is_file() and sha(path) == clip['frame_sha256'][index]
            pixels = rgba(path)
            assert pixels.shape == (256, 256, 4) and int(pixels[:, :, 3].min()) == 0
            if args.verify_raw:
                assert path.read_bytes() == decode(job['last_response']['images'][index])
                raw_matches += 1
            frames.append(pixels)
            frame_count += 1
        assert len(list((clip_dir / 'frames').glob('frame-*.png'))) == count
        sheet = rgba(clip_dir / 'sheet.png')
        assert sheet.shape == (((count + 7) // 8) * 256, 2048, 4)
        for index, pixels in enumerate(frames):
            assert np.array_equal(sheet[index // 8 * 256:index // 8 * 256 + 256,
                                        index % 8 * 256:index % 8 * 256 + 256], pixels)
        for index in range(count, ((count + 7) // 8) * 8):
            assert np.all(sheet[index // 8 * 256:index // 8 * 256 + 256,
                                index % 8 * 256:index % 8 * 256 + 256, 3] == 0)
        assert all(sha(clip_dir / name) == digest for name, digest in clip['artifact_sha256'].items())
        with Image.open(clip_dir / 'preview.gif') as gif:
            gif_count = gif.n_frames
            gif_loop = gif.info.get('loop')
            assert gif_loop == (None if row['one_way'] else 0)
        first = Image.fromarray(frames[0], 'RGBA')
        last = Image.fromarray(frames[-1], 'RGBA')
        assert clip['first_vs_input'] == difference(first, Image.fromarray(rgba(first_path), 'RGBA'))
        assert clip['last_vs_target'] == difference(last, Image.fromarray(rgba(last_path), 'RGBA'))
        assert clip['loop_seam_last_to_first'] == (difference(last, first) if row['loop'] else None)
        details.append({'key': key, 'kind': row['kind'], 'frames': count, 'gif_frames': gif_count,
                        'gif_loop_extension': gif_loop,
                        'first_vs_input': clip['first_vs_input'],
                        'last_vs_target': clip['last_vs_target'],
                        'loop_seam_last_to_first': clip['loop_seam_last_to_first'],
                        'neighbor_first_to_second': clip['neighbor_first_to_second'],
                        'neighbor_penultimate_to_last': clip['neighbor_penultimate_to_last'],
                        'edge_frames': clip['edge_frames'],
                        'margin_violation_frames': clip['margin_violation_frames']})
    report = {'status': 'PASS', 'meaning': 'Technical provenance and raw-byte verification only',
              'expected_clips': 18, 'completed_clips': len(selected),
              'raw_png_frames': frame_count,
              'raw_api_byte_matches': raw_matches if args.verify_raw else 'not checked',
              'source_and_input_reconstruction': True,
              'all_job_ids_match_admissions': True,
              'artistic_acceptance': 'open', 'integration': False,
              'details': details}
    path = ROOT / ('validation-partial.json' if args.completed_only else 'validation.json')
    path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'details'}))


if __name__ == '__main__':
    main()
