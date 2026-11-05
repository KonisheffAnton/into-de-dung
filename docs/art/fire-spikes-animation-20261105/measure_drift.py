"""Measure fixed-stone and whole-tile drift across every returned PNG frame."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image


ROOT = Path(__file__).resolve().parent


def pixels(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert('RGBA')).astype(np.int16)


def bbox(array: np.ndarray) -> list[int] | None:
    ys, xs = np.where(array[:, :, 3] > 8)
    if not len(xs):
        return None
    return [int(xs.min()), int(ys.min()), int(xs.max() + 1), int(ys.max() + 1)]


def main() -> None:
    rows = json.loads((ROOT / 'requests.json').read_text(encoding='utf-8'))
    report = {}
    for row in rows:
        directory = ROOT / 'pixellab' / row['key']
        clip_path = directory / 'clip.json'
        if not clip_path.exists():
            continue
        clip = json.loads(clip_path.read_text(encoding='utf-8'))
        source = pixels(ROOT / row['first_input'])
        ys = np.indices((256, 256))[0]
        # Lower visible body excludes the animated top and metal tips.
        stone = (ys >= 155) & (source[:, :, 3] > 200)
        source_bbox = bbox(source)
        frames = []
        for index in range(clip['actual_frames']):
            frame = pixels(directory / 'frames' / f'frame-{index:02d}.png')
            delta = np.abs(frame - source)
            changed = np.any(delta > 8, axis=2)
            box = bbox(frame)
            frames.append({'index': index,
                           'stone_side_pixels_changed_gt8': int(np.count_nonzero(changed & stone)),
                           'stone_side_rgba_mae': float(delta[stone].mean()) if np.any(stone) else 0.0,
                           'alpha_bbox': box,
                           'alpha_bbox_delta_xywh': [box[0] - source_bbox[0], box[1] - source_bbox[1],
                                                     (box[2] - box[0]) - (source_bbox[2] - source_bbox[0]),
                                                     (box[3] - box[1]) - (source_bbox[3] - source_bbox[1])]
                           if box and source_bbox else None})
        report[row['key']] = {'source_alpha_bbox_gt8': source_bbox,
                              'stone_mask_pixels': int(np.count_nonzero(stone)),
                              'max_stone_side_pixels_changed_gt8': max(x['stone_side_pixels_changed_gt8'] for x in frames),
                              'max_stone_side_rgba_mae': max(x['stone_side_rgba_mae'] for x in frames),
                              'frames': frames,
                              'note': 'Direct source pixel differences include lighting/recolor as well as motion; visual review is required.'}
    (ROOT / 'drift.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'clips_measured': len(report),
                      'max_stone_changed_by_clip': {key: value['max_stone_side_pixels_changed_gt8']
                                                    for key, value in report.items()}}, ensure_ascii=False))


if __name__ == '__main__':
    main()
