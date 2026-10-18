"""Package saved PixelLab outputs without changing the provider PNG bytes.

Run with the bundled Python (Pillow) and --provider-dir pointing to the saved
request workspace. This script never contacts PixelLab or loads credentials.
"""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def images(value):
    if not isinstance(value, dict):
        return []
    if isinstance(value.get('base64'), str):
        data = base64.b64decode(value['base64'].split(',', 1)[-1], validate=True)
        if data.startswith(b'\x89PNG\r\n\x1a\n'):
            return [data]
    result = []
    for key in ('image', 'images', 'last_response', 'result', 'output'):
        child = value.get(key)
        for item in child if isinstance(child, list) else [child]:
            result.extend(images(item))
    return result


def preview_files(folder, frames):
    width, height = frames[0].size
    sheet = Image.new('RGBA', (width * len(frames), height))
    contact = Image.new('RGBA', (width * 4, height * ((len(frames) + 3) // 4)))
    for i, frame in enumerate(frames):
        sheet.paste(frame, (i * width, 0))
        contact.paste(frame, ((i % 4) * width, (i // 4) * height))
    sheet.save(folder / 'spritesheet.png')
    contact.save(folder / 'contact.png')
    # GIF is a convenience preview: a shared 255-color palette and 1-bit alpha.
    # The untouched RGBA frame PNGs, not GIF colors, are the authoritative output.
    palette_source = Image.new('RGB', sheet.size, (32, 40, 36))
    palette_source.paste(sheet, mask=sheet.getchannel('A'))
    palette = palette_source.quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    gif_frames = []
    for frame in frames:
        flat = Image.new('RGB', frame.size, (32, 40, 36))
        flat.paste(frame, mask=frame.getchannel('A'))
        converted = flat.quantize(palette=palette, dither=Image.Dither.NONE)
        transparent = frame.getchannel('A').point(lambda x: 255 if x < 128 else 0)
        converted.paste(255, mask=transparent)
        converted.info['transparency'] = 255
        gif_frames.append(converted)
    gif_frames[0].save(folder / 'loop.gif', save_all=True,
                       append_images=gif_frames[1:], duration=160, loop=0,
                       transparency=255, disposal=2, optimize=False)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--provider-dir', type=Path, required=True)
    args = parser.parse_args()
    plan = json.loads((ROOT / 'plan.json').read_text(encoding='utf-8'))
    outputs, pending = [], []
    for item in plan:
        provider = args.provider_dir / 'items' / f'{item["id"]:03d}'
        result_path = provider / 'result.json'
        if not result_path.exists():
            pending.append({'id': item['id'], 'status': 'not_completed'})
            continue
        result = json.loads(result_path.read_text(encoding='utf-8'))
        if result['status'] != 'completed':
            pending.append({'id': item['id'], 'status': result['status']})
            continue
        response = json.loads((provider / 'response.json').read_text(encoding='utf-8'))
        accepted = json.loads((provider / 'submitted.json').read_text(encoding='utf-8'))
        assert response['id'] == result['job_id'] == accepted['background_job_id']
        pngs = images(response)
        expected = 1 if item['kind'] == 'diorama' else 9
        assert len(pngs) == expected, (item['id'], len(pngs), expected)
        if item['kind'] == 'diorama':
            folder = ROOT / 'dioramas'
            paths = [folder / f'{item["label"]}.png']
        else:
            folder = ROOT / 'animations' / f'{item["label"]}-{item["variant"]:02d}'
            folder.mkdir(exist_ok=True)
            paths = [folder / f'frame-{i + 1:02d}.png' for i in range(expected)]
        record = {k: v for k, v in item.items() if k != 'request'}
        record.update(job_id=result['job_id'], usage=result['usage'], frames=[])
        decoded = []
        for path, data, original in zip(paths, pngs, result['outputs']):
            assert sha(data) == original['sha256']
            if path.exists():
                assert path.read_bytes() == data, f'Refusing to overwrite changed {path}'
            else:
                path.write_bytes(data)
            im = Image.open(io.BytesIO(data)).convert('RGBA')
            if item['kind'] == 'animation':
                assert im.size == (256, 256), (path, im.size)
            decoded.append(im)
            record['frames'].append({'file': path.relative_to(ROOT).as_posix(),
                                     'sha256': sha(data), 'size': im.size,
                                     'alpha_extrema': im.getchannel('A').getextrema()})
        if item['kind'] == 'animation':
            preview_files(folder, decoded)
            record.update(preview_frame_ms=160, preview_duration_ms=len(decoded) * 160,
                          unique_frames=len({sha(im.tobytes()) for im in decoded}),
                          first_last_identical=decoded[0].tobytes() == decoded[-1].tobytes())
        outputs.append(record)
    manifest = {'provider': 'PixelLab.ai API v2', 'preview_only': True,
                'provider_workspace': str(args.provider_dir),
                'outputs': outputs, 'pending': pending,
                'gif_note': 'GIF uses a shared preview palette and binary alpha; PNG frames preserve provider bytes.'}
    save_json(ROOT / 'manifest.json', manifest)
    print(json.dumps({'packaged': len(outputs), 'pending': pending}, ensure_ascii=False))


if __name__ == '__main__':
    main()
