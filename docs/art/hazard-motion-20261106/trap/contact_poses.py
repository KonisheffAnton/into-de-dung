from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RAW = ROOT / 'docs/art/fire-spikes-animation-20261105/pixellab/spike01-01/frames'
MODEL = ROOT / 'docs/art/fire-spikes-animation-20261105/model/spike01'
images = [('source retracted', MODEL / 'retracted-input-256.png')]
images += [(f'raw {i:02}', RAW / f'frame-{i:02}.png') for i in (0, 2, 3, 4, 5, 8)]
images += [('source extended', MODEL / 'extended-input-256.png')]
out = Image.new('RGBA', (4*256, 2*284), (40, 43, 48, 255))
draw = ImageDraw.Draw(out)
for index, (label, path) in enumerate(images):
    img = Image.open(path).convert('RGBA')
    x = (index % 4)*256
    y = (index // 4)*284
    out.alpha_composite(img, (x, y+24))
    draw.text((x+5, y+5), label, fill='white')
out.convert('RGB').save(HERE/'trap-pose-contact.jpg', quality=95)
detail = Image.new('RGBA', (4*384, 3*240), (40, 43, 48, 255))
dd = ImageDraw.Draw(detail)
for row, (cx,cy) in enumerate(((128,54),(83,91),(128,129))):
    for col, (label,path) in enumerate((images[0], images[3], images[4], images[6])):
        img=Image.open(path).convert('RGBA')
        crop=img.crop((cx-12,cy-12,cx+12,cy+12)).resize((192,192),Image.Resampling.NEAREST)
        x=col*384; y=row*240
        detail.alpha_composite(crop,(x+96,y+28))
        dd.text((x+5,y+5),f'{label} {cx},{cy}',fill='white')
detail.convert('RGB').save(HERE/'trap-socket-contact.png')
