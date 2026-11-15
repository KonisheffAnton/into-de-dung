"""Check the five raw clips against saved API responses and presentation artifacts."""
from pathlib import Path
import base64
import hashlib
import json
import re
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path('D:/Codex/home/generated_images/rvanoukh-abilities-five-20261115')

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(data):
    return hashlib.sha256(data).hexdigest()

def decode(value):
    return base64.b64decode(value['base64'].split(',')[-1], validate=True)

def main():
    requests = read(ROOT / 'requests.json')
    assert len(requests) == 5 and {r['key'] for r in requests} == {f'ability-{i}' for i in range(1, 6)}
    input_bytes = (ROOT / 'model/input-256.png').read_bytes()
    original = ROOT.parent / 'rvanoukh-animation-20261115/model/input-256.png'
    assert input_bytes == original.read_bytes()
    manifest = read(ROOT / 'model/input-manifest.json')
    assert sha(input_bytes) == manifest['input_sha256']
    assert (ROOT / 'model/source-full.png').read_bytes() == (REPO / manifest['source']).read_bytes()
    initial = np.asarray(Image.open(original).convert('RGBA'))
    records, quality_issues = [], []
    for row in requests:
        key = row['key']
        assert row['kind'] == 'ability' and row['attack'] is False and row['gameplay_mechanic_defined'] is False
        assert row['loop'] is False and row['return_to_first'] is True
        folder = JOBS / 'pixellab' / key
        request, admission, job = (read(folder / f) for f in ('request.json', 'admission.json', 'job-latest.json'))
        assert (folder / 'submit-started.json').is_file()
        assert job['status'] == 'completed' and job['id'] == admission['background_job_id']
        assert request['description'] == row['prompt'] and 0 < len(row['prompt']) <= 1000
        assert request['frame_count'] == 32 and request['seed'] == row['seed']
        assert request['no_background'] is True and request['enhance_prompt'] is False
        assert all(request[k] == v for k, v in row['captions'].items())
        assert decode(request['first_frame']) == decode(request['last_frame']) == input_bytes
        clip = read(ROOT / 'pixellab' / key / 'clip.json')
        assert clip['actual_frames'] == 33 and clip['canvas'] == [256, 256] and clip['anchor'] == [128, 200]
        assert clip['job_id'] == job['id'] and clip['durations_ms'] == [70] * 32 + [500]
        assert clip['total_duration_ms'] == 2740 and clip['integration'] is False
        sheet_path = ROOT / clip['spritesheet']['file']
        sheet = Image.open(sheet_path).convert('RGBA')
        assert sheet.size == (2048, 1280) and sha(sheet_path.read_bytes()) == clip['spritesheet']['sha256']
        items = job['last_response']['images']
        assert len(items) == len(clip['frame_records']) == 33
        actual_paths = list((ROOT / 'pixellab' / key / 'frames').glob('*.png'))
        assert len(actual_paths) == 33
        frames, edges, heights = [], [], []
        for i, item in enumerate(items):
            entry = clip['frame_records'][i]
            data = (ROOT / entry['file']).read_bytes()
            assert data == decode(item) and sha(data) == entry['sha256']
            image = Image.open(ROOT / entry['file'])
            assert image.format == 'PNG' and image.mode == 'RGBA' and image.size == (256, 256)
            alpha = image.getchannel('A')
            box = alpha.getbbox()
            assert box is not None and alpha.getextrema() == (0, 255)
            edge = box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248
            assert entry['alpha_bbox'] == list(box) and entry['alpha_margin_violation'] == edge
            if edge:
                edges.append(i)
            visible_box = alpha.point(lambda a: 255 if a >= 8 else 0).getbbox()
            heights.append(visible_box[3] - visible_box[1])
            cell = sheet.crop(((i % 8) * 256, (i // 8) * 256, (i % 8 + 1) * 256, (i // 8 + 1) * 256))
            assert image.tobytes() == cell.tobytes()
            frames.append(np.asarray(image))
        first_visible = (frames[0][:, :, 3] > 0) | (initial[:, :, 3] > 0)
        assert np.array_equal(frames[0][first_visible], initial[first_visible])
        last_diff = int(np.count_nonzero(np.any(frames[-1] != initial, axis=2)))
        assert bool(last_diff == 0) == clip['last_frame_returns_to_input_rgba']
        assert edges == clip['raw_alpha_edge_frames']
        if edges:
            quality_issues.append({'key': key, 'edge_frames': edges})
        gif_path = ROOT / clip['preview_gif']['file']
        assert sha(gif_path.read_bytes()) == clip['preview_gif']['sha256']
        with Image.open(gif_path) as gif:
            durations = []
            for i in range(gif.n_frames):
                gif.seek(i)
                durations.append(gif.info['duration'])
            assert sum(durations) == 2740 and durations == clip['preview_gif']['durations_ms']
        records.append({'key': key, 'frames': 33, 'raw_api_bytes_exact': True, 'sheet_pixels_exact': True,
                        'edge_frames': edges, 'visible_height_range': [min(heights), max(heights)],
                        'last_rgba_differing_pixels': last_diff, 'preview_ms': 2740})
    html = (ROOT / 'gallery.html').read_text(encoding='utf-8')
    assert 'без атак' in html.lower()
    for row in requests:
        assert row['key'] in html and row['name'] in html
    embedded = re.findall(r'data:image/png;base64,([A-Za-z0-9+/=]+)', html)
    sheet_hashes = {sha((ROOT / 'pixellab' / r['key'] / 'spritesheet.png').read_bytes()) for r in requests}
    embedded_hashes = {sha(base64.b64decode(s)) for s in embedded}
    assert sheet_hashes <= embedded_hashes
    with Image.open(ROOT / 'preview.gif') as gif:
        preview_ms = 0
        for i in range(gif.n_frames):
            gif.seek(i)
            preview_ms += gif.info['duration']
        assert preview_ms == 2740
        preview_size, preview_count = list(gif.size), gif.n_frames
    baseline = read(ROOT / 'baseline.json')
    assert all(sha((REPO / p).read_bytes()) == digest for p, digest in baseline['foreign_sha256'].items())
    report = {'status': 'PASS', 'scope': 'raw provenance, canvas, alpha, sheet cells, source, timing, embedded sheets, protected files',
              'quality_status': 'EDGE_FAIL' if quality_issues else 'EDGES_PASS', 'quality_issues': quality_issues,
              'clips': records, 'raw_pngs_verified': 165, 'embedded_pngs': len(embedded),
              'preview_gif': {'size': preview_size, 'frames': preview_count, 'duration_ms': preview_ms},
              'foreign_files_unchanged': len(baseline['foreign_sha256']), 'runtime_integration': False,
              'open': ['user choice', 'exact return seam', 'gameplay meaning', 'runtime/F5']}
    (ROOT / 'validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'clips'}, ensure_ascii=False))

if __name__ == '__main__':
    main()
