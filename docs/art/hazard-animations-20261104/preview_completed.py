"""Собрать малые обзорные листы только из completed admitted jobs."""
from pathlib import Path
import base64
import io
import json
import sys
from PIL import Image
import numpy as np

JOBS = Path('C:/Users/Aston/.codex/generated_images/hazard-animations-20261104/pixellab')
ROOT = Path(__file__).resolve().parent
OUT = ROOT.parents[2] / 'test_reports' / 'hazard-animations-20261104'


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for key in sys.argv[1:]:
        folder = JOBS / key
        admission = json.loads((folder / 'admission.json').read_text(encoding='utf-8-sig'))
        job = json.loads((folder / 'job-latest.json').read_text(encoding='utf-8-sig'))
        assert job['status'] == 'completed' and job['id'] == admission['background_job_id']
        images = job['last_response']['images']
        assert len(images) >= 5
        strip = Image.new('RGBA', (256 * 5, 256))
        frames = []
        with Image.open(ROOT / 'model' / key.split('-')[0] / 'input-256.png') as image:
            initial = np.asarray(image.convert('RGBA')).astype(np.int16)
        side = (np.indices((256, 256))[0] >= 150) & (initial[:, :, 3] > 8)
        for item in images:
            raw = base64.b64decode(item['base64'].split(',')[-1], validate=True)
            with Image.open(io.BytesIO(raw)) as image:
                assert image.format == 'PNG' and image.size == (256, 256)
                frames.append(np.asarray(image.convert('RGBA')).astype(np.int16))
        samples = [round((len(frames) - 1) * column / 4) for column in range(5)]
        for column, index in enumerate(samples):
            strip.paste(Image.fromarray(frames[index].astype('uint8'), 'RGBA'), (column * 256, 0))
        target = OUT / f'{key}-filmstrip.png'
        strip.save(target)
        side_mae = [float(np.abs(frame - initial)[side].mean()) for frame in frames]
        last = frames[-1]
        visible = (last[:, :, 3] > 0) | (initial[:, :, 3] > 0)
        alpha_delta = np.abs(last[:, :, 3] - initial[:, :, 3])
        metrics = {'key': key, 'job_id': job['id'], 'frames': len(frames), 'filmstrip_frame_indices': samples,
                   'side_proxy_pixels': int(np.count_nonzero(side)),
                   'side_rgba_mae_max': max(side_mae),
                   'last_alpha_differing_pixels': int(np.count_nonzero(alpha_delta)),
                   'last_alpha_diff_gt8_pixels': int(np.count_nonzero(alpha_delta > 8)),
                   'last_alpha_diff_gt64_pixels': int(np.count_nonzero(alpha_delta > 64)),
                   'last_visible_rgba_differing_pixels': int(np.count_nonzero(np.any(last != initial, axis=2) & visible)),
                   'note': 'Side proxy is input alpha>8 and y>=150; colour difference is not proof of geometry drift.'}
        (OUT / f'{key}-metrics.json').write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
        print(json.dumps({'filmstrip': str(target), **metrics}, ensure_ascii=False))


if __name__ == '__main__':
    main()
