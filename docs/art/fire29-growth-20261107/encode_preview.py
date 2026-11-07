"""Упаковывает GPU PNG без изменения пикселей и проверяет полный цикл."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
CAPTURES = REPO / 'test_reports/fire29-growth-hud-20261107/preview/frames'
selection = json.loads((ROOT / 'selection.json').read_text(encoding='utf-8'))
poses = [Image.open(CAPTURES / f'{i:03d}.png').convert('RGBA') for i in range(len(selection['frames']))]
frames = [poses[i] for i in selection['order']]
output = ROOT / 'fire29-growth-neighbours.webp'
frames[0].save(output, save_all=True, append_images=frames[1:], duration=selection['durations_ms'],
               loop=0, lossless=True, method=4)
with Image.open(output) as animated:
    assert animated.n_frames == len(frames) and animated.info['loop'] == 0
    for index, expected in enumerate(frames):
        animated.seek(index)
        assert animated.convert('RGBA').tobytes() == expected.tobytes()
        assert animated.info['duration'] == selection['durations_ms'][index]
proof = {'frames': len(frames), 'unique_provider_poses': len(poses), 'period_ms': selection['period_ms'],
         'format': 'lossless animatedWebP', 'all_decoded_frames_equal_gpu_png': True,
         'sha256': hashlib.sha256(output.read_bytes()).hexdigest(), 'bytes': output.stat().st_size}
native_captures = REPO / 'test_reports/fire29-growth-hud-20261107/preview-native/frames'
native_poses = [Image.open(native_captures / f'{i:03d}.png').convert('RGBA') for i in range(7)]
native_frames = [native_poses[i] for i in selection['order']]
native_output = ROOT / 'fire29-growth-native.webp'
native_frames[0].save(native_output, save_all=True, append_images=native_frames[1:],
                      duration=selection['durations_ms'], loop=0, lossless=True, method=4)
with Image.open(native_output) as animated:
    assert animated.n_frames == 12 and animated.size == (480, 400) and animated.info['loop'] == 0
    for index, expected in enumerate(native_frames):
        animated.seek(index)
        assert animated.convert('RGBA').tobytes() == expected.tobytes()
        assert animated.info['duration'] == 120
proof['native'] = {'tile_size': [128, 96], 'viewport': [480, 400], 'frames': 12,
                   'all_decoded_frames_equal_gpu_png': True,
                   'sha256': hashlib.sha256(native_output.read_bytes()).hexdigest(), 'bytes': native_output.stat().st_size}
(ROOT / 'preview-validation.json').write_text(json.dumps(proof, indent=2) + '\n', encoding='utf-8')
print('PASS lossless preview:', len(frames), 'frames')
