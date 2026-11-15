"""Prepare a bounded nine-clip batch; never submit or overwrite attempted jobs."""
from pathlib import Path
import base64
import hashlib
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('D:/Codex/home/generated_images/rvanoukh-animation-20261115')
CAPTIONS = {
    'direction': 'south-east',
    'view': 'low top-down',
    'subject_description': 'A small pale grey beastlike hunched goblin with a massive brow, torn pointed ears, short bent legs, long clawed arms, three yellow blisters on its hump, a ragged brown loincloth with holes, and one short iron-headed club in its right hand',
    'initial_pose': 'Deeply crouched facing screen right, huge head low ahead of its hump, both clawed feet planted, free clawed hand near the ground, other hand holding the short club diagonally across the belly',
}


def main():
    source = ROOT / 'model/input-256.png'
    frame = {'base64': base64.b64encode(source.read_bytes()).decode('ascii'), 'format': 'png'}
    rows = json.loads((ROOT / 'clip-prompts.json').read_text(encoding='utf-8'))['clips']
    expected = {f'{kind}-{variant}' for kind in ('idle', 'ability', 'death') for variant in range(1, 4)}
    assert {f"{r['kind']}-{r['variant']}" for r in rows} == expected and len(rows) == 9
    for row in rows:
        folder = JOBS / 'pixellab' / f"{row['kind']}-{row['variant']}"
        if (folder / 'submit-started.json').exists():
            raise SystemExit(f'Already attempted: {folder.name}; do not overwrite requests')
        assert 1 <= len(row['prompt']) <= 1000
    prepared = []
    for index, row in enumerate(rows):
        key = f"{row['kind']}-{row['variant']}"
        folder = JOBS / 'pixellab' / key
        folder.mkdir(parents=True, exist_ok=True)
        request = {'first_frame': frame, 'description': row['prompt'], 'frame_count': 32,
                   'seed': 2026111501 + index, 'no_background': True, 'enhance_prompt': False, **CAPTIONS}
        if row['kind'] != 'death':
            request['last_frame'] = frame
        (folder / 'request.json').write_text(json.dumps(request), encoding='utf-8')
        (folder / 'prompt.txt').write_text(row['prompt'], encoding='utf-8')
        prepared.append({**row, 'key': key, 'seed': request['seed'], 'frame_count': 32,
                         'expected_frames': 33, 'endpoint': 'animate-pixminimax',
                         'loop': row['kind'] == 'idle', 'return_to_first': row['kind'] != 'death',
                         'input': 'model/input-256.png', 'input_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
                         'captions': CAPTIONS})
    (ROOT / 'requests.json').write_text(json.dumps(prepared, ensure_ascii=False, indent=2), encoding='utf-8')
    print('Prepared nine requests; no submissions')


if __name__ == '__main__':
    main()
