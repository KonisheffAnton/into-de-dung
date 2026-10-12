"""Сравнить почти чёрные пиксели внешней границы, не смешивая их с тенями внутри."""
from pathlib import Path
from collections import Counter
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent

def measure(relative):
    image = Image.open(ROOT / relative).convert('RGBA')
    colors = Counter()
    for y in range(image.height):
        for x in range(image.width):
            pixel = image.getpixel((x, y))
            if not pixel[3]:
                continue
            if any(nx < 0 or nx >= image.width or ny < 0 or ny >= image.height or image.getpixel((nx, ny))[3] == 0 for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1))):
                colors[pixel[:3]] += 1
    return {'source': relative, 'boundary_pixels': sum(colors.values()), 'boundary_maxrgb_below_28': sum(n for color, n in colors.items() if max(color) < 28), 'darkest_boundary_colors': sorted(colors.items(), key=lambda item: sum(item[0]))[:5]}

results = {'definition': 'Visible silhouette boundary with at least one transparent four-neighbor; max(RGB)<28 is a diagnostic, not art acceptance.', 'reference': measure('reference-128.png'), 'before': [measure(f'inputs/{pose}.png') for pose in ('cross','release','settle')], 'after': [measure(f'final/frames/frame-{i:02}.png') for i in range(1,4)]}
(ROOT / 'outline-boundary.json').write_text(json.dumps(results, indent=2) + '\n', encoding='utf-8')
print(json.dumps({key: [{'boundary': row['boundary_pixels'], 'nearblack': row['boundary_maxrgb_below_28']} for row in values] for key, values in results.items() if key in ('before','after')}))
