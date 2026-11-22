"""Provider edits: smaller individual bones, unchanged heap scale. No POST retries."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
import argparse, base64, importlib.util, json

ROOT = Path(__file__).resolve().parent
OLD = ROOT.parent/'mixed-bone-heaps-five-20261123'
spec = importlib.util.spec_from_file_location('remains_client',ROOT.parent/'battle-remains-variants-20261122/pixellab/run.py')
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT/'pixellab'
SOURCES = {'PL14':'PL9','PL15':'PL10','PL16':'PL11-clean','PL17':'PL12','PL18':'PL13'}
PROMPT = ('REDRAW the heap with MUCH SMALLER INDIVIDUAL BONES. Replace EVERY large bone with 2-3 short fragments, '
    'half the length and thickness. Keep the WHOLE heap footprint the same. 12-16 mixed small short shafts, '
    'curved chips, flat shards and knobbly ends, overlapping in ONE low compact pile. No bone longer than a '
    'quarter of heap width. Preserve simple chunky pixel style, palette and camera. No skull, face, ribcage, '
    'large loop, plate, flesh, rocks, floor, glow or smoothing. Transparent.')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action',choices=['submit','poll','create-small','adapt','poll-adapt'])
    parser.add_argument('--id',default='all')
    args=parser.parse_args()
    assert len(PROMPT)<=500
    client.ROOT.mkdir(exist_ok=True)
    if args.action in ('adapt','poll-adapt'):
        def adapt(item):
            index,(identifier,source)=item
            name=identifier+'-adapt'
            directory=client.ROOT/name
            if args.action=='adapt':
                data=base64.b64encode((ROOT/'provider-inputs'/(f'G{index+6}'+'.png')).read_bytes()).decode()
                client.submit(name,'/edit-image-pixen',{'image':{'type':'base64','base64':data,'format':'png'},
                    'description':'Preserve the exact arrangement, count and SMALL size of these varied short bone fragments. Keep the low flat compact heap. Clean the pixel clusters into simple crisp native pixel art. Use dirty ivory and taupe with purple-gray shadows, selective dark outline. Remove any faint background halo. Transparent background. No large bones, skull, ribs, floor, tray, pedestal, stones, smoothing or extra details.',
                    'width':64,'height':64,'no_background':True,'seed':202611440+index})
            else:
                if (directory/'image.png').exists(): return
                receipt=json.loads((directory/'response.json').read_text())
                status=client.request('GET','/background-jobs/'+receipt['background_job_id'])
                client.save(directory/'status.json',status)
                paths=client.decode(status,directory) if status.get('status')=='completed' else []
                print(json.dumps({'id':name,'status':status.get('status'),'files':paths,'usage':status.get('usage')}),flush=True)
        with ThreadPoolExecutor(max_workers=5) as pool:
            list(pool.map(adapt,[(i,v) for i,v in enumerate(SOURCES.items()) if args.id in ('all',v[0])]))
        return
    if args.action=='create-small':
        compositions=['wide irregular oval','low rounded triangle','flat asymmetric mound','compact oval with a lower left edge','small dense uneven wedge']
        def create(item):
            index,(identifier,source)=item
            client.submit(identifier+'-small','/create-image-pixen',{
                'description': 'A small LOW compact pile of MANY TINY broken BONE CHIPS and SHORT BONE SPLINTERS. '
                'About 14 small fragments packed together: short uneven stubs, flat chipped shards, little crooked splinters, '
                'tiny knobbly ends. Every piece is different. Individual fragments only 4 to 9 pixels long. '
                'NO full long bones, no large curved bones, no loops, no large slab, no repeated dog-bone shapes, '
                'no skull, head, face, jaw or recognizable skeleton. One low '+compositions[index]+'. '
                'The entire heap occupies about 48x30 pixels, centered with clear transparent margins in 64x64. '
                'Simple crisp chunky dark fantasy pixel art, limited dirty ivory/taupe palette with purple-gray deep shadows, '
                'selective dark outline, overhead three-quarter camera. Bare dry bone, no flesh. '
                'Transparent background. No floor, stones, rocks, dirt, pedestal, shadow halo, smoothing or text.',
                'image_size':{'width':64,'height':64},'outline':'selective outline','detail':'low detail',
                'view':'high top-down','no_background':True,'enhance_prompt':False,'seed':202611420+index})
        with ThreadPoolExecutor(max_workers=5) as pool:
            list(pool.map(create,[(i,v) for i,v in enumerate(SOURCES.items()) if args.id in ('all',v[0])]))
        return
    def execute(item):
        index,(identifier,source)=item
        directory=client.ROOT/identifier
        if args.action=='submit':
            data=base64.b64encode((OLD/'pixellab'/source/'image.png').read_bytes()).decode()
            client.submit(identifier,'/edit-image-pixen',{'image':{'type':'base64','base64':data,'format':'png'},
                'description':PROMPT,'width':64,'height':64,'no_background':True,'seed':202611400+index})
        else:
            if (directory/'image.png').exists(): return
            receipt=json.loads((directory/'response.json').read_text())
            status=client.request('GET','/background-jobs/'+receipt['background_job_id'])
            client.save(directory/'status.json',status)
            paths=client.decode(status,directory) if status.get('status')=='completed' else []
            print(json.dumps({'id':identifier,'status':status.get('status'),'files':paths,'usage':status.get('usage')}),flush=True)
    with ThreadPoolExecutor(max_workers=5) as pool:
        list(pool.map(execute,[(i,v) for i,v in enumerate(SOURCES.items()) if args.id in ('all',v[0])]))

if __name__=='__main__': main()
