"""Compare existing PixelLab silhouettes with the fixed 2026-11-06 field selection.

Read-only inputs; output is diagnostic proposals, never provider or runtime art.
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[4]
OLD = ROOT / 'docs/art/fire-single-tongue-20261106'
SELECTION = OLD / 'field-selection/selection.json'
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/field-selection.json'
PREVIEW = OLD / 'field-preview/manifest.json'
FIELD_INPUTS = ROOT / 'test_reports/fire-single-tongue-20261106/field-inputs.json'
OUT = ROOT / 'test_reports/fire-readable-sway-20261106/selection-analysis.json'
CONTACTS = Path(__file__).resolve().parent / 'contacts'
SPEC = importlib.util.spec_from_file_location('old_field_selection_readonly', OLD / 'field-selection/build.py')
assert SPEC and SPEC.loader
old_build = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(old_build)
CONTACT_OBSERVATIONS = {
    'fire24-field04r1': 'Flat painted flame remains attached in the contact; the wider bend is still subtle at tile scale.',
    'fire29-field06': 'The warm edge changes shape without a detached tongue in the contact; ordered raw indices are nonchronological.',
    'fire29-field21': 'Broader soft heat strokes stay on the original top plane in the contact; the longer sequence needs playback review.',
    'fire29-field25': 'The front-corner glow has the largest visible adjacent step of these proposals; inspect playback for a flash before adoption.',
    'fire29-short01': 'The rim heat stroke changes modestly; this is the sole proposal using a frame admitted only by the 6px diagnostic limit.',
}


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def alpha_xor(a: np.ndarray, b: np.ndarray) -> int:
    return int(np.count_nonzero(np.logical_xor(a, b)))


def cheb_displacement(a: np.ndarray, b: np.ndarray) -> int:
    """Smallest Chebyshev dilation radius that mutually covers both silhouettes."""
    if np.array_equal(a, b):
        return 0
    aa = Image.fromarray((a * 255).astype('uint8'))
    bb = Image.fromarray((b * 255).astype('uint8'))
    for radius in range(1, 13):
        da = np.asarray(aa.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
        db = np.asarray(bb.filter(ImageFilter.MaxFilter(2 * radius + 1))) > 0
        if not np.any(b & ~da) and not np.any(a & ~db):
            return radius
    return 13


def contact(key: str, source: Image.Image, arrays: list[np.ndarray], old_peak: int, new: list[int]) -> tuple[str, str]:
    size = source.width
    indexes = [None, old_peak] + new
    columns = 4
    image = Image.new('RGB', (size * columns, math.ceil(len(indexes) / columns) * (size + 25)), '#202838')
    draw = ImageDraw.Draw(image)
    for n, index in enumerate(indexes):
        frame = source if index is None else Image.alpha_composite(source, Image.fromarray(arrays[index].astype('uint8'), 'RGBA'))
        x, y = (n % columns) * size, (n // columns) * (size + 25)
        image.paste(frame.convert('RGB'), (x, y))
        label = 'source' if index is None else ('old peak ' if n == 1 else f'new {n-2}: ') + f'raw{index:02}'
        draw.text((x + 5, y + size + 5), label, fill='#f4f6fa')
    CONTACTS.mkdir(parents=True, exist_ok=True)
    path = CONTACTS / f'{key}.png'
    image.save(path)
    return path.relative_to(ROOT).as_posix(), sha(path)


def main() -> None:
    old_selection = json.loads(SELECTION.read_text(encoding='utf-8'))
    old_report = json.loads(REPORT.read_text(encoding='utf-8'))
    preview = json.loads(PREVIEW.read_text(encoding='utf-8'))
    field_inputs = json.loads(FIELD_INPUTS.read_text(encoding='utf-8'))
    core_weight = {group['key']: group['core_pixels'] for style in field_inputs['styles'].values() for group in style['groups']}
    playback_by_key = {group['key']: group for style in preview['styles'] for group in style['groups']}
    report_by_key = {row['key']: row for row in old_report['clips']}
    assert len(old_selection['clips']) == 56
    assert preview['selection_sha256'] == sha(SELECTION)
    assert set(playback_by_key) == {row['key'] for row in old_selection['clips']}
    results = []
    for selected in old_selection['clips']:
        key = selected['key']
        row = report_by_key[key]
        assert row['status'] == 'selected'
        frames = row['frames']
        arrays = []
        for frame in frames:
            raw = ROOT / frame['raw_path']
            assert sha(raw) == frame['raw_sha256'], f'{key} raw{frame["index"]} SHA mismatch'
            arrays.append(old_build.rgba(raw))
        source = Image.open(ROOT / row['source']).convert('RGBA').crop(row['crop_xyxy'])
        plate = np.asarray(source, dtype=np.int16)
        input_arr = old_build.rgba(ROOT / row['input'])
        base_mask = input_arr[:, :, 3] > 8
        allowed6 = np.asarray(Image.fromarray((base_mask * 255).astype('uint8')).filter(ImageFilter.MaxFilter(13))) > 0
        excluded = set(old_build.REVIEW_EXCLUDED_RAW.get(key, [])) | {0}
        masks = [a[:, :, 3] > 8 for a in arrays]
        eligible = []
        newly_eligible = []
        for frame, mask in zip(frames, masks):
            i = frame['index']
            reasons = [reason for reason in frame['reasons'] if reason != 'new contour exceeds native 4px dilation']
            outside6 = int(np.count_nonzero(mask & ~allowed6))
            if outside6:
                reasons.append('new contour exceeds native 6px dilation')
            if i in excluded and not reasons:
                reasons.append('raw00 or independent review excluded')
            if not reasons:
                eligible.append(i)
                if not frame['eligible']:
                    newly_eligible.append(i)
        old_order = selected['order']
        playback = playback_by_key[key]
        assert playback['order'] == old_order
        passes = playback['passes_in_common_cycle']
        phase = playback['phase_offset_slots']
        maximum_loop_slots = 96 // passes
        assert old_order[-1] == old_order[0]
        forward_old = old_order[:(len(old_order) + 1) // 2]
        start = forward_old[0]
        assert start in eligible
        shape_by_sha = {frames[i]['alpha_gt8_shape_sha256']: masks[i] for i in eligible}
        shape_of = {i: frames[i]['alpha_gt8_shape_sha256'] for i in eligible}
        alpha_cache: dict[tuple[str, str], int] = {}

        def ax(i: int, j: int) -> int:
            a, b = sorted((shape_of[i], shape_of[j]))
            if (a, b) not in alpha_cache:
                alpha_cache[a, b] = alpha_xor(shape_by_sha[a], shape_by_sha[b])
            return alpha_cache[a, b]

        color_cache: dict[tuple[int, int], dict] = {}

        def pair(i: int, j: int) -> dict:
            a, b = sorted((i, j))
            if (a, b) not in color_cache:
                color_cache[a, b] = old_build.pair(arrays[a], arrays[b], plate)
            return color_cache[a, b]

        old_peak = max(forward_old, key=lambda i: ax(start, i))
        old_alpha_span = ax(start, old_peak)
        old_visible_span = pair(start, old_peak)['visible_crop_rgb_gt8_pixels']
        old_adjacent = [pair(a, b) for a, b in zip(forward_old, forward_old[1:])]
        old_worst_visible_step = max(x['visible_crop_rgb_gt8_pixels'] for x in old_adjacent)
        old_worst_alpha_step = max(x['alpha_gt8_xor_pixels'] for x in old_adjacent)
        old_boundary = cheb_displacement(masks[start], masks[old_peak])

        # Strictly increasing alpha distance from the existing start creates a
        # small directed acyclic graph. Retaining this start preserves the seam.
        distance = {i: ax(start, i) for i in eligible}
        nodes = sorted((i for i in eligible if distance[i] > 0), key=lambda i: (distance[i], i))
        # State is (end, length) -> (worst visible step, worst alpha step, total visible, path).
        paths: dict[tuple[int, int], tuple[int, int, int, list[int]]] = {(start, 1): (0, 0, 0, [start])}
        for end in nodes:
            for previous in [start] + [i for i in nodes if distance[i] < distance[end]]:
                step_alpha = ax(previous, end)
                if not 1 <= step_alpha <= 180:
                    continue
                step_visible = pair(previous, end)['visible_crop_rgb_gt8_pixels']
                # New passes may be larger, but not an abrupt visible color jump.
                if step_visible > max(int(old_worst_visible_step * 1.35), old_worst_visible_step + 60):
                    continue
                for length in range(1, 8):
                    if (previous, length) not in paths:
                        continue
                    worst_visible, worst_alpha, total_visible, path = paths[previous, length]
                    value = (max(worst_visible, step_visible), max(worst_alpha, step_alpha), total_visible + step_visible, path + [end])
                    state = (end, length + 1)
                    if state not in paths or value[:3] < paths[state][:3]:
                        paths[state] = value
        options = []
        for (end, length), value in paths.items():
            if length < 3 or end == start:
                continue
            if 2 * length - 1 > maximum_loop_slots:
                continue
            alpha_span = distance[end]
            visible_span = pair(start, end)['visible_crop_rgb_gt8_pixels']
            alpha_ratio = alpha_span / max(old_alpha_span, 1)
            visible_ratio = visible_span / max(old_visible_span, 1)
            if alpha_ratio < 1.45 or visible_ratio < 1.15 or alpha_ratio > 2.4:
                continue
            worst_visible, worst_alpha, _, path = value
            options.append((min(alpha_ratio, visible_ratio), alpha_ratio, visible_ratio, -worst_visible, -len(path), path))
        best = max(options, default=None)
        summary = {
            'key': key, 'group_key': selected['group_key'],
            'old_order': old_order, 'old_raw_sha256': {str(i): frames[i]['raw_sha256'] for i in set(old_order)},
            'old_alpha_xor_span_px': old_alpha_span, 'old_visible_crop_rgb_gt8_span_px': old_visible_span,
            'old_boundary_chebyshev_px': old_boundary,
            'old_worst_adjacent_alpha_xor_px': old_worst_alpha_step,
            'old_worst_adjacent_visible_rgb_gt8_px': old_worst_visible_step,
            'eligible6_count': len(eligible), 'newly_eligible_6px': newly_eligible,
            'raw00_excluded': True,
            'independent_review_excluded_raw': sorted(old_build.REVIEW_EXCLUDED_RAW.get(key, [])),
            'baseline_passes_in_96_slots': passes,
            'baseline_phase_offset_slots': phase,
            'maximum_loop_frames_without_skipping': maximum_loop_slots,
        }
        if best:
            path = best[-1]
            peak = path[-1]
            order = path + path[-2::-1]
            displayed_positions = [(((slot + phase) % 96) * passes * len(order) // 96) % len(order) for slot in range(97)]
            assert set(displayed_positions[:96]) == set(range(len(order)))
            assert displayed_positions[96] == displayed_positions[0]
            transitions = [pair(a, b) for a, b in zip(path, path[1:])]
            new_boundary = cheb_displacement(masks[start], masks[peak])
            contact_path, contact_sha = contact(key, source, arrays, old_peak, path)
            summary['proposal'] = {
                'forward_raw': path, 'order': order, 'frame_ms': selected['frame_ms'],
                'passes_in_96_slots': passes, 'phase_offset_slots': phase,
                'loop_frames': len(order), 'fits_96_slot_mapping_without_skips': len(order) <= maximum_loop_slots,
                'raw_sha256': {str(i): frames[i]['raw_sha256'] for i in path},
                'raw_paths_sha256': {str(i): {'path': frames[i]['raw_path'], 'sha256': frames[i]['raw_sha256']} for i in path},
                'alpha_xor_span_px': distance[peak],
                'visible_crop_rgb_gt8_span_px': pair(start, peak)['visible_crop_rgb_gt8_pixels'],
                'boundary_chebyshev_px': new_boundary,
                'alpha_span_ratio': round(best[1], 3), 'visible_span_ratio': round(best[2], 3),
                'worst_adjacent_alpha_xor_px': max(x['alpha_gt8_xor_pixels'] for x in transitions),
                'worst_adjacent_visible_rgb_gt8_px': max(x['visible_crop_rgb_gt8_pixels'] for x in transitions),
                'worst_visible_step_vs_old_ratio': round(max(x['visible_crop_rgb_gt8_pixels'] for x in transitions) / old_worst_visible_step, 3),
                'max_new_alpha_outside_input_dilation6_px': max(int(np.count_nonzero(masks[i] & ~allowed6)) for i in path),
                'core_uncovered_max_px': max(frames[i]['uncovered_original_core_pixels'] for i in path),
                'crop_border_alpha_max_px': max(frames[i]['nonzero_alpha_on_crop_border_pixels'] for i in path),
                'luma_ratio_range': [min(frames[i]['premultiplied_luma_vs_input_ratio'] for i in path), max(frames[i]['premultiplied_luma_vs_input_ratio'] for i in path)],
                'max_visible_luma_flash': max(frames[i]['max_positive_visible_luma_vs_original_plate'] for i in path),
                'max_core_chroma_delta': [max(frames[i]['absolute_core_gr_br_delta'][j] for i in path) for j in range(2)],
                'distinct_alpha_silhouettes': len({shape_of[i] for i in path}),
                'exact_seam': bool(np.array_equal(arrays[order[0]], arrays[order[-1]])),
                'all_order_positions_displayed_in_96_slots': True,
                'minimum_96_slot_samples_per_order_position': min(displayed_positions[:96].count(i) for i in range(len(order))),
                'slot96_equals_slot0_pose': True,
                'contact': contact_path, 'contact_sha256': contact_sha,
                'uses_6px_only_frame': bool(set(path) & set(newly_eligible)),
                'contact_observation': CONTACT_OBSERVATIONS.get(key, 'Static contact requires full-cycle playback review.'),
                'diagnostic_status': 'candidate_needs_full_cycle_visual_review',
            }
        results.append(summary)
    proposals = [r for r in results if 'proposal' in r]
    aggregate = {}
    for style in ('24', '29'):
        rows = [row for row in results if row['key'].startswith('fire' + style)]
        old_alpha = sum(row['old_alpha_xor_span_px'] for row in rows)
        new_alpha = sum(row.get('proposal', {}).get('alpha_xor_span_px', row['old_alpha_xor_span_px']) for row in rows)
        old_visible = sum(row['old_visible_crop_rgb_gt8_span_px'] for row in rows)
        new_visible = sum(row.get('proposal', {}).get('visible_crop_rgb_gt8_span_px', row['old_visible_crop_rgb_gt8_span_px']) for row in rows)
        old_weighted = sum(core_weight[row['group_key']] * row['old_alpha_xor_span_px'] for row in rows)
        new_weighted = sum(core_weight[row['group_key']] * row.get('proposal', {}).get('alpha_xor_span_px', row['old_alpha_xor_span_px']) for row in rows)
        aggregate[style] = {
            'groups': len(rows), 'proposed_groups': sum('proposal' in row for row in rows),
            'sum_alpha_xor_span_old_px': old_alpha, 'sum_alpha_xor_span_proposed_px': new_alpha,
            'sum_alpha_xor_span_ratio': round(new_alpha / old_alpha, 4),
            'sum_visible_source_over_rgb_gt8_span_old_px': old_visible,
            'sum_visible_source_over_rgb_gt8_span_proposed_px': new_visible,
            'sum_visible_source_over_rgb_gt8_span_ratio': round(new_visible / old_visible, 4),
            'core_pixel_weighted_alpha_span_ratio': round(new_weighted / old_weighted, 4),
        }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    data = {
        'scope': 'Existing raw PixelLab poses for the same 56 source groups; no API requests or new motion pixels.',
        'baseline_head': 'ecb49cd37da381ed7d9e8ca006861a771b0bfc56',
        'baseline_selection_sha256': sha(SELECTION), 'baseline_report_sha256': sha(REPORT),
        'baseline_preview_manifest_sha256': sha(PREVIEW),
        'baseline_field_inputs_report_sha256': sha(FIELD_INPUTS),
        'independent_review_excluded_raw_count': sum(len(indices) for indices in old_build.REVIEW_EXCLUDED_RAW.values()),
        'screen': 'Original core fully covered, alpha crop border zero, input contour dilation 6 native px, source color/luma gates unchanged, raw00 and all independent-review exclusions removed; adjacent alpha XOR 1..180. Candidate retains old first pose, uses increasing silhouette distance and reverse raw poses.',
        'proposal_count': len(proposals), 'unchanged_count': len(results) - len(proposals),
        'style_aggregate_proxy': aggregate,
        'aggregate_caveat': 'Sums and core-pixel-weighted ratios compare each group at its own extreme, not simultaneous 96-slot full-field animation. They do not establish 1.5–2x whole-tile visibility or art acceptance.',
        'selection_policy': 'Propose only when alpha span >=1.45x and visible source-over RGB>8 span >=1.15x, alpha ratio <=2.4x, each visible step <=max(1.35x prior worst, prior worst+60), and reverse-loop length <=floor(96/old passes). Preserve old phase and passes, so every selected pose is displayed in the 7.68s common cycle. These diagnostic thresholds are stricter than the old gates; art review still required.',
        'clips': results,
        'art_accepted': False,
    }
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'proposals': len(proposals), 'unchanged': len(results) - len(proposals),
                      'keys': [(r['key'], r['proposal']['alpha_span_ratio'], r['proposal']['visible_span_ratio']) for r in proposals]}))


if __name__ == '__main__':
    main()
