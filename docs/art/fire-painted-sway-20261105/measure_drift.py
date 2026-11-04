"""Измерить отличия камня и alpha у экспортированных кадров; это не арт-приёмка."""
from pathlib import Path
import argparse
import json
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPORT = ROOT.parents[2] / 'test_reports' / 'fire-painted-sway-20261105' / 'drift.json'


def rgba(path: Path) -> np.ndarray:
    with Image.open(path) as image:
        return np.asarray(image.convert('RGBA')).astype(np.int16)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    requests = json.loads((ROOT / 'requests.json').read_text(encoding='utf-8'))
    if args.completed_only:
        requests = [row for row in requests if (ROOT / 'pixellab' / row['key'] / 'clip.json').exists()]
    details = []
    for row in requests:
        initial = rgba(ROOT / row['input'])
        yy = np.indices((256, 256))[0]
        stone = (yy >= 150) & (initial[:, :, 3] > 8)
        count = json.loads((ROOT / 'pixellab' / row['key'] / 'clip.json').read_text(encoding='utf-8'))['actual_frames']
        frames = [rgba(ROOT / 'pixellab' / row['key'] / 'frames' / f'frame-{i:02d}.png')
                  for i in range(count)]
        changes = []
        for frame in frames:
            diff = np.abs(frame - initial)
            changes.append({
                'stone_side_rgba_mae': round(float(diff[stone].mean()), 3),
                'stone_side_changed_pixels_gt8': int(np.count_nonzero(np.any(diff[stone] > 8, axis=1))),
                'alpha_changed_pixels': int(np.count_nonzero(diff[:, :, 3])),
                'visible_rgba_changed_pixels': int(np.count_nonzero(np.any(diff[:, :, :] > 8, axis=2) & ((frame[:, :, 3] > 8) | (initial[:, :, 3] > 8)))),
            })
        details.append({
            'key': row['key'], 'kind': row['kind'],
            'stone_side_pixels': int(np.count_nonzero(stone)),
            'stone_side_rgba_mae_max': max(x['stone_side_rgba_mae'] for x in changes),
            'stone_side_changed_pixels_gt8_max': max(x['stone_side_changed_pixels_gt8'] for x in changes),
            'alpha_changed_pixels_max': max(x['alpha_changed_pixels'] for x in changes),
            'visible_rgba_changed_pixels_max': max(x['visible_rgba_changed_pixels'] for x in changes),
            'first': changes[0], 'last': changes[-1],
        })
    result = {'clips': len(details), 'note': 'Stone proxy is bottom y>=150 with input alpha>8. Colour differences do not alone prove geometry changes; inspect the frames.', 'details': details}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    output = REPORT.with_name('drift-partial.json') if args.completed_only else REPORT
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'clips': len(details),
                      'max_stone_side_rgba_mae': max(x['stone_side_rgba_mae_max'] for x in details),
                      'max_alpha_changed_pixels': max(x['alpha_changed_pixels_max'] for x in details)}))


if __name__ == '__main__':
    main()
