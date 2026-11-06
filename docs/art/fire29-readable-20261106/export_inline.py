"""Display-only APNG export; poses remain exact provider RGBA at fixed native XY."""
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageSequence

PACKAGE = Path(__file__).resolve().parent
REPO = PACKAGE.parents[2]
OUT = REPO/'test_reports/fire29-spikes-20261106/fire29/inline-preview'

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    path=PACKAGE/'preview/manifest.json'
    manifest=read(path)
    previous=read(REPO/'docs/art/fire-readable-sway-20261106/preview/manifest.json')
    results=[]
    for style in manifest['styles']:
        source=Image.open(REPO/style['source']).convert('RGBA')
        assert sha(REPO/style['source'])==style['source_sha256']
        raw={}
        for group in style['groups']:
            for index,item in group['raw_frames'].items():
                assert sha(REPO/item['path'])==item['sha256']
                raw[group['key'],int(index)]=Image.open(REPO/item['path']).convert('RGBA')
        frames=[]
        # The extra endpoint at slot96 verifies the loop; it is not a held frame.
        for slot in style['mapping'][:96]:
            native=source.copy()
            for group in style['groups']:
                box=tuple(group['crop_xyxy'])
                native.paste(Image.alpha_composite(native.crop(box),raw[group['key'],slot['poses'][group['key']]]),box[:2])
            surface=native.crop((288,233,966,746)).resize((512,387),Image.Resampling.LANCZOS)
            frames.append(Image.alpha_composite(Image.new('RGBA',surface.size,'#171c25'),surface).convert('RGB'))
        assert len(frames)==96
        target=OUT/f"fire{style['style']}-inline.png"
        frames[0].save(target,save_all=True,append_images=frames[1:],duration=80,loop=0,disposal=0,blend=0)
        with Image.open(target) as saved:
            decoded=[frame.convert('RGB').copy() for frame in ImageSequence.Iterator(saved)]
            durations=[]
            for i in range(saved.n_frames):
                saved.seek(i);durations.append(saved.info['duration'])
            assert len(decoded)==96 and durations==[80.0]*96 and saved.info['loop']==0
        assert all(np.array_equal(np.array(a),np.array(b)) for a,b in zip(frames,decoded))
        old=next(s for s in previous['styles'] if s['style']==style['style'])
        old_delta=sum(t['native']['max_rgb_diff_sum'] for t in old['temporal_transitions'])
        new_delta=sum(t['native']['max_rgb_diff_sum'] for t in style['temporal_transitions'])
        results.append({'style':style['style'],'path':target.relative_to(REPO).as_posix(),
                        'sha256':sha(target),'bytes':target.stat().st_size,'frames':96,'duration_ms':7680,
                        'decoded_rgb_exact':True,'native_crop_xyxy':[288,233,966,746],'display_size':[512,387],
                        'old_native_transition_rgb_sum':old_delta,'new_native_transition_rgb_sum':new_delta,
                        'native_transition_rgb_sum_ratio':new_delta/old_delta,
                        'metric_is_not_a_perceptual_visibility_score':True})
        print(json.dumps(results[-1]),flush=True)
    result={'manifest_sha256':sha(path),'display_only':True,'results':results}
    (OUT/'export-validation.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')

if __name__=='__main__':main()
