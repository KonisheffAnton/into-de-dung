"""Measure a complete VFX cycle, including detached pieces and the wrap transition."""
from pathlib import Path
from collections import deque
import json
import sys
import numpy as np
from PIL import Image

PACKAGE = Path(__file__).resolve().parent
key = sys.argv[1]
assert key.startswith('vfx29-') and key.removeprefix('vfx29-').isdigit()
folder = PACKAGE / 'raw' / key
manifest = json.loads((folder / 'frames.json').read_bytes())
frames = [np.array(Image.open(folder / row['file']).convert('RGBA')) for row in manifest['frames']]
source = np.array(Image.open(PACKAGE / 'inputs/vfx-tile-start.png').convert('RGBA'))
assert all(frame.shape == source.shape == (256, 256, 4) for frame in frames)

def components(mask):
    visited = np.zeros(mask.shape, dtype=bool)
    result = []
    for y, x in zip(*np.where(mask)):
        if visited[y, x]:
            continue
        pending = deque([(y, x)])
        visited[y, x] = True
        size = 0
        while pending:
            cy, cx = pending.popleft()
            size += 1
            for dy, dx in ((-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)):
                ny, nx = cy + dy, cx + dx
                if 0 <= ny < mask.shape[0] and 0 <= nx < mask.shape[1] and mask[ny,nx] and not visited[ny,nx]:
                    visited[ny,nx] = True
                    pending.append((ny,nx))
        result.append(size)
    return sorted(result, reverse=True)

yy, xx = np.indices((256,256))
inner = np.abs(xx-128)/115 + np.abs(yy-128)/87 < .78
changed = np.any(np.stack(frames) != frames[0], axis=(0,3))
metrics = []
for index, frame in enumerate(frames):
    following = frames[(index+1) % len(frames)]
    delta = np.abs(frame.astype(int)-following.astype(int))
    premultiplied = frame[:,:,:3].astype(float) * frame[:,:,3:4] / 255
    luminance = premultiplied @ np.array([.2126,.7152,.0722])
    metrics.append({'frame':index, 'alpha32_components':components(frame[:,:,3] > 32),
                    'inner_rgb_differs_from_input':int(np.any(frame[inner,:3] != source[inner,:3], axis=1).sum()),
                    'inner_temporal_rgba_changed':int(np.any(delta[inner] != 0, axis=1).sum()),
                    'next_changed_rgba_pixels':int(np.any(delta != 0, axis=2).sum()),
                    'next_rgba_abs_sum':int(delta.sum()),
                    'new_alpha32_pixels':int(((frame[:,:,3]>32)&(source[:,:,3]<=32)).sum()),
                    'dynamic_area_luminance':float(luminance[changed].sum())})
ratios = []
for index, row in enumerate(metrics):
    a, b = row['dynamic_area_luminance'], metrics[(index+1)%len(metrics)]['dynamic_area_luminance']
    ratios.append(max(a/b,b/a) if a and b else 1.0)
result = {'key':key, 'frames':len(frames), 'duration_ms':sum(row['duration_ms'] for row in manifest['frames']),
          'dynamic_pixels':int(changed.sum()), 'largest_secondary_alpha32_component':max((row['alpha32_components'][1] if len(row['alpha32_components'])>1 else 0) for row in metrics),
          'max_adjacent_dynamic_luminance_ratio':max(ratios), 'wrap_dynamic_luminance_ratio':ratios[-1],
          'max_internal_rgba_abs_sum':max(row['next_rgba_abs_sum'] for row in metrics[:-1]),
          'wrap_rgba_abs_sum':metrics[-1]['next_rgba_abs_sum'], 'per_frame':metrics,
          'art_acceptance':'Not established by these metrics'}
(folder / 'cycle-inspection.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='per_frame'}))
