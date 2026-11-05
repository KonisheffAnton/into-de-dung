"""Embed native PNG source, masks, raw64 and unretouched ROI assemblies in one HTML."""

from __future__ import annotations

import argparse
import base64
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29', 'caltrops03')


def read(path: Path) -> object:
    return json.loads(path.read_text(encoding='utf-8'))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = read(ROOT / 'requests.json')
    validation = read(ROOT / ('validation-partial.json' if args.completed_only else 'validation.json'))
    if len(rows) != 15 or validation['expected_clips'] != 15:
        raise SystemExit('Expected fifteen prepared requests')
    if args.completed_only:
        rows = [row for row in rows if (ROOT / 'pixellab' / row['key'] / 'clip.json').exists()]
    elif validation['exported_clips'] != 15 or not validation['complete']:
        raise SystemExit('Full gallery requires fifteen exports')
    observations_path = ROOT / 'clip-observations.json'
    observations = read(observations_path) if observations_path.exists() else {}
    if not args.completed_only and set(observations) != {row['key'] for row in rows}:
        raise SystemExit('Full gallery requires per-clip observations')
    assets = {}

    def embed(path: Path) -> str:
        if not path.is_file() or path.suffix.lower() != '.png':
            raise SystemExit(f'Gallery PNG missing: {path}')
        key = path.relative_to(ROOT).as_posix()
        if key not in assets:
            assets[key] = 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode('ascii')
        return key

    groups, clips = [], []
    for source in SOURCES:
        subset = [row for row in rows if row['key'].startswith(source + '-')]
        if not subset:
            continue
        first_model = ROOT / 'model' / subset[0]['key']
        groups.append({'source': source, 'name': 'Воронёные иглы 03' if source == 'caltrops03' else 'Нарисованный огонь ' + source[4:],
                       'static': embed(first_model / 'input-256.png')})
        for row in subset:
            key = row['key']
            model = ROOT / 'model' / key
            output = ROOT / 'pixellab' / key
            meta = read(output / 'clip.json')
            if meta['key'] != key or meta['returned_frames'] != 4:
                raise SystemExit(f'Unexpected gallery frame count: {key}')
            clips.append({'key': key, 'source': source, 'kind': 'glint' if source == 'caltrops03' else 'fire',
                          'source_static': embed(model / 'input-256.png'),
                          'roi_static': embed(model / 'roi-static.png'),
                          'mask1': embed(model / 'mask-1.png'), 'mask2': embed(model / 'mask-2.png'),
                          'mask_context': embed(model / 'mask-context-256.png'),
                          'raw_sheet': embed(output / 'sheet-raw-64.png'),
                          'assembled_sheet': embed(output / 'sheet-assembled-256.png'),
                          'playback_order': row['playback_order'],
                          'durations_ms': row['durations_ms'],
                          'mask_pixels': row['mask_white_pixels'],
                          'temporal_pass': meta['temporal_outside_mask_and_loop_pass'],
                          'strict_source_pass': meta['strict_mask_preservation_pass'],
                          'source_normalized_pixels': meta['frames'][0]['outside_mask_rgba_changed_pixels'],
                          'observation': observations.get(key, 'Художественная оценка полного цикла ещё открыта.')})
    if len(clips) != len(rows):
        raise SystemExit('Missing cards')
    html = (ROOT / 'gallery_template.html').read_text(encoding='utf-8')
    for marker, value in (('__ASSETS__', assets), ('__GROUPS__', groups), ('__CLIPS__', clips)):
        html = html.replace(marker, json.dumps(value, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c'))
    target = ROOT / ('gallery-partial.html' if args.completed_only else 'gallery.html')
    target.write_text(html, encoding='utf-8')
    print(json.dumps({'groups': len(groups), 'clips': len(clips), 'assets': len(assets),
                      'bytes': target.stat().st_size, 'complete': not args.completed_only}))


if __name__ == '__main__':
    main()
