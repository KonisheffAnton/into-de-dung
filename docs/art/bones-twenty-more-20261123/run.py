"""Independent PixelLab bone-heap batch; no POST retries or runtime edits."""
from pathlib import Path
import argparse, base64, importlib.util, json

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('remains_client', ROOT.parent / 'battle-remains-variants-20261122/pixellab/run.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT / 'pixellab'

DESCRIPTION = (
    'One SMALL FLAT PILE OF SHORT BROKEN BONES for a dark fantasy pixel art tactics game. '
    'Only 7 to 10 different short skeletal fragments per pile, overlapping in TWO LOW LAYERS. '
    'A compact flat oval, footprint only about 34 pixels wide and 18 pixels high in the 64-pixel canvas. '
    'All pieces lie FLAT, not sticking up. The heap is viewed from above in shallow three-quarter perspective. '
    'Every fragment has a DIFFERENT recognizable BONE shape: thin gently bent bone segments, short blunt '
    'tubular stubs with small broken ends, tiny rounded joint knobs, a few flat tapered bone flakes. '
    'Each piece short, about 4 to 8 pixels long. Some bone fragments curve but no complete rings. '
    'Make bones, not rocks, shards of stone or spiky scrap. No uniform collection of straight sticks. '
    'Allow little dark gaps separating the overlapping pieces. Compact mound, not scattered specimens. '
    'Different images should explore noticeably different low footprints and arrangements: '
    'flattened oval, low wedge, bent bean, lopsided trapezoid, short diagonal cluster. '
    'SIMPLE COARSE PIXEL ART, minimal detail, large clean flat pixel clusters, only six earthy colors. '
    'Muted warm dirty ivory, warm taupe shadow, dark gray-purple deepest outline. Upper-left light. '
    'NO skull, eyes, face, jaw, teeth, ribcage, identifiable skeleton, horns, spikes, whole long femurs, '
    'dominant pale plate, smooth shading, meat, blood, clothes, equipment, floor, tile, pedestal or shadow halo. '
    'Transparent background, generous empty margins. Bare universal bones, impossible to tell human or monster.'
)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['generate', 'generate-fragments', 'poll', 'poll-fragments', 'balance'])
    args = parser.parse_args()
    if args.action == 'balance':
        result = client.request('GET', '/balance')
        client.save(ROOT / 'balance.json', result)
        print(json.dumps(result))
    elif args.action == 'generate-fragments':
        reference = ROOT.parent / 'bones-twenty-exploration-20261123/pixellab/pro-small/image-6.png'
        client.submit('fragments', '/generate-image-v2', {
            'description': 'One NEW universal BONE FRAGMENT HEAP sprite. Keep the reference pixel-art style and SMALL BROKEN fragments, '
                'but invent DIFFERENT LOW COMPOSITIONS. A compact low heap of 8 to 12 tiny unequal skeletal fragments: '
                'short snapped crooked segments, tiny hollow stubs, small flat curved flakes, little rounded joint ends. '
                'Every fragment is SHORTER THAN ONE THIRD of the pile width. All lie flat, overlapping in a dense low mound. '
                'NO intact long femur, no repeated dumbbell shape, no large U-shaped curve, no rib framework. '
                'Think of a handful of crushed dry bones: smaller irregular bone fragments, not whole skeleton bones. '
                'Keep enough elongated and bent tiny silhouettes to read as bone rather than pebbles or gravel. '
                'Low broad asymmetric footprint, shallow overhead three-quarter view, upper-left light. '
                'Simple bold crisp pixel clusters, sparse flat shading, dirty ivory with taupe and dark purple-gray shadows. '
                'Mix different shapes WITHIN each heap. Explore small flattened ovals, wedges and bean shapes. '
                'No skull, face, eye sockets, jaw, teeth, horns, spikes, standing fragments, flesh, blood, clothes, '
                'floor, rocks, tray, pedestal, cast-shadow patch, halo or background. Transparent empty margins.',
            'image_size': {'width': 64, 'height': 64}, 'seed': 202611562, 'no_background': True,
            'style_image': {'image': {'base64': base64.b64encode(reference.read_bytes()).decode()},
                            'size': {'width': 64, 'height': 64},
                            'usage_description': 'Small varied broken fragments and simple pixel style only. New flatter heaps, no large whole bones.'},
            'style_options': {'color_palette': False, 'outline': True, 'detail': True, 'shading': True},
            'target_palette': {'colors': ['#e0d6be', '#c6bba7', '#aa9f90', '#8c8179', '#71676b', '#564c59', '#3e3544', '#28232e'],
                               'max_colors': 8, 'name': 'muted ivory bone fragments'}
        })
    elif args.action == 'generate':
        client.submit('candidates', '/generate-image-v2', {
            'description': DESCRIPTION,
            'image_size': {'width': 64, 'height': 64},
            'seed': 202611561, 'no_background': True,
            'style_options': {'color_palette': False, 'outline': False, 'detail': False, 'shading': False},
            'target_palette': {'colors': ['#ddd0b4', '#b8aa91', '#938474', '#716369', '#4e414f', '#2d2733'],
                               'max_colors': 6, 'name': 'earthy ivory bones'}
        })
    else:
        directory = client.ROOT / ('fragments' if args.action == 'poll-fragments' else 'candidates')
        receipt = json.loads((directory / 'response.json').read_text())
        result = client.request('GET', '/background-jobs/' + receipt['background_job_id'])
        client.save(directory / 'status.json', result)
        paths = client.decode(result, directory) if result.get('status') == 'completed' else []
        print(json.dumps({'status': result.get('status'), 'files': paths, 'usage': result.get('usage')}))

if __name__ == '__main__':
    main()
