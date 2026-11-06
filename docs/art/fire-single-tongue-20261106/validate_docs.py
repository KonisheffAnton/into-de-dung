"""Bounded documentation preservation and local-link audit for this art slice.

Read-only outside two JSON reports. Designed to rerun after HANDOFF/HISTORY
closeout without scanning unrelated historical galleries or large payloads.
"""
from __future__ import annotations

from collections import Counter, defaultdict
import hashlib
import json
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[3]
PACKAGE = Path(__file__).resolve().parent
REPORT_DIR = ROOT / 'test_reports/fire-single-tongue-20261106'
BASE = '3ca6efe5f931525265480b14c3acc4a6d0be92f7'
ENTRY_DOCS = {
    'AGENTS.md': 5000,
    'docs/CODEX_HANDOFF.md': 2500,
    'docs/PROJECT_CONTEXT.md': 3500,
    'docs/CODEX_WORKFLOW.md': 4500,
}
PRESERVE_EXACT = ['AGENTS.md', 'docs/PROJECT_CONTEXT.md', 'docs/CODEX_WORKFLOW.md']
INSERT_ONLY = ['docs/ART_DIRECTION.md', 'docs/GRAPHICS_WORKFLOW.md']
TOP_LINK_DOCS = INSERT_ONLY + ['docs/CODEX_HANDOFF.md', 'docs/HISTORY.md']
CHARACTER_HEADING = '## Зафиксированная стилистика персонажей — 2026-11-03'
MARKDOWN_LINK = re.compile(r'!?\[[^\]\n]*\]\((<[^>]+>|[^)\n]+)\)')
HTML_ATTR = re.compile(r'\b(?:src|href)\s*=\s*(["\'])(.*?)\1', re.IGNORECASE)


def base_bytes(path: str) -> bytes:
    return subprocess.check_output(['git', 'show', f'{BASE}:{path}'], cwd=ROOT)


def current_bytes(path: str) -> bytes:
    return (ROOT / path).read_bytes()


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def lf_text(data: bytes) -> str:
    return data.decode('utf-8-sig').replace('\r\n', '\n').replace('\r', '\n')


def lf_chars(data: bytes) -> int:
    # Match PowerShell/.NET String.Length from CODEX_WORKFLOW (UTF-16 units).
    return len(lf_text(data).encode('utf-16-le')) // 2


def section(text: str, heading: str) -> str:
    lines = text.splitlines(keepends=True)
    start = next(i for i, line in enumerate(lines) if line.rstrip('\n') == heading)
    stop = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('## ')), len(lines))
    return ''.join(lines[start:stop])


def is_insertions_only(old: str, new: str) -> tuple[bool, int, int | None]:
    old_lines, new_lines = old.splitlines(keepends=True), new.splitlines(keepends=True)
    cursor = 0
    for index, old_line in enumerate(old_lines):
        while cursor < len(new_lines) and new_lines[cursor] != old_line:
            cursor += 1
        if cursor >= len(new_lines):
            return False, len(new_lines) - len(old_lines), index + 1
        cursor += 1
    return True, len(new_lines) - len(old_lines), None


