"""Independently verify masked 64px provenance, full-frame assembly and playback."""

from __future__ import annotations

import base64
import hashlib
import io
import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
ART = ROOT.parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-masked-retry-20261105')
EXPECTED = [f'{source}-{variant:02d}'
            for source in ('fire22', 'fire23', 'fire24', 'fire29', 'caltrops03')
            for variant in range(1, 4)]


def read(path: Path) -> object:
    return json.loads(path.read_text(encoding='utf-8'))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(item: dict) -> bytes:
    value = item['base64']
    return base64.b64decode(value.split(',', 1)[1] if value.startswith('data:') else value, validate=True)


def pixels(path: Path, size: tuple[int, int], mode: str = 'RGBA') -> np.ndarray:
    with Image.open(path) as image:
        image.load()
        assert image.format == 'PNG' and image.mode == mode and image.size == size, path
        return np.asarray(image).copy()


def main() -> None:
    rows = read(ROOT / 'requests.json')
    assert [row['key'] for row in rows] == EXPECTED
    assert len({row['seed'] for row in rows}) == 15
    exported = read(ROOT / 'validation.json')
    assert exported['complete'] and exported['exported_clips'] == 15
    before = read(ROOT / 'balance-before.json')['subscription']['generations']
    after = read(ROOT / 'balance-after.json')['subscription']['generations']
    details = []
    raw_matches = assembled_matches = 0
    usage_total = 0.0
    for row in rows:
        key = row['key']
        model = ROOT / 'model' / key
        output = ROOT / 'pixellab' / key
        external = JOBS / 'pixellab' / key
        assert row['endpoint'] == 'animate-with-text'
        assert row['raw_api_canvas'] == [64, 64] and row['derived_canvas'] == [256, 256]
        assert sha(ART / row['source']) == sha(model / 'source-original.png') == row['source_sha256']
        assert sha(model / 'input-256.png') == row['input_sha256']
        source = pixels(model / 'input-256.png', (256, 256))
        with Image.open(model / 'source-original.png') as original:
            reconstructed = original.resize((256, 256), Image.Resampling.LANCZOS)
            assert np.array_equal(np.asarray(reconstructed), source)
        x0, y0, x1, y1 = row['roi_xyxy']
        assert 0 <= x0 < x1 <= 256 and 0 <= y0 < y1 <= 256 and x1 - x0 == 64 and y1 - y0 == 64
        roi = pixels(model / 'roi-static.png', (64, 64))
        assert np.array_equal(source[y0:y1, x0:x1], roi) and sha(model / 'roi-static.png') == row['roi_sha256']
        assert sha(external / 'request.json') == row['request_sha256']
        assert (external / 'submit-started.json').exists()
        request = read(external / 'request.json')
        assert request['n_frames'] == 4 and request['image_size'] == {'width': 64, 'height': 64}
        assert request['image_guidance_scale'] == row['image_guidance_scale']
        assert request['text_guidance_scale'] == row['text_guidance_scale']
        assert request['action'] == row['action'] and request['description'] == row['description']
        assert all(decode(item) == (model / 'roi-static.png').read_bytes() for item in request['inpainting_images'])
        masks = []
        for index in range(4):
            path = model / f'mask-{index}.png'
            assert sha(path) == row['mask_sha256'][index]
            assert decode(request['mask_images'][index]) == path.read_bytes()
            channels = pixels(path, (64, 64), mode='RGB')
            assert np.array_equal(channels[:, :, 0], channels[:, :, 1]) and np.array_equal(channels[:, :, 1], channels[:, :, 2])
            mask = channels[:, :, 0] > 0
            assert int(mask.sum()) == row['mask_white_pixels'][index]
            masks.append(mask)
        assert not masks[0].any() and not masks[3].any()
        assert (external / 'response-raw.json').read_bytes() == (output / 'response-raw.json').read_bytes()
        response = read(output / 'response-raw.json')
        assert len(response['images']) == 4
        clip = read(output / 'clip.json')
        assert clip['request_sha256'] == row['request_sha256'] and clip['response_sha256'] == sha(output / 'response-raw.json')
        assert clip['returned_frames'] == 4 and clip['raw_api_canvas'] == [64, 64]
        usage = response['usage']
        assert usage['type'] == 'generations' and usage['generations'] > 0
        usage_total += usage['generations']
        frames = []
        source_normalization = []
        for index in range(4):
            raw_path = output / 'raw-64' / f'frame-{index:02d}.png'
            raw = raw_path.read_bytes()
            assert raw == decode(response['images'][index])
            raw_matches += 1
            frame = pixels(raw_path, (64, 64))
            frames.append(frame)
            derived = pixels(output / 'assembled-256' / f'frame-{index:02d}.png', (256, 256))
            expected = source.copy()
            expected[y0:y1, x0:x1] = frame
            assert np.array_equal(expected, derived)
            assembled_matches += 1
            outside = ~masks[index]
            changed_vs_source = np.any(frame[outside] != roi[outside], axis=1)
            visible = (frame[outside][:, 3] > 8) | (roi[outside][:, 3] > 8)
            assert int(np.count_nonzero(changed_vs_source & visible)) == 0
            source_normalization.append(int(np.count_nonzero(changed_vs_source)))
            assert int(np.count_nonzero(np.any(frame[outside] != frames[0][outside], axis=1))) == 0
        assert np.array_equal(frames[0], frames[3])
        assert source_normalization == [source_normalization[0]] * 4
        raw_sheet = pixels(output / 'sheet-raw-64.png', (256, 64))
        assembled_sheet = pixels(output / 'sheet-assembled-256.png', (1024, 256))
        for index in range(4):
            assert np.array_equal(raw_sheet[:, index * 64:(index + 1) * 64], frames[index])
            assert np.array_equal(assembled_sheet[:, index * 256:(index + 1) * 256],
                                  pixels(output / 'assembled-256' / f'frame-{index:02d}.png', (256, 256)))
        order, durations = row['playback_order'], row['durations_ms']
        assert len(order) == len(durations) and all(0 <= i < 4 for i in order) and all(t > 0 for t in durations)
        if row['kind'] == 'fire':
            assert order == [0, 1, 2, 3]
        else:
            assert order[0] == 0 and order[-1] == 3 and set(order) == {0, 1, 2, 3}
            assert order.count(1) in (1, 2) and order.count(2) == 1
        details.append({'key': key, 'raw_frames': 4,
                        'masked_white_pixels': row['mask_white_pixels'],
                        'outside_mask_source_normalized_pixels': source_normalization[0],
                        'outside_mask_visible_changes_alpha_gt8': 0,
                        'outside_mask_temporal_changed_pixels': 0,
                        'first_last_raw_rgba_equal': True,
                        'playback_order': order, 'durations_ms': durations,
                        'usage': usage})
    assert before - after == usage_total
    report = {'status': 'PASS', 'meaning': 'Provenance, raw API bytes, integer assembly and temporal mask checks',
              'clips': len(details), 'raw64_api_byte_matches': raw_matches,
              'derived256_exact_integer_assemblies': assembled_matches,
              'temporal_outside_mask_and_seam_passes': len(details),
              'strict_source_rgba_equal': False,
              'source_normalization_note': 'Provider changes only constant almost-transparent source pixels outside masks; no visible alpha>8 change or temporal change outside masks.',
              'balance_before': before, 'balance_after': after,
              'total_generations': usage_total,
              'artistic_acceptance': 'open', 'integration': False,
              'details': details}
    (ROOT / 'package-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in report.items() if key != 'details'}))


if __name__ == '__main__':
    main()
