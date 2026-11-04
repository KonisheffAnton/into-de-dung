"""Однократная ревизия только 14 fire-запросов без submit-started."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/pixellab')
PROVENANCE = ROOT / 'prompt-revision-01.json'
TARGETS = [f'fire23-{i:02d}' for i in range(2, 6)] + [
    f'{source}-{i:02d}' for source in ('fire24', 'fire22') for i in range(1, 6)]
CAPTIONS = {
    'direction': 'south-east',
    'view': 'low top-down',
    'subject_description': 'A fixed isometric stone tile with a flat glowing orange surface texture confined to its diamond top',
    'initial_pose': 'Exact original tile silhouette; orange embers lie flat on the top, with exposed masonry side faces fixed',
}
MOTIONS = [
    ('Тихое мерцание плёнки', 'Very small existing orange patches brighten and dim at staggered positions, like a quiet ember shimmer. No patch moves or changes shape.'),
    ('Медленные световые полосы', 'A faint brightness pulse passes across existing orange surface pixels in broad low bands, then returns to the starting palette. No shapes move.'),
    ('Редкие тёплые точки', 'Sparse existing orange flecks brighten briefly in alternating places with long soft intervals; each returns to its original colour.'),
    ('Плавная диагональ', 'A very subtle diagonal wave of warm colour shifts through the existing flat surface texture and fades, without moving any outline.'),
    ('Неровная пульсация', 'Several small groups of existing orange pixels cycle gently through nearby warm shades at irregular offsets, then settle together.'),
]
GUARD = ('The animation is strictly 2D in-place palette and brightness cycling on the original diamond top only. '
         'Preserve the exact original silhouette and alpha envelope in every frame. Stone top edges, cracks and all masonry side-face pixels remain still. '
         'No vertical expansion, rising tongues, flames, sparks, smoke, new shapes, redrawing, translation, camera motion or motion across stone sides. '
         'Flat glowing orange surface texture throughout. Seamless return to the exact starting appearance.')


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    if PROVENANCE.exists():
        raise SystemExit('Revision already recorded; do not apply twice')
    requests_path = ROOT / 'requests.json'
    rows = json.loads(requests_path.read_text(encoding='utf-8'))
    assert len(rows) == 30 and [r['key'] for r in rows if r['key'] in TARGETS] == TARGETS
    original_manifest_sha = sha(requests_path)
    changed = []
    for row in rows:
        key = row['key']
        folder = JOBS / key
        if key not in TARGETS:
            continue
        if (folder / 'submit-started.json').exists() or (folder / 'admission.json').exists():
            raise SystemExit(f'Already submitted: {key}')
        request_path = folder / 'request.json'
        original = json.loads(request_path.read_text(encoding='utf-8'))
        assert sha(request_path) == row['request_sha256']
        name, motion = MOTIONS[row['variant'] - 1]
        prompt = f'{motion} {GUARD}'
        assert 0 < len(prompt) <= 1000
        before = {'key': key, 'name': row['name'], 'prompt': row['prompt'],
                  'captions': row['captions'], 'request_sha256': row['request_sha256']}
        original.update(CAPTIONS)
        original['description'] = prompt
        request_path.write_text(json.dumps(original), encoding='utf-8')
        (folder / 'prompt.txt').write_text(prompt, encoding='utf-8')
        row['name'] = name
        row['prompt'] = prompt
        row['captions'] = CAPTIONS
        row['request_sha256'] = sha(request_path)
        changed.append({'before': before,
                        'after': {'name': name, 'prompt': prompt, 'captions': CAPTIONS,
                                  'request_sha256': row['request_sha256']}})
    assert [item['before']['key'] for item in changed] == TARGETS
    requests_path.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    provenance = {'revision': 1, 'reason': 'Completed fire probes produced rising flames and changes on masonry sides',
                  'original_requests_sha256': original_manifest_sha,
                  'revised_requests_sha256': sha(requests_path),
                  'unchanged_submitted': ['fire29-01', 'fire29-02', 'fire29-03', 'fire29-04', 'fire29-05', 'fire23-01'],
                  'unchanged_pending': [f'{source}-{i:02d}' for source in ('acidfilm', 'caltrops03') for i in range(1, 6)],
                  'changed': changed}
    PROVENANCE.write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'revision': 1, 'changed': len(changed), 'unchanged_submitted': 6,
                      'unchanged_pending': 10, 'max_prompt_length': max(len(c['after']['prompt']) for c in changed)}))


if __name__ == '__main__':
    main()
