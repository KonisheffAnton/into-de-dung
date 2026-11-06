"""Select bounded existing PixelLab pose runs without creating motion pixels.

Only fully extracted field jobs enter the selection. Missing or incomplete jobs
are recorded as pending. The script never edits source, input or raw images.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parent
ROOT = HERE.parents[3]
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/field-selection.json'
MAX_RUN = 8
POSE_MS = 160
INCLUDED_SHORT_CONTROLS = {'fire24-short01','fire24-short02','fire29-short01'}
EXPLICIT_POSE_RUNS = {'fire29-short01': [1,12,16,11], 'fire24-field04r1': [1,13,4],
                      'fire29-field13': [1,15,14], 'fire24-field24': [4,5,7]}
# Независимый просмотр нашёл отдельные точки/полосы: исключаем весь raw кадр,
# а не ретушируем движение или надеемся на выбор другого диапазона.
REVIEW_EXCLUDED_RAW = {'fire24-field18': [2,7,9,11], 'fire29-field06': [1,5,11],
                       'fire24-field14': [1,5,11], 'fire24-field16': [4,14,16],
                       'fire24-field24': [9], 'fire24-field08': [5,6,7]}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert('RGBA'), dtype=np.int16)


def mask_hash(mask: np.ndarray) -> str:
    return hashlib.sha256(np.packbits(mask.ravel()).tobytes()).hexdigest()


def premul(rgb: np.ndarray) -> np.ndarray:
    return rgb[:, :, :3].astype(np.float32) * (rgb[:, :, 3:4].astype(np.float32) / 255.0)


def luma(arr: np.ndarray) -> np.ndarray:
    p = premul(arr)
    return p[:, :, 0] * .2126 + p[:, :, 1] * .7152 + p[:, :, 2] * .0722


def pair(a: np.ndarray, b: np.ndarray, plate: np.ndarray) -> dict:
    alpha_a, alpha_b = a[:, :, 3], b[:, :, 3]
    da = np.max(np.abs(premul(a) - premul(b)), axis=2)
    # A crop-sized original plate is used only for visible-color diagnostics.
    pa = np.asarray(Image.alpha_composite(Image.fromarray(plate.astype('uint8'), 'RGBA'), Image.fromarray(a.astype('uint8'), 'RGBA')), dtype=np.int16)
    pb = np.asarray(Image.alpha_composite(Image.fromarray(plate.astype('uint8'), 'RGBA'), Image.fromarray(b.astype('uint8'), 'RGBA')), dtype=np.int16)
    dv = np.max(np.abs(pa[:, :, :3] - pb[:, :, :3]), axis=2)
    return {
        'alpha_gt8_xor_pixels': int(np.logical_xor(alpha_a > 8, alpha_b > 8).sum()),
        'alpha_abs_sum': int(np.abs(alpha_a - alpha_b).sum()),
        'premul_max_rgb_gt8_pixels': int((da > 8).sum()),
        'premul_max_rgb_sum': round(float(da.sum()), 2),
        'visible_crop_rgb_gt8_pixels': int((dv > 8).sum()),
        'visible_crop_rgb_sum': int(dv.sum()),
        'exact_rgba': bool(np.array_equal(a, b)),
    }


def inspect_job(request: Path) -> dict:
    meta = json.loads(request.read_text(encoding='utf-8'))
    key = meta['key']
    result = PACKAGE / 'results' / key
    manifest_path = result / 'manifest.json'
    if not manifest_path.is_file():
        return {'key': key, 'status': 'pending', 'reason': 'No completed result manifest; no raw poses used.'}
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    count = manifest['returned_frames']
    assert manifest['key'] == key and count >= 4 and len(manifest['frames']) == count
    assert [row['frame'] for row in manifest['frames']] == list(range(count))
    group = meta['group']
    x0, y0, x1, y1 = group['crop_xyxy']
    assert x1 - x0 == y1 - y0 == group['crop_size']
    source_path = ROOT / f"docs/art/fire-low-styles-20261104/fire-low-{key[4:6]}.png"
    input_path = ROOT / group['input_path']
    core_path = ROOT / group['core_mask_path']
    context_path = ROOT / group['context_path']
    for path, expected in [(source_path, meta['source_sha256']), (input_path, group['input_sha256']),
                           (core_path, group['core_mask_sha256']), (context_path, group['context_sha256'])]:
        assert path.is_file() and digest(path) == expected, f'{key}: source/input provenance mismatch'
    source = Image.open(source_path).convert('RGBA')
    assert source.size == (1254, 1254)
    plate = np.asarray(source.crop((x0, y0, x1, y1)), dtype=np.int16)
    base = rgba(input_path)
    core = np.asarray(Image.open(core_path).convert('L')) > 0
    assert base.shape == plate.shape and core.shape == base.shape[:2]
    base_mask = base[:, :, 3] > 8
    # PIL MaxFilter(9) is an exact 4-pixel Chebyshev dilation of the binary mask.
    allowed = np.asarray(Image.fromarray((base_mask * 255).astype('uint8')).filter(ImageFilter.MaxFilter(9))) > 0
    base_luma = luma(base)
    plate_luma = luma(plate)
    base_total = float(base_luma.sum())
    assert base_total > 0
    base_core_rgb = base[core, :3].astype(float).mean(axis=0)
    base_core_ratios = base_core_rgb[1:] / max(base_core_rgb[0], 1)
    arrays = []
    rows = []
    for i, entry in enumerate(manifest['frames']):
        raw_path = result / 'raw' / f'frame-{i:02}.png'
        assert raw_path.is_file() and digest(raw_path) == entry['sha256']
        arr = rgba(raw_path)
        assert arr.shape == base.shape
        arrays.append(arr)
        alpha = arr[:, :, 3]
        shape = alpha > 8
        border = int(np.count_nonzero(np.r_[alpha[0, :], alpha[-1, :], alpha[:, 0], alpha[:, -1]] > 0))
        lit = luma(arr)
        ratio = float(lit.sum() / base_total)
        max_bright = float(np.max(lit - base_luma))
        composited = np.asarray(Image.alpha_composite(Image.fromarray(plate.astype('uint8'),'RGBA'),Image.fromarray(arr.astype('uint8'),'RGBA')),dtype=np.int16)
        max_visible_bright = float(np.max(luma(composited)-plate_luma))
        core_rgb = arr[core, :3].astype(float).mean(axis=0)
        core_ratios = core_rgb[1:] / max(core_rgb[0], 1)
        chroma_delta = np.abs(core_ratios - base_core_ratios)
        frame = {
            'index': i, 'raw_path': raw_path.relative_to(ROOT).as_posix(), 'raw_sha256': entry['sha256'],
            'uncovered_original_core_pixels': int((core & ~shape).sum()),
            'new_alpha_gt8_outside_input_dilation4_pixels': int((shape & ~allowed).sum()),
            'nonzero_alpha_on_crop_border_pixels': border,
            'alpha_gt8_xor_input_pixels': int(np.logical_xor(shape, base_mask).sum()),
            'alpha_gt8_shape_sha256': mask_hash(shape),
            'premultiplied_luma_vs_input_ratio': round(ratio, 5),
            'max_positive_premultiplied_luma_vs_input': round(max_bright, 2),
            'max_positive_visible_luma_vs_original_plate': round(max_visible_bright, 2),
            'source_core_gr_br': [round(float(v),5) for v in base_core_ratios],
            'raw_core_gr_br': [round(float(v),5) for v in core_ratios],
            'absolute_core_gr_br_delta': [round(float(v),5) for v in chroma_delta],
            'difference_from_input': pair(base, arr, plate),
        }
        reasons = []
        if i == 0: reasons.append('raw00 is excluded')
        if i in REVIEW_EXCLUDED_RAW.get(key, []): reasons.append('independent raw review: detached speck or gray bar')
        if frame['uncovered_original_core_pixels']: reasons.append('original core exposed')
        if frame['new_alpha_gt8_outside_input_dilation4_pixels']: reasons.append('new contour exceeds native 4px dilation')
        if border: reasons.append('alpha touches crop border')
        if not .90 <= ratio <= 1.08: reasons.append('global premultiplied brightness excursion')
        if max_visible_bright > 160: reasons.append('local visible brightness flash on original plate')
        if chroma_delta[0] > .06 or chroma_delta[1] > .05: reasons.append('core chromatic ratios depart from source palette')
        frame['eligible'] = not reasons
        frame['reasons'] = reasons
        rows.append(frame)
    # Choose a bounded monotonic excursion with >=3 distinct silhouettes.
    # The reverse uses the same PNGs, so no 16->1 jump can enter the loop.
    chosen = None
    best_score = None
    for start in range(1, count - 2):
        if not rows[start]['eligible'] or rows[start]['alpha_gt8_xor_input_pixels'] < 5:
            continue
        candidate = [start]
        previous_distance = 0
        for nxt in range(start + 1, min(count, start + MAX_RUN)):
            if not rows[nxt]['eligible']:
                break
            step = pair(arrays[nxt - 1], arrays[nxt], plate)
            distance = pair(arrays[start], arrays[nxt], plate)['alpha_gt8_xor_pixels']
            if not 1 <= step['alpha_gt8_xor_pixels'] <= 180 or distance <= previous_distance:
                break
            candidate.append(nxt)
            previous_distance = distance
        if len(candidate) >= 3 and len({rows[i]['alpha_gt8_shape_sha256'] for i in candidate}) >= 3:
            worst_step = max(pair(arrays[a], arrays[b], plate)['alpha_gt8_xor_pixels'] for a,b in zip(candidate,candidate[1:]))
            score = (len(candidate), -worst_step, -start)
            if best_score is None or score > best_score:
                chosen = candidate
                best_score = score
    explicit = key in EXPLICIT_POSE_RUNS
    if explicit:
        chosen = EXPLICIT_POSE_RUNS[key]
        assert len(chosen)>=3 and all(rows[i]['eligible'] for i in chosen)
        assert len({rows[i]['alpha_gt8_shape_sha256'] for i in chosen})==len(chosen)
        distances=[pair(arrays[chosen[0]],arrays[i],plate)['alpha_gt8_xor_pixels'] for i in chosen]
        assert all(a<b for a,b in zip(distances,distances[1:]))
        assert all(1<=pair(arrays[a],arrays[b],plate)['alpha_gt8_xor_pixels']<=180 for a,b in zip(chosen,chosen[1:]))
    output = {
        'key': key, 'group_key': group['key'], 'status': 'selected' if chosen else 'rejected_or_needs_review',
        'source': source_path.relative_to(ROOT).as_posix(), 'source_sha256': digest(source_path),
        'input': input_path.relative_to(ROOT).as_posix(), 'input_sha256': digest(input_path),
        'core_mask': core_path.relative_to(ROOT).as_posix(), 'core_mask_sha256': digest(core_path),
        'crop_xyxy': [x0, y0, x1, y1], 'crop_size': group['crop_size'],
        'returned_frames': count, 'frames': rows, 'raw00_excluded': True,
    }
    if not chosen:
        output['reason'] = 'No eligible contiguous generated run with at least three distinct changing silhouettes and bounded adjacent alpha.'
        return output
    order = chosen + chosen[-2::-1]
    timeline = [{'slot': slot, 'raw_frame': index, 'duration_ms': POSE_MS,
                 'raw_sha256': rows[index]['raw_sha256']} for slot, index in enumerate(order)]
    transitions = []
    for slot in range(len(order)):
        nxt = (slot + 1) % len(order)
        transitions.append({'from_slot': slot, 'to_slot': nxt,
                            'from_raw': order[slot], 'to_raw': order[nxt],
                            **pair(arrays[order[slot]], arrays[order[nxt]], plate)})
    assert transitions[-1]['exact_rgba'] and all(rows[i]['eligible'] for i in chosen)
    out_dir = HERE / key
    out_dir.mkdir(parents=True, exist_ok=True)
    # Contact is a derived visual proof, not raw provider output.
    source_crop = source.crop((x0, y0, x1, y1))
    first = Image.alpha_composite(source_crop, Image.fromarray(arrays[chosen[0]].astype('uint8'), 'RGBA'))
    last = Image.alpha_composite(source_crop, Image.fromarray(arrays[chosen[-1]].astype('uint8'), 'RGBA'))
    size = group['crop_size']
    contact = Image.new('RGB', (size * 3, size + 28), '#1e2430')
    drawer = ImageDraw.Draw(contact)
    for n, (image, title) in enumerate([(source_crop, 'original crop'), (first, f'raw {chosen[0]:02}'), (last, f'raw {chosen[-1]:02}')]):
        background = Image.new('RGBA', image.size, '#27313f')
        contact.paste(Image.alpha_composite(background, image).convert('RGB'), (n * size, 0))
        drawer.text((n * size + 5, size + 5), title, fill='#f5f5f5')
    contact_path = out_dir / 'contact-source-min-max.png'
    contact.save(contact_path)
    output.update({
        'selection_reason': (f'Explicit reordered existing provider poses {chosen}, selected by measured contour proximity; no locally generated intermediate pose.' if explicit else f'Longest bounded monotonic contour excursion (ties prefer smaller adjacent alpha change), native generated frames {chosen}.') + ' All selected poses cover core, stay inside4px dilation and crop, and satisfy brightness/chroma bounds.',
        'distinct_generated_poses': chosen, 'order': order, 'pose_duration_ms': POSE_MS,
        'cycle_duration_ms': len(order) * POSE_MS,
        'timeline': timeline, 'transitions': transitions,
        'exact_seam': transitions[-1]['exact_rgba'],
        'contact': contact_path.relative_to(ROOT).as_posix(), 'contact_sha256': digest(contact_path),
        'max_adjacent_alpha_xor': max(t['alpha_gt8_xor_pixels'] for t in transitions),
        'max_adjacent_premul_rgb_gt8': max(t['premul_max_rgb_gt8_pixels'] for t in transitions),
        'art_accepted': False,
    })
    (out_dir / 'timeline.json').write_text(json.dumps({k: v for k, v in output.items() if k != 'frames'}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    return output


def main() -> None:
    requests = sorted(p for p in (PACKAGE / 'requests').glob('*/request-metadata.json')
                      if '-field' in p.parent.name or p.parent.name in INCLUDED_SHORT_CONTROLS)
    completed_keys = {p.parent.name for p in requests if (PACKAGE/'results'/p.parent.name/'manifest.json').is_file()}
    clips = [inspect_job(p) for p in requests if p.parent.name in completed_keys]
    pending_out_of_scope = [{'key': p.parent.name, 'status': 'not_extracted'}
                            for p in requests if p.parent.name not in completed_keys]
    selected = [c for c in clips if c['status'] == 'selected']
    assert len({c['group_key'] for c in selected}) == len(selected), 'More than one selected clip for a source group'
    thumbs = []
    for c in selected:
        im = Image.open(ROOT / c['contact']).convert('RGB')
        thumb = im.resize((384, 142), Image.Resampling.LANCZOS)
        thumbs.append((c['key'], thumb))
    if thumbs:
        sheet = Image.new('RGB', (400, len(thumbs) * 166), '#161c26')
        d = ImageDraw.Draw(sheet)
        for index, (key, thumb) in enumerate(thumbs):
            y = index * 166
            d.text((8, y + 4), key, fill='#f5f5f5')
            sheet.paste(thumb, (8, y + 22))
        sheet_path = HERE / 'selected-contact.png'
        sheet.save(sheet_path)
        sheet_rel = sheet_path.relative_to(ROOT).as_posix()
        sheet_sha = digest(sheet_path)
    else:
        sheet_rel = sheet_sha = None
    report = {
        'scope': 'Existing completed PixelLab field results only; no API calls or new motion pixels.',
        'screen': {'alpha_threshold': 8, 'input_dilation_chebyshev_native_px': 4,
                   'core_uncovered_max_px': 0, 'alpha_on_crop_border_max_px': 0,
                   'premultiplied_luma_total_ratio_range': [0.90, 1.08],
                   'max_positive_visible_luma_vs_original_plate_per_pixel': 160,
                   'max_absolute_core_mean_gr_br_delta': [.06,.05],
                   'adjacent_alpha_xor_range_for_forward_run': [1, 180],
                   'min_distinct_generated_silhouettes': 3, 'max_forward_run_frames': MAX_RUN,
                   'raw00_excluded': True},
        'selection_algorithm': 'Scan eligible generated starts with at least 5 alpha XOR pixels from input; extend consecutive poses while alpha XOR per step stays 1..180 and distance from the starting silhouette increases; require >=3 distinct silhouettes. Prefer the longest run, then smaller worst adjacent alpha change, then earlier start. Reverse the same pose list, including the original first pose as the last slot.',
        'selected_contact': sheet_rel, 'selected_contact_sha256': sheet_sha,
        'completed_keys': sorted(completed_keys),
        'explicit_existing_pose_runs': EXPLICIT_POSE_RUNS,
        'independent_review_excluded_raw': REVIEW_EXCLUDED_RAW,
        'other_requests_not_used': pending_out_of_scope,
        'clips': clips,
        'art_acceptance': 'Not automatic. Full tile assembly and visual review remain separate.',
    }
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    recovery_path = ROOT / 'test_reports/fire-single-tongue-20261106/provider-recovery.json'
    recovery = json.loads(recovery_path.read_text(encoding='utf-8')) if recovery_path.is_file() else {'jobs': []}
    unavailable = {job['key'] for job in recovery['jobs'] if job.get('kind') == 'unavailable_after_404'}
    inactive = [{'key': row['key'],
                 'status': 'unavailable_after_404' if row['key'] in unavailable else 'processing_or_not_extracted'}
                for row in pending_out_of_scope]
    selection = {
        'schema': 'fire-field-selection-v1',
        'purpose': 'Pose ordering contract for full-field assembly; no art acceptance.',
        'path_base': 'repository_root',
        'source_of_truth_report': REPORT.relative_to(ROOT).as_posix(),
        'clips': [{
            'key': c['key'], 'group_key': c['group_key'], 'selected': True,
            'source': c['source'], 'source_sha256': c['source_sha256'],
            'input': c['input'], 'input_sha256': c['input_sha256'],
            'core_mask': c['core_mask'], 'core_mask_sha256': c['core_mask_sha256'],
            'native_crop_xyxy': c['crop_xyxy'], 'native_crop_size': c['crop_size'],
            'order': c['order'], 'frame_ms': c['pose_duration_ms'],
            'raw_frames': [{'index': i, 'path': c['frames'][i]['raw_path'],
                            'sha256': c['frames'][i]['raw_sha256']}
                           for i in c['distinct_generated_poses']],
            'metrics': {'distinct_silhouettes': len(c['distinct_generated_poses']),
                        'max_adjacent_alpha_xor': c['max_adjacent_alpha_xor'],
                        'max_adjacent_premul_rgb_gt8': c['max_adjacent_premul_rgb_gt8'],
                        'exact_seam': c['exact_seam'], 'core_covered': True,
                        'new_contour_outside_input_4px': 0, 'alpha_on_crop_border': 0},
            'timeline_report': (HERE / c['key'] / 'timeline.json').relative_to(ROOT).as_posix(),
        } for c in selected],
        'other_requests': inactive,
    }
    (HERE / 'selection.json').write_text(json.dumps(selection, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'selected_count':len(selected),
                      'selected_by_style':{s:sum(c['key'].startswith('fire'+s) for c in selected) for s in ('24','29')},
                      'not_ready_count':len(pending_out_of_scope),
                      'rejected': [c['key'] for c in clips if c['status'] == 'rejected_or_needs_review']}))


if __name__ == '__main__':
    main()
