"""Меняет только ещё не отправленные запросы на короткий позитивный V3 prompt."""

from pathlib import Path
import hashlib
import json
import os


ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-painted-sway-20261105')
TARGETS = {'fire24-03': 4, 'fire29-01': 8, 'fire29-02': 8, 'fire29-03': 4}
ACTION = (
    'Nearly still finished 2D painting. Gently bend ONLY the already-painted '
    'orange-red brush-stroke tips horizontally by one pixel and back. Every existing '
    'stroke stays attached at its base, keeps its original height, silhouette, '
    'position, color and brightness. Keep the stone and transparent background '
    'perfectly still. Match the supplied first and last picture.'
)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_bytes(path: Path, data: bytes) -> None:
    temporary = path.with_name(path.name + '.tmp')
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main() -> None:
    manifest_path = ROOT / 'requests.json'
    history_path = ROOT / 'prompt-revision-01-positive.json'
    if history_path.exists():
        raise SystemExit('Revision already recorded')
    before_manifest = manifest_path.read_bytes()
    rows = json.loads(before_manifest)
    by_key = {row['key']: row for row in rows}
    if len(rows) != 12 or not TARGETS.keys() <= by_key.keys():
        raise SystemExit('Unexpected 12-key manifest')
    old_requests = {}
    new_requests = {}
    for key, frame_count in TARGETS.items():
        folder = JOBS / 'pixellab' / key
        if any((folder / name).exists() for name in ('submit-started.json', 'admission.json', 'job-latest.json', 'request-original-draft.json')):
            raise SystemExit(f'POST barrier or backup already exists: {key}')
        path = folder / 'request.json'
        old = path.read_bytes()
        if sha(old) != by_key[key]['request_sha256']:
            raise SystemExit(f'Original draft SHA mismatch: {key}')
        request = json.loads(old)
        if (request['first_frame'] != request['last_frame'] or request['frame_count'] != 8
                or by_key[key]['endpoint'] != 'animate-with-text-v3'):
            raise SystemExit(f'Original V3 contract mismatch: {key}')
        request['action'] = ACTION
        request['frame_count'] = frame_count
        if set(request) != {'first_frame', 'last_frame', 'action', 'frame_count', 'seed', 'no_background', 'drift_threshold', 'enhance_prompt'}:
            raise SystemExit(f'Unexpected request fields: {key}')
        encoded = json.dumps(request).encode('utf-8')
        old_requests[key], new_requests[key] = old, encoded
        by_key[key].update({'prompt': ACTION, 'frame_count': frame_count, 'request_sha256': sha(encoded),
                            'expected_frames': None,
                            'expected_frames_policy': 'Read count from admitted completed response; do not assume requested count plus one'})
    after_manifest = (json.dumps(rows, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    history = {
        'reason': 'U requires barely moving already-painted contours; first V3 outputs redrew the top',
        'source': 'root technical steering after first V3 full-cycle review',
        'only_unsubmitted_keys': list(TARGETS),
        'old_manifest_sha256': sha(before_manifest), 'new_manifest_sha256': sha(after_manifest),
        'action': ACTION, 'action_length': len(ACTION),
        'changes': {key: {'old_request_sha256': sha(old_requests[key]),
                          'new_request_sha256': sha(new_requests[key]),
                          'old_frame_count': 8, 'new_frame_count': TARGETS[key],
                          'original_draft_backup': f'C:/Users/Aston/.codex/generated_images/fire-painted-sway-20261105/pixellab/{key}/request-original-draft.json'}
                    for key in TARGETS},
    }
    # Runner is stopped; check every barrier again immediately before changing a request.
    for key in TARGETS:
        folder = JOBS / 'pixellab' / key
        if (folder / 'submit-started.json').exists() or (folder / 'admission.json').exists():
            raise SystemExit(f'POST began during revision: {key}')
        if (folder / 'request.json').read_bytes() != old_requests[key]:
            raise SystemExit(f'Draft changed during revision: {key}')
        (folder / 'request-original-draft.json').write_bytes(old_requests[key])
        atomic_bytes(folder / 'request.json', new_requests[key])
        (folder / 'prompt.txt').write_text(ACTION, encoding='utf-8')
    atomic_bytes(manifest_path, after_manifest)
    history_path.write_text(json.dumps(history, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'changed': list(TARGETS), 'frame_counts': TARGETS,
                      'action_length': len(ACTION), 'post': False}))


if __name__ == '__main__':
    main()
