"""Строит обзор всех кадров и измеряет alpha-расширение без изменения исходников."""

import json
from pathlib import Path
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parent
REPORT = ROOT.parents[2] / 'test_reports/fire-painted-sway-20261105'


def main() -> None:
    REPORT.mkdir(parents=True, exist_ok=True)
    rows = json.loads((ROOT / 'requests.json').read_text(encoding='utf-8'))
    results = []
    for row in rows:
        key = row['key']
        folder = ROOT / 'pixellab' / key / 'frames'
        if not (folder / 'frame-00.png').exists():
            continue
        with Image.open(ROOT / row['input']) as image:
            original = image.convert('RGBA')
            input_alpha = original.getchannel('A')
            original_box = input_alpha.getbbox()
        count = json.loads((ROOT / 'pixellab' / key / 'clip.json').read_text(encoding='utf-8'))['actual_frames']
        columns = 4
        sheet = Image.new('RGB', (columns * 256, ((count + columns - 1) // columns) * 280), '#111827')
        draw = ImageDraw.Draw(sheet)
        samples = []
        for index in range(count):
            with Image.open(folder / f'frame-{index:02d}.png') as image:
                frame = image.convert('RGBA')
            box = frame.getchannel('A').getbbox()
            extension = max(0, original_box[1] - box[1]) if box else 0
            samples.append({'frame': index, 'alpha_box': box, 'top_extension_px': extension})
            x, y = index % columns * 256, index // columns * 280
            sheet.paste(frame, (x, y), frame)
            draw.text((x + 6, y + 256), f'{index:02d}  top +{extension}px', fill='#ffffff')
        sheet.save(REPORT / f'{key}-all-frames.png')
        results.append({'key': key, 'input_alpha_box': original_box,
                        'max_top_extension_px': max(s['top_extension_px'] for s in samples),
                        'frames_with_top_extension': [s['frame'] for s in samples if s['top_extension_px'] > 0],
                        'frames': samples})
    (REPORT / 'all-frame-alpha.json').write_text(json.dumps({'clips': results}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'clips': len(results), 'max_top_extension_px': {r['key']: r['max_top_extension_px'] for r in results}}))


if __name__ == '__main__':
    main()
