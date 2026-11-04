"""Показать локальное состояние очереди без сетевых запросов."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/pixellab')


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig')) if path.exists() else {}


def main() -> None:
    rows = read(ROOT / 'requests.json')
    states = {'completed': [], 'active': [], 'pending': [], 'failed': [], 'cancelled': [], 'ambiguous': []}
    active_ids = {}
    for row in rows:
        key = row['key']
        folder = JOBS / key
        status = read(folder / 'job-latest.json').get('status')
        admitted_id = read(folder / 'admission.json').get('background_job_id')
        if status in ('completed', 'failed', 'cancelled'):
            states[status].append(key)
        elif admitted_id:
            states['active'].append(key)
            active_ids[key] = admitted_id
        elif (folder / 'submit-started.json').exists():
            states['ambiguous'].append(key)
        else:
            states['pending'].append(key)
    print(json.dumps({**states, 'pending_count': len(states['pending']), 'active_ids': active_ids}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
