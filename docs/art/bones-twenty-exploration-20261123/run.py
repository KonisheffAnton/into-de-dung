"""Ten independent PixelLab concepts. Fresh generation, no ImageGen-derived inputs."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse,base64,importlib.util,json
ROOT=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('remains_client',ROOT.parent/'battle-remains-variants-20261122/pixellab/run.py')
client=importlib.util.module_from_spec(spec); spec.loader.exec_module(client)
client.ROOT=ROOT/'pixellab'
COMMON=('One small low heap of anonymous BROKEN BONES. Many SMALL different fragments tightly overlap: '
    'short hollow bone stubs, tiny crooked splinters, flat chips, small knobbly joint ends. '
    'Most pieces 4-7 pixels long, about 12 pieces in total. NO complete long bones, skull, head, face, jaw, '
    'ribcage, large loop or large plate. Clearly bone material, not rocks or gravel. '
    'ONE compact LOW mound, wide irregular silhouette, not arranged specimens. '
    'Simple chunky pixel art, only a few flat dirty ivory/taupe/purple-gray colors, selective dark outline. '
    'Three-quarter overhead camera, top-left light. Centered small ground prop with transparent margins. '
    'Transparent background; NO floor, ground patch, tile, tray, pedestal, rocks, flesh, glow or smooth shading. ')
LAYOUTS=[
    'Dense flattened oval; mostly tiny short bone stubs mixed with thin crossing splinters and two flat chips.',
    'Low irregular triangular heap; small knobbly fragments mixed with crooked thin slivers, asymmetrical top edge.',
    'Elongated low heap along a gentle diagonal; little tube ends, flat flakes and short bent splinters interlocked.',
    'Small rounded heap; differently shaped broken hollow-ended stubs overlap tiny thin shards, all lying flat.',
    'Broad flat heap; mostly small chipped flakes with tiny joint ends and short narrow bone slivers.',
    'Compact low wedge; thin crooked fragments alternate with short chunky bone stumps. Uneven front edge.',
    'Low dense irregular mound; two tiny curved bone pieces among short straight chips and small blunt ends. No hole or ring.',
    'Lopsided compact heap; many thin short fragments surround three small knobbly joint chips. Clearly distinct bone shapes.',
    'Very flat dense heap of short snapped slivers, wedge chips and tiny joint knobs; longest bits partially buried.',
    'Balanced small heap of short blunt stubs, thin splinters, tiny curved pieces and flat chips. No dominant large bone.'
]

def main():
    p=argparse.ArgumentParser(); p.add_argument('action',choices=['generate','poll','pro','pro-small','poll-pro','poll-pro-small']); p.add_argument('--id',default='all')
    args=p.parse_args(); client.ROOT.mkdir(exist_ok=True)
    if args.action=='pro-small':
        client.submit('pro-small','/generate-image-v2',{
            'description':'One low compact mound of tiny BONE FRAGMENTS and BONE SHARDS for a dark fantasy pixel game. '
                'The bones are all snapped into small unequal pieces: short jagged tubular ends, thin pointed splinters, '
                'flat curved flakes and tiny joint chips. Mostly stubby and irregular. About 18 small fragments, '
                'close together and overlapping. The heap is a low irregular oval, about 40 pixels wide and 22 pixels high. '
                'Every individual fragment is only 3-7 pixels long. NO whole bones. NO large dog-bone silhouettes. '
                'NO skull or recognizable skeleton. Clearly dry dirty ivory bone material, not round rocks. '
                'Each image should be a different irregular arrangement with varied bone shapes. '
                'Simple crisp low-resolution pixel art, sparse flat shading, selective dark outline. '
                'Top-down three-quarter camera, top-left light. Transparent empty margins, no ground, tray, tile, floor or shadow halo.',
            'image_size':{'width':64,'height':64},'seed':202611551,'no_background':True,
            'style_options':{'color_palette':False,'outline':False,'detail':False,'shading':False},
            'target_palette':{'colors':['#e0d6be','#c6bba7','#aa9f90','#8c8179','#71676b','#564c59','#3e3544','#28232e'],'max_colors':8,'name':'muted ivory bone and gray purple shadow'}})
        return
    if args.action=='pro':
        raw=base64.b64encode((ROOT.parent/'bones-five-20261123/B5-v2/image.png').read_bytes()).decode()
        client.submit('pro-candidates','/generate-image-v2',{
            'description':'A universal battlefield remains sprite: ONE low compact irregular HEAP OF SMALL BROKEN BONES. '
                'Many visibly DIFFERENT tiny skeletal fragments tightly overlapping: SHORT hollow tubular ends, '
                'thin snapped splinters, small gently bent bone pieces, tiny knobbly joint fragments and little flat chipped shards. '
                'About 12 to 16 pieces in each heap. Each fragment much smaller than the whole heap, most only 4 to 9 pixels long. '
                'There is NO dominant long bone. Bare dry dirty ivory bone, not rocks, cobblestones, meat, pebbles or bricks. '
                'Keep small fragments long/thin or crooked enough to read as bones, not round stone lumps. '
                'Some pieces have small broken hollow ends, but no repeated tube pattern. '
                'NO skull, face, eye sockets, jaw, teeth, complete ribcage, anatomical skeleton, large plate, large circular bone, '
                'upright bone or recognizable species. All pieces are lying low on the ground in ONE compact heap. '
                'Simple readable coarse PIXEL ART, few flat colors and selective dark outline, hard crisp pixels. '
                'Three-quarter overhead view, top-left light, low wide irregular silhouette. '
                'Use different compositions and different bone shapes while keeping the same style and palette. '
                'The reference is only a pixel-style guide, not a composition to copy. '
                'Transparent background with empty margins. No floor, ground patch, tile, base, pedestal, tray, shadow halo or glow.',
            'image_size':{'width':64,'height':64},'seed':202611550,'no_background':True,
            'style_image':{'image':{'base64':raw},'size':{'width':64,'height':64},'usage_description':'Only simple chunky pixel style, outline and sparse shading. Generate entirely new bone heaps with smaller varied fragments.'},
            'style_options':{'color_palette':False,'outline':True,'detail':True,'shading':True},
            'target_palette':{'colors':['#e0d6be','#c6bba7','#aa9f90','#8c8179','#71676b','#564c59','#3e3544','#28232e'],'max_colors':8,'name':'muted ivory bone and gray purple shadow'}})
        return
    if args.action in ('poll-pro','poll-pro-small'):
        directory=client.ROOT/('pro-small' if args.action=='poll-pro-small' else 'pro-candidates')
        receipt=json.loads((directory/'response.json').read_text())
        result=client.request('GET','/background-jobs/'+receipt['background_job_id'])
        client.save(directory/'status.json',result)
        paths=client.decode(result,directory) if result.get('status')=='completed' else []
        print(json.dumps({'status':result.get('status'),'files':paths,'usage':result.get('usage')}),flush=True)
        return
    def run(item):
        i,layout=item; name=f'PL{i+19}'; directory=client.ROOT/name
        if args.action=='generate':
            pixflux=i<5
            payload={'description':COMMON+layout,'image_size':{'width':48,'height':48},
                'outline':'selective outline','detail':'low detail','view':'high top-down',
                'no_background':True,'seed':202611500+i}
            if pixflux: payload.update({'shading':'basic shading','text_guidance_scale':10})
            else: payload['enhance_prompt']=False
            client.submit(name,'/create-image-pixflux' if pixflux else '/create-image-pixen',payload)
        else:
            if (directory/'image.png').exists(): return
            receipt=json.loads((directory/'response.json').read_text())
            result=client.request('GET','/background-jobs/'+receipt['background_job_id'])
            client.save(directory/'status.json',result)
            paths=client.decode(result,directory) if result.get('status')=='completed' else []
            print(json.dumps({'id':name,'status':result.get('status'),'files':paths,'usage':result.get('usage')}),flush=True)
    with ThreadPoolExecutor(max_workers=5) as pool:
        list(pool.map(run,[(i,v) for i,v in enumerate(LAYOUTS) if args.id in ('all',f'PL{i+19}')]))
if __name__=='__main__': main()
