"""Prepare an unsubmitted edit-animation-v2 palette experiment.

Palette swatches are exact RGB values from visible source pixels. Raw PixelLab
frames are byte-copied into the JSON body as base64, never modified or printed.
"""
from __future__ import annotations

import base64
from collections import Counter
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
PACKAGE = HERE.parent
SOURCE = PACKAGE / 'field-inputs/fire24/fire24-29/input-transparent.png'
META = PACKAGE / 'requests/fire24-field29/request-metadata.json'
RESULT = PACKAGE / 'results/fire24-field29'
OPENAPI = Path('C:/Users/Aston/.codex/generated_images/fire-single-tongue-20261106/openapi-before-post-fire24-field10.json')
RAW_ORDER = [0, 12, 16, 20]
QUOTAS = [('pale_yellow_core', 8), ('orange_body', 9), ('ochre_edge', 8), ('dark_border', 7)]
DESCRIPTION = (
    "Copy the first frame's original pale-yellow, golden-orange and muted-ochre "
    "painted color treatment to the other frames. Change colors only. Keep each "
    "frame's existing geometry, pixel positions, alpha, silhouette, size, motion "
    "and frame order exactly. Preserve the first frame unchanged. No bright pure "
    "red, new shapes, glow, sparks or lighting changes."
)


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def category(rgb: tuple[int, int, int]) -> str:
    r, g, _ = rgb
    if r >= 235 and g >= 190:
        return 'pale_yellow_core'
    if r >= 200 and 130 <= g < 190:
        return 'orange_body'
    if r >= 170 and 105 <= g < 130:
        return 'ochre_edge'
    return 'dark_border'


def select_colors(colors: Counter, name: str, quota: int) -> list[tuple[int, int, int]]:
    pool = sorted((rgb for rgb in colors if category(rgb) == name))
    assert len(pool) >= quota
    values = np.asarray(pool, dtype=np.float32)
    weights = np.asarray([colors[rgb] for rgb in pool], dtype=np.float32)
    mean = np.average(values, axis=0, weights=weights)
    first = int(np.argmin(np.sum((values - mean) ** 2, axis=1)))
    picked = [first]
    # Deterministic representative medoids: broad coverage, with frequency
    # softly preferring colors that actually occur repeatedly in the source.
    while len(picked) < quota:
        distance = np.min(np.sum((values[:, None, :] - values[picked][None, :, :]) ** 2, axis=2), axis=1)
        score = distance * np.sqrt(1 + np.log1p(weights))
        score[picked] = -1
        picked.append(int(np.argmax(score)))
    selected = [pool[i] for i in picked]
    return sorted(selected, key=lambda rgb: (-sum(rgb), rgb))


