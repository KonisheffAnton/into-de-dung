"""Сверить фактический usage двенадцати клипов с балансом до и после."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-subtle-animation-20261105')


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main() -> None:
    manifest = read(ROOT / 'pixellab-validation.json')
    if manifest['expected'] != manifest['completed'] or manifest['expected'] != 12 or not manifest['complete']:
        raise SystemExit('Нужны все 12 completed')
    before = read(JOBS / 'balance-before.json')['subscription']
    after = read(JOBS / 'balance-after-all.json')['subscription']
    clips = []
    for row in manifest['clips']:
        usage = row['usage']
        if usage['type'] != 'generations' or usage['generations'] <= 0:
            raise SystemExit(f'Некорректный usage {row["key"]}')
        clips.append({'key': row['key'], 'endpoint': row['endpoint'], 'job_id': row['job_id'],
                      'requested_frame_count': row['frame_count'], 'returned_frames': row['actual_frames'],
                      'generations': usage['generations']})
    total = sum(row['generations'] for row in clips)
    if total != 60 or before['generations'] - after['generations'] != total:
        raise SystemExit('Сумма usage не совпала с разницей баланса')
    report = {'status': 'PASS', 'clips': len(clips), 'total_generations': total,
              'balance_before': before['generations'], 'balance_after': after['generations'],
              'balance_type': before['type'], 'plan': before['plan'], 'credits_usd': 0.0,
              'clips_detail': clips}
    (ROOT / 'usage.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in ('status', 'clips', 'total_generations', 'balance_before', 'balance_after')}))


if __name__ == '__main__':
    main()
