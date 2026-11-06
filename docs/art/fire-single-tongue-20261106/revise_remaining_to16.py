"""Revise only unsubmitted field-batch drafts from 32 to 16 frames.

No API calls. Submitted/admitted keys are immutable. The old request bytes are
archived outside the repository before either request copy is replaced.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
from pathlib import Path

PACKAGE = Path(__file__).resolve().parent
ROOT = PACKAGE.parents[2]
JOBS = Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106')
PLAN32 = PACKAGE / 'field-batch-plan.json'
PLAN16 = PACKAGE / 'field-batch-plan16.json'
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/draft-revision16.json'
REASON = 'Successful short16 color control preserved the original yellow/orange palette on fire24-field29; lower all remaining unsubmitted field drafts to 16 requested frames.'
PROTECTED_NAMES = {'submit-started.json', 'admission.json', 'job-latest.json', 'response-raw.json'}


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha(path: Path) -> str:
    return sha_bytes(path.read_bytes())


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8')


def replace_atomic(path: Path, data: bytes) -> None:
    temp = path.with_name(path.name + '.revision16.tmp')
    assert not temp.exists(), f'stale temp: {temp}'
    with temp.open('xb') as file:
        file.write(data)
        file.flush()
        os.fsync(file.fileno())
    os.replace(temp, path)


def revise_one_field(raw: bytes) -> bytes:
    pattern = rb'("frame_count"\s*:\s*)32(\s*[,}])'
    edited, count = re.subn(pattern, lambda m: m.group(1) + b'16' + m.group(2), raw)
    assert count == 1, 'Expected exactly one frame_count:32 token'
    old, new = json.loads(raw), json.loads(edited)
    assert old['frame_count'] == 32 and new['frame_count'] == 16
    assert {k: v for k, v in old.items() if k != 'frame_count'} == {k: v for k, v in new.items() if k != 'frame_count'}
    assert edited.replace(b'"frame_count": 16', b'"frame_count": 32') == raw, 'Unexpected byte difference'
    return edited


def paths(key: str) -> tuple[Path, Path, Path, Path]:
    local = PACKAGE / 'requests' / key / 'request.json'
    meta = PACKAGE / 'requests' / key / 'request-metadata.json'
    job = JOBS / 'pixellab' / key
    return local, meta, job / 'request.json', job


def guard_job(job: Path, *, admitted: bool) -> None:
    assert job.is_dir(), f'missing job dir: {job}'
    present = {name for name in PROTECTED_NAMES if (job / name).exists()}
    if admitted:
        assert 'submit-started.json' in present, f'expected admitted barrier: {job}'
    else:
        assert not present, f'refuse admitted/ambiguous job: {job}: {sorted(present)}'
        assert {entry.name for entry in job.iterdir()} == {'request.json'}, f'unexpected external files in unsubmitted job: {job}'


def inspect() -> tuple[dict, list[dict], list[str]]:
    plan = json.loads(PLAN32.read_text(encoding='utf-8'))
    keys = plan['keys']
    assert len(keys) == 50 and len(set(keys)) == 50 and plan['frames_requested_each'] == 32
    prepared, admitted = [], []
    for key in keys:
        local, meta_path, external, job = paths(key)
        assert local.is_file() and meta_path.is_file() and external.is_file()
        barrier = (job / 'submit-started.json').exists()
        guard_job(job, admitted=barrier)
        if barrier:
            admitted.append(key)
            continue
        raw = local.read_bytes()
        assert raw == external.read_bytes(), f'local/external request mismatch: {key}'
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        assert meta['key'] == key and meta['requested_frames'] == 32 and meta['request_sha256'] == sha_bytes(raw)
        assert 'draft_revision16' not in meta
        revised = revise_one_field(raw)
        archive = JOBS / 'draft-revisions' / key / 'request32.json'
        if archive.exists():
            assert archive.read_bytes() == raw, f'archive mismatch: {key}'
        prepared.append({'key': key, 'local': local, 'metadata': meta_path, 'external': external,
                         'job': job, 'archive': archive, 'old_bytes': raw, 'new_bytes': revised,
                         'old_sha256': sha_bytes(raw), 'new_sha256': sha_bytes(revised), 'old_metadata_sha256': sha(meta_path)})
    assert len(prepared) == 44 and len(admitted) == 6, f'unexpected counts: {len(prepared)} pending, {len(admitted)} admitted'
    return plan, prepared, admitted


def apply() -> None:
    plan, prepared, admitted = inspect()  # Entire batch preflight before first mutation.
    records = []
    for item in prepared:
        key, job = item['key'], item['job']
        guard_job(job, admitted=False)  # Repeat barrier check at the mutation boundary.
        archive = item['archive']
        archive.parent.mkdir(parents=True, exist_ok=True)
        if not archive.exists():
            with archive.open('xb') as file:
                file.write(item['old_bytes'])
                file.flush()
                os.fsync(file.fileno())
        assert archive.read_bytes() == item['old_bytes']
        metadata = json.loads(item['metadata'].read_text(encoding='utf-8'))
        assert metadata['request_sha256'] == item['old_sha256'] and metadata['requested_frames'] == 32
        metadata['request_sha256'] = item['new_sha256']
        metadata['requested_frames'] = 16
        metadata['draft_revision16'] = {
            'status': 'unsubmitted_revised_draft', 'reason': REASON,
            'old_request_sha256': item['old_sha256'], 'new_request_sha256': item['new_sha256'],
            'old_request_archive_external': str(archive),
            'only_payload_field_changed': 'frame_count', 'old_value': 32, 'new_value': 16,
        }
        guard_job(job, admitted=False)
        replace_atomic(item['local'], item['new_bytes'])
        guard_job(job, admitted=False)
        replace_atomic(item['external'], item['new_bytes'])
        replace_atomic(item['metadata'], json_bytes(metadata))
        assert item['local'].read_bytes() == item['external'].read_bytes() == item['new_bytes']
        assert sha(item['local']) == metadata['request_sha256']
        records.append({'key': key, 'old_request_sha256': item['old_sha256'],
                        'new_request_sha256': item['new_sha256'],
                        'old_metadata_sha256': item['old_metadata_sha256'],
                        'new_metadata_sha256': sha(item['metadata']),
                        'old_request_archive_external': str(archive),
                        'local_request': item['local'].relative_to(ROOT).as_posix(),
                        'external_request': str(item['external']),
                        'only_json_difference': {'frame_count': [32, 16]},
                        'both_revised_copies_byte_equal': True,
                        'admission_barrier_absent_at_revision': True})
    plan16 = {**plan, 'purpose': 'Only the 44 remaining unsubmitted source-stroke drafts, revised to 16 requested frames.',
              'frames_requested_each': 16, 'keys': [item['key'] for item in prepared],
              'source_plan_sha256': sha(PLAN32), 'admitted_untouched_keys': admitted,
              'revision_reason': REASON}
    PLAN16.write_bytes(json_bytes(plan16))
    report = {'status': 'completed_unsubmitted_draft_revision', 'reason': REASON,
              'source_plan': PLAN32.relative_to(ROOT).as_posix(), 'source_plan_sha256': sha(PLAN32),
              'plan16': PLAN16.relative_to(ROOT).as_posix(), 'plan16_sha256': sha(PLAN16),
              'revised_count': len(records), 'admitted_untouched_count': len(admitted),
              'admitted_untouched_keys': admitted, 'revisions': records,
              'provider_posts': 0}
    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_bytes(json_bytes(report))
    verify()
    print(json.dumps({'revised': len(records), 'admitted_untouched': len(admitted),
                      'plan16': PLAN16.relative_to(ROOT).as_posix()}))


def verify() -> None:
    plan = json.loads(PLAN16.read_text(encoding='utf-8'))
    report = json.loads(REPORT.read_text(encoding='utf-8'))
    assert len(plan['keys']) == report['revised_count'] == 44
    assert len(plan['admitted_untouched_keys']) == report['admitted_untouched_count'] == 6
    assert sha(PLAN16) == report['plan16_sha256']
    assert [r['key'] for r in report['revisions']] == plan['keys']
    for record in report['revisions']:
        key = record['key']
        local, meta_path, external, job = paths(key)
        guard_job(job, admitted=False)
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        old = Path(record['old_request_archive_external']).read_bytes()
        new = local.read_bytes()
        assert sha_bytes(old) == record['old_request_sha256']
        assert sha_bytes(new) == record['new_request_sha256'] == meta['request_sha256']
        assert new == external.read_bytes() == revise_one_field(old)
        assert meta['requested_frames'] == 16 and json.loads(new)['frame_count'] == 16
        assert meta['draft_revision16']['old_request_sha256'] == record['old_request_sha256']
    for key in plan['admitted_untouched_keys']:
        local, meta_path, external, job = paths(key)
        guard_job(job, admitted=True)
        meta = json.loads(meta_path.read_text(encoding='utf-8'))
        assert meta['requested_frames'] == 32 and 'draft_revision16' not in meta
        assert sha(local) == sha(external) == meta['request_sha256']


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['check', 'apply', 'verify'])
    args = parser.parse_args()
    if args.action == 'check':
        _, items, admitted_keys = inspect()
        print(json.dumps({'ready_to_revise': len(items), 'admitted_untouched': len(admitted_keys)}))
    elif args.action == 'apply':
        apply()
    else:
        verify()
        print(json.dumps({'verified_revised': 44, 'admitted_untouched': 6}))
