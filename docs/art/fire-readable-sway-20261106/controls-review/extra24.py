"""Evaluate two completed fire24 PixelLab controls without editing raw or old selection."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[4]
PACKAGE = ROOT / 'docs/art/fire-readable-sway-20261106'
OLD = ROOT / 'docs/art/fire-single-tongue-20261106'
REPORT = ROOT / 'test_reports/fire-readable-sway-20261106/extra24-analysis.json'
CONTACTS = PACKAGE / 'controls-review/contacts-extra24'
KEYS = {'fire24-strong02': [1, 2, 3], 'fire24-strong03': [1, 2, 3, 4]}

spec = importlib.util.spec_from_file_location('controls_analysis_readonly', PACKAGE / 'controls-review/analyze.py')
assert spec and spec.loader
tools = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tools)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def contact(key: str, source: Image.Image, old_peak: np.ndarray, arrays: list[np.ndarray], forward: list[int]) -> dict:
    size = source.width
    images = [(source, 'original crop'),
              (Image.alpha_composite(source, Image.fromarray(old_peak.astype('uint8'), 'RGBA')), 'old peak')]
    images += [(Image.alpha_composite(source, Image.fromarray(arrays[i].astype('uint8'), 'RGBA')), f'raw{i:02}') for i in forward]
    columns = 4
    rows = (len(images) + columns - 1) // columns
    out = Image.new('RGB', (size * columns, rows * (size + 26)), '#202838')
    draw = ImageDraw.Draw(out)
    for i, (image, label) in enumerate(images):
        x, y = (i % columns) * size, (i // columns) * (size + 26)
        out.paste(image.convert('RGB'), (x, y))
        draw.text((x + 5, y + size + 5), label, fill='#f4f6fa')
    CONTACTS.mkdir(parents=True, exist_ok=True)
    path = CONTACTS / f'{key}.png'
    out.save(path)
    return {'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path)}


def main() -> None:
    selection_path = OLD / 'field-selection/selection.json'
    preview_path = OLD / 'field-preview/manifest.json'
    selection = json.loads(selection_path.read_text(encoding='utf-8'))
    preview = json.loads(preview_path.read_text(encoding='utf-8'))
    assert preview['selection_sha256'] == sha(selection_path)
    selected = {c['key']: c for c in selection['clips']}
    playback = {g['key']: g for style in preview['styles'] for g in style['groups']}
    results = []
    for key, forward in KEYS.items():
        request_dir = PACKAGE / 'requests' / key
        result_dir = PACKAGE / 'results' / key
        meta = json.loads((request_dir / 'request-metadata.json').read_text(encoding='utf-8'))
        manifest = json.loads((result_dir / 'manifest.json').read_text(encoding='utf-8'))
        assert meta['key'] == manifest['key'] == key and manifest['returned_frames'] == 17
        assert sha(request_dir / 'request.json') == meta['request_sha256']
        group = meta['group']
        old_key = meta['controlled_comparison_to']
        baseline = selected[old_key]
        assert baseline['input_sha256'] == meta['input_sha256']
        assert baseline['native_crop_xyxy'] == group['crop_xyxy']
        source_path = ROOT / 'docs/art/fire-low-styles-20261104/fire-low-24.png'
        input_path = ROOT / group['input_path']
        core_path = ROOT / group['core_mask_path']
        assert sha(source_path) == meta['source_sha256']
        assert sha(input_path) == group['input_sha256'] and sha(core_path) == group['core_mask_sha256']
        source = Image.open(source_path).convert('RGBA').crop(group['crop_xyxy'])
        plate = np.asarray(source, dtype=np.int16)
        input_arr = tools.old.rgba(input_path)
        input_mask = input_arr[:, :, 3] > 8
        core = np.asarray(Image.open(core_path).convert('L')) > 0
        input_luma = tools.old.luma(input_arr)
        plate_luma = tools.old.luma(plate)
        base_rgb = input_arr[core, :3].astype(float).mean(axis=0)
        base_ratios = base_rgb[1:] / max(base_rgb[0], 1)
        arrays, frames = [], []
        for i, entry in enumerate(manifest['frames']):
            path = result_dir / 'raw' / f'frame-{i:02}.png'
            assert entry['frame'] == i and sha(path) == entry['sha256']
            arr = tools.old.rgba(path)
            assert arr.shape == input_arr.shape
            arrays.append(arr)
            mask = arr[:, :, 3] > 8
            composite = np.asarray(Image.alpha_composite(source, Image.fromarray(arr.astype('uint8'), 'RGBA')), dtype=np.int16)
            visible_delta = np.max(np.abs(composite[:, :, :3] - plate[:, :, :3]), axis=2)
            raw_luma = tools.old.luma(arr)
            core_rgb = arr[core, :3].astype(float).mean(axis=0)
            ratios = core_rgb[1:] / max(core_rgb[0], 1)
            border = int(np.count_nonzero(np.r_[arr[0, :, 3], arr[-1, :, 3], arr[:, 0, 3], arr[:, -1, 3]] > 0))
            detached = tools.new_detached(mask, input_mask)
            frame = {
                'raw': i, 'path': path.relative_to(ROOT).as_posix(), 'sha256': entry['sha256'],
                'alpha_gt8_xor_input_px': int(np.logical_xor(input_mask, mask).sum()),
                'core_uncovered_px': int(np.count_nonzero(core & ~mask)),
                'core_total_px': int(core.sum()),
                'input_alpha_gt8_uncovered_px': int(np.count_nonzero(input_mask & ~mask)),
                'envelope_chebyshev_native_px': tools.envelope_radius(mask, input_mask),
                'crop_border_nonzero_alpha_px': border,
                'new_detached_components': detached,
                'premultiplied_luma_ratio_vs_input': round(float(raw_luma.sum() / input_luma.sum()), 5),
                'max_positive_visible_luma_vs_source_plate': round(float(np.max(tools.old.luma(composite) - plate_luma)), 2),
                'absolute_core_gr_br_delta': [round(float(v), 5) for v in np.abs(ratios - base_ratios)],
                'source_over_rgb_gt8_changed_px': int(np.count_nonzero(visible_delta > 8)),
            }
            frame['old_gate4_core0_pass'] = bool(i != 0 and frame['core_uncovered_px'] == 0 and frame['envelope_chebyshev_native_px'] <= 4 and border == 0 and not detached and .90 <= frame['premultiplied_luma_ratio_vs_input'] <= 1.08 and frame['max_positive_visible_luma_vs_source_plate'] <= 160 and frame['absolute_core_gr_br_delta'][0] <= .06 and frame['absolute_core_gr_br_delta'][1] <= .05)
            frame['preferred_gate6_core0_pass'] = bool(frame['old_gate4_core0_pass'] or (i != 0 and frame['core_uncovered_px'] == 0 and frame['envelope_chebyshev_native_px'] <= 6 and border == 0 and not detached and .90 <= frame['premultiplied_luma_ratio_vs_input'] <= 1.08 and frame['max_positive_visible_luma_vs_source_plate'] <= 160 and frame['absolute_core_gr_br_delta'][0] <= .06 and frame['absolute_core_gr_br_delta'][1] <= .05))
            frames.append(frame)
        old_raw = {item['index']: tools.old.rgba(ROOT / item['path']) for item in baseline['raw_frames']}
        old_forward = baseline['order'][:(len(baseline['order']) + 1) // 2]
        old_peak = old_raw[old_forward[-1]]
        old_span = tools.old.pair(old_raw[old_forward[0]], old_peak, plate)
        old_boundary = tools.boundary_displacement(old_raw[old_forward[0]][:, :, 3] > 8, old_peak[:, :, 3] > 8)
        old_steps = [tools.old.pair(old_raw[a], old_raw[b], plate) for a, b in zip(old_forward, old_forward[1:])]
        steps = []
        for a, b in zip(forward, forward[1:]):
            metrics = tools.old.pair(arrays[a], arrays[b], plate)
            steps.append({'from_raw': a, 'to_raw': b,
                          'boundary_chebyshev_native_px': tools.boundary_displacement(arrays[a][:, :, 3] > 8, arrays[b][:, :, 3] > 8),
                          **metrics})
        span = tools.old.pair(arrays[forward[0]], arrays[forward[-1]], plate)
        boundary = tools.boundary_displacement(arrays[forward[0]][:, :, 3] > 8, arrays[forward[-1]][:, :, 3] > 8)
        order = forward + forward[-2::-1]
        passes = playback[old_key]['passes_in_common_cycle']
        phase = playback[old_key]['phase_offset_slots']
        positions = [(((slot + phase) % 96) * passes * len(order) // 96) % len(order) for slot in range(97)]
        assert len(order) <= 96 // passes and positions[96] == positions[0] and set(positions[:96]) == set(range(len(order)))
        assert np.array_equal(arrays[order[0]], arrays[order[-1]])
        visual_contact = contact(key, source, old_peak, arrays, forward)
        candidate = {
            'forward_raw': forward, 'order': order, 'raw_sha256': {str(i): frames[i]['sha256'] for i in forward},
            'raw_paths': {str(i): frames[i]['path'] for i in forward},
            'alpha_xor_span_px': span['alpha_gt8_xor_pixels'],
            'alpha_span_vs_old_ratio': round(span['alpha_gt8_xor_pixels'] / old_span['alpha_gt8_xor_pixels'], 3),
            'visible_source_over_rgb_gt8_span_px': span['visible_crop_rgb_gt8_pixels'],
            'visible_span_vs_old_ratio': round(span['visible_crop_rgb_gt8_pixels'] / old_span['visible_crop_rgb_gt8_pixels'], 3),
            'boundary_chebyshev_native_px': boundary,
            'boundary_vs_old_ratio': round(boundary / old_boundary, 3),
            'steps': steps,
            'max_adjacent_alpha_xor_px': max(x['alpha_gt8_xor_pixels'] for x in steps),
            'max_adjacent_boundary_chebyshev_native_px': max(x['boundary_chebyshev_native_px'] for x in steps),
            'max_adjacent_visible_rgb_gt8_px': max(x['visible_crop_rgb_gt8_pixels'] for x in steps),
            'max_core_uncovered_px': max(frames[i]['core_uncovered_px'] for i in forward),
            'max_core_uncovered_percent': round(100 * max(frames[i]['core_uncovered_px'] for i in forward) / int(core.sum()), 3),
            'max_input_alpha_uncovered_px': max(frames[i]['input_alpha_gt8_uncovered_px'] for i in forward),
            'max_input_envelope_native_px': max(frames[i]['envelope_chebyshev_native_px'] for i in forward),
            'max_visible_luma_flash': max(frames[i]['max_positive_visible_luma_vs_source_plate'] for i in forward),
            'luma_ratio_range': [min(frames[i]['premultiplied_luma_ratio_vs_input'] for i in forward), max(frames[i]['premultiplied_luma_ratio_vs_input'] for i in forward)],
            'max_core_gr_br_delta': [max(frames[i]['absolute_core_gr_br_delta'][j] for i in forward) for j in (0, 1)],
            'all_raw00_excluded': 0 not in forward,
            'all_core0': all(frames[i]['core_uncovered_px'] == 0 for i in forward),
            'all_envelope6': all(frames[i]['envelope_chebyshev_native_px'] <= 6 for i in forward),
            'all_adjacent_alpha_le180': all(x['alpha_gt8_xor_pixels'] <= 180 for x in steps),
            'all_adjacent_alpha_le220': all(x['alpha_gt8_xor_pixels'] <= 220 for x in steps),
            'all_adjacent_boundary_le6': all(x['boundary_chebyshev_native_px'] <= 6 for x in steps),
            'no_detached_components': all(not frames[i]['new_detached_components'] for i in forward),
            'old_passes_in_96_slots': passes, 'old_phase_offset_slots': phase,
            'loop_frames': len(order), 'max_loop_frames_without_skips': 96 // passes,
            'all_order_positions_displayed': True, 'slot96_equals_slot0': True, 'exact_raw_seam': True,
            'contact': visual_contact,
        }
        if key.endswith('02'):
            candidate['diagnostic_status'] = 'visible_amplitude_improvement_requires_full_cycle_art_review: raw02→03 alpha step386 exceeds exploratory220; raw03 opens1/3039 core pixel. No automatic technical PASS. Raw01→02 alone improves +23% alpha/visible but offers only two distinct positions and an alpha253 step.'
        else:
            candidate['diagnostic_status'] = 'not_recommended_as_visibility_upgrade: core0, adjacent alpha≤220 and boundary≤6, but raw04 envelope7 exceeds preferred6; visible source-over span is smaller than the old loop despite larger boundary travel.'
        result = {
            'key': key, 'old_key': old_key, 'request_sha256': meta['request_sha256'],
            'source_sha256': meta['source_sha256'], 'input_sha256': meta['input_sha256'],
            'core_mask_sha256': group['core_mask_sha256'], 'crop_xyxy': group['crop_xyxy'],
            'returned_raw_frames': len(frames), 'raw_frames': frames,
            'old_loop': {'order': baseline['order'], 'forward_raw': old_forward,
                         'alpha_xor_span_px': old_span['alpha_gt8_xor_pixels'],
                         'visible_source_over_rgb_gt8_span_px': old_span['visible_crop_rgb_gt8_pixels'],
                         'boundary_chebyshev_native_px': old_boundary,
                         'max_adjacent_alpha_xor_px': max(x['alpha_gt8_xor_pixels'] for x in old_steps),
                         'max_adjacent_visible_rgb_gt8_px': max(x['visible_crop_rgb_gt8_pixels'] for x in old_steps),
                         'passes_in_96_slots': passes, 'phase_offset_slots': phase},
            'diagnostic_candidate': candidate, 'art_accepted': False,
        }
        results.append(result)
    output = {
        'scope': 'Read-only evaluation of two completed 17-frame fire24 controls; raw PNGs remain PixelLab bytes.',
        'baseline_selection_sha256': sha(selection_path), 'baseline_preview_manifest_sha256': sha(preview_path),
        'old_gate_caveat': 'Core0 and input envelope4 remain old technical gates. Envelope6 is preferred only for diagnosis; <1% core gaps do not become automatic PASS.',
        'controls': results, 'art_acceptance': 'Separate reviewer/root visual decision; neither diagnostic candidate is integrated or automatically approved.'}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps([{'key': row['key'], 'forward': row['diagnostic_candidate']['forward_raw'],
                       'alpha_ratio': row['diagnostic_candidate']['alpha_span_vs_old_ratio'],
                       'visible_ratio': row['diagnostic_candidate']['visible_span_vs_old_ratio'],
                       'max_core_gap': row['diagnostic_candidate']['max_core_uncovered_px'],
                       'max_envelope': row['diagnostic_candidate']['max_input_envelope_native_px'],
                       'max_adjacent_alpha': row['diagnostic_candidate']['max_adjacent_alpha_xor_px']}
                      for row in results]))


if __name__ == '__main__':
    main()
