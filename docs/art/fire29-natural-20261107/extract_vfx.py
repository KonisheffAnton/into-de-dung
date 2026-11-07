"""Download PixelLab VFX exports and slice exact atlas rectangles, no pose edits."""
from pathlib import Path
import hashlib
import json
import sys
import urllib.parse
import urllib.request
from PIL import Image

PACKAGE = Path(__file__).resolve().parent
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire29-natural-20261107')
key = sys.argv[1]
assert key.startswith('vfx29-') and key.removeprefix('vfx29-').isdigit()
response = EXTERNAL / 'pixellab' / key / 'job-latest.json'
state = json.loads(response.read_bytes())
assert state['status'] == 'completed'
body = state['last_response']
output = PACKAGE / 'raw' / key
output.mkdir(parents=True, exist_ok=True)
downloads = []
for name, url in body['files'].items():
    assert Path(name).name == name and Path(name).suffix in ('.png', '.json', '.gif')
    parsed = urllib.parse.urlsplit(url)
    assert parsed.scheme == 'https' and parsed.hostname == 'api.pixellab.ai'
    target = output / name
    if target.exists():
        data = target.read_bytes()
    else:
        with urllib.request.urlopen(url, timeout=35) as stream:
            data = stream.read()
        target.write_bytes(data)
    downloads.append({'name': name, 'url': url, 'sha256': hashlib.sha256(data).hexdigest(), 'bytes': len(data)})
metadata = {name: value for name, value in body.items() if name not in ('conversation', 'pixel_tools_image')}
metadata.update(job_id=state['id'], response_sha256=hashlib.sha256(response.read_bytes()).hexdigest(),
                downloads=downloads, usage=state['usage'])
(output / 'metadata.json').write_text(json.dumps(metadata, indent=2) + '\n', encoding='utf-8')
atlas_file = next(row['name'] for row in downloads if row['name'].endswith('.png'))
layout_file = next(row['name'] for row in downloads if row['name'].endswith('.json'))
layout = json.loads((output / layout_file).read_bytes())
atlas = Image.open(output / atlas_file).convert('RGBA')
frames = []
for index, row in enumerate(layout['frames']):
    rectangle = row['frame']
    assert not row['rotated'] and not row['trimmed']
    x, y, width, height = [rectangle[name] for name in ('x', 'y', 'w', 'h')]
    assert 0 <= x < x + width <= atlas.width and 0 <= y < y + height <= atlas.height
    frame = atlas.crop((x, y, x + width, y + height))
    name = f'frame-{index:02d}.png'
    target = output / name
    if target.exists():
        assert Image.open(target).convert('RGBA').tobytes() == frame.tobytes()
    else:
        frame.save(target)
    frames.append({'file': name, 'atlas_rect': rectangle,
                   'rgba_sha256': hashlib.sha256(frame.tobytes()).hexdigest(), 'duration_ms': row['duration']})
(output / 'frames.json').write_text(json.dumps({'source': atlas_file, 'frames': frames,
                                                'pose_pixels_unchanged': True}, indent=2) + '\n', encoding='utf-8')
print(key, 'unchanged atlas frames:', len(frames), 'usage:', state['usage'])
