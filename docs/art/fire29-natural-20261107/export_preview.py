"""Export exact GPU captures as lossless animated WebP, then decode-verify them."""
from pathlib import Path
import hashlib
import json
import sys
from PIL import Image

PACKAGE = Path(__file__).resolve().parent
REPORT = PACKAGE.parents[2] / 'test_reports/fire29-natural-20261107'


def main():
    label, stem = sys.argv[1:]
    assert all(value.replace('-', '').isalnum() for value in (label, stem))
    capture = REPORT / label
    selection = json.loads((capture / 'selection.json').read_bytes())
    completion = json.loads((capture / 'completion.json').read_bytes())
    assert completion['exit_code'] == 0
    assert completion['selection_sha256'] == hashlib.sha256((capture / 'selection.json').read_bytes()).hexdigest()
    assert completion['script_sha256'] == hashlib.sha256((capture / 'capture_preview.gd').read_bytes()).hexdigest()
    rows = []
    for size, suffix in ((128, 'native'), (384, 'neighbours')):
        paths = sorted((capture / str(size)).glob('*.png'))
        assert [path.name for path in paths] == [f'{index:03d}.png' for index in range(selection['slots'])]
        for path in paths:
            assert completion['files'][f'{size}/{path.name}'] == hashlib.sha256(path.read_bytes()).hexdigest()
        frames = [Image.open(path).convert('RGBA') for path in paths]
        output = PACKAGE / f'{stem}-{suffix}.webp'
        assert not output.exists(), 'Preserve earlier previews; use a distinct name.'
        durations = [selection['slot_ms']] * len(frames)
        frames[0].save(output, save_all=True, append_images=frames[1:],
                       duration=durations, loop=0, lossless=True, method=6)
        decoded = Image.open(output)
        assert decoded.n_frames == len(frames)
        for index, original in enumerate(frames):
            decoded.seek(index)
            rgba = decoded.convert('RGBA')
            assert rgba.tobytes() == original.tobytes(), (output.name, index)
            assert decoded.info['duration'] == durations[index]
        rows.append({'file': output.name, 'tile_size': [size, size * 3 // 4],
                     'frames': len(frames), 'duration_ms': sum(durations),
                     'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                     'decoded_rgba_and_timing_equal_gpu': True})
    result = {'capture': str(capture.relative_to(PACKAGE.parents[2])),
              'selection_sha256': hashlib.sha256((capture / 'selection.json').read_bytes()).hexdigest(),
              'exports': rows}
    (PACKAGE / f'{stem}-exports.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result))


if __name__ == '__main__':
    main()
