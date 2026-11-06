"""Build two diagnostic loops from byte-checked, unchanged PixelLab RGBA poses.

All full-tile images are derived assemblies; 256-pixel files are viewing
downscales. The moving pixels always come from the listed raw ROI PNGs.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
ROOT = HERE.parents[3]
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/field-loops.json'
PLANS = {
    'fire24-field07': [1, 2, 3, 2, 1],
    'fire29-field01': [1, 2, 3, 4, 3, 2, 1],
}
FRAME_MS = 180


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pixels(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert('RGBA'), dtype=np.int16)


def bbox(mask: np.ndarray) -> list[int] | None:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]


def premul(arr: np.ndarray) -> np.ndarray:
    return arr[:, :, :3].astype(np.float32) * (arr[:, :, 3:4].astype(np.float32) / 255.0)


def step(a_raw, b_raw, a_full, b_full, a_256, b_256):
    a_alpha, b_alpha = a_raw[:, :, 3], b_raw[:, :, 3]
    raw_delta = np.max(np.abs(premul(a_raw) - premul(b_raw)), axis=2)
    full_delta = np.max(np.abs(a_full[:, :, :3].astype(np.int16) - b_full[:, :, :3].astype(np.int16)), axis=2)
    small_delta = np.max(np.abs(a_256[:, :, :3].astype(np.int16) - b_256[:, :, :3].astype(np.int16)), axis=2)
    return {
        'raw_alpha_gt8_xor_pixels': int(np.logical_xor(a_alpha > 8, b_alpha > 8).sum()),
        'raw_alpha_abs_sum': int(np.abs(a_alpha - b_alpha).sum()),
        'raw_premultiplied_max_rgb_gt8_pixels': int((raw_delta > 8).sum()),
        'raw_premultiplied_max_rgb_sum': round(float(raw_delta.sum()), 2),
        'fulltile_native_visible_max_rgb_gt8_pixels': int((full_delta > 8).sum()),
        'fulltile_native_visible_max_rgb_sum': int(full_delta.sum()),
        'fulltile_256_visible_max_rgb_gt8_pixels': int((small_delta > 8).sum()),
        'fulltile_256_visible_max_rgb_sum': int(small_delta.sum()),
        'fulltile_exact_rgba': bool(np.array_equal(a_full, b_full)),
    }


def build_clip(key: str, order: list[int]) -> dict:
    request_path = PACKAGE / 'requests' / key / 'request-metadata.json'
    result_dir = PACKAGE / 'results' / key
    meta = json.loads(request_path.read_text(encoding='utf-8'))
    manifest = json.loads((result_dir / 'manifest.json').read_text(encoding='utf-8'))
    assert meta['key'] == manifest['key'] == key
    assert len(manifest['frames']) == manifest['returned_frames'] == 17
    box = meta['group']['crop_xyxy']
    size = meta['group']['crop_size']
    assert box[2] - box[0] == box[3] - box[1] == size
    source_path = ROOT / f"docs/art/fire-low-styles-20261104/fire-low-{key[4:6]}.png"
    input_path = ROOT / meta['group']['input_path']
    core_path = ROOT / meta['group']['core_mask_path']
    assert sha(source_path) == meta['source_sha256']
    assert sha(input_path) == meta['input_sha256']
    assert sha(core_path) == meta['group']['core_mask_sha256']
    source = Image.open(source_path).convert('RGBA')
    assert source.size == (1254, 1254)
    core = np.asarray(Image.open(core_path).convert('L')) > 0
    out = HERE / key
    native_dir, small_dir, crop_dir = out / 'assembled-native', out / 'view-256', out / 'crop-native'
    native_dir.mkdir(parents=True, exist_ok=True)
    small_dir.mkdir(parents=True, exist_ok=True)
    crop_dir.mkdir(parents=True, exist_ok=True)
    original_256 = small_dir / 'source.png'
    source.resize((256, 256), Image.Resampling.LANCZOS).save(original_256)
    original_crop = crop_dir / 'source.png'
    source.crop(box).save(original_crop)
    frames = {}
    for index in sorted(set(order)):
        row = manifest['frames'][index]
        assert row['frame'] == index
        raw_path = result_dir / 'raw' / f'frame-{index:02}.png'
        assert sha(raw_path) == row['sha256']
        raw = Image.open(raw_path).convert('RGBA')
        assert raw.size == (size, size)
        raw_arr = pixels(raw)
        uncovered = int((core & (raw_arr[:, :, 3] <= 8)).sum())
        assert uncovered == 0, f'{key} frame {index} exposes original core'
        alpha_border = bool(np.any(raw_arr[0, :, 3] > 0) or np.any(raw_arr[-1, :, 3] > 0) or np.any(raw_arr[:, 0, 3] > 0) or np.any(raw_arr[:, -1, 3] > 0))
        assert not alpha_border, f'{key} frame {index} cuts ROI border'
        layer = Image.new('RGBA', source.size)
        layer.paste(raw, box[:2])
        assembled = Image.alpha_composite(source, layer)
        native_path = native_dir / f'raw-{index:02}.png'
        assembled.save(native_path)
        small = assembled.resize((256, 256), Image.Resampling.LANCZOS)
        small_path = small_dir / f'raw-{index:02}.png'
        small.save(small_path)
        crop_path = crop_dir / f'raw-{index:02}.png'
        assembled.crop(box).save(crop_path)
        # The native assembly is identical to the source outside the ROI.
        full_arr = pixels(assembled)
        source_arr = pixels(source)
        x0, y0, x1, y1 = box
        changed = np.any(full_arr != source_arr, axis=2)
        changed[y0:y1, x0:x1] = False
        assert not changed.any()
        frames[index] = {
            'raw_path': raw_path.relative_to(ROOT).as_posix(),
            'raw_sha256': row['sha256'],
            'assembled_native_path': native_path.relative_to(ROOT).as_posix(),
            'assembled_native_sha256': sha(native_path),
            'view_256_path': small_path.relative_to(ROOT).as_posix(),
            'view_256_sha256': sha(small_path),
            'crop_native_path': crop_path.relative_to(ROOT).as_posix(),
            'crop_native_sha256': sha(crop_path),
            'raw_alpha_bbox_xyxy': bbox(raw_arr[:, :, 3] > 8),
            'uncovered_original_core_pixels': uncovered,
            'raw_alpha_on_roi_border': alpha_border,
            'raw_array': raw_arr,
            'full_array': full_arr,
            'small_array': pixels(small),
        }
    timeline = []
    for n, index in enumerate(order + [order[0]]):
        row = frames[index]
        timeline.append({'slot': n, 'raw_frame': index, 'duration_ms': FRAME_MS if n < len(order) else 0,
                         'raw_sha256': row['raw_sha256'], 'assembled_native_sha256': row['assembled_native_sha256']})
    transitions = []
    for pos in range(len(order)):
        left, right = order[pos], order[(pos + 1) % len(order)]
        a, b = frames[left], frames[right]
        transitions.append({'from_slot': pos, 'to_slot': (pos + 1) % len(order),
                            'from_raw': left, 'to_raw': right,
                            **step(a['raw_array'], b['raw_array'], a['full_array'], b['full_array'], a['small_array'], b['small_array'])})
    assert transitions[-1]['fulltile_exact_rgba']
    first, last = frames[order[0]], frames[order[-1]]
    assert first['raw_sha256'] == last['raw_sha256']
    raw0_path = result_dir / 'raw/frame-00.png'
    assert sha(raw0_path) == manifest['frames'][0]['sha256']
    raw0_arr = pixels(Image.open(raw0_path))
    source_arr = pixels(source)
    source_small_arr = pixels(Image.open(original_256))
    entry = step(raw0_arr, first['raw_array'], source_arr, first['full_array'], source_small_arr, first['small_array'])
    summary = {
        'key': key, 'source': source_path.relative_to(ROOT).as_posix(), 'source_sha256': sha(source_path),
        'input': input_path.relative_to(ROOT).as_posix(), 'input_sha256': sha(input_path),
        'source_view_256': original_256.relative_to(ROOT).as_posix(), 'source_view_256_sha256': sha(original_256),
        'source_crop_native': original_crop.relative_to(ROOT).as_posix(), 'source_crop_native_sha256': sha(original_crop),
        'core_mask': core_path.relative_to(ROOT).as_posix(), 'core_mask_sha256': sha(core_path),
        'crop_xyxy': box, 'native_crop_size': size, 'raw0_excluded': True,
        'order': order, 'frame_ms': FRAME_MS, 'duration_ms': len(order) * FRAME_MS,
        'frames': {str(i): {k: v for k, v in row.items() if not k.endswith('_array')} for i, row in frames.items()},
        'timeline': timeline, 'transitions': transitions,
        'max_adjacent_alpha_xor': max(t['raw_alpha_gt8_xor_pixels'] for t in transitions),
        'max_adjacent_raw_premul_gt8': max(t['raw_premultiplied_max_rgb_gt8_pixels'] for t in transitions),
        'max_adjacent_256_visible_gt8': max(t['fulltile_256_visible_max_rgb_gt8_pixels'] for t in transitions),
        'raw00_source_to_first_pose': entry,
        'exact_cycle_seam': transitions[-1]['fulltile_exact_rgba'],
        'unchanged_source_outside_roi': True, 'core_covered': True,
    }
    (out / 'timeline.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return summary


def main():
    clips = [build_clip(key, order) for key, order in PLANS.items()]
    report = {
        'scope': 'Two already completed PixelLab field pilots only; no new poses or API calls.',
        'method': 'Each unique raw RGBA crop is pasted without pixel modification at its native 1254-source ROI; alpha-over assembly. Only 256 viewing images use Lanczos downscale.',
        'selection': {'fire24-field07': 'Frames 01,02,03 remain low and cover the original core; excluded raw00 and stronger 04..14. 15/16 were rejected because jumps from 03 are larger.',
                      'fire29-field01': 'Frames 01..04 form a small contour excursion; the return reuses the same raw poses. Excluded raw00 and near-static 11..16.'},
        'visual_assessment': {
            'fire24-field07': 'Native crop shows a small existing contour bend and PixelLab color grain, with no new tall jet or flash in selected poses. At 256 full tile only 16-24 visible pixels >8 change per moving step; not a full-tile art pass.',
            'fire29-field01': 'Native crop shows a soft edge contraction, without a new jet or flash. At 256 full tile only 0-4 visible pixels >8 change per moving step, so usable motion is not established.'},
        'limitations': ['These are isolated single field strokes, not complete animated fire24/fire29 tiles.',
                        'Even the first selected PixelLab pose has a source-to-generated color transition; the loop avoids that transition internally by excluding raw00. It remains visible if a source still is followed immediately by playback.',
                        'Returning along identical poses yields a short, stepped pulse, not an independently generated fluid reverse motion.',
                        'PixelLab color grain remains visible at native crop size. At full tile 256 display the small motion is subdued; technical loop closure does not establish art acceptance.'],
        'clips': clips,
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    web = []
    for clip in clips:
        web.append({k: v for k, v in clip.items() if k not in ('timeline', 'transitions')})
        web[-1]['transitions'] = clip['transitions']
    (HERE / 'gallery-data.js').write_text('window.FIELD_LOOPS=' + json.dumps(web, ensure_ascii=False, separators=(',', ':')) + ';\n', encoding='utf-8')
    print(json.dumps([{'key': c['key'], 'order': c['order'], 'max_alpha_xor': c['max_adjacent_alpha_xor'], 'max_256_gt8': c['max_adjacent_256_visible_gt8']} for c in clips]))


if __name__ == '__main__':
    main()
