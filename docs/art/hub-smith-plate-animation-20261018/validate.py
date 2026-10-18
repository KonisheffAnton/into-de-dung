"""Read-only checks for PixelLab provenance and final assembled previews."""
import argparse
import base64
import hashlib
import json
from html.parser import HTMLParser
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.local = []

    def handle_starttag(self, tag, attrs):
        for key, value in attrs:
            if key in ('href', 'src') and value and not value.startswith(('#', 'http', 'data:')):
                self.local.append(value)


def restore_request(value):
    if isinstance(value, dict):
        if isinstance(value.get('file'), str) and isinstance(value.get('sha256'), str):
            path = ROOT / value['file']
            data = path.read_bytes()
            assert hashlib.sha256(data).hexdigest() == value['sha256'], value['file']
            return {'type': 'base64', 'base64': base64.b64encode(data).decode(), 'format': 'png'}
        return {key: restore_request(child) for key, child in value.items()}
    if isinstance(value, list):
        return [restore_request(child) for child in value]
    return value


def check_image(path):
    assert path.is_file(), path
    with Image.open(path) as image:
        image.load()
        return image.format, image.size, getattr(image, 'n_frames', 1), image.info


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider-dir', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    sources = json.loads((ROOT / 'sources.json').read_text(encoding='utf-8'))
    for source in sources:
        assert sha(ROOT / source['file']) == source['sha256']
        assert sha(Path(source['source_path'])) == source['sha256']
        if 'input' in source:
            assert sha(ROOT / source['input']) == source['input_sha256']

    plan = json.loads((ROOT / 'plan.json').read_text(encoding='utf-8'))
    actual_plan = json.loads((args.provider_dir / 'plan.json').read_text(encoding='utf-8'))
    assert len(plan) == len(actual_plan)
    actual_by_id = {item['id']: item for item in actual_plan}
    assert len(actual_by_id) == len(actual_plan)
    for item in plan:
        sent = actual_by_id[item['id']]
        assert item['endpoint'] == sent['endpoint']
        restored = restore_request(item['request'])
        assert restored == sent['request'], f"Public request differs: {item['id']}"
        saved = json.loads((args.provider_dir / 'items' / f"{item['id']:03d}" / 'request.json').read_text(encoding='utf-8'))
        assert saved == {'endpoint': item['endpoint'], 'body': restored}, f"Saved request differs: {item['id']}"

    manifest = json.loads((ROOT / 'manifest.json').read_text(encoding='utf-8'))
    assert manifest['pending'] == [], manifest['pending']
    output_by_id = {item['id']: item for item in manifest['outputs']}
    pending_by_id = {item['id']: item for item in manifest['pending']}
    plan_ids = {item['id'] for item in plan}
    assert len(output_by_id) == len(manifest['outputs'])
    assert len(pending_by_id) == len(manifest['pending'])
    assert set(output_by_id).isdisjoint(pending_by_id)
    assert set(output_by_id) | set(pending_by_id) == plan_ids
    plan_by_id = {item['id']: item for item in plan}
    pngs, dynamic_links = 0, []
    authoritative_frames = {}
    for output in manifest['outputs']:
        item = plan_by_id[output['id']]
        assert output['kind'] == item['kind']
        expected = 9 if item['kind'] == 'animation' else 1
        assert len(output['frames']) == expected, (output['id'], len(output['frames']), expected)
        for frame in output['frames']:
            assert frame['file'] not in authoritative_frames, frame['file']
            authoritative_frames[frame['file']] = frame
            path = ROOT / frame['file']
            assert sha(path) == frame['sha256']
            with Image.open(path) as image:
                image.load()
                assert list(image.size) == frame['size']
                alpha = image.convert('RGBA').getchannel('A')
                assert list(alpha.getextrema()) == frame['alpha_extrema']
                if item['kind'] == 'animation':
                    assert image.size == (256, 256) and alpha.getextrema()[0] == 0
            pngs += 1
            dynamic_links.append(frame['file'])
        if item['kind'] == 'animation':
            assert output['unique_frames'] > 1
            folder = Path(output['frames'][0]['file']).parent
            for filename in ('contact.png', 'spritesheet.png', 'loop.gif'):
                preview = ROOT / folder / filename
                image_format, _, frame_count, info = check_image(preview)
                if filename == 'loop.gif':
                    assert image_format == 'GIF' and info.get('loop') == 0 and frame_count >= 2
                else:
                    assert image_format == 'PNG'
                dynamic_links.append((folder / filename).as_posix())

    final_path = ROOT / 'final-manifest.json'
    final = json.loads(final_path.read_text(encoding='utf-8'))
    variants = final['variants']
    assert len(variants) == 5
    assert final['preview_frame_ms'] == 160
    seen_variants = set()
    for entry in variants:
        variant = entry['variant']
        assert isinstance(variant, int) and 1 <= variant <= 5 and variant not in seen_variants
        seen_variants.add(variant)
        assert len(entry['frames']) == 9
        contact_frame = entry['contact_frame']
        first_sparks_frame = entry['first_sparks_frame']
        assert isinstance(contact_frame, int) and isinstance(first_sparks_frame, int)
        assert 1 <= contact_frame < first_sparks_frame <= 9
        for index, record in enumerate(entry['frames'], start=1):
            final_relative = f"animations/smith-{variant:02d}/frame-{index:02d}.png"
            assert record['file'] == final_relative
            source_relative = record['source']
            assert source_relative in authoritative_frames, source_relative
            source_record = authoritative_frames[source_relative]
            assert source_record['size'] == [256, 256]
            assert source_record['alpha_extrema'][0] == 0
            final_file = ROOT / final_relative
            source_file = ROOT / source_relative
            assert sha(final_file) == source_record['sha256'] == record['sha256']
            assert final_file.read_bytes() == source_file.read_bytes()
            assert sha(source_file) == source_record['sha256']
            dynamic_links.extend((final_relative, source_relative))
        folder = ROOT / 'animations' / f'smith-{variant:02d}'
        for filename in ('contact.png', 'spritesheet.png', 'loop.gif'):
            preview = folder / filename
            image_format, _, frame_count, info = check_image(preview)
            if filename == 'loop.gif':
                assert image_format == 'GIF' and info.get('loop') == 0 and frame_count >= 2
            else:
                assert image_format == 'PNG'
            dynamic_links.append(preview.relative_to(ROOT).as_posix())
    assert seen_variants == {1, 2, 3, 4, 5}

    links = Links()
    links.feed((ROOT / 'gallery.html').read_text(encoding='utf-8'))
    for path in links.local + dynamic_links:
        assert (ROOT / path).is_file(), path
    kinds = [item['kind'] for item in plan]
    requested_counts = sorted({item['request'].get('frame_count') for item in plan if item['kind'] == 'animation'})
    result = {'status': 'PASS', 'source_copies': len(sources),
              'request_provenance': len(plan), 'provider_pngs': pngs,
              'packaged_outputs': len(manifest['outputs']), 'pending_outputs': len(manifest['pending']),
              'reference_edits': kinds.count('reference-edit'),
              'repair_edits': sum(kind in ('impact-repair', 'cleanup-edit') for kind in kinds),
              'animations': kinds.count('animation'), 'requested_animation_frame_counts': requested_counts,
              'final_variants': len(variants), 'final_frames': sum(len(item['frames']) for item in variants),
              'contact_before_first_sparks_labels': True,
              'local_links_checked': len(links.local + dynamic_links),
              'limits': 'Static provenance and file checks only. Contact/spark frame order checks declared labels; it is not an automatic visual timing guarantee.'}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__':
    main()
