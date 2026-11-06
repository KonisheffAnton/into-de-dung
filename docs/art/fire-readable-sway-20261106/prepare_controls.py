"""Two controlled amplitude prompts; preserve input, seed, palette settings and frame count."""
from pathlib import Path
import hashlib
import json
import os
import argparse

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]
OLD = ROOT.parent / 'fire-single-tongue-20261106'
EXTERNAL = Path('C:/Users/Aston/.codex/generated_images/fire-readable-sway-20261106')
DESCRIPTION = (
    'The EXISTING curled tips of this one low painted shape visibly bend sideways and gently return. '
    'Each existing tip travels about 6 to 8 pixels sideways, a clearly readable but small bend. '
    'Show intermediate curved poses between the neutral and leaning tips. '
    'The broad lower body and all roots remain pinned in exactly the same place. '
    'Preserve the original low flattened height and number of painted curls. '
    'No tip rises higher, stretches upward, sprouts, shoots out, or breaks away. '
    'Maintain the original pale yellow, orange, and ochre colors, constant light and opacity. '
    'Only gently flex the existing drawn ends; nothing appears or disappears. Fixed camera, transparent background.'
)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--batch', choices=['initial','two_more_24'], default='initial')
    args = parser.parse_args()
    sources = ([('fire24-short01', 'fire24-strong01'), ('fire29-field02r1', 'fire29-strong01')]
               if args.batch == 'initial' else [('fire24-short02', 'fire24-strong02'), ('fire24-field20', 'fire24-strong03')])
    for old_key, key in sources:
        old_request_path = OLD / 'requests' / old_key / 'request.json'
        request = json.loads(old_request_path.read_text())
        old_meta = json.loads((old_request_path.parent / 'request-metadata.json').read_text())
        before = dict(request)
        request['description'] = DESCRIPTION
        assert [k for k in request if request[k] != before[k]] == ['description']
        assert request['frame_count'] == 16
        out = ROOT / 'requests' / key
        job = EXTERNAL / 'pixellab' / key
        assert not out.exists() and not job.exists(), 'Prepared controls are immutable'
        out.mkdir(parents=True); job.mkdir(parents=True)
        payload = (json.dumps(request, indent=2) + '\n').encode()
        (out / 'request.json').write_bytes(payload)
        (job / 'request.json').write_bytes(payload)
        input_path = REPO / old_meta['group']['input_path']
        assert sha(input_path) == old_meta['input_sha256']
        meta = {'key': key, 'group': old_meta['group'], 'endpoint': 'animate-pixminimax',
                'input': Path(os.path.relpath(input_path, ROOT)).as_posix(),
                'input_sha256': sha(input_path), 'input_size': old_meta['input_size'],
                'source_sha256': old_meta['source_sha256'], 'request_sha256': sha(out / 'request.json'),
                'requested_frames': 16, 'native_crop_no_resize': True, 'local_motion_generation': False,
                'controlled_comparison_to': old_key, 'old_request_sha256': sha(old_request_path),
                'changed_payload_fields': ['description'], 'requested_tip_sideways_native_px': [6,8]}
        (out / 'request-metadata.json').write_text(json.dumps(meta,indent=2)+'\n',encoding='utf-8',newline='\n')
        print(json.dumps({'prepared':key,'control':old_key,'changed_fields':['description']}))
