"""Native static cutouts in; unchanged PixelLab poses out. No local motion synthesis."""
from pathlib import Path
import argparse, base64, hashlib, json
import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def write(path, value):
    temp = path.with_name(path.name + '.tmp')
    temp.write_text(json.dumps(value, indent=2) + '\n', encoding='utf-8', newline='\n')
    temp.replace(path)

def prepare(group_key, frame_count=32, replacement=False):
    inventory = json.loads((REPO / 'test_reports/fire-single-tongue-20261106/field-inputs.json').read_text())
    style = group_key[4:6]
    group = next(g for g in inventory['styles'][style]['groups'] if g['key'] == group_key)
    source = REPO / group['input_path']
    assert sha(source) == group['input_sha256']
    im = Image.open(source).convert('RGBA')
    assert im.size == (group['crop_size'],) * 2 and group['crop_size'] in (128, 256)
    assert im.getchannel('A').getextrema()[0] == 0
    key = group_key.replace('-', '-field')
    replaces = key if replacement else None
    if replacement:
        resolution = json.loads((JOBS/'pixellab'/key/'resolution.json').read_text())
        assert resolution['kind'] == 'unavailable_after_404' and resolution['http_status'] == 404
        key += 'r1'
    out = ROOT / 'requests' / key
    job = JOBS / 'pixellab' / key
    assert not out.exists() and not job.exists(), 'Immutable request already exists'
    blob = {'type': 'base64', 'format': 'png', 'base64': base64.b64encode(source.read_bytes()).decode('ascii')}
    description = ('The existing small curled ends of this single painted shape softly bend a few pixels sideways, then return. '
        'Its broad lower body stays pinned in exactly the same position. The whole shape keeps its original flattened height '
        'and horizontal footprint. One smooth restrained sway. Maintain constant color, light and opacity. '
        'Nothing grows, appears, breaks away or disappears. Fixed camera and transparent background.')
    request = {'first_frame': blob, 'last_frame': blob, 'description': description, 'frame_count': frame_count,
        'seed': 202611060000 + int(style) * 100 + int(group_key[-2:]), 'no_background': True,
        'drift_threshold': 0, 'enhance_prompt': False, 'direction': 'east', 'view': 'high top-down',
        'subject_description': 'One small flattened orange and yellow curved painted brushstroke on transparency',
        'initial_pose': 'A low horizontal painted silhouette with a fixed broad lower body and softly curved small upper ends'}
    out.mkdir(parents=True); job.mkdir(parents=True)
    write(out / 'request.json', request)
    (job / 'request.json').write_bytes((out / 'request.json').read_bytes())
    meta = {'key': key, 'group': group, 'endpoint': 'animate-pixminimax',
        'input': source.relative_to(ROOT).as_posix(), 'input_sha256': sha(source),
        'input_size': list(im.size), 'request_sha256': sha(job / 'request.json'), 'requested_frames': frame_count,
        'native_crop_no_resize': True, 'local_motion_generation': False,
        'source_sha256': inventory['styles'][style]['source_sha256']}
    if replaces: meta['replaces_unavailable_job'] = replaces
    write(out / 'request-metadata.json', meta)
    print(json.dumps({'prepared': key, 'size': im.size, 'input_sha256': sha(source)}))

def extract(key):
    meta = json.loads((ROOT / 'requests' / key / 'request-metadata.json').read_text())
    job = JOBS / 'pixellab' / key
    outer = json.loads((job / 'job-latest.json').read_text(encoding='utf-8-sig'))
    assert outer['status'] == 'completed'
    res = outer['last_response']; out = ROOT / 'results' / key; raw = out / 'raw'
    raw.mkdir(parents=True, exist_ok=True)
    source = np.array(Image.open(ROOT / meta['input']).convert('RGBA'))
    own_core = np.array(Image.open(REPO / meta['group']['core_mask_path']).convert('L')) > 0
    n = len(res['images']); size = source.shape[0]
    contact = Image.new('RGBA', (size * 4, (size + 22) * ((n + 3) // 4)), (32, 36, 44, 255))
    d = ImageDraw.Draw(contact); rows = []; arrays = []
    for i, item in enumerate(res['images']):
        path = raw / f'frame-{i:02d}.png'; data = base64.b64decode(item['base64'])
        if path.exists(): assert path.read_bytes() == data, 'Raw provider bytes changed'
        else: path.write_bytes(data)
        im = Image.open(path).convert('RGBA'); assert im.size == tuple(meta['input_size'])
        v = np.array(im); arrays.append(v)
        alpha = v[:, :, 3] > 127; orig = source[:, :, 3] > 127
        premul = v[:, :, :3].astype(float) * v[:, :, 3, None] / 255
        orig_p = source[:, :, :3].astype(float) * source[:, :, 3, None] / 255
        rows.append({'frame': i, 'sha256': sha(path), 'alpha_bbox': im.getbbox(),
            'alpha_pixels': int(alpha.sum()), 'alpha_xor_source': int((alpha ^ orig).sum()),
            'uncovered_original_core': int((own_core & (v[:, :, 3] == 0)).sum()),
            'visible_rgb_change_gt8': int(np.any(np.abs(premul - orig_p) > 8, axis=2).sum()),
            'premultiplied_rgb_sum': [round(float(x), 3) for x in premul.sum(axis=(0, 1))]})
        x, y = i % 4 * size, i // 4 * (size + 22)
        contact.alpha_composite(im, (x, y)); d.text((x + 4, y + size + 3), str(i), fill='white')
    contact.save(out / 'contact-native.png')
    report = {'key': key, 'requested_frames': meta['requested_frames'], 'returned_frames': n,
        'response_external': str(job / 'job-latest.json'), 'response_sha256': sha(job / 'job-latest.json'),
        'billing_usage': res.get('billing_usage'), 'frames': rows,
        'first_last_rgba_equal': bool(np.array_equal(arrays[0], arrays[-1])),
        'raw_pixels_modified': False, 'art_acceptance': False}
    write(out / 'manifest.json', report)
    print(json.dumps({'extracted': key, 'frames': n, 'billing_usage': res.get('billing_usage'),
        'max_core_uncovered': max(r['uncovered_original_core'] for r in rows)}))

if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('action', choices=('prepare', 'extract')); p.add_argument('keys', nargs='+'); p.add_argument('--frames', type=int, choices=(16,32), default=32); p.add_argument('--replacement', action='store_true')
    a = p.parse_args()
    for key in a.keys:
        if a.action == 'prepare': prepare(key, a.frames, a.replacement)
        else: extract(key)