def make_swatch(colors: list[dict]) -> Path:
    tile_w, tile_h = 120, 76
    canvas = Image.new('RGB', (tile_w * 8, tile_h * 4), '#1c2430')
    draw = ImageDraw.Draw(canvas)
    for i, item in enumerate(colors):
        x, y = (i % 8) * tile_w, (i // 8) * tile_h
        rgb = tuple(item['rgb'])
        draw.rectangle((x + 6, y + 5, x + tile_w - 7, y + 47), fill=rgb)
        draw.text((x + 7, y + 52), item['hex'], fill='#eef2f6')
    path = HERE / 'palette-32.png'
    canvas.save(path)
    return path


def make_contact(raw_paths: list[Path]) -> Path:
    images = [Image.open(path).convert('RGBA') for path in raw_paths]
    assert all(image.size == (256, 256) for image in images)
    contact = Image.new('RGB', (1024, 285), '#1c2430')
    draw = ImageDraw.Draw(contact)
    for i, image in enumerate(images):
        plate = Image.new('RGBA', image.size, '#1c2430')
        contact.paste(Image.alpha_composite(plate, image).convert('RGB'), (i * 256, 0))
        draw.text((i * 256 + 8, 263), f'raw {RAW_ORDER[i]:02}', fill='#eef2f6')
    path = HERE / 'selected-raw-contact.png'
    contact.save(path)
    return path


def main() -> None:
    request_meta = json.loads(META.read_text(encoding='utf-8'))
    manifest = json.loads((RESULT / 'manifest.json').read_text(encoding='utf-8'))
    assert request_meta['key'] == manifest['key'] == 'fire24-field29'
    assert sha(SOURCE) == request_meta['input_sha256']
    openapi = json.loads(OPENAPI.read_text(encoding='utf-8'))
    operation = openapi['paths']['/edit-animation-v2']['post']
    assert '81-256px: Up to 4 frames' in operation['description']
    schema = openapi['components']['schemas']['EditAnimationV2Request']
    assert schema['properties']['frames']['maxItems'] >= 4
    assert len(RAW_ORDER) == 4 and len(DESCRIPTION) <= 2000
    components = openapi['components']['schemas']
    schema_slice = {
        'snapshot_sha256': sha(OPENAPI),
        'operation_description': operation['description'],
        'request_schema': schema,
        'frame_schema': components['app__endpoints__external__v2__edit_animation_v2__FrameImage'],
        'frame_size_schema': components['app__endpoints__external__v2__edit_animation_v2__FrameImageSize'],
        'output_size_schema': components['app__endpoints__external__v2__edit_animation_v2__ImageSize'],
        'base64_image_schema': components['Base64Image'],
        'target_palette_schema': components['TargetPalette'],
    }
    schema_path = HERE / 'schema-slice.json'
    schema_path.write_text(json.dumps(schema_slice, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    source_rgba = np.asarray(Image.open(SOURCE).convert('RGBA'))
    assert source_rgba.shape == (256, 256, 4)
    visible = source_rgba[:, :, :3][source_rgba[:, :, 3] > 8]
    source_colors = Counter(tuple(map(int, pixel)) for pixel in visible)
    # Pure-red-looking high-R/low-G source pixels are deliberately left out of
    # the proposed target palette; every selected swatch still occurs in source.
    eligible = Counter({rgb: count for rgb, count in source_colors.items()
                        if not (rgb[0] >= 220 and rgb[1] < 105)})
    swatches = []
    for name, quota in QUOTAS:
        for rgb in select_colors(eligible, name, quota):
            swatches.append({'group': name, 'rgb': list(rgb),
                             'hex': '#%02X%02X%02X' % rgb,
                             'visible_source_pixels_exact_rgb': source_colors[rgb]})
    assert len(swatches) == len({s['hex'] for s in swatches}) == 32
    assert all(tuple(s['rgb']) in source_colors for s in swatches)
    assert all(not (s['rgb'][0] >= 220 and s['rgb'][1] < 105) for s in swatches)
    raw_paths = []
    frame_rows = []
    body_frames = []
    for index in RAW_ORDER:
        row = manifest['frames'][index]
        path = RESULT / 'raw' / f'frame-{index:02}.png'
        assert row['frame'] == index and sha(path) == row['sha256']
        with Image.open(path) as image:
            assert image.size == (256, 256) and image.mode == 'RGBA'
        raw_paths.append(path)
        frame_rows.append({'raw_index': index, 'path': path.relative_to(ROOT).as_posix(),
                           'sha256': row['sha256'], 'native_size': [256, 256]})
        body_frames.append({'image': {'type': 'base64', 'format': 'png',
                                      'base64': base64.b64encode(path.read_bytes()).decode('ascii')},
                            'size': {'width': 256, 'height': 256}})
    body = {'description': DESCRIPTION, 'frames': body_frames,
            'image_size': {'width': 256, 'height': 256}, 'no_background': True,
            'target_palette': {'colors': [s['hex'] for s in swatches],
                               'name': 'Original fire24 pale yellow, orange and ochre',
                               'max_colors': 32}}
    assert set(body).issubset(schema['properties'])
    assert len(body['frames']) == 4 and len(body['target_palette']['colors']) == 32
    body_path = HERE / 'draft.json'
    body_path.write_text(json.dumps(body, ensure_ascii=False, separators=(',', ':')) + '\n', encoding='utf-8')
    # Re-read the saved body: base64 must decode to the exact raw PNG bytes.
    saved = json.loads(body_path.read_text(encoding='utf-8'))
    for item, path in zip(saved['frames'], raw_paths):
        assert base64.b64decode(item['image']['base64'], validate=True) == path.read_bytes()
    swatch_path = make_swatch(swatches)
    contact_path = make_contact(raw_paths)
    palette = {'source': SOURCE.relative_to(ROOT).as_posix(), 'source_sha256': sha(SOURCE),
               'visible_alpha_threshold_gt': 8, 'visible_pixel_count': len(visible),
               'visible_unique_rgb_count': len(source_colors),
               'excluded_bright_red_source_pixels': sum(count for rgb, count in source_colors.items() if rgb[0] >= 220 and rgb[1] < 105),
               'selection': '32 exact source RGB medoids, stratified by warm luminance/color roles; no RGB is synthesized.',
               'groups': dict(QUOTAS), 'colors': swatches,
               'swatch_image': swatch_path.relative_to(ROOT).as_posix(), 'swatch_sha256': sha(swatch_path)}
    (HERE / 'palette.json').write_text(json.dumps(palette, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    metadata = {'status': 'unsubmitted_draft', 'endpoint': '/v2/edit-animation-v2',
                'schema_snapshot': str(OPENAPI), 'schema_snapshot_sha256': sha(OPENAPI),
                'schema_slice': schema_path.relative_to(ROOT).as_posix(), 'schema_slice_sha256': sha(schema_path),
                'schema_note': 'Operation description limits native 81-256px output to 4 frames; 8 would exceed 2x2 grid despite schema maxItems 16.',
                'fresh_official_schema_required_before_post': True,
                'draft': body_path.relative_to(ROOT).as_posix(), 'draft_sha256': sha(body_path),
                'palette': (HERE / 'palette.json').relative_to(ROOT).as_posix(),
                'palette_sha256': sha(HERE / 'palette.json'),
                'palette_all_32_rgb_exactly_present_in_visible_source': True,
                'palette_bright_pure_red_colors': 0,
                'source_input_sha256': sha(SOURCE), 'source_request_sha256': request_meta['request_sha256'],
                'source_result_response_sha256': manifest['response_sha256'],
                'selected_raw_frames': frame_rows,
                'raw_contact': contact_path.relative_to(ROOT).as_posix(), 'raw_contact_sha256': sha(contact_path),
                'constraints': ['Provider must create all edited motion frames; this package only selects existing raw input frames and palette values.',
                                'Color-only instruction is a request, not a guarantee of exact geometry/alpha preservation.',
                                'Four edited frames would not replace the 33-frame original clip or establish a full field animation.'],
                'provider_posts': 0}
    (HERE / 'metadata.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'status': 'unsubmitted_draft', 'frames': RAW_ORDER,
                      'palette_colors': len(swatches), 'draft_sha256': sha(body_path),
                      'source_sha256': sha(SOURCE)}))


if __name__ == '__main__':
    main()
