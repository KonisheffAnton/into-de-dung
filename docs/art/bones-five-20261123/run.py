"""Five requested bone layouts for selection; no runtime integration."""
from pathlib import Path
import argparse, base64, importlib.util, json
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
PRIOR = ROOT.parent / 'battle-remains-variants-20261122' / 'pixellab'
spec = importlib.util.spec_from_file_location('remains_client', PRIOR / 'run.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT
COMMON = ('Redesign ONLY the bone arrangement in this sprite. Keep its exact simple chunky pixel-art '
          'style, ivory/taupe/purple-gray palette, 64px scale and overhead camera. Bare anonymous bones: '
          'no flesh, skull, face, teeth, horns, hands, feet, clothing or species traits. '
          'Remove the tall upright plate completely. A low flat pile resting on the floor. '
          'Transparent background; no floor, shadow halo or smoothing. ')
VARIANTS = {
    'B1': 'Five separated bone fragments form a wide loose triangle with open gaps. No central mound.',
    'B2': 'A narrow diagonal pile: two long parallel broken shafts with three short pieces crossing them.',
    'B3': 'Six short bone fragments form a low open crescent around a small empty central gap.',
    'B4': 'Two small unequal clusters with a narrow gap, joined by one short bone fragment.',
    'B5': 'Four broken bones radiate as a low uneven fan from one small joint fragment.'
}
GEN_STYLE = ('A tiny UNIVERSAL bare-bones remains prop for a dark fantasy pixel-art tactics game. '
             'Simple chunky crisp native 64x64 pixel art, low detail, muted dirty ivory and taupe bone, '
             'purple-gray shadows, selective charcoal outline, top-left light. Shallow three-quarter '
             'overhead camera. Flat on the ground, overall occupied footprint about 48x28 pixels. '
             'Anonymous thick bone fragments: impossible to identify human or monster. '
             'NO skull, head, face, jaw, teeth, claws, horns, hands, feet, tall plate, upright bone, '
             'complete skeleton, flesh, blood, clothing, soil, pedestal or background. '
             'No blur, glow or smooth illustration. Transparent RGBA. ')
REFINED = {
    'B2-v2': 'A LONG NARROW diagonal arrangement: exactly TWO long straight broken shafts almost parallel, plus TWO tiny chips near one end. A thin elongated silhouette. Not a round heap or ring.',
    'B3-v2': 'An OPEN CURVED arrangement of THREE separate plain curved bone fragments and ONE short shaft. A shallow asymmetrical arc with a large open side. Never a complete ring, hole in a solid bone or ribcage.',
    'B4-v2': 'TWO DISTINCT SMALL CLUSTERS lying side by side, each made of only THREE short bone fragments. A clearly empty 8-pixel gap separates the clusters. Wide low shape. Nothing in the gap, no single central heap.',
    'B5-v2': 'A LOW DENSE TRIANGULAR heap of SEVEN short irregular overlapping broken bone chips. Mostly short flat fragments, one small thicker joint piece. Wide squat triangle, no long upright projection or central plate.'
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['fresh', 'bones', 'poll'])
    parser.add_argument('--id', default='all')
    args = parser.parse_args()
    assert all(len(COMMON + layout) <= 500 for layout in VARIANTS.values())
    if args.id == 'B4-clean':
        directory=ROOT/'B4-clean'
        if args.action=='fresh':
            image=base64.b64encode((ROOT/'B4-v2'/'image.png').read_bytes()).decode()
            mask=base64.b64encode((ROOT/'B4-clean-mask.png').read_bytes()).decode()
            client.submit('B4-clean','/inpaint-image-pro-flash',{'image':{'base64':image},'mask_image':{'base64':mask},
                'description':'Erase every isolated stray dark stroke and shadow in the white masked background. Make all white masked regions fully transparent. Preserve the two unmasked bone clusters exactly. Do not add any pixels, bones, ground, debris or shadows.',
                'no_background':True,'output_method':'Modify current layer','crop_to_mask':True,'seed':202611299})
        else:
            receipt=json.loads((directory/'response.json').read_text())
            status=client.request('GET','/background-jobs/'+receipt['background_job_id'])
            client.save(directory/'status.json',status)
            paths=client.decode(status,directory) if status.get('status')=='completed' else []
            print(json.dumps({'id':'B4-clean','status':status.get('status'),'files':paths,'usage':status.get('usage')}),flush=True)
        return
    if args.action == 'bones':
        def generate(item):
            index, (identifier, layout) = item
            client.submit(identifier,'/create-image-pixen',{'description':GEN_STYLE+layout,
                'image_size':{'width':64,'height':64},'outline':'selective outline','detail':'low detail',
                'view':'high top-down','no_background':True,'enhance_prompt':False,'seed':202611280+index})
        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(generate,[(i,v) for i,v in enumerate(REFINED.items()) if args.id in ('all',v[0])]))
        return
    for index, (identifier, layout) in enumerate(VARIANTS.items()):
        if args.id not in ('all', identifier): continue
        directory = ROOT / identifier
        if args.action == 'fresh':
            prompt = COMMON + layout
            assert len(prompt) <= 500
            raw = base64.b64encode((PRIOR/'PL-B3'/'image.png').read_bytes()).decode()
            client.submit(identifier, '/edit-image-pixen', {'image': {'type':'base64','base64':raw,'format':'png'},
                'description':prompt,'width':64,'height':64,'no_background':True,'seed':202611260+index})
        else:
            if (directory/'image.png').exists(): continue
            receipt = json.loads((directory/'response.json').read_text())
            status = client.request('GET','/background-jobs/'+receipt['background_job_id'])
            client.save(directory/'status.json',status)
            paths = client.decode(status,directory) if status.get('status')=='completed' else []
            print(json.dumps({'id':identifier,'status':status.get('status'),'files':paths,'usage':status.get('usage')}),flush=True)


if __name__ == '__main__':
    main()
