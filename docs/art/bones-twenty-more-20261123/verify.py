"""Read-only asset checks and saved report; no image edits or generation."""
from pathlib import Path
import hashlib, json
from PIL import Image

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[2]

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    selection = json.loads((ROOT/'selection.json').read_text())
    assert len(selection) == 20
    records = []
    for name, relative in selection.items():
        path = ROOT/relative
        with Image.open(path) as im:
            assert im.mode == 'RGBA'
            alpha = im.getchannel('A')
            alpha_min, alpha_max = alpha.getextrema()
            # Raw ImageGen may top out at 254; report that rather than repainting its alpha.
            assert alpha_min == 0 and alpha_max >= 254
            pixels = list(im.get_flattened_data())
            count = len({p[:3] for p in pixels if p[3]})
            if name.startswith('PL'):
                assert im.size == (64, 64)
                assert (alpha_min, alpha_max) == (0, 255)
                assert count <= 8
            records.append({'id': name, 'path': relative, 'size': list(im.size),
                            'visible_rgb': count, 'alpha_range': list(alpha.getextrema()),
                            'soft_alpha_pixels': sum(0 < p[3] < 255 for p in pixels),
                            'sha256': digest(path)})
    assert len({r['sha256'] for r in records}) == 20
    protected = json.loads((ROOT/'protected-hashes.json').read_text())
    for path, sha in protected.items():
        assert digest(REPO/path) == sha, path
    for item in json.loads((ROOT/'imagegen-sources.json').read_text()):
        assert digest(Path(item['source'])) == digest(ROOT/item['destination'])
    usage = []
    for folder in ['candidates', 'fragments']:
        status = json.loads((ROOT/'pixellab'/folder/'status.json').read_text())
        assert status['status'] == 'completed'
        usage.append(status['usage'])
    report = {'base': 'fca68bb8fdef124439bb1fecc366e57b52456ac4',
              'images': records, 'protected_unchanged': len(protected),
              'imagegen_original_copies': True, 'imagegen_calls': 10,
              'pixellab_usage': usage,
              'pixellab_generations': sum(v.get('generations', 0) for v in usage),
              'runtime_changed': False, 'godot_run': False}
    (ROOT/'verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({'images': len(records), 'protected': len(protected),
                      'pixellab_generations': report['pixellab_generations']}))

if __name__ == '__main__':
    main()
