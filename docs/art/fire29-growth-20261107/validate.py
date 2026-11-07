"""Проверка происхождения кандидата; API/генерацию/игровой код не запускает."""
from pathlib import Path
import base64
import hashlib
import json
import numpy as np
from PIL import Image, ImageChops, ImageDraw

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire29-growth-20261107')
REPORT = REPO / 'test_reports/fire29-growth-hud-20261107'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decode(item):
    image = item.get('image', item)
    return base64.b64decode(image['base64'].split(',', 1)[-1])


def validate():
    keys = ['growth-keypose01', 'growth-motion01', 'growth-motion02']
    usage = 0
    raw_count = 0
    for key, expected_count in zip(keys, [1, 17, 33]):
        request_path = ROOT / 'requests' / key / 'request.json'
        meta = read(request_path.parent / 'metadata.json')
        request = read(request_path)
        job = EXTERNAL / 'pixellab' / key
        assert request_path.read_bytes() == (job / 'request.json').read_bytes()
        assert sha(request_path) == meta['request_sha256']
        state = read(job / 'job-latest.json')
        assert state['status'] == 'completed'
        body = state['last_response']
        images = body.get('images') or [body['image']]
        assert len(images) == expected_count
        raw_metadata = read(ROOT / 'raw' / key / 'metadata.json')
        assert sha(job / 'job-latest.json') == raw_metadata['response_sha256']
        assert state['id'] == raw_metadata['job_id'] == read(job / 'admission.json')['background_job_id']
        for index, item in enumerate(images):
            path = ROOT / 'raw' / key / f'{index:02d}.png'
            assert path.read_bytes() == decode(item)
            assert sha(path) == raw_metadata['images'][index]['sha256']
            with Image.open(path) as im:
                assert im.size == (256, 256) and im.mode == 'RGBA'
        raw_count += len(images)
        usage += body['billing_usage']['generations']
        if key == 'growth-keypose01':
            assert decode(request['inpainting_image']) == (ROOT / meta['input']).read_bytes()
            assert decode(request['mask_image']) == (ROOT / meta['mask']).read_bytes()
            assert sha(ROOT / meta['input']) == meta['input_sha256']
            assert sha(ROOT / meta['mask']) == meta['mask_sha256']
            assert sha(REPO / meta['source']) == meta['source_sha256']
        else:
            for field in ['first_frame', 'last_frame']:
                assert decode(request[field]) == (ROOT / meta[field]).read_bytes()
                assert sha(ROOT / meta[field]) == meta[field + '_sha256']
    assert usage == 17 and raw_count == 51
    before = read(ROOT / 'balance-before.json')['subscription']['generations']
    after = read(ROOT / 'balance-after.json')['subscription']['generations']
    assert before == 4359 and after == 4342 and before - after == usage

    meta = read(ROOT / 'requests/growth-keypose01/metadata.json')
    frame = Image.open(REPO / meta['source']).convert('RGBA').crop((0, 0, 256, 194))
    mask = Image.new('L', frame.size)
    ImageDraw.Draw(mask).polygon([(128, 12), (243, 99), (128, 187), (13, 99)], fill=255)
    frame.putalpha(ImageChops.multiply(frame.getchannel('A'), mask))
    prepared = Image.new('RGBA', (256, 256))
    prepared.paste(frame, (0, 29))
    start = Image.open(ROOT / 'inputs/start.png').convert('RGBA')
    assert prepared.tobytes() == start.tobytes()
    original = np.array(start)
    grown = np.array(Image.open(ROOT / 'raw/growth-keypose01/00.png').convert('RGBA'))
    allowed = np.array(Image.open(ROOT / 'inputs/growth-mask.png').convert('L')) > 0
    assert np.array_equal(original[~allowed], grown[~allowed])
    keypose_growth = int(((original[:, :, 3] <= 8) & (grown[:, :, 3] > 8)).sum())
    assert keypose_growth == 1118

    selection = read(ROOT / 'selection.json')
    assert selection['runtime_integration'] is False
    assert selection['order'] == list(range(7)) + list(range(5, 0, -1))
    assert selection['durations_ms'] == [120] * 12 and selection['period_ms'] == 1440
    selected = []
    counts = []
    brightness = []
    lost = []
    prior = None
    for file in selection['frames']:
        assert sha(ROOT / file) == selection['frame_sha256'][file]
        pixels = np.array(Image.open(ROOT / file).convert('RGBA'))
        selected.append(pixels)
        new = (pixels[:, :, 3] > 8) & (original[:, :, 3] <= 8)
        counts.append(int(new.sum()))
        lost.append(int((prior & ~new).sum()) if prior is not None else 0)
        prior = new
        brightness.append(float((pixels[:, :, :3] * (pixels[:, :, 3:] / 255.)).sum()))
    assert counts == [61, 131, 250, 395, 588, 794, 1120]
    ordered = [brightness[index] for index in selection['order']]
    jumps = [max(a, b) / min(a, b) for a, b in zip(ordered, ordered[1:] + ordered[:1])]
    assert max(jumps) < 1.03
    visible = original[:, :, 3] > 8
    original_rgb_changed = int(np.any(selected[0][:, :, :3] != original[:, :, :3], axis=2)[visible].sum())
    assert original_rgb_changed > 0  # Не выдавать generated palette за побайтный исходник.

    encoded = ROOT / 'fire29-growth-neighbours.webp'
    export = read(ROOT / 'preview-validation.json')
    assert sha(encoded) == export['sha256']
    with Image.open(encoded) as animation:
        assert animation.n_frames == 12 and animation.info['loop'] == 0
        for index, pose in enumerate(selection['order']):
            animation.seek(index)
            expected = Image.open(REPORT / 'preview/frames' / f'{pose:03d}.png').convert('RGBA')
            assert animation.convert('RGBA').tobytes() == expected.tobytes()
            assert animation.info['duration'] == 120
    log = (REPORT / 'preview/capture.log').read_text(encoding='utf-8')
    assert 'GROWTH PREVIEW PASS: 7' in log and 'ERROR' not in log
    native = ROOT / 'fire29-growth-native.webp'
    assert sha(native) == export['native']['sha256']
    with Image.open(native) as animation:
        assert animation.n_frames == 12 and animation.size == (480, 400) and animation.info['loop'] == 0
        for index, pose in enumerate(selection['order']):
            animation.seek(index)
            expected = Image.open(REPORT / 'preview-native/frames' / f'{pose:03d}.png').convert('RGBA')
            assert animation.convert('RGBA').tobytes() == expected.tobytes()
            assert animation.info['duration'] == 120
    native_log = (REPORT / 'preview-native/capture.log').read_text(encoding='utf-8')
    assert 'GROWTH PREVIEW PASS: 7' in native_log and 'ERROR' not in native_log
    result = {'status': 'PASS', 'provider_requests': 3, 'raw_png': raw_count, 'usage_generations': usage,
              'inpaint_outside_mask_rgba_changes': 0, 'keypose_new_visible_pixels': keypose_growth,
              'selected_new_visible_area': counts, 'lost_outside_pixels_per_step': lost,
              'strict_pixelwise_addition': False, 'source_visible_rgb_changed_in_selected_first': original_rgb_changed,
              'whole_source_rgb_preserved': False, 'largest_adjacent_or_wrap_brightness_ratio': max(jumps),
              'cycle_total_brightness_ratio': max(brightness) / min(brightness),
              'selected_raw_unchanged': True, 'encoded_pixels_equal_gpu': True, 'native_scale_export_exact': True,
              'runtime_integration': False, 'manual_art_acceptance': 'open'}
    (ROOT / 'validation.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
    print('PASS: 3 jobs,51 raw PNG,7 provider poses,12 exact GPU frames; runtime unchanged')


if __name__ == '__main__':
    validate()
