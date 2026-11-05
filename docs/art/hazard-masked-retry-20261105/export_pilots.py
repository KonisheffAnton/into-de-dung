"""Export byte-exact legacy 64px responses and transparent 256px ROI assemblies."""

from __future__ import annotations

import base64
import hashlib
import io
import json
import shutil
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-masked-retry-20261105')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(image: dict) -> bytes:
    value = image['base64']
    return base64.b64decode(value.split(',', 1)[1] if value.startswith('data:') else value, validate=True)


def png_rgba(data: bytes, label: str) -> Image.Image:
    with Image.open(io.BytesIO(data)) as image:
        image.load()
        if image.format != 'PNG' or image.mode != 'RGBA' or image.size != (64, 64):
            raise SystemExit(f'Unexpected raw API PNG: {label}, {image.format}/{image.mode}/{image.size}')
        return image.copy()


def main() -> None:
    rows = json.loads((ROOT / 'pilots.json').read_text(encoding='utf-8'))
    if [row['key'] for row in rows] != ['fire23-01', 'caltrops03-01']:
        raise SystemExit('Expected exactly two approved pilot keys')
    reports = []
    for row in rows:
        key = row['key']
        external = JOBS / 'pixellab' / key
        response_path = external / 'response-raw.json'
        if not (external / 'submit-started.json').exists() or not response_path.exists():
            continue
        response = json.loads(response_path.read_text(encoding='utf-8'))
        if not isinstance(response.get('images'), list):
            raise SystemExit(f'Legacy synchronous images missing: {key}; inspect admission/GET')
        request_path = external / 'request.json'
        if sha(request_path) != row['request_sha256']:
            raise SystemExit(f'Immutable request SHA changed: {key}')
        request = json.loads(request_path.read_text(encoding='utf-8'))
        model = ROOT / 'model' / key
        source = model / 'input-256.png'
        roi_path = model / 'roi-static.png'
        if sha(source) != row['input_sha256'] or sha(roi_path) != row['roi_sha256']:
            raise SystemExit(f'Input SHA changed: {key}')
        roi_bytes = roi_path.read_bytes()
        if any(decode(item) != roi_bytes for item in request['inpainting_images']):
            raise SystemExit(f'Four inpainting images differ from ROI: {key}')
        masks = []
        for index, item in enumerate(request['mask_images']):
            raw = decode(item)
            if hashlib.sha256(raw).hexdigest() != row['mask_sha256'][index]:
                raise SystemExit(f'Mask SHA changed: {key}:{index}')
            with Image.open(io.BytesIO(raw)) as mask_image:
                mask_image.load()
                if mask_image.format != 'PNG' or mask_image.mode != 'RGB' or mask_image.size != (64, 64):
                    raise SystemExit(f'Unexpected mask format: {key}:{index}')
                mask = np.asarray(mask_image)[:, :, 0] > 0
                if not np.all(np.asarray(mask_image)[:, :, 0] == np.asarray(mask_image)[:, :, 1]) or not np.all(np.asarray(mask_image)[:, :, 1] == np.asarray(mask_image)[:, :, 2]):
                    raise SystemExit(f'Mask must be grayscale: {key}:{index}')
            if int(mask.sum()) != row['mask_white_pixels'][index]:
                raise SystemExit(f'Mask area changed: {key}:{index}')
            masks.append(mask)
        if masks[0].any() or masks[-1].any():
            raise SystemExit(f'Endpoint masks are not black: {key}')
        output = ROOT / 'pixellab' / key
        raw_dir, assembled_dir = output / 'raw-64', output / 'assembled-256'
        raw_dir.mkdir(parents=True, exist_ok=True)
        assembled_dir.mkdir(parents=True, exist_ok=True)
        response_copy = output / 'response-raw.json'
        if response_copy.exists() and response_copy.read_bytes() != response_path.read_bytes():
            raise SystemExit(f'Prior raw response copy differs: {key}')
        shutil.copyfile(response_path, response_copy)
        first = np.asarray(Image.open(roi_path)).copy()
        full = np.asarray(Image.open(source)).copy()
        if first.shape != (64, 64, 4) or full.shape != (256, 256, 4):
            raise SystemExit(f'Input geometry changed: {key}')
        x0, y0, x1, y1 = row['roi_xyxy']
        if x1 - x0 != 64 or y1 - y0 != 64 or not np.array_equal(full[y0:y1, x0:x1], first):
            raise SystemExit(f'ROI does not match original canvas: {key}')
        frames, frame_reports, arrays = [], [], []
        for index, item in enumerate(response['images']):
            raw = decode(item)
            image = png_rgba(raw, f'{key}:{index}')
            path = raw_dir / f'frame-{index:02d}.png'
            if path.exists() and path.read_bytes() != raw:
                raise SystemExit(f'Existing raw frame differs: {key}:{index}')
            path.write_bytes(raw)
            pixels = np.asarray(image)
            assembled = full.copy()
            assembled[y0:y1, x0:x1] = pixels
            Image.fromarray(assembled, mode='RGBA').save(assembled_dir / f'frame-{index:02d}.png')
            outside = ~masks[index] if index < 4 else np.ones((64, 64), dtype=bool)
            exact_outside = np.all(pixels[outside] == first[outside], axis=1)
            exact_endpoint = bool(np.array_equal(pixels, first)) if index in (0, 3) else None
            frame_reports.append({'index': index, 'raw_png_sha256': hashlib.sha256(raw).hexdigest(),
                                  'masked_white_pixels': int(masks[index].sum()) if index < 4 else None,
                                  'outside_mask_rgba_changed_pixels': int(np.count_nonzero(~exact_outside)),
                                  'endpoint_rgba_equal_to_source': exact_endpoint,
                                  'assembled_outside_roi_rgba_equal': bool(np.array_equal(
                                      assembled[:y0], full[:y0]) and np.array_equal(assembled[y1:], full[y1:])
                                      and np.array_equal(assembled[y0:y1, :x0], full[y0:y1, :x0])
                                      and np.array_equal(assembled[y0:y1, x1:], full[y0:y1, x1:]))})
            frames.append(image)
            arrays.append(pixels)
        sheet_raw = Image.new('RGBA', (64 * len(frames), 64), (0, 0, 0, 0))
        sheet_full = Image.new('RGBA', (256 * len(frames), 256), (0, 0, 0, 0))
        for index, image in enumerate(frames):
            sheet_raw.paste(image, (index * 64, 0))
            with Image.open(assembled_dir / f'frame-{index:02d}.png') as assembled:
                sheet_full.paste(assembled, (index * 256, 0))
        sheet_raw.save(output / 'sheet-raw-64.png')
        sheet_full.save(output / 'sheet-assembled-256.png')
        for index, pixels in enumerate(arrays):
            outside = ~masks[index] if index < 4 else np.ones((64, 64), dtype=bool)
            frame_reports[index]['outside_mask_vs_frame0_changed_pixels'] = int(np.count_nonzero(
                np.any(pixels[outside] != arrays[0][outside], axis=1)))
            frame_reports[index]['outside_mask_vs_source_visible_changed_pixels_alpha_gt8'] = int(np.count_nonzero(
                np.any(pixels[outside] != first[outside], axis=1) &
                ((pixels[outside][:, 3] > 8) | (first[outside][:, 3] > 8))))
            frame_reports[index]['inside_mask_vs_frame0_changed_pixels'] = int(np.count_nonzero(
                np.any(pixels[masks[index]] != arrays[0][masks[index]], axis=1))) if index < 4 else None
        strict = len(frames) == 4 and all(f['outside_mask_rgba_changed_pixels'] == 0 for f in frame_reports) and all(f['endpoint_rgba_equal_to_source'] for f in frame_reports if f['endpoint_rgba_equal_to_source'] is not None)
        temporal = len(frames) == 4 and bool(np.array_equal(arrays[0], arrays[3])) and all(f['outside_mask_vs_frame0_changed_pixels'] == 0 for f in frame_reports)
        report = {'key': key, 'status': 'completed', 'transport': 'synchronous',
                  'raw_api_canvas': [64, 64], 'derived_canvas': [256, 256],
                  'requested_frames': request['n_frames'], 'returned_frames': len(frames),
                  'request_sha256': row['request_sha256'], 'response_sha256': sha(response_copy),
                  'usage': response.get('usage'), 'strict_mask_preservation_pass': strict,
                  'temporal_outside_mask_and_loop_pass': temporal,
                  'first_last_raw_rgba_equal': bool(np.array_equal(arrays[0], arrays[-1])),
                  'mask_white_pixels': row['mask_white_pixels'],
                  'assembly': 'Paste entire unmodified raw 64px frame into integer ROI of original 256px image; no scale or mask repair',
                  'frames': frame_reports, 'integration': False, 'artistic_acceptance': 'open'}
        (output / 'clip.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        reports.append(report)
    summary = {'expected_pilots': 2, 'exported_pilots': len(reports),
               'raw_api_frames': sum(x['returned_frames'] for x in reports),
               'strict_mask_passes': [x['key'] for x in reports if x['strict_mask_preservation_pass']],
               'strict_mask_failures': [x['key'] for x in reports if not x['strict_mask_preservation_pass']],
               'clips': reports, 'integration': False, 'artistic_acceptance': 'open'}
    (ROOT / 'pilot-validation.json').write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: value for key, value in summary.items() if key != 'clips'}))


if __name__ == '__main__':
    main()
