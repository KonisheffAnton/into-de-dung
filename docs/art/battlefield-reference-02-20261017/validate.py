"""Проверка поставки; художественная оценка и устойчивость анимации сюда не входят."""
import base64
import hashlib
import json
import re
from pathlib import Path
from PIL import Image, ImageChops
ROOT = Path(__file__).resolve().parent
RAW = Path('C:/Users/Aston/.codex/generated_images/battlefield-reference-02-20261017')

def require(condition, detail='validation failed'):
    if not condition:
        raise ValueError(detail)

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def save(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')

def pngs(value):
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
            result.extend(pngs(item))
    return result

def verify_output(folder):
    result = read(folder / 'result.json')
    require(result['status'] == 'completed', folder)
    info = result['outputs'][0] if 'outputs' in result else result['original']
    output = folder / 'original.png'
    require(sha(output) == info['sha256'], output)
    with Image.open(output) as image:
        image.load()
        require(image.format == 'PNG')
        require(image.mode == info['mode'])
        require([image.width, image.height] == [info['width'], info['height']])
        require(list(image.convert('RGBA').getchannel('A').getextrema()) == info['alpha_extrema'] == [255, 255])
    return (result, info)

def verify_refs(request):
    refs = request.get('referenced_image_paths')
    if refs is None:
        body = request['body']
        if request['endpoint'] == '/inpaint-v3':
            refs = [body['inpainting_image'], body['mask_image']]
        else:
            require(request['endpoint'] == '/generate-image-v2')
            refs = [body['style_image'], *body['reference_images']]
    for ref in refs:
        path = ROOT / ref.get('relative_path', ref.get('path', ''))
        require(path.is_file(), path)
        require(sha(path) == ref['sha256'], path)
        if 'size_bytes' in ref:
            require(path.stat().st_size == ref['size_bytes'], path)
        if 'size' in ref:
            with Image.open(path) as image:
                require({'width': image.width, 'height': image.height} == ref['size'], path)
    return refs

def verify_pixel(folder, result, request, refs):
    raw_folder = Path(result['native_source']['raw_folder'])
    raw_result = read(raw_folder / 'result.json')
    raw_request = read(raw_folder / 'request.json')
    response = read(raw_folder / 'response.json')
    require(response['status'] == raw_result['status'] == 'completed')
    require(raw_result['job_id'] == result['job_id'] == response['id'])
    require(raw_result['usage'] == result['usage'])
    decoded = pngs(response)
    require(len(decoded) == 1 and decoded[0] == (folder / 'original.png').read_bytes())
    require(raw_request['endpoint'] == request['endpoint'])
    raw_body = raw_request['body']
    clean_body = request['body']
    require(set(raw_body) == set(clean_body), folder)
    if request['endpoint'] == '/inpaint-v3':
        image_keys = ('inpainting_image', 'mask_image')
        raw_refs = [raw_body[key] for key in image_keys]
    else:
        require(request['endpoint'] == '/generate-image-v2')
        image_keys = ('style_image', 'reference_images')
        raw_refs = [raw_body['style_image'], *raw_body['reference_images']]
    for key, value in raw_body.items():
        if key not in image_keys:
            require(clean_body[key] == value, (folder, key))
    require(len(raw_refs) == len(refs))
    for actual, ref in zip(raw_refs, refs):
        require(set(actual['image']) == {'base64'}, folder)
        data = base64.b64decode(actual['image']['base64'], validate=True)
        require(hashlib.sha256(data).hexdigest() == ref['sha256'])
        require({k: v for k, v in actual.items() if k != 'image'} ==
                {k: v for k, v in ref.items() if k not in ('path', 'sha256')}, folder)
    if request['endpoint'] == '/inpaint-v3':
        with Image.open(ROOT / refs[0]['path']) as source, Image.open(ROOT / refs[1]['path']) as mask, Image.open(folder / 'original.png') as output:
            require(mask.mode == 'L' and set(mask.tobytes()) == {0, 255}, folder)
            require(source.size == mask.size == output.size, folder)
            difference = ImageChops.difference(source.convert('RGBA'), output.convert('RGBA'))
            channels = [ImageChops.multiply(channel, ImageChops.invert(mask)) for channel in difference.split()]
            maximum = channels[0]
            for channel in channels[1:]:
                maximum = ImageChops.lighter(maximum, channel)
            count = sum(value != 0 for value in maximum.tobytes())
            if 'outside_mask_changed_pixels' in result:
                require(count == result['outside_mask_changed_pixels'], (folder, 'incorrect recorded mask diff'))
            return {'status': 'FAIL' if count else 'PASS', 'outside_mask_changed_pixels': count,
                    'outside_mask_bbox': maximum.getbbox(), 'max_rgba_delta': max(maximum.tobytes()),
                    'outside_mask_alpha_changes': sum(value != 0 for value in channels[3].tobytes())}
    return None

def main():
    plan = read(ROOT / 'plan.json')
    animation = read(ROOT / 'animation-ready-imagegen/plan.json')
    require(len(plan) == 20 and len(animation) == 10)
    entries = [(item, ROOT / 'items' / f"{item['id']:03d}") for item in plan]
    entries += [(item, ROOT / 'animation-ready-imagegen/items' / f"{item['id']:03d}") for item in animation]
    entries.append((read(ROOT / 'animation-friendly/brief.json'), ROOT / 'animation-friendly'))
    require(len({item['label'] for item, _ in entries}) == 31)
    manifest = []
    for item, folder in entries:
        result, info = verify_output(folder)
        request = read(folder / 'request.json')
        prompt = request.get('prompt', request.get('body', {}).get('description'))
        require(prompt == item['prompt'], item['label'])
        refs = verify_refs(request)
        mask_report = None
        if item['engine'] == 'ImageGen':
            native = Path(result['native_source']['source_path'])
            require(native.read_bytes() == (folder / 'original.png').read_bytes())
            proof_file = RAW / 'imagegen' / (item['label'] + ('-correction' if result['correction'] else '') + '.json')
            proof = read(proof_file)
            require(proof['prompt'] == prompt and Path(proof['source_path']) == native)
            require(proof['transparent_background'] == request['transparent_background'])
            require(len(proof['referenced_image_paths']) == len(refs) == 3)
            for index, original_ref in enumerate(proof['referenced_image_paths']):
                source = Path(original_ref)
                if result['correction'] and index == 0:
                    source = ROOT / 'iterations' / (item['label'] + '-first') / 'original.png'
                require(sha(source) == refs[index]['sha256'])
        else:
            mask_report = verify_pixel(folder, result, request, refs)
            if mask_report and mask_report['status'] == 'FAIL':
                require(result.get('accepted_as_concept_with_mask_exception') is True,
                        (item['label'], 'undocumented selected mask exception'))
                require(result.get('outside_mask_changed_pixels') == mask_report['outside_mask_changed_pixels'])
        manifest.append({'label': item['label'], 'provider': item['engine'], 'path': (folder / 'original.png').relative_to(ROOT).as_posix(), **{k: info[k] for k in ('sha256', 'width', 'height', 'mode', 'alpha_extrema')}, 'request': (folder / 'request.json').relative_to(ROOT).as_posix(), 'usage': result['usage'], 'mask_preservation': mask_report})
    require(len({entry['sha256'] for entry in manifest}) == 31)
    archived = []
    for folder in sorted((ROOT / 'iterations').iterdir()):
        if not folder.is_dir():
            continue
        result, info = verify_output(folder)
        request = read(folder / 'request.json')
        refs = verify_refs(request)
        mask_report = None
        if result['provider'] == 'PixelLab':
            mask_report = verify_pixel(folder, result, request, refs)
        else:
            require(result['provider'] == 'built-in image_gen')
            require(Path(result['native_source']['source_path']).read_bytes() == (folder / 'original.png').read_bytes())
            proof = read(RAW / 'imagegen' / (folder.name.removesuffix('-first') + '.json'))
            require(proof['prompt'] == request['prompt'])
            require(proof['transparent_background'] == request['transparent_background'])
            require(len(proof['referenced_image_paths']) == len(refs))
            for source, ref in zip(proof['referenced_image_paths'], refs):
                require(sha(Path(source)) == ref['sha256'])
        archived.append({'path': folder.relative_to(ROOT).as_posix(), 'sha256': info['sha256'], 'mask_preservation': mask_report})
    html = (ROOT / 'gallery.html').read_text(encoding='utf-8')
    pairs = json.loads(re.search('<script>const pairs=(.*?);const \\$=', html).group(1))
    cards = [entry for pair in pairs for entry in pair['items']]
    require(len(cards) == 31 and len({x['label'] for x in cards}) == 31)
    for item, folder in entries:
        card = next((x for x in cards if x['label'] == item['label']))
        require(card['state'] == 'complete' and card['prompt'] == item['prompt'])
        require(ROOT / card['image'] == folder / 'original.png')
    require((ROOT / 'reference.png').read_bytes() == (RAW / 'reference.png').read_bytes())
    save(ROOT / 'manifest.json', {'selected': manifest, 'iterations': archived})
    selected_exceptions = [{'label': x['label'], **x['mask_preservation']} for x in manifest if x['mask_preservation'] and x['mask_preservation']['status'] == 'FAIL']
    archived_exceptions = [{'path': x['path'], **x['mask_preservation']} for x in archived if x['mask_preservation'] and x['mask_preservation']['status'] == 'FAIL']
    save(ROOT / 'validation.json', {'status': 'PASS_WITH_RECORDED_MASK_FAILURES' if selected_exceptions or archived_exceptions else 'PASS', 'selected_pngs': 31, 'unique_pngs': 31, 'gallery_cards': 31, 'archived_iterations': len(archived), 'provider_bytes_and_actual_requests': 'PASS', 'dimensions_alpha_hashes_references': 'PASS', 'inpaint_mask_preservation': {'status': 'FAIL' if selected_exceptions or archived_exceptions else 'PASS', 'selected_exceptions': selected_exceptions, 'archived_exceptions': archived_exceptions}, 'exact_tile_ratio': 'not measured', 'animation_stability': 'not tested', 'runtime_integration': 'none'})
    print('PNG PROVENANCE PASS: 31 unique originals, actual provider bytes/requests/references, alpha/dimensions/SHA, gallery31; archives:', len(archived))
    print('MASK PRESERVATION:', 'FAIL' if selected_exceptions or archived_exceptions else 'PASS', selected_exceptions)
if __name__ == '__main__':
    main()
