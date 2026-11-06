"""Read-only diagnosis of the two 6–8px PixelLab controls against fixed field loops."""
from __future__ import annotations

import hashlib
import importlib.util
import json
import heapq
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[4]
PACKAGE = ROOT / 'docs/art/fire-readable-sway-20261106'
OLD = ROOT / 'docs/art/fire-single-tongue-20261106'
REPORT = ROOT / 'test_reports/fire-readable-sway-20261106/controls-analysis.json'
SELECTION_PATH = OLD / 'field-selection/selection.json'
PREVIEW_PATH = OLD / 'field-preview/manifest.json'
KEYS = {'fire24-strong01': ('fire24-short01', [8, 7, 1, 2]),
        'fire29-strong01': ('fire29-field02r1', [1, 3, 4, 5, 6])}
BOUNDED_PILOTS = {'fire24-strong01': [8, 1, 2], 'fire29-strong01': [1, 3, 4, 5]}

spec = importlib.util.spec_from_file_location('old_selection_readonly', OLD / 'field-selection/build.py')
assert spec and spec.loader
old = importlib.util.module_from_spec(spec)
spec.loader.exec_module(old)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def shape_sha(mask: np.ndarray) -> str:
    return hashlib.sha256(np.packbits(mask.ravel()).tobytes()).hexdigest()


