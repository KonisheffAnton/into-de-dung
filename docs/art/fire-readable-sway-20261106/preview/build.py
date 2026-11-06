"""Assemble a 96-slot diagnostic field preview from selected raw PixelLab poses.

The source tiles and raw PNGs are read-only. Native assembly places each raw
RGBA image at its recorded ROI without geometric or palette changes.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PACKAGE = HERE.parent
SELECTION = PACKAGE / 'selection.json'
OLD_MANIFEST = ROOT / 'docs/art/fire-single-tongue-20261106/field-preview/manifest.json'
OLD_GROUPS = {g['group_key']: g for s in json.loads(OLD_MANIFEST.read_text())['styles'] for g in s['groups']}
INPUT_REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/field-inputs.json'
REPORT = ROOT / 'test_reports/fire-readable-sway-20261106/field-preview.json'
SLOTS = 96
SLOT_MS = 80
TOTAL_MS = SLOTS * SLOT_MS
SNAPSHOTS = (0, 24, 48, 72, 96)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert('RGBA'), dtype=np.uint8)


def visible_metrics_arrays(x: np.ndarray, y: np.ndarray) -> dict:
    x, y = x.astype(np.int16), y.astype(np.int16)
    rgb = np.max(np.abs(x[:, :, :3] - y[:, :, :3]), axis=2)
    premul_x = x[:, :, :3].astype(np.float32) * (x[:, :, 3:4] / 255.0)
    premul_y = y[:, :, :3].astype(np.float32) * (y[:, :, 3:4] / 255.0)
    premul_diff = np.max(np.abs(premul_x - premul_y), axis=2)
    return {'different_rgba_pixels': int(np.any(x != y, axis=2).sum()),
            'alpha_gt8_xor_pixels': int(np.logical_xor(x[:, :, 3] > 8, y[:, :, 3] > 8).sum()),
            'max_rgb_diff_gt8_pixels': int((rgb > 8).sum()),
            'max_rgb_diff_sum': int(rgb.sum()),
            'premultiplied_max_rgb_diff_gt8_pixels': int((premul_diff > 8).sum()),
            'premultiplied_max_rgb_diff_sum': round(float(premul_diff.sum()), 2),
            'exact_rgba': bool(np.array_equal(x, y))}


def visible_metrics(a: Image.Image, b: Image.Image) -> dict:
    return visible_metrics_arrays(rgba(a), rgba(b))


def luminance_sum(arr: np.ndarray, mask: np.ndarray) -> float:
    selected = arr[mask].astype(np.float64)
    weighted = selected[:, :3] @ np.array([.2126, .7152, .0722])
    return round(float(np.sum(weighted * selected[:, 3] / 255.0)), 3)


def load_clip(row: dict, style: str) -> dict:
    assert row['selected'] is True and row['key'].startswith(f'fire{style}-')
    x0, y0, x1, y1 = row['native_crop_xyxy']
    size = row['native_crop_size']
    assert x1 - x0 == y1 - y0 == size and size in (128, 256)
    input_path = ROOT / row['input']
    core_path = ROOT / row['core_mask']
    assert sha(input_path) == row['input_sha256'] and sha(core_path) == row['core_mask_sha256']
    input_image = Image.open(input_path).convert('RGBA')
    assert input_image.size == (size, size)
    input_alpha = np.asarray(input_image)[:, :, 3] > 8
    dilation = row.get('dilation_native_px', 4)
    assert dilation in (4, 6, 12)
    permitted = np.asarray(Image.fromarray((input_alpha * 255).astype('uint8')).filter(ImageFilter.MaxFilter(2*dilation+1))) > 0
    core = np.asarray(Image.open(core_path).convert('L')) > 0
    assert core.shape == input_alpha.shape
    frames = {}
    raw_provenance = {}
    for item in row['raw_frames']:
        index = item['index']
        path = ROOT / item['path']
        assert path.is_file() and sha(path) == item['sha256']
        image = Image.open(path).convert('RGBA')
        assert image.size == (size, size)
        alpha = np.asarray(image)[:, :, 3]
        shape = alpha > 8
        assert not np.any(shape & ~permitted), f"{row['key']} raw{index}: contour beyond recorded bound"
        exposed = int(np.count_nonzero(core & ~shape))
        # Three reviewed pilots leave a small part of the original glow visible.
        # All inherited clips retain the stricter zero-exposure contract.
        exposure_bound = row.get('max_exposed_source_core_px', 0)
        assert exposure_bound in (0, 1, 13, 27)
        assert exposed <= exposure_bound, f"{row['key']} raw{index}: core exposure beyond reviewed bound"
        assert not (np.any(alpha[0, :]) or np.any(alpha[-1, :]) or np.any(alpha[:, 0]) or np.any(alpha[:, -1])), f"{row['key']} raw{index}: crop clipped"
        frames[index] = image
        raw_provenance[str(index)] = {'path': item['path'], 'sha256': item['sha256']}
    order = row['order']
    assert len(order) >= 5 and order[0] == order[-1] and set(order) == set(frames) and 0 not in order
    original_ms = len(order) * row['frame_ms']
    # Preserve the previous cadence; a wider excursion must not merely play faster.
    old = OLD_GROUPS[row['group_key']]
    passes = old['passes_in_common_cycle']
    phase_slots = old['phase_offset_slots']
    assert len(order) * passes <= SLOTS, 'No intermediate selected pose may be skipped'
    assert 2 <= passes <= 8
    return {**row, 'box': (x0, y0, x1, y1), 'frames': frames,
            'raw_provenance': raw_provenance, 'passes': passes,
            'phase_offset_slots': phase_slots, 'original_cycle_ms': original_ms,
            'effective_cycle_ms': TOTAL_MS / passes, 'permitted': permitted,
            'core': core}


def pose_at(clip: dict, slot: int) -> int:
    # Integer-only lookup; slot 96 is exactly slot 0, with no inferred pixels.
    phase = (slot + clip['phase_offset_slots']) % SLOTS
    pose_slot = (phase * clip['passes'] * len(clip['order'])) // SLOTS
    return clip['order'][pose_slot % len(clip['order'])]


def build_style(style: str, clips: list[dict], field_inputs: dict) -> dict:
    source_path = ROOT / f'docs/art/fire-low-styles-20261104/fire-low-{style}.png'
    expected = field_inputs['styles'][style]['source_sha256']
    assert sha(source_path) == expected
    source = Image.open(source_path).convert('RGBA')
    assert source.size == (1254, 1254)
    for clip in clips:
        assert clip['source'] == source_path.relative_to(ROOT).as_posix() and clip['source_sha256'] == expected
    union = np.zeros((1254, 1254), dtype=bool)
    core_union = np.zeros((1254, 1254), dtype=bool)
    for clip in clips:
        x0, y0, x1, y1 = clip['box']
        union[y0:y1, x0:x1] |= clip['permitted']
        core_union[y0:y1, x0:x1] |= clip['core']
    total_groups = field_inputs['styles'][style]['group_count']
    assert len(clips) <= total_groups
    source_core = field_inputs['styles'][style]['core_pixels_total']
    selected_core = int(core_union.sum())
    assert selected_core == sum(int(c['core'].sum()) for c in clips), f'fire{style}: selected core overlap'
    assert not np.any(core_union & ~union)
    style_dir = HERE / f'fire{style}'
    view_dir, native_dir = style_dir / 'view-256', style_dir / 'native'
    view_dir.mkdir(parents=True, exist_ok=True)
    native_dir.mkdir(parents=True, exist_ok=True)
    mapping = []
    views = []
    saved_native = []
    source_array = rgba(source)
    source_luminance = {'effect_union': luminance_sum(source_array, union),
                        'selected_core': luminance_sum(source_array, core_union)}
    outside_violation_max = 0
    crop_clipping_count = 0
    first_assembled = last_assembled = None
    first_view = last_view = None
    first_native_array = first_view_array = first_overlay = None
    previous_native_array = previous_view_array = previous_overlay = None
    transitions = []
    luminance_slots = []
    for slot in range(SLOTS + 1):
        chosen = {c['key']: pose_at(c, slot) for c in clips}
        mapping.append({'slot': slot, 'time_ms': slot * SLOT_MS, 'poses': chosen})
        if slot == SLOTS:
            # Verify an actual independent reconstruction at the endpoint.
            assert chosen == mapping[0]['poses']
        assembled = source.copy()
        overlay = np.zeros((1254, 1254), dtype=bool)
        for clip in clips:
            x0, y0, x1, y1 = clip['box']
            raw = clip['frames'][chosen[clip['key']]]
            old_crop = assembled.crop((x0, y0, x1, y1))
            assembled.paste(Image.alpha_composite(old_crop, raw), (x0, y0))
            arr = np.asarray(raw)[:, :, 3]
            overlay[y0:y1, x0:x1] |= arr > 8
            crop_clipping_count += int(bool(np.any(arr[0, :]) or np.any(arr[-1, :]) or np.any(arr[:, 0]) or np.any(arr[:, -1])))
        current = rgba(assembled)
        changed_outside = int((np.any(current != source_array, axis=2) & ~union).sum())
        outside_violation_max = max(outside_violation_max, changed_outside)
        assert changed_outside == 0, f'fire{style} slot{slot}: outside union changed'
        if slot in SNAPSHOTS:
            native_path = native_dir / f'slot-{slot:02}.png'
            assembled.save(native_path)
            saved_native.append({'slot': slot, 'path': native_path.relative_to(ROOT).as_posix(), 'sha256': sha(native_path)})
        if slot == 0: first_assembled = assembled.copy()
        if slot == 95: last_assembled = assembled.copy()
        if slot == SLOTS:
            assert np.array_equal(rgba(assembled), rgba(first_assembled))
            continue
        luminance_slots.append({'slot': slot,
                                'effect_union': luminance_sum(current, union),
                                'selected_core': luminance_sum(current, core_union)})
        view = assembled.resize((256, 256), Image.Resampling.LANCZOS)
        view_array = rgba(view)
        view_path = view_dir / f'slot-{slot:02}.png'
        view.save(view_path)
        views.append({'slot': slot, 'path': view_path.relative_to(ROOT).as_posix(), 'sha256': sha(view_path)})
        if slot == 0:
            first_view = view.copy()
            first_native_array, first_view_array, first_overlay = current.copy(), view_array.copy(), overlay.copy()
        if slot == 95: last_view = view.copy()
        if slot > 0:
            transitions.append({'from_slot': slot - 1, 'to_slot': slot,
                                'native': visible_metrics_arrays(previous_native_array, current),
                                'view_256': visible_metrics_arrays(previous_view_array, view_array),
                                'raw_overlay_alpha_gt8_xor_pixels': int(np.logical_xor(previous_overlay, overlay).sum())})
        previous_native_array, previous_view_array, previous_overlay = current, view_array, overlay
    assert outside_violation_max == 0 and crop_clipping_count == 0
    transitions.append({'from_slot': 95, 'to_slot': 0,
                        'native': visible_metrics_arrays(previous_native_array, first_native_array),
                        'view_256': visible_metrics_arrays(previous_view_array, first_view_array),
                        'raw_overlay_alpha_gt8_xor_pixels': int(np.logical_xor(previous_overlay, first_overlay).sum())})
    assert len(transitions) == SLOTS
    def temporal_summary(area: str) -> dict:
        values = [row[area] for row in luminance_slots]
        steps = []
        for index in range(SLOTS):
            before, after = values[index], values[(index + 1) % SLOTS]
            ratio = after / before if before else 1.0
            steps.append({'from_slot': index, 'to_slot': (index + 1) % SLOTS,
                          'to_over_from': round(ratio, 7),
                          'absolute_ratio': round(max(ratio, 1 / ratio), 7) if ratio else None})
        worst = max(steps, key=lambda row: row['absolute_ratio'])
        return {'source_luminance': source_luminance[area],
                'min_luminance': min(values), 'min_slot': values.index(min(values)),
                'max_luminance': max(values), 'max_slot': values.index(max(values)),
                'max_over_min_ratio': round(max(values) / min(values), 7),
                'biggest_adjacent_ratio': worst, 'adjacent_ratios': steps}
    luminance_summary = {area: temporal_summary(area) for area in ('effect_union', 'selected_core')}
    native_seam = visible_metrics(last_assembled, first_assembled)
    view_seam = visible_metrics(last_view, first_view)
    source_view = source.resize((256, 256), Image.Resampling.LANCZOS)
    source_view_path = style_dir / 'source-256.png'
    source_view.save(source_view_path)
    # Reference snapshots, including t=7680 which must be byte-identical to t=0.
    contact = Image.new('RGB', (256 * 6, 286), '#1b2230')
    draw = ImageDraw.Draw(contact)
    items = [('original', source_view)] + [(f'{slot:02}', Image.open(view_dir / f'slot-{slot:02}.png').convert('RGBA') if slot < 96 else first_view) for slot in SNAPSHOTS]
    for i, (label, image) in enumerate(items):
        contact.paste(Image.alpha_composite(Image.new('RGBA', (256, 256), '#1b2230'), image).convert('RGB'), (i * 256, 0))
        draw.text((i * 256 + 7, 262), label, fill='#f4f4f4')
    contact_path = style_dir / 'contact-256.png'
    contact.save(contact_path)
    for transition in transitions:
        left = mapping[transition['from_slot']]['poses']
        right = mapping[transition['to_slot']]['poses']
        per_group = {}
        for clip in clips:
            a = np.asarray(clip['frames'][left[clip['key']]])[:, :, 3] > 8
            b = np.asarray(clip['frames'][right[clip['key']]])[:, :, 3] > 8
            per_group[clip['key']] = int(np.logical_xor(a, b).sum())
        transition['group_alpha_xor'] = per_group
    worst_alpha = max(transitions, key=lambda t: t['raw_overlay_alpha_gt8_xor_pixels'])
    worst_visible = max(transitions, key=lambda t: t['native']['max_rgb_diff_gt8_pixels'])

    def assemble_at(slot: int) -> Image.Image:
        result = source.copy()
        chosen = mapping[slot]['poses']
        for clip in clips:
            box = clip['box']
            result.paste(Image.alpha_composite(result.crop(box), clip['frames'][chosen[clip['key']]]), box[:2])
        return result

    def transition_contact(transition: dict, name: str) -> dict:
        before_slot, after_slot = transition['from_slot'], transition['to_slot']
        dominant_key = max(transition['group_alpha_xor'], key=lambda key: transition['group_alpha_xor'][key])
        dominant = next(c for c in clips if c['key'] == dominant_key)
        before_crop = assemble_at(before_slot).crop(dominant['box'])
        after_crop = assemble_at(after_slot).crop(dominant['box'])
        before_view = Image.open(view_dir / f'slot-{before_slot:02}.png').convert('RGBA')
        after_view = Image.open(view_dir / f'slot-{after_slot:02}.png').convert('RGBA')
        panels = [('source', source_view), (f'slot {before_slot:02}', before_view),
                  (f'slot {after_slot:02}', after_view), (f'{dominant_key} before', before_crop),
                  (f'{dominant_key} after', after_crop)]
        sheet = Image.new('RGB', (256 * len(panels), 286), '#1b2230')
        drawer = ImageDraw.Draw(sheet)
        for index, (label, picture) in enumerate(panels):
            plate = Image.new('RGBA', (256, 256), '#1b2230')
            x = (256 - picture.width) // 2
            y = (256 - picture.height) // 2
            plate.alpha_composite(picture, (x, y))
            sheet.paste(plate.convert('RGB'), (index * 256, 0))
            drawer.text((index * 256 + 6, 264), label, fill='#f4f4f4')
        path = style_dir / f'{name}-contact.png'
        sheet.save(path)
        return {'from_slot': before_slot, 'to_slot': after_slot,
                'dominant_group': dominant_key,
                'path': path.relative_to(ROOT).as_posix(), 'sha256': sha(path),
                'transition': transition}

    worst_contacts = {
        'raw_overlay_alpha_xor': transition_contact(worst_alpha, 'worst-alpha'),
        'native_visible_rgb_gt8': transition_contact(worst_visible, 'worst-visible'),
    }
    return {
        'style': style, 'source': source_path.relative_to(ROOT).as_posix(), 'source_sha256': expected,
        'source_view_256': source_view_path.relative_to(ROOT).as_posix(), 'source_view_256_sha256': sha(source_view_path),
        'selected_group_count': len(clips), 'total_group_count': total_groups,
        'selected_core_pixels': selected_core, 'total_core_pixels': source_core,
        'selected_core_percent': round(selected_core / source_core * 100, 3),
        'allowed_union_pixels': int(union.sum()),
        'groups': [{'key': c['key'], 'group_key': c['group_key'], 'crop_xyxy': list(c['box']),
                    'input': c['input'], 'input_sha256': c['input_sha256'],
                    'core_mask': c['core_mask'], 'core_mask_sha256': c['core_mask_sha256'],
                    'dilation_native_px': c.get('dilation_native_px', 4),
                    'max_exposed_source_core_px': c.get('max_exposed_source_core_px', 0),
                    'raw_frames': c['raw_provenance'], 'order': c['order'], 'frame_ms': c['frame_ms'],
                    'passes_in_common_cycle': c['passes'], 'phase_offset_slots': c['phase_offset_slots'],
                    'original_cycle_ms': c['original_cycle_ms'], 'effective_cycle_ms': round(c['effective_cycle_ms'], 3)}
                   for c in clips],
        'mapping': mapping, 'views_256': views, 'native_snapshots': saved_native,
        'contact_256': contact_path.relative_to(ROOT).as_posix(), 'contact_256_sha256': sha(contact_path),
        'all_97_native_assemblies_unchanged_outside_allowed_union': True,
        'max_outside_union_changed_pixels': outside_violation_max,
        'crop_clip_events': crop_clipping_count,
        'slot96_equals_slot0_exact_rgba': True,
        'display_seam_slot95_to0_native': native_seam,
        'display_seam_slot95_to0_view256': view_seam,
        'temporal_transitions': transitions,
        'temporal_luminance_slots': luminance_slots,
        'temporal_luminance_summary': luminance_summary,
        'worst_transitions': worst_contacts,
    }


def main() -> None:
    selection_sha = sha(SELECTION)
    selection = json.loads(SELECTION.read_text(encoding='utf-8'))
    assert selection['schema'] == 'fire-field-selection-v1' and selection['path_base'] == 'repository_root'
    field_inputs = json.loads(INPUT_REPORT.read_text(encoding='utf-8'))
    clips_by_style = {'24': [], '29': []}
    for row in selection['clips']:
        if not row.get('selected'):
            continue
        style = row['group_key'][4:6]
        if style not in clips_by_style:
            continue
        clips_by_style[style].append(load_clip(row, style))
    assert all(clips_by_style.values())
    styles = [build_style(style, clips_by_style[style], field_inputs) for style in ('24', '29')]
    assert sha(SELECTION) == selection_sha, 'selection.json changed during preview build; rerun required'
    combined = Image.new('RGB', (1536, 572), '#151a24')
    for i, style in enumerate(styles):
        combined.paste(Image.open(ROOT / style['contact_256']).convert('RGB'), (0, i * 286))
    combined_path = HERE / 'contact-both-256.png'
    combined.save(combined_path)
    manifest = {'schema': 'fire-field-preview-v1', 'selection': SELECTION.relative_to(ROOT).as_posix(),
                'selection_sha256': selection_sha, 'old_manifest_sha256': sha(OLD_MANIFEST), 'slots': SLOTS, 'slot_ms': SLOT_MS,
                'period_ms': TOTAL_MS, 'slot96_is_endpoint_check_only': True,
                'mapping_rule': 'pose = order[((slot+phase_offset_slots)%96 * passes_in_common_cycle * len(order) // 96) % len(order)]',
                'native_compositing': 'PIL RGBA alpha-over raw PNG on original source crop at exact recorded XY; no warp/repaint/tween.',
                'view_256': 'LANCZOS display-only downscale of assembled native1254 tile.',
                'styles': styles,
                'combined_contact_256': combined_path.relative_to(ROOT).as_posix(),
                'combined_contact_256_sha256': sha(combined_path),
                'art_accepted': False}
    manifest_path = HERE / 'manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    web_styles = []
    for style in styles:
        web_styles.append({'style': style['style'], 'source': style['source'],
                           'selected_group_count': style['selected_group_count'], 'total_group_count': style['total_group_count'],
                           'selected_core_percent': style['selected_core_percent'],
                           'groups': style['groups'], 'mapping': style['mapping'],
                           'display_seam_slot95_to0_native': style['display_seam_slot95_to0_native']})
    (HERE / 'gallery-data.js').write_text('window.FIELD_PREVIEW=' + json.dumps({'slots': SLOTS, 'slot_ms': SLOT_MS, 'styles': web_styles}, ensure_ascii=False, separators=(',', ':')) + ';\n', encoding='utf-8')
    report_keys = ('style','selected_group_count','total_group_count','selected_core_pixels','total_core_pixels','selected_core_percent','max_outside_union_changed_pixels','crop_clip_events','slot96_equals_slot0_exact_rgba','display_seam_slot95_to0_native','display_seam_slot95_to0_view256','temporal_transitions','temporal_luminance_slots','temporal_luminance_summary','worst_transitions')
    report = {'manifest': manifest_path.relative_to(ROOT).as_posix(), 'manifest_sha256': sha(manifest_path),
              'selection_sha256': selection_sha, 'styles': [{k: s[k] for k in report_keys} for s in styles],
              'all_96_playback_slots_verified': True, 'art_accepted': False}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps([{'style': s['style'], 'selected_groups': s['selected_group_count'], 'total_groups': s['total_group_count'], 'native_seam': s['display_seam_slot95_to0_native'], 'view256_seam': s['display_seam_slot95_to0_view256']} for s in styles]))


if __name__ == '__main__':
    main()
