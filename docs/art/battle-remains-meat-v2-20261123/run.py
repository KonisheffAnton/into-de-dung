"""Three focused PixelLab edits of existing fresh remains; dry bones are read-only."""
from pathlib import Path
import argparse, base64, importlib.util, json

ROOT = Path(__file__).resolve().parent
PREVIOUS = ROOT.parent / 'battle-remains-variants-20261122' / 'pixellab'
spec = importlib.util.spec_from_file_location('remains_client', PREVIOUS / 'run.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT
PROMPT = ('Slightly increase the attached meat on this SAME universal bone pile: about one-third more '
          'dark burgundy and muted brown-red flesh than currently. Make a few fuller chunky patches '
          'between and around the bones. Keep the bones clearly visible, in their exact positions. '
          'Preserve shape, scale, palette, 64px pixel grid and camera. No skull, face, organs, species '
          'traits, clothing, equipment, blood puddle or extra debris. No smoothing or glow. Transparent background.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['fresh', 'poll'])
    parser.add_argument('--id', default='all')
    args = parser.parse_args()
    assert len(PROMPT) <= 500
    for index in range(1, 4):
        identifier = f'PL-F{index}'
        if args.id not in ('all', identifier): continue
        if args.action == 'fresh':
            raw = base64.b64encode((PREVIOUS / identifier / 'image.png').read_bytes()).decode()
            client.submit(identifier, '/edit-image-pixen', {'image': {'type': 'base64', 'base64': raw, 'format': 'png'},
                'description': PROMPT, 'width': 64, 'height': 64, 'no_background': True, 'seed': 202611240 + index})
        else:
            directory = ROOT / identifier
            if (directory / 'image.png').exists(): continue
            receipt = json.loads((directory / 'response.json').read_text())
            status = client.request('GET', '/background-jobs/' + receipt['background_job_id'])
            client.save(directory / 'status.json', status)
            paths = client.decode(status, directory) if status.get('status') == 'completed' else []
            print(json.dumps({'id': identifier, 'status': status.get('status'), 'files': paths,
                'usage': status.get('usage')}, ensure_ascii=False), flush=True)


if __name__ == '__main__':
    main()
