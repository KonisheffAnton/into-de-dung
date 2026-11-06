"""Verify archived provider PNG bytes and the unchanged earlier task inputs."""
from pathlib import Path
import json,base64,hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[2];REPORT=REPO/'test_reports'/'hazard-motion-20261106'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    rows=[];usage=0;count=0
    for job in sorted((ROOT/'fire'/'pixellab').iterdir()):
        key=job.name;source,attempt=key.split('-',1);model=ROOT/'fire'/source/attempt
        request=read(job/'request.json')
        if (job/'rejected-response.json').exists():
            rejection=read(job/'rejected-response.json');assert key=='fire24-layer01' and 'Max frame_count: 8' in rejection['detail'];rows.append({'key':key,'admitted':False,'reason':rejection['detail']});continue
        if attempt.startswith('long01-c'):
            start=int(attempt[-2:]);model=ROOT/'fire'/source/'long01';res=read(job/'response-raw.json');files=[model/'raw'/f'frame-{start+i:02d}.png' for i in range(4)]
        elif attempt=='mask02':
            res=read(job/'response-raw.json');files=sorted((model/'raw').glob('*.png'))
        else:
            outer=read(job/'job-latest.json');assert outer['status']=='completed';res=outer['last_response'];files=[model/'raw.png'] if attempt=='keypose02' else sorted((model/'raw').glob('*.png'))
        images=[res['image']] if 'image' in res else res['images'];assert len(images)==len(files)
        for item,p in zip(images,files):
            assert p.read_bytes()==base64.b64decode(item['base64']),p
            with Image.open(p) as im:assert im.format=='PNG' and im.mode=='RGBA'
        bill=res.get('billing_usage',res.get('usage'));billed=bill['generations'];usage+=billed;count+=len(files)
        rows.append({'key':key,'admitted':True,'raw_png_byte_matches':len(files),'usage_generations':billed,'request_sha256':sha(job/'request.json')})
    assert count==44 and usage==36
    before=read(ROOT/'fire'/'balance-before.json')['subscription']['generations'];after=read(ROOT/'fire'/'balance-after.json')['subscription']['generations'];assert before-after==usage
    baseline=read(REPORT/'baseline.json');groups={}
    for group,entries in baseline.items():
        if not isinstance(entries,list) or not entries or not isinstance(entries[0],dict) or 'path' not in entries[0]:continue
        for e in entries:assert sha(REPO/e['path'])==e['sha256'],e['path']
        groups[group]=len(entries)
    assert (REPORT/'previous-handoff.bytes').read_bytes()==(REPO/'docs'/'CODEX_HANDOFF.history-20261106.md').read_bytes()
    report={'pass':True,'raw_png_matches':count,'usage_generations':usage,'jobs':rows,'preserved_groups':groups,'archive_byte_exact':True,'fire_art_result':'Not achieved; all new fire trials rejected internally','spikes_result':'Technical APPROVE; user selection open','runtime_integrated':False,'godot_run':False}
    (REPORT/'package-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(json.dumps({'pass':True,'raw_png_matches':count,'usage_generations':usage,'preserved_groups':groups}))
if __name__=='__main__':main()