def new_detached(mask: np.ndarray, original: np.ndarray) -> list[dict]:
    """8-connected raw alpha islands with no contact with any original alpha pixel."""
    h, w = mask.shape
    seen = np.zeros(mask.shape, dtype=bool)
    islands = []
    for y, x in zip(*np.nonzero(mask)):
        if seen[y, x]:
            continue
        queue = deque([(int(y), int(x))])
        seen[y, x] = True
        count = 0
        touches_original = False
        left = right = int(x)
        top = bottom = int(y)
        while queue:
            cy, cx = queue.popleft()
            count += 1
            touches_original |= bool(original[cy, cx])
            left, right = min(left, cx), max(right, cx)
            top, bottom = min(top, cy), max(bottom, cy)
            for ny in range(max(0, cy - 1), min(h, cy + 2)):
                for nx in range(max(0, cx - 1), min(w, cx + 2)):
                    if mask[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        queue.append((ny, nx))
        if not touches_original:
            islands.append({'pixels': count, 'bbox_xyxy': [left, top, right + 1, bottom + 1]})
    return islands


def envelope_radius(mask: np.ndarray, original: np.ndarray) -> int | str:
    source = Image.fromarray((original * 255).astype('uint8'))
    for radius in range(17):
        expanded = np.asarray(source.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
        if not np.any(mask & ~expanded):
            return radius
    return '>16'


def boundary_displacement(a: np.ndarray, b: np.ndarray) -> int | str:
    if np.array_equal(a, b):
        return 0
    aa = Image.fromarray((a * 255).astype('uint8'))
    bb = Image.fromarray((b * 255).astype('uint8'))
    for radius in range(1, 17):
        da = np.asarray(aa.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
        db = np.asarray(bb.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
        if not np.any(b & ~da) and not np.any(a & ~db):
            return radius
    return '>16'


def minimax_route(start: int, end: int, nodes: list[int], arrays: list[np.ndarray], plate: np.ndarray) -> dict | None:
    """Smallest unavoidable alpha jump from start to end; no art/gate waiver."""
    if start not in nodes or end not in nodes:
        return None
    queue = [(0, 0, start, [start])]
    best = {(start, 0): 0}
    while queue:
        worst_alpha, length, current, path = heapq.heappop(queue)
        if current == end:
            return {'forward_raw': path, 'minimum_possible_worst_adjacent_alpha_xor_px': worst_alpha,
                    'fits_old_max_forward_length': True}
        if length == 5:  # 8 passes in 96 slots permit at most 6 forward poses.
            continue
        for nxt in nodes:
            if nxt in path:
                continue
            step = old.pair(arrays[current], arrays[nxt], plate)['alpha_gt8_xor_pixels']
            if step == 0:
                continue
            candidate = max(worst_alpha, step)
            state = (nxt, length + 1)
            if candidate < best.get(state, 10**9):
                best[state] = candidate
                heapq.heappush(queue, (candidate, length + 1, nxt, path + [nxt]))
    return None


def find_path(eligible: list[int], masks: list[np.ndarray], arrays: list[np.ndarray], plate: np.ndarray,
              old_alpha_span: int, old_worst_visible_step: int, max_loop: int, max_alpha_step: int) -> dict | None:
    """Find monotone silhouette excursion and its exact PNG reverse, no invented pose."""
    pair_cache: dict[tuple[int, int], dict] = {}

    def pair(i: int, j: int) -> dict:
        a, b = sorted((i, j))
        if (a, b) not in pair_cache:
            pair_cache[a, b] = old.pair(arrays[a], arrays[b], plate)
        return pair_cache[a, b]

    best = None
    max_forward = min(8, (max_loop + 1) // 2)
    for start in eligible:
        distances = {i: pair(start, i)['alpha_gt8_xor_pixels'] for i in eligible}
        def visit(path: list[int], visible_worst: int) -> None:
            nonlocal best
            end = path[-1]
            if len(path) >= 3 and len({shape_sha(masks[i]) for i in path}) == len(path):
                alpha_span = distances[end]
                visible_span = pair(start, end)['visible_crop_rgb_gt8_pixels']
                candidate = (alpha_span, visible_span, -visible_worst, -len(path), path.copy())
                if best is None or candidate[:4] > best[:4]:
                    best = candidate
            if len(path) == max_forward:
                return
            for nxt in eligible:
                if nxt in path or distances[nxt] <= distances[end]:
                    continue
                step = pair(end, nxt)
                if not 1 <= step['alpha_gt8_xor_pixels'] <= max_alpha_step:
                    continue
                if step['visible_crop_rgb_gt8_pixels'] > max(int(old_worst_visible_step * 1.35), old_worst_visible_step + 60):
                    continue
                visit(path + [nxt], max(visible_worst, step['visible_crop_rgb_gt8_pixels']))
        visit([start], 0)
    if best is None:
        return None
    path = best[-1]
    order = path + path[-2::-1]
    steps = [pair(a, b) for a, b in zip(path, path[1:])]
    return {'forward_raw': path, 'order': order,
            'alpha_xor_span_px': best[0], 'alpha_span_vs_old_ratio': round(best[0] / max(old_alpha_span, 1), 3),
            'visible_source_over_rgb_gt8_span_px': best[1],
            'worst_adjacent_alpha_xor_px': max(x['alpha_gt8_xor_pixels'] for x in steps),
            'worst_adjacent_visible_rgb_gt8_px': max(x['visible_crop_rgb_gt8_pixels'] for x in steps),
            'exact_seam': bool(np.array_equal(arrays[order[0]], arrays[order[-1]])),
            'passes_existing_color_step_bound': True}


def main() -> None:
    selection = json.loads(SELECTION_PATH.read_text(encoding='utf-8'))
    preview = json.loads(PREVIEW_PATH.read_text(encoding='utf-8'))
    assert preview['selection_sha256'] == sha(SELECTION_PATH)
    preview_groups = {g['key']: g for style in preview['styles'] for g in style['groups']}
    selected = {c['key']: c for c in selection['clips']}
    results = []
    for key, (old_key, suggested) in KEYS.items():
        request_dir = PACKAGE / 'requests' / key
        result_dir = PACKAGE / 'results' / key
        meta = json.loads((request_dir / 'request-metadata.json').read_text(encoding='utf-8'))
        manifest = json.loads((result_dir / 'manifest.json').read_text(encoding='utf-8'))
        assert meta['key'] == manifest['key'] == key and manifest['returned_frames'] == 17
        assert sha(request_dir / 'request.json') == meta['request_sha256']
        group = meta['group']
        source_path = ROOT / f'docs/art/fire-low-styles-20261104/fire-low-{key[4:6]}.png'
        input_path = ROOT / group['input_path']
        core_path = ROOT / group['core_mask_path']
        assert sha(source_path) == meta['source_sha256'] and sha(input_path) == meta['input_sha256']
        assert sha(core_path) == group['core_mask_sha256']
        old_clip = selected[old_key]
        assert old_clip['input_sha256'] == meta['input_sha256']
        assert old_clip['native_crop_xyxy'] == group['crop_xyxy']
        playback = preview_groups[old_key]
        assert playback['order'] == old_clip['order']
        passes, phase = playback['passes_in_common_cycle'], playback['phase_offset_slots']
        maximum_loop = 96 // passes
        source = Image.open(source_path).convert('RGBA').crop(group['crop_xyxy'])
        plate = np.asarray(source, dtype=np.int16)
        input_arr = old.rgba(input_path)
        core = np.asarray(Image.open(core_path).convert('L')) > 0
        base = input_arr[:, :, 3] > 8
        permitted = {radius: np.asarray(Image.fromarray((base * 255).astype('uint8')).filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0 for radius in (4, 6, 8)}
        base_luma = old.luma(input_arr)
        plate_luma = old.luma(plate)
        base_core_rgb = input_arr[core, :3].astype(float).mean(axis=0)
        base_core_ratios = base_core_rgb[1:] / max(base_core_rgb[0], 1)
        arrays, rows = [], []
        for index, entry in enumerate(manifest['frames']):
            path = result_dir / 'raw' / f'frame-{index:02}.png'
            assert entry['frame'] == index and sha(path) == entry['sha256']
            arr = old.rgba(path)
            assert arr.shape == input_arr.shape
            arrays.append(arr)
            mask = arr[:, :, 3] > 8
            border = int(np.count_nonzero(np.r_[arr[0, :, 3], arr[-1, :, 3], arr[:, 0, 3], arr[:, -1, 3]] > 0))
            visible = np.asarray(Image.alpha_composite(source, Image.fromarray(arr.astype('uint8'), 'RGBA')), dtype=np.int16)
            visible_rgb_delta = np.max(np.abs(visible[:, :, :3] - plate[:, :, :3]), axis=2)
            lit = old.luma(arr)
            visible_luma_delta = old.luma(visible) - plate_luma
            core_rgb = arr[core, :3].astype(float).mean(axis=0)
            core_ratios = core_rgb[1:] / max(core_rgb[0], 1)
            chroma = np.abs(core_ratios - base_core_ratios)
            outside = {str(radius): int(np.count_nonzero(mask & ~permitted[radius])) for radius in permitted}
            detached = new_detached(mask, base)
            row = {'index': index, 'raw_path': path.relative_to(ROOT).as_posix(), 'raw_sha256': entry['sha256'],
                   'alpha_gt8_xor_input_px': int(np.logical_xor(mask, base).sum()),
                   'alpha_gt8_shape_sha256': shape_sha(mask),
                   'uncovered_original_core_px': int(np.count_nonzero(core & ~mask)),
                   'original_core_px': int(core.sum()),
                   'outside_input_dilation_px': outside,
                   'maximum_input_envelope_chebyshev_native_px': envelope_radius(mask, base),
                   'nonzero_alpha_on_crop_border_px': border,
                   'detached_raw_alpha_components': detached,
                   'premultiplied_luma_vs_input_ratio': round(float(lit.sum() / base_luma.sum()), 5),
                   'input_core_premultiplied_luma_mean': round(float(base_luma[core].mean()), 3),
                   'raw_core_premultiplied_luma_vs_input_ratio': round(float(lit[core].mean() / base_luma[core].mean()), 5),
                   'source_over_core_luma_vs_original_plate_ratio': round(float(old.luma(visible)[core].mean() / plate_luma[core].mean()), 5),
                   'max_positive_premultiplied_luma_vs_input': round(float(np.max(lit - base_luma)), 2),
                   'max_positive_visible_luma_vs_source_plate': round(float(np.max(visible_luma_delta)), 2),
                   'source_core_gr_br': [round(float(v), 5) for v in base_core_ratios],
                   'raw_core_gr_br': [round(float(v), 5) for v in core_ratios],
                   'absolute_core_gr_br_delta': [round(float(v), 5) for v in chroma],
                   'source_over_rgb_gt8_changed_px': int(np.count_nonzero(visible_rgb_delta > 8)),
                   'source_over_rgb_abs_sum': int(visible_rgb_delta.sum()),
                   'source_over_rgb_max': int(visible_rgb_delta.max())}
            shared = (index != 0 and row['uncovered_original_core_px'] == 0 and border == 0 and
                      row['premultiplied_luma_vs_input_ratio'] >= .90 and row['premultiplied_luma_vs_input_ratio'] <= 1.08 and
                      row['max_positive_visible_luma_vs_source_plate'] <= 160 and chroma[0] <= .06 and chroma[1] <= .05 and not detached)
            row['old_4px_gate_pass'] = bool(shared and outside['4'] == 0)
            row['diagnostic_6px_gate_with_core0_pass'] = bool(shared and outside['6'] == 0)
            row['diagnostic_8px_gate_with_core0_pass'] = bool(shared and outside['8'] == 0)
            rows.append(row)
        assert len(rows) == 17
        old_frames = {r['index']: old.rgba(ROOT / r['path']) for r in old_clip['raw_frames']}
        old_forward = old_clip['order'][:(len(old_clip['order']) + 1) // 2]
        old_span = old.pair(old_frames[old_forward[0]], old_frames[old_forward[-1]], plate)
        old_steps = [old.pair(old_frames[a], old_frames[b], plate) for a, b in zip(old_forward, old_forward[1:])]
        old_worst_visible = max(p['visible_crop_rgb_gt8_pixels'] for p in old_steps)
        masks = [a[:, :, 3] > 8 for a in arrays]
        natural_steps = [{'from_raw': a, 'to_raw': a + 1, **old.pair(arrays[a], arrays[a + 1], plate)} for a in range(16)]
        pairwise = []
        for a in range(17):
            for b in range(a + 1, 17):
                metric = old.pair(arrays[a], arrays[b], plate)
                pairwise.append({'from_raw': a, 'to_raw': b,
                                 'alpha_gt8_xor_px': metric['alpha_gt8_xor_pixels'],
                                 'visible_source_over_rgb_gt8_px': metric['visible_crop_rgb_gt8_pixels']})
        eligible6 = [r['index'] for r in rows if r['diagnostic_6px_gate_with_core0_pass']]
        eligible8 = [r['index'] for r in rows if r['diagnostic_8px_gate_with_core0_pass']]
        # Search both old 180px and exploratory 220px adjacent contour limits.
        paths = {'strict_6px_alpha180': find_path(eligible6, masks, arrays, plate, old_span['alpha_gt8_xor_pixels'], old_worst_visible, maximum_loop, 180),
                 'strict_8px_alpha220': find_path(eligible8, masks, arrays, plate, old_span['alpha_gt8_xor_pixels'], old_worst_visible, maximum_loop, 220)}
        for candidate in paths.values():
            if candidate:
                candidate['visible_span_vs_old_ratio'] = round(candidate['visible_source_over_rgb_gt8_span_px'] / max(old_span['visible_crop_rgb_gt8_pixels'], 1), 3)
                candidate['raw_sha256'] = {str(i): rows[i]['raw_sha256'] for i in candidate['forward_raw']}
                candidate['fits_old_96slot_cadence'] = len(candidate['order']) <= maximum_loop
        suggested_steps = []
        for a, b in zip(suggested, suggested[1:]):
            suggested_steps.append({'from_raw': a, 'to_raw': b, **old.pair(arrays[a], arrays[b], plate)})
        suggested_order = suggested + suggested[-2::-1]
        suggested_display_positions = [(((slot + phase) % 96) * passes * len(suggested_order) // 96) % len(suggested_order) for slot in range(97)]
        pilot_forward = BOUNDED_PILOTS[key]
        pilot_order = pilot_forward + pilot_forward[-2::-1]
        pilot_steps = []
        for a, b in zip(pilot_forward, pilot_forward[1:]):
            pilot_steps.append({'from_raw': a, 'to_raw': b,
                                'boundary_chebyshev_displacement_native_px': boundary_displacement(masks[a], masks[b]),
                                **old.pair(arrays[a], arrays[b], plate)})
        pilot_span = old.pair(arrays[pilot_forward[0]], arrays[pilot_forward[-1]], plate)
        pilot_positions = [(((slot + phase) % 96) * passes * len(pilot_order) // 96) % len(pilot_order) for slot in range(97)]
        assert pilot_positions[96] == pilot_positions[0] and set(pilot_positions[:96]) == set(range(len(pilot_order)))
        pilot = {
            'status': 'bounded_visual_pilot_with_explicit_old_gate_failures',
            'forward_raw': pilot_forward, 'order': pilot_order,
            'raw_sha256': {str(i): rows[i]['raw_sha256'] for i in pilot_forward},
            'raw_paths': {str(i): rows[i]['raw_path'] for i in pilot_forward},
            'raw_alpha_xor_span_px': pilot_span['alpha_gt8_xor_pixels'],
            'alpha_span_vs_old_ratio': round(pilot_span['alpha_gt8_xor_pixels'] / old_span['alpha_gt8_xor_pixels'], 3),
            'visible_source_over_rgb_gt8_span_px': pilot_span['visible_crop_rgb_gt8_pixels'],
            'visible_span_vs_old_ratio': round(pilot_span['visible_crop_rgb_gt8_pixels'] / old_span['visible_crop_rgb_gt8_pixels'], 3),
            'steps': pilot_steps,
            'worst_adjacent_alpha_xor_px': max(step['alpha_gt8_xor_pixels'] for step in pilot_steps),
            'worst_adjacent_visible_rgb_gt8_px': max(step['visible_crop_rgb_gt8_pixels'] for step in pilot_steps),
            'worst_adjacent_boundary_chebyshev_native_px': max(step['boundary_chebyshev_displacement_native_px'] for step in pilot_steps),
            'max_uncovered_original_core_px': max(rows[i]['uncovered_original_core_px'] for i in pilot_forward),
            'original_core_px': int(core.sum()),
            'max_input_envelope_chebyshev_native_px': max(rows[i]['maximum_input_envelope_chebyshev_native_px'] for i in pilot_forward),
            'max_positive_visible_luma_vs_source_plate': max(rows[i]['max_positive_visible_luma_vs_source_plate'] for i in pilot_forward),
            'luma_ratio_range': [min(rows[i]['premultiplied_luma_vs_input_ratio'] for i in pilot_forward),
                                 max(rows[i]['premultiplied_luma_vs_input_ratio'] for i in pilot_forward)],
            'max_core_gr_br_delta': [max(rows[i]['absolute_core_gr_br_delta'][j] for i in pilot_forward) for j in (0, 1)],
            'detached_components': {str(i): rows[i]['detached_raw_alpha_components'] for i in pilot_forward if rows[i]['detached_raw_alpha_components']},
            'old_core0_gate_pass': all(rows[i]['uncovered_original_core_px'] == 0 for i in pilot_forward),
            'old_4px_envelope_gate_pass': all(rows[i]['outside_input_dilation_px']['4'] == 0 for i in pilot_forward),
            'diagnostic_8px_envelope_gate_pass': all(rows[i]['outside_input_dilation_px']['8'] == 0 for i in pilot_forward),
            'old_adjacent_alpha180_gate_pass': all(step['alpha_gt8_xor_pixels'] <= 180 for step in pilot_steps),
            'exploratory_adjacent_alpha220_gate_pass': all(step['alpha_gt8_xor_pixels'] <= 220 for step in pilot_steps),
            'loop_length': len(pilot_order), 'fits_old_96slot_cadence': len(pilot_order) <= maximum_loop,
            'all_order_positions_displayed_in_96slots': True, 'slot96_equals_slot0_pose': True,
            'exact_raw_first_last_seam': bool(np.array_equal(arrays[pilot_order[0]], arrays[pilot_order[-1]])),
            'art_accepted': False,
        }
        conditional_nodes = [r['index'] for r in rows if r['index'] != 0 and r['uncovered_original_core_px'] <= (13 if key.startswith('fire24') else 51)
                             and r['outside_input_dilation_px']['6'] == 0 and r['nonzero_alpha_on_crop_border_px'] == 0
                             and not r['detached_raw_alpha_components'] and .90 <= r['premultiplied_luma_vs_input_ratio'] <= 1.08
                             and r['max_positive_visible_luma_vs_source_plate'] <= 160
                             and r['absolute_core_gr_br_delta'][0] <= .06 and r['absolute_core_gr_br_delta'][1] <= .05]
        conditional_bridge = minimax_route(8, 2, conditional_nodes, arrays, plate) if key.startswith('fire24') else None
        result = {
            'key': key, 'controlled_comparison_to': old_key,
            'request_sha256': meta['request_sha256'], 'source_sha256': meta['source_sha256'],
            'input_sha256': meta['input_sha256'], 'core_mask_sha256': group['core_mask_sha256'],
            'crop_xyxy': group['crop_xyxy'], 'returned_raw_frames': len(rows),
            'old_loop': {'order': old_clip['order'], 'forward': old_forward, 'alpha_xor_span_px': old_span['alpha_gt8_xor_pixels'],
                         'visible_source_over_rgb_gt8_span_px': old_span['visible_crop_rgb_gt8_pixels'],
                         'worst_adjacent_alpha_xor_px': max(p['alpha_gt8_xor_pixels'] for p in old_steps),
                         'worst_adjacent_visible_rgb_gt8_px': old_worst_visible,
                         'passes_in_96_slots': passes, 'phase_offset_slots': phase, 'maximum_loop_frames_without_skips': maximum_loop},
            'frame_gates': {'old_core_uncovered_max_px': 0, 'old_input_envelope_native_px': 4,
                            'diagnostic_envelopes_native_px': [6, 8], 'old_crop_border_alpha_max_px': 0,
                            'old_luma_ratio_range': [.90, 1.08], 'old_max_visible_luma_flash': 160,
                            'old_core_chroma_delta_max': [.06, .05], 'raw00_excluded': True},
            'raw_frames': rows,
            'raw_natural_adjacent_steps': natural_steps,
            'all_raw_pairwise_extrema': {
                'max_alpha_xor': max(pairwise, key=lambda x: x['alpha_gt8_xor_px']),
                'max_visible_source_over_rgb_gt8': max(pairwise, key=lambda x: x['visible_source_over_rgb_gt8_px'])},
            'eligible_raw_4px_core0': [r['index'] for r in rows if r['old_4px_gate_pass']],
            'eligible_raw_6px_core0': eligible6,
            'eligible_raw_8px_core0': eligible8,
            'path_search': paths,
            'bounded_pilot': pilot,
            'conditional_bridge_exploration': {'purpose': 'Diagnostic only; does not change core0 or envelope gates.',
                                               'raw8_to_raw2_with_core_uncovered_at_most13_and_envelope6': conditional_bridge} if key.startswith('fire24') else None,
            'root_preliminary_order': {'forward_raw': suggested, 'order': suggested_order,
                                       'frame_gate_failures': [{'raw': i, 'core_uncovered_px': rows[i]['uncovered_original_core_px'],
                                                                'outside_input_6px': rows[i]['outside_input_dilation_px']['6'],
                                                                'outside_input_8px': rows[i]['outside_input_dilation_px']['8'],
                                                                'detached_components': rows[i]['detached_raw_alpha_components']}
                                                               for i in suggested if not rows[i]['diagnostic_6px_gate_with_core0_pass']],
                                       'adjacent_steps': suggested_steps,
                                       'max_adjacent_alpha_xor_px': max(p['alpha_gt8_xor_pixels'] for p in suggested_steps),
                                       'alpha_xor_span_first_to_last_px': old.pair(arrays[suggested[0]], arrays[suggested[-1]], plate)['alpha_gt8_xor_pixels'],
                                       'visible_source_over_rgb_gt8_span_first_to_last_px': old.pair(arrays[suggested[0]], arrays[suggested[-1]], plate)['visible_crop_rgb_gt8_pixels'],
                                       'fits_old_96slot_cadence': len(suggested_order) <= maximum_loop and set(suggested_display_positions[:96]) == set(range(len(suggested_order))) and suggested_display_positions[96] == suggested_display_positions[0]},
            'existing_composite_contact': (PACKAGE / 'controls-review' / f'fire{key[4:6]}-composite.png').relative_to(ROOT).as_posix(),
            'art_accepted': False,
        }
        results.append(result)
    output = {'scope': 'Read-only evaluation of all 34 existing PixelLab raw frames; no generated/retouched pixels or API calls.',
              'baseline_selection_sha256': sha(SELECTION_PATH), 'baseline_preview_manifest_sha256': sha(PREVIEW_PATH),
              'screen_separation': 'Old gate requires core0 and input envelope4; 6px/8px are diagnostics and never waive core0, border0, color or luma bounds.',
              'controls': results, 'art_acceptance': 'Not automatic; root/reviewer examine visible source-over playback separately.'}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(output, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps([{'key': r['key'], 'eligible6': r['eligible_raw_6px_core0'],
                       'strict_best6_alpha_vs_old': r['path_search']['strict_6px_alpha180']['alpha_span_vs_old_ratio'] if r['path_search']['strict_6px_alpha180'] else None,
                       'pilot_forward': r['bounded_pilot']['forward_raw'],
                       'pilot_core_uncovered': r['bounded_pilot']['max_uncovered_original_core_px'],
                       'pilot_envelope_radius': r['bounded_pilot']['max_input_envelope_chebyshev_native_px'],
                       'pilot_worst_alpha_step': r['bounded_pilot']['worst_adjacent_alpha_xor_px']} for r in results]))


if __name__ == '__main__':
    main()