def document_checks() -> dict:
    measured = {}
    for path, guide in ENTRY_DOCS.items():
        before, after = base_bytes(path), current_bytes(path)
        old_count, new_count = lf_chars(before), lf_chars(after)
        growth = round((new_count / old_count - 1) * 100, 3) if old_count else None
        measured[path] = {'base_lf_chars': old_count, 'current_lf_chars': new_count,
                          'guide_lf_chars': guide, 'over_guide': new_count > guide,
                          'growth_percent_from_base': growth,
                          'growth_over_10_percent': growth is not None and growth > 10,
                          'base_sha256': sha(before), 'current_sha256': sha(after),
                          'byte_exact_vs_base': before == after,
                          'lf_text_unchanged_vs_base': lf_text(before) == lf_text(after)}
    unchanged = {path: lf_text(current_bytes(path)) == lf_text(base_bytes(path)) for path in PRESERVE_EXACT}
    insertion_results = {}
    for path in INSERT_ONLY:
        before, after = base_bytes(path), current_bytes(path)
        insert_only, inserted_lines, first_unmatched = is_insertions_only(lf_text(before), lf_text(after))
        insertion_results[path] = {'insertions_only': insert_only,
                                   'inserted_lines': inserted_lines,
                                   'first_unmatched_base_line': first_unmatched,
                                   'base_lf_chars': lf_chars(before), 'current_lf_chars': lf_chars(after),
                                   'growth_percent_from_base': round((lf_chars(after) / lf_chars(before) - 1) * 100, 3)}
    character_base = section(lf_text(base_bytes('docs/ART_DIRECTION.md')), CHARACTER_HEADING)
    character_now = section(lf_text(current_bytes('docs/ART_DIRECTION.md')), CHARACTER_HEADING)
    snapshot = REPORT_DIR / 'previous-handoff.bytes'
    archive = ROOT / 'docs/CODEX_HANDOFF.history-20261106-2.md'
    original_handoff = base_bytes('docs/CODEX_HANDOFF.md')
    snapshot_exists, archive_exists = snapshot.is_file(), archive.is_file()
    snapshot_data = snapshot.read_bytes() if snapshot_exists else None
    archive_data = archive.read_bytes() if archive_exists else None
    history = current_bytes('docs/HISTORY.md')
    handoff = current_bytes('docs/CODEX_HANDOFF.md')
    closeout = {'handoff_updated_from_base': handoff != original_handoff,
                'history_updated_from_base': history != base_bytes('docs/HISTORY.md'),
                'previous_handoff_snapshot_exists': snapshot_exists,
                'history_archive_exists': archive_exists,
                'snapshot_equals_archive_exact_bytes': snapshot_exists and archive_exists and snapshot_data == archive_data,
                'snapshot_equals_base_handoff_exact_bytes': snapshot_exists and snapshot_data == original_handoff,
                'history_links_archive': 'CODEX_HANDOFF.history-20261106-2.md' in lf_text(history)}
    return {'base': BASE, 'entry_sizes': measured,
            'preserved_exact': unchanged, 'art_graphics_insertions_only': insertion_results,
            'character_style_section': {'heading': CHARACTER_HEADING,
                                        'unchanged_exact_lf_text': character_base == character_now,
                                        'base_sha256': sha(character_base.encode('utf-8')),
                                        'current_sha256': sha(character_now.encode('utf-8')),
                                        'base_lf_chars': len(character_base.encode('utf-16-le')) // 2,
                                        'current_lf_chars': len(character_now.encode('utf-16-le')) // 2},
            'closeout': closeout}


def clean_markdown(text: str) -> str:
    # Remove fenced examples, not the rest of the document.
    lines = []
    fenced = False
    for line in text.splitlines(keepends=True):
        if line.lstrip().startswith('```'):
            fenced = not fenced
            lines.append('\n')
        else:
            lines.append('\n' if fenced else line)
    return ''.join(lines)


def md_targets(data: bytes) -> list[str]:
    return [match.group(1).strip() for match in MARKDOWN_LINK.finditer(clean_markdown(lf_text(data)))]


def html_targets(data: bytes) -> list[str]:
    return [match.group(2).strip() for match in HTML_ATTR.finditer(lf_text(data))]


def resolve_target(document: Path, raw: str) -> tuple[str, Path | None]:
    target = raw.strip()
    if target.startswith('<') and '>' in target:
        target = target[1:target.index('>')]
    elif ' ' in target:
        target = target.split(' ', 1)[0]
    if not target or target.startswith('#') or '${' in target or '{{' in target:
        return 'skip_anchor_or_dynamic', None
    parsed = urlsplit(target)
    if parsed.scheme or target.startswith('//'):
        return 'skip_external_or_data', None
    path_part = unquote(parsed.path).replace('\\', '/')
    if not path_part:
        return 'skip_anchor_or_dynamic', None
    resolved = ((ROOT / path_part.lstrip('/')) if path_part.startswith('/') else (document.parent / path_part)).resolve()
    return ('exists' if resolved.exists() else 'missing'), resolved


def link_record(document: Path, target: str, origin: str) -> dict:
    status, resolved = resolve_target(document, target)
    return {'document': document.relative_to(ROOT).as_posix(), 'target': target,
            'origin': origin, 'status': status,
            'resolved': str(resolved) if resolved is not None else None}


def link_checks() -> dict:
    package_docs = sorted(PACKAGE.rglob('*.md'))
    package_html = sorted(PACKAGE.rglob('*.html'))
    own = []
    for doc in package_docs:
        own.extend(link_record(doc, target, 'package_markdown') for target in md_targets(doc.read_bytes()))
    for doc in package_html:
        own.extend(link_record(doc, target, 'package_static_html') for target in html_targets(doc.read_bytes()))
    introduced, preexisting = [], []
    touched = []
    for relative in TOP_LINK_DOCS:
        before, after = base_bytes(relative), current_bytes(relative)
        if before == after:
            continue
        touched.append(relative)
        base_counts = Counter(md_targets(before))
        seen = defaultdict(int)
        doc = ROOT / relative
        for target in md_targets(after):
            seen[target] += 1
            origin = 'preexisting_top_doc' if seen[target] <= base_counts[target] else 'introduced_top_doc'
            record = link_record(doc, target, origin)
            (preexisting if origin == 'preexisting_top_doc' else introduced).append(record)
    own_broken = [record for record in own + introduced if record['status'] == 'missing']
    preexisting_broken = [record for record in preexisting if record['status'] == 'missing']
    return {'scope': {'package_markdown_files': len(package_docs),
                      'package_html_files': len(package_html),
                      'touched_top_docs': touched},
            'own_and_introduced_links': own + introduced,
            'own_broken_links': own_broken,
            'preexisting_top_doc_links': preexisting,
            'preexisting_broken_links': preexisting_broken,
            'skipped_statuses': ['skip_anchor_or_dynamic', 'skip_external_or_data'],
            'historical_galleries_outside_package_scanned': False}


def main() -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    docs = document_checks()
    links = link_checks()
    errors = []
    if not all(docs['preserved_exact'].values()):
        errors.append('AGENTS/PROJECT_CONTEXT/CODEX_WORKFLOW LF text changed from base')
    if not all(row['insertions_only'] for row in docs['art_graphics_insertions_only'].values()):
        errors.append('ART_DIRECTION or GRAPHICS_WORKFLOW contains a deletion/replacement')
    if not docs['character_style_section']['unchanged_exact_lf_text']:
        errors.append('ART_DIRECTION character-style section changed')
    if not docs['closeout']['snapshot_equals_archive_exact_bytes'] or not docs['closeout']['snapshot_equals_base_handoff_exact_bytes']:
        errors.append('HANDOFF archive or previous-handoff snapshot is not byte-exact')
    if links['own_broken_links']:
        errors.append('Package or introduced top-doc local Markdown/HTML link is broken')
    pending_closeout = not all(docs['closeout'][key] for key in ('handoff_updated_from_base', 'history_updated_from_base', 'history_links_archive'))
    warnings = []
    preexisting_over_guide = []
    for path, row in docs['entry_sizes'].items():
        if row['over_guide'] and row['lf_text_unchanged_vs_base']:
            preexisting_over_guide.append(path)
        elif not row['lf_text_unchanged_vs_base'] and (row['over_guide'] or row['growth_over_10_percent']):
            warnings.append(f'{path}: size guide or 10% growth needs closeout explanation')
    link_path = REPORT_DIR / 'links.json'
    link_path.write_text(json.dumps(links, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    report = {**docs, 'links_report': link_path.relative_to(ROOT).as_posix(),
              'link_counts': {'own_or_introduced': len(links['own_and_introduced_links']),
                              'own_broken': len(links['own_broken_links']),
                              'preexisting_broken': len(links['preexisting_broken_links'])},
              'errors': errors, 'warnings': warnings,
              'preexisting_over_guide_unchanged': preexisting_over_guide,
              'closeout_pending': pending_closeout,
              'status': 'errors' if errors else ('partial_snapshot' if pending_closeout else 'document_checks_pass'),
              'artifact_completion': 'not_assessed_by_this_validator',
              'scope_note': 'Entry documents compared with fixed base; only this package and introduced links in touched top documents are checked.'}
    (REPORT_DIR / 'doc-validation.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': report['status'], 'errors': len(errors), 'warnings': len(warnings),
                      'own_broken_links': len(links['own_broken_links']),
                      'preexisting_broken_links': len(links['preexisting_broken_links']),
                      'closeout_pending': pending_closeout}))


if __name__ == '__main__':
    main()
