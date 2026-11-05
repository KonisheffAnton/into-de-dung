"""Build source-plus-four-frame contact sheets for visual review only."""

from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
for source in ('fire22', 'fire23', 'fire24', 'fire29', 'caltrops03'):
    canvas = Image.new('RGBA', (1280, 768), (0, 0, 0, 0))
    draw = ImageDraw.Draw(canvas)
    for variant in range(1, 4):
        key = f'{source}-{variant:02d}'
        top = (variant - 1) * 256
        with Image.open(ROOT / 'model' / key / 'input-256.png') as original:
            canvas.paste(original, (0, top))
        for index in range(4):
            with Image.open(ROOT / 'pixellab' / key / 'assembled-256' / f'frame-{index:02d}.png') as frame:
                canvas.paste(frame, ((index + 1) * 256, top))
        draw.text((2, top + 2), key + ' | original, 0, 1, 2, 3', fill='#ffffff')
    canvas.save(ROOT / f'review-{source}.png')
    print(source)
