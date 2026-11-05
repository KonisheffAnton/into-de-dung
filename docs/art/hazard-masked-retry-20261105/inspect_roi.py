"""Temporary read-only ROI study from accepted original assets."""
from pathlib import Path
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parent
ART = ROOT.parent
SOURCES = {
    'fire23': (ART / 'fire-low-styles-20261104' / 'fire-low-23.png',
               ART / 'fire-painted-sway-20261105' / 'model' / 'fire23' / 'input-256.png', (96, 67, 160, 131)),
    'caltrops03': (ART / 'hazard-variants-20261103' / 'caltrops-03.png',
                   ART / 'hazard-animations-20261104' / 'model' / 'caltrops03' / 'input-256.png', (94, 70, 158, 134)),
}
for key, (source, input_path, box) in SOURCES.items():
    model = ROOT / 'model' / key
    model.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, model / 'source-original.png')
    shutil.copyfile(input_path, model / 'input-256.png')
    with Image.open(input_path) as image:
        image.crop(box).save(model / 'roi-static.png')
    if key == 'caltrops03':
        old = ART / 'hazard-animations-20261104' / 'pixellab' / 'caltrops03-01' / 'frames'
        for index in (0, 8, 9, 10, 17, 18, 24, 25, 26):
            with Image.open(old / f'frame-{index:02d}.png') as image:
                image.crop(box).save(model / f'old-accepted-{index:02d}-roi.png')
    print(key, box, source.stat().st_size, input_path.stat().st_size)
