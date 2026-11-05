"""Submit each approved masked legacy request once, with at most three active POSTs."""

from __future__ import annotations

import argparse
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-masked-retry-20261105')
EXPECTED = [f'{source}-{variant:02d}'
            for source in ('fire22', 'fire23', 'fire24', 'fire29', 'caltrops03')
            for variant in range(1, 4)]


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8'))


def completed(key: str) -> bool:
    path = JOBS / 'pixellab' / key / 'response-raw.json'
    return path.is_file() and len(read(path).get('images', [])) == 4


def call(key: str) -> tuple[str, int, str]:
    result = subprocess.run(['pwsh', '-NoProfile', '-File', str(JOBS / 'invoke-pixellab.ps1'),
                             '-Action', 'Submit', '-Variant', key],
                            capture_output=True, text=True, encoding='utf-8', errors='replace')
    return key, result.returncode, result.stdout.strip()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--active', type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.active <= 3:
        raise SystemExit('Maximum active POSTs is three')
    rows = read(ROOT / 'requests.json')
    if [row['key'] for row in rows] != EXPECTED:
        raise SystemExit('Expected exact fifteen frozen keys')
    pending, blocked = [], []
    for key in EXPECTED:
        if completed(key):
            continue
        folder = JOBS / 'pixellab' / key
        if (folder / 'submit-started.json').exists():
            blocked.append(key)
        else:
            pending.append(key)
    if blocked:
        raise SystemExit(f'Ambiguous or incomplete prior POST, do not repeat: {blocked}')
    done = [key for key in EXPECTED if completed(key)]
    print(json.dumps({'already_completed': done, 'pending': pending, 'active_limit': args.active}), flush=True)
    next_index = 0
    running = {}
    stop = False
    with ThreadPoolExecutor(max_workers=args.active) as pool:
        while next_index < len(pending) or running:
            while not stop and next_index < len(pending) and len(running) < args.active:
                key = pending[next_index]
                next_index += 1
                running[pool.submit(call, key)] = key
            if not running:
                break
            future = next(as_completed(running))
            key = running.pop(future)
            try:
                key, code, stdout = future.result()
            except Exception as exc:
                code, stdout = 1, type(exc).__name__
            print(json.dumps({'key': key, 'exit_code': code, 'bridge': stdout,
                              'completed': completed(key)}), flush=True)
            if code != 0 or not completed(key):
                stop = True
                print(f'Blocked after {key}; finish active jobs, no new POSTs', flush=True)
    summary = {'expected': 15, 'completed': [key for key in EXPECTED if completed(key)],
               'blocked': [key for key in EXPECTED if (JOBS / 'pixellab' / key / 'submit-started.json').exists() and not completed(key)],
               'pending': [key for key in EXPECTED if not (JOBS / 'pixellab' / key / 'submit-started.json').exists()],
               'active_limit': args.active}
    (JOBS / 'batch-status.json').write_text(json.dumps(summary, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(summary), flush=True)
    if summary['blocked'] or summary['pending']:
        raise SystemExit(1)


if __name__ == '__main__':
    main()
