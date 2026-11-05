"""Build portable HTML with original endpoints beside every raw animation."""

from __future__ import annotations

import argparse
import base64
import json
import mimetypes
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29', 'spike01', 'caltrops03')


def read(path: Path) -> object:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = read(ROOT / 'requests.json')
    validation_path = ROOT / ('pixellab-validation-partial.json' if args.completed_only
                              else 'pixellab-validation.json')
    validation = read(validation_path)
    if len(rows) != 18 or validation['expected'] != 18:
        raise SystemExit('Expected 18 prepared requests')
    if args.completed_only:
        rows = [row for row in rows if (ROOT / 'pixellab' / row['key'] / 'clip.json').exists()]
    elif not validation['complete'] or validation['completed'] != 18:
        raise SystemExit('Full gallery requires 18 completed clips')
    observations_path = ROOT / 'clip-observations.json'
    observations = read(observations_path) if observations_path.exists() else {}
    if not args.completed_only and set(observations) != {row['key'] for row in rows}:
        raise SystemExit('Full gallery requires per-clip visual observations')
    assets: dict[str, str] = {}

    def embed(path: Path) -> str:
        if not path.is_file():
            raise SystemExit(f'Missing gallery asset: {path}')
        mime = mimetypes.guess_type(path.name)[0]
        if mime not in ('image/png', 'image/gif'):
            raise SystemExit(f'Unsupported gallery asset: {path}')
        key = path.relative_to(ROOT).as_posix()
        if key not in assets:
            assets[key] = f'data:{mime};base64,{base64.b64encode(path.read_bytes()).decode("ascii")}'
        return key

    groups, clips = [], []
    for source in SOURCES:
        subset = [row for row in rows if row['source_key'] == source]
        if not subset:
            continue
        model = ROOT / 'model' / source
        if source == 'spike01':
            original = model / 'source-pair-original.png'
            first = model / 'retracted-input-256.png'
            last = model / 'extended-input-256.png'
        else:
            original = model / 'source-original.png'
            first = last = model / 'input-256.png'
        groups.append({'key': source, 'name': subset[0]['group'],
                       'kind': subset[0]['kind'], 'source': embed(original),
                       'first': embed(first), 'last': embed(last)})
        for row in subset:
            directory = ROOT / 'pixellab' / row['key']
            meta = read(directory / 'clip.json')
            if meta['key'] != row['key'] or meta['actual_frames'] < row['frame_count']:
                raise SystemExit(f'Incomplete clip: {row["key"]}')
            clips.append({'key': row['key'], 'source_key': source, 'kind': row['kind'],
                          'name': row['name'], 'count': meta['actual_frames'],
                          'timing': meta['durations_ms'], 'fps': meta['fps_preview'],
                          'loop': row['loop'], 'one_way': row['one_way'],
                          'first': embed(first), 'last': embed(last),
                          'sheet': embed(directory / 'sheet.png'),
                          'gif': embed(directory / 'preview.gif'),
                          'edge': bool(meta['edge_frames']),
                          'first_target_diff': meta['first_vs_input'],
                          'last_target_diff': meta['last_vs_target'],
                          'seam_diff': meta['loop_seam_last_to_first'],
                          'observation': observations.get(row['key'], 'Все кадры ещё не оценены визуально.')})
    if len(clips) != len(rows):
        raise SystemExit('Missing gallery cards')
    html = (ROOT / 'gallery_template.html').read_text(encoding='utf-8')
    for marker, value in (('__ASSETS__', assets), ('__GROUPS__', groups), ('__CLIPS__', clips)):
        html = html.replace(marker, json.dumps(value, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c'))
    output = ROOT / ('gallery-partial.html' if args.completed_only else 'gallery.html')
    output.write_text(html, encoding='utf-8')
    print(json.dumps({'clips': len(clips), 'groups': len(groups),
                      'embedded_assets': len(assets), 'html_bytes': output.stat().st_size,
                      'complete': not args.completed_only}))


if __name__ == '__main__':
    main()
