"""Собирает автономную галерею двенадцати проб низкого огня."""
from pathlib import Path
import argparse
import base64
import json
import mimetypes

ROOT = Path(__file__).resolve().parent
SOURCES = ('fire22', 'fire23', 'fire24', 'fire29')


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--completed-only', action='store_true')
    args = parser.parse_args()
    rows = json.loads((ROOT / 'requests.json').read_text(encoding='utf-8'))
    validation_name = 'pixellab-validation-partial.json' if args.completed_only else 'pixellab-validation.json'
    validation = json.loads((ROOT / validation_name).read_text(encoding='utf-8'))
    expected = [f'{source}-{i:02d}' for source in SOURCES for i in range(1, 4)]
    if [row.get('key') for row in rows] != expected or validation.get('expected') != 12:
        raise SystemExit('Некорректный манифест 12 проб')
    if args.completed_only:
        rows = [row for row in rows if (ROOT / 'pixellab' / row['key'] / 'clip.json').is_file()]
        if validation.get('completed') != len(rows) or validation.get('complete'):
            raise SystemExit('Нужен согласованный частичный экспорт')
    elif validation.get('completed') != 12 or not validation.get('complete'):
        raise SystemExit('Нужен завершённый экспорт 12 проб')
    observations = json.loads((ROOT / 'clip-observations.json').read_text(encoding='utf-8'))
    if not args.completed_only and set(observations) != {row['key'] for row in rows}:
        raise SystemExit('Для полной галереи нужны наблюдения по каждому клипу')
    assets = {}

    def embed(path: Path) -> str:
        if not path.is_file():
            raise SystemExit(f'Отсутствует {path}')
        mime = mimetypes.guess_type(path.name)[0]
        if mime not in ('image/png', 'image/gif'):
            raise SystemExit(f'Неожиданный тип {path}')
        key = path.relative_to(ROOT).as_posix()
        assets[key] = f'data:{mime};base64,{base64.b64encode(path.read_bytes()).decode("ascii")}'
        return key

    groups, clips = [], []
    for source in SOURCES:
        subset = [row for row in rows if row['source_key'] == source]
        if not subset:
            continue
        groups.append({'key': source, 'name': subset[0]['group'],
                       'source': embed(ROOT / 'model' / source / 'source-original.png'),
                       'initial': embed(ROOT / 'model' / source / 'input-256.png')})
        for row in subset:
            folder = ROOT / 'pixellab' / row['key']
            meta = json.loads((folder / 'clip.json').read_text(encoding='utf-8'))
            if meta['key'] != row['key'] or meta['actual_frames'] != row['expected_frames'] or len(meta['durations_ms']) != row['expected_frames']:
                raise SystemExit(f'Неполный клип {row["key"]}')
            clips.append({'key': row['key'], 'source_key': source, 'name': row['name'],
                          'count': meta['actual_frames'], 'timing': meta['durations_ms'],
                          'sheet': embed(folder / 'sheet.png'), 'gif': embed(folder / 'preview.gif'),
                          'edge': bool(meta['edge_frames']), 'endpoint_equal': meta['endpoint_frame_rgba_equal'],
                          'observation': observations.get(row['key'], 'Просмотр движения ещё не выполнен')})
    assert len(clips) == len(rows) and len(assets) == 2 * len(groups) + 2 * len(clips)
    if not args.completed_only:
        assert len(groups) == 4 and len(clips) == 12 and len(assets) == 32
    html = (ROOT / 'gallery_template.html').read_text(encoding='utf-8')
    if args.completed_only:
        html = html.replace('12 проб PixelLab', f'{len(clips)} из 12 проб PixelLab')
    for marker, value in (('__ASSETS__', assets), ('__GROUPS__', groups), ('__CLIPS__', clips)):
        html = html.replace(marker, json.dumps(value, ensure_ascii=False, separators=(',', ':')).replace('<', '\\u003c'))
    output = ROOT / ('gallery-partial.html' if args.completed_only else 'gallery.html')
    output.write_text(html, encoding='utf-8')
    print(json.dumps({'clips': len(clips), 'groups': len(groups), 'assets': len(assets), 'complete': not args.completed_only, 'html_bytes': output.stat().st_size}))


if __name__ == '__main__':
    main()
