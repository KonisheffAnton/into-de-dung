"""Сверить фактический usage всех клипов с balance GET до и после серии."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104')


def read(path: Path) -> dict:
    return json.loads(path.read_text(encoding='utf-8-sig'))


def main() -> None:
    manifest = read(ROOT / 'pixellab-validation.json')
    assert manifest['expected'] == manifest['completed'] == 30 and manifest['complete']
    before = read(JOBS / 'balance-before.json')['subscription']
    after = read(JOBS / 'balance-after-all.json')['subscription']
    clips = []
    for row in manifest['clips']:
        usage = row['usage']
        assert usage['type'] == 'generations' and usage['generations'] > 0
        clips.append({'key': row['key'], 'endpoint': row['endpoint'], 'job_id': row['job_id'],
                      'requested_frame_count': row['frame_count'], 'returned_frames': row['actual_frames'],
                      'generations': usage['generations']})
    total = sum(row['generations'] for row in clips)
    assert total == 153 and before['generations'] - after['generations'] == total
    report = {'status': 'PASS', 'clips': len(clips), 'total_generations': total,
              'balance_before': before['generations'], 'balance_after': after['generations'],
              'balance_type': before['type'], 'plan': before['plan'], 'credits_usd': 0.0,
              'clips_detail': clips}
    (ROOT / 'usage.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: report[key] for key in ('status', 'clips', 'total_generations', 'balance_before', 'balance_after')}))


if __name__ == '__main__':
    main()
