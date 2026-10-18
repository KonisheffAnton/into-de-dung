"""Assemble reviewed PixelLab frames, without painting or modifying PNG pixels.

Run package.py first. Provider frames and repair outputs stay immutable;
animations/ contains only byte copies selected by the mapping below.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image
from package import preview_files

ROOT = Path(__file__).resolve().parent
SEQUENCES = {
    1: [1, 2, 3, 4, 'contact', 6, 7, 8, 9],
    2: [1, 2, 3, 'approach', 'contact', 'sparks', 'approach', 3, 9],
    3: [1, 3, 4, 'contact', 5, 6, 7, 8, 9],
    4: [1, 2, 3, 4, 'contact', 'sparks', 7, 8, 9],
    5: [1, 2, 3, 'approach', 'contact', 'sparks', 7, 8, 9],
}


def main():
    manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    authoritative = {frame['file']: frame['sha256']
                     for output in manifest['outputs'] for frame in output['frames']}
    variants = []
    for variant, sequence in SEQUENCES.items():
        folder = ROOT / 'animations' / f'smith-{variant:02d}'
        folder.mkdir(parents=True, exist_ok=True)
        records, frames = [], []
        for index, token in enumerate(sequence, 1):
            source = (f'provider-animations/smith-{variant:02d}/frame-{token:02d}.png'
                      if isinstance(token, int) else f'repairs/smith-{variant:02d}-{token}.png')
            data = (ROOT / source).read_bytes()
            digest = hashlib.sha256(data).hexdigest()
            assert authoritative[source] == digest, source
            target = folder / f'frame-{index:02d}.png'
            target.write_bytes(data)
            frame = Image.open(target).convert('RGBA')
            assert frame.size == (256, 256)
            frames.append(frame)
            records.append({'file': target.relative_to(ROOT).as_posix(),
                            'source': source, 'sha256': digest})
        preview_files(folder, frames)
        variants.append({'variant': variant, 'contact_frame': 4 if variant == 3 else 5,
                         'first_sparks_frame': 5 if variant == 3 else 6,
                         'frames': records})
    final = {'preview_frame_ms': 160, 'variants': variants,
             'method': 'Byte copies of selected PixelLab frames and PixelLab edit-image-pixen repairs; no hand-painted pixels or interpolation.',
             'timing_note': 'Contact/spark indices are visual review annotations, not automated detection.'}
    (ROOT / 'final-manifest.json').write_text(json.dumps(final, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Assembled 5 loops / 45 byte-preserved frames')


if __name__ == '__main__':
    main()
