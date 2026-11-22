"""Five mixed bone heaps for selection; one request per variant, no retries."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, base64, importlib.util, json

ROOT = Path(__file__).resolve().parent
PRIOR = ROOT.parent / 'battle-remains-variants-20261122' / 'pixellab'
spec = importlib.util.spec_from_file_location('remains_client', PRIOR / 'run.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT / 'pixellab'

COMMON = (
    'ONE compact low heap of MIXED TYPES OF BONE FRAGMENTS for a pixel-art dungeon tactics game. '
    'Inside this ONE heap every bone has a DIFFERENT silhouette: one long thick broken shaft, '
    'two short thin splinters, one curved arc fragment, one flat irregular chipped shard, '
    'one knobbly joint stump and one short angular chunk. Seven to nine overlapping pieces total. '
    'Mix long and short, thick and thin, curved and flat pieces TOGETHER in one connected mound. '
    'Do NOT repeat identical cartoon dog bones. No separate clusters, ring or neat arrangement. '
    'Bare anonymous bones, impossible to tell human or monster. NO skull, face, eye holes, jaw, '
    'teeth, pelvis, complete rib cage, hands, feet, claws, horns, upright plate, flesh or blood. '
    'Simple crisp chunky native 64x64 pixel sprite; visible heap about 48x28 pixels. '
    'Only 8-10 muted dirty ivory, taupe and purple-gray flat colors; selective dark outline. '
    'Shallow three-quarter overhead camera, light top left. Very low wide silhouette. '
    'Transparent background. No floor, pedestal, debris outside the heap, soft shadows, glow, '
    'antialiasing, gradients, detailed surface texture, lettering or watermark. '
)
VARIANTS = {
    'PL9': 'A long thick shaft is half buried diagonally at the back, a curved fragment hugs the left edge, flat chip and short splinters overlap at the center, chunky joint sits low on the right. One dense low irregular mound.',
    'PL10': 'A compact rounded low mound with a flat angular shard lying nearly horizontal at the center, a thin bent bone and thick short stump crossing behind, a knobbly joint and two splinters in front. Every piece has a different shape.',
    'PL11': 'A wide flattened heap: curved thick fragment at the front, long straight thin shaft crossing behind, flat chip and small joint piece sandwiched between, two tiny angular broken stubs tucked into the sides. All touching.',
    'PL12': 'A squat uneven triangular mound: short thick knobbly joint stump, long slender shaft, broad flat broken chip, curved narrow piece and three tiny irregular fragments overlapping. Keep the flat chip horizontal, no vertical plate.',
    'PL13': 'A lopsided compact heap with a thick snapped bone across a broad flat shard, a longer thin curved fragment behind, one rounded joint piece and three short angular chips at the front. Distinct lengths, widths, ends and curvatures.',
    'PL11-v2': 'The pile is mostly SHORT DIFFERENT fragments: broad flat triangular chip, squat irregular joint lump, short block-like snapped end, thin straight splinter, ONE tiny curved arc, and only ONE longer narrow shaft. Mixed lengths and widths. Absolutely NO repeated arcs, NO parallel ribs, NO backbone or rib cage; no recognizable skeleton. One low connected mound.'
}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--id', default='all')
    args = parser.parse_args()
    client.ROOT.mkdir(exist_ok=True)
    if args.id == 'PL11-clean':
        image = base64.b64encode((client.ROOT/'PL11-v4'/'image.png').read_bytes()).decode()
        mask = base64.b64encode((ROOT/'PL11-clean-mask.png').read_bytes()).decode()
        client.submit(args.id,'/inpaint-image-pro-flash',{'image':{'base64':image},'mask_image':{'base64':mask},
            'description':'Erase ALL background rocks and stone fragments in every white masked area. Make all masked background fully transparent. Preserve the central unmasked bone heap exactly. Do not add bones, rocks, floor, shadows, debris, glow or any new objects. This is background removal only.',
            'no_background':True,'output_method':'Modify current layer','crop_to_mask':True,'seed':202611342})
        return
    if args.id == 'poll-clean':
        directory = client.ROOT/'PL11-clean'
        receipt = json.loads((directory/'response.json').read_text())
        result = client.request('GET','/background-jobs/'+receipt['background_job_id'])
        client.save(directory/'status.json',result)
        paths = client.decode(result,directory) if result.get('status')=='completed' else []
        print(json.dumps({'status':result.get('status'),'files':paths,'usage':result.get('usage')}))
        return
    if args.id == 'PL11-v4':
        client.submit(args.id, '/create-image-pixen', {
            'description': 'One LOW WIDE compact heap of DIFFERENT anonymous bare bone fragments. '
                'A chunky joint stump, one thin crooked splinter, a flat chipped shard lying horizontally, '
                'one short thick broken shaft and two tiny irregular chips, all overlapping. '
                'No skull, face, ribcage, ring, recognizable skeleton or tall upright plate. '
                'Simple dark fantasy pixel art, large crisp clusters, dirty ivory and taupe with dark purple-gray shadows, '
                'selective dark outline. Low three-quarter overhead view, low mound resting on the ground. '
                'Sprite centered with transparent margins, wide footprint, no floor, background, meat, shadow halo or smoothing.',
            'image_size':{'width':64,'height':64},'outline':'selective outline','detail':'low detail',
            'view':'low top-down','no_background':True,'enhance_prompt':False,'seed':202611341})
        return
    if args.id == 'PL11-v3':
        description = ('Keep the same simple pixel style, palette and low wide heap size. '
            'Make all bones overlap into ONE LOW compact pile. Mix different shapes: one short thick broken shaft, '
            'one small knobbly joint, one flat irregular chip, two thin short splinters and ONE short curved fragment. '
            'Reduce long shafts. No repeated parallel arcs, rib cage, skull, face, holes, loops, upright plates or rectangular block. '
            'All bones lie flat. Transparent background, no shadow halo.')
        assert len(description) <= 500
        raw = base64.b64encode((client.ROOT/'PL10'/'image.png').read_bytes()).decode()
        client.submit(args.id, '/edit-image-pixen', {'image':{'type':'base64','base64':raw,'format':'png'},
            'description':description,'width':64,'height':64,'no_background':True,'seed':202611337})
        return
    if args.id == 'poll-v3':
        directory = client.ROOT/'PL11-v3'
        receipt = json.loads((directory/'response.json').read_text())
        result = client.request('GET','/background-jobs/'+receipt['background_job_id'])
        client.save(directory/'status.json',result)
        paths = client.decode(result,directory) if result.get('status')=='completed' else []
        print(json.dumps({'status':result.get('status'),'files':paths,'usage':result.get('usage')}))
        return
    def generate(item):
        index, (identifier, composition) = item
        client.submit(identifier, '/create-image-pixen', {
            'description': COMMON + composition,
            'image_size': {'width':64, 'height':64},
            'outline':'selective outline', 'detail':'low detail', 'view':'high top-down',
            'no_background':True, 'enhance_prompt':False, 'seed':202611330 + index
        })
    with ThreadPoolExecutor(max_workers=5) as pool:
        list(pool.map(generate, [(i,v) for i,v in enumerate(VARIANTS.items())
            if args.id == v[0] or (args.id == 'all' and '-v' not in v[0])]))

if __name__ == '__main__':
    main()
