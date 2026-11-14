"""Bounded PixelLab concept batch. Secrets only inherited in process environment."""
import argparse, base64, concurrent.futures, hashlib, io, json, os, threading, time, uuid
from pathlib import Path
from urllib.request import Request, build_opener, HTTPRedirectHandler
from urllib.error import HTTPError
from PIL import Image

ROOT = Path('C:\\Users\\Aston\\.codex\\generated_images\\kostyash-feral-small-five-20261115\\feral-generation')
BASE = 'https://api.pixellab.ai/v2'
LOCK = threading.Lock()
STOP = threading.Event()
RESERVATION = None
class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise RuntimeError('Unexpected redirect blocked; credentials stay on api.pixellab.ai')

def save(path, value):
    temporary=path.with_name(path.name+'.'+uuid.uuid4().hex+'.tmp')
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf-8')
    os.replace(temporary,path)

def log(value):
    with LOCK:
        print(value, flush=True)

def api(method, route, body=None):
    assert route.startswith('/') and '://' not in route
    token = os.environ['PIXELLAB_API_KEY']
    req = Request(BASE + route, data=None if body is None else json.dumps(body).encode(),
                  method=method, headers={'Authorization':'Bearer '+token, 'Content-Type':'application/json'})
    try:
        with build_opener(NoRedirect()).open(req, timeout=600) as response:
            return json.load(response)
    except HTTPError as exc:
        raw = exc.read().decode('utf-8', errors='replace').replace(token, '[REDACTED]')
        raise RuntimeError('HTTP '+str(exc.code)+' '+raw[:2000]) from None

def extract_pngs(value):
    if not isinstance(value, dict):
        return []
    if isinstance(value.get('base64'), str):
        encoded = value['base64'].split(',',1)[-1]
        data = base64.b64decode(encoded, validate=True)
        if data.startswith(b'\x89PNG\r\n\x1a\n'):
            return [data]
    found=[]
    for key in ('image','images','last_response','result','output'):
        v=value.get(key)
        for item in v if isinstance(v,list) else [v]:
            found.extend(extract_pngs(item))
    return found

def run_one_locked(item):
    number = item['id']
    folder = ROOT / 'items' / f'{number:03d}'
    folder.mkdir(parents=True,exist_ok=True)
    metadata = folder/'result.json'
    previous={}
    if metadata.exists():
        previous=json.loads(metadata.read_text(encoding='utf-8'))
        if previous.get('status')=='completed':
            outputs=previous.get('outputs',[])
            valid=bool(outputs) and all((folder/Path(x['path']).name).is_file() and
                hashlib.sha256((folder/Path(x['path']).name).read_bytes()).hexdigest()==x['sha256'] for x in outputs)
            if valid:
                log(f'{number:03d} already completed and hash verified'); return
            log(f'{number:03d} restoring original from saved provider response')
    stored_request=folder/'request.json'
    if stored_request.exists():
        actual=json.loads(stored_request.read_text(encoding='utf-8'))
        if actual!={'endpoint':item['endpoint'],'body':item['request']}:
            raise RuntimeError(f'{number:03d} plan differs from preserved request; refusing provenance overwrite')
    request = item['request']
    if len(request['description'])>2000 and item['endpoint']=='/generate-image-v2':
        raise ValueError('Prompt exceeds 2000 characters')
    submitted=folder/'submitted.json'
    marker=folder/'submission-started.json'
    local_final=(folder/'response.json').exists()
    if local_final:
        response=json.loads((folder/'response.json').read_text(encoding='utf-8'))
    elif submitted.exists():
        response=json.loads(submitted.read_text(encoding='utf-8'))
    else:
        if STOP.is_set():
            log(f'{number:03d} skipped after account-level error'); return
        if marker.exists():
            reserved=json.loads(marker.read_text(encoding='utf-8'))
            if not RESERVATION or reserved.get('reserved_by')!=RESERVATION:
                log(f'{number:03d} previous or reserved POST; not resubmitting'); return
        else:
            if RESERVATION:
                raise RuntimeError(f'{number:03d} missing required reservation; POST refused')
            # Atomic claim for concurrently launched new runners; never auto-delete a POST marker.
            with marker.open('x',encoding='utf-8') as handle:
                json.dump({'claim':True},handle)
        save(marker, {'utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'owner':RESERVATION})
        if not stored_request.exists():
            save(stored_request, {'endpoint':item['endpoint'], 'body':request})
        if not (folder/'brief.json').exists():
            save(folder/'brief.json', {k:v for k,v in item.items() if k!='request'})
        try:
            response=api('POST',item['endpoint'],request)
            save(submitted,response)
        except Exception as exc:
            save(metadata,{'status':'submission_error','error':str(exc)})
            if 'HTTP 401' in str(exc) or 'HTTP 402' in str(exc): STOP.set()
            log(f'{number:03d} submission_error: {exc}'); return
    job=response.get('background_job_id') or (response.get('id') if local_final else None) or previous.get('job_id')
    if job and not local_final:
        log(f'{number:03d} accepted {job}')
        deadline=time.monotonic()+3600
        while time.monotonic()<deadline:
            try:
                response=api('GET','/background-jobs/'+job)
                save(folder/'job-latest.json',response)
            except Exception as exc:
                log(f'{number:03d} polling unavailable: {exc}')
                time.sleep(20); continue
            status=response.get('status')
            if status=='completed': break
            if status in ('failed','cancelled','canceled','error'):
                save(metadata,{'status':status,'job_id':job,'response':response})
                log(f'{number:03d} {status}'); return
            time.sleep(10)
        else:
            save(metadata,{'status':'pending','job_id':job})
            log(f'{number:03d} pending, resume same job'); return
    pngs=extract_pngs(response)
    save(folder/'response.json',response)
    if not pngs:
        save(metadata,{'status':'no_encoded_png','job_id':job,'keys':list(response)})
        log(f'{number:03d} no encoded PNG'); return
    outputs=[]
    for i,data in enumerate(pngs):
        path=folder/('original.png' if i==0 else f'original-{i+1}.png')
        path.write_bytes(data)
        with Image.open(io.BytesIO(data)) as image:
            image.load()
            alpha=image.convert('RGBA').getchannel('A').getextrema()
            outputs.append({'path':str(path),'sha256':hashlib.sha256(data).hexdigest(),
                            'width':image.width,'height':image.height,'mode':image.mode,'alpha_extrema':alpha})
    last=response.get('last_response') or response
    usage=last.get('billing_usage',last.get('usage',response.get('usage')))
    save(metadata,{'status':'completed','job_id':job,'usage':usage,'outputs':outputs})
    log(f'{number:03d} completed {outputs[0]["width"]}x{outputs[0]["height"]} usage={usage}')

def run_one(item):
    folder=ROOT/'items'/f'{item["id"]:03d}'
    folder.mkdir(parents=True,exist_ok=True)
    claim=folder/'runner.lock'
    try:
        handle=claim.open('x',encoding='utf-8')
    except FileExistsError:
        log(f'{item["id"]:03d} runner.lock present; skipped. If owner died, verify process and saved response before manually releasing this lock; never delete submission-started.json.'); return
    try:
        with handle:
            json.dump({'pid':os.getpid(),'reservation':RESERVATION},handle)
        run_one_locked(item)
    finally:
        claim.unlink(missing_ok=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--ids',default='all')
    parser.add_argument('--workers',type=int,default=2)
    parser.add_argument('--reservation')
    args=parser.parse_args()
    RESERVATION=args.reservation
    plan=json.loads((ROOT/'plan.json').read_text(encoding='utf-8-sig'))
    assert len(plan)<=100 and len({x['id'] for x in plan})==len(plan)
    ids=None if args.ids=='all' else {int(s) for s in args.ids.split(',')}
    selected=[x for x in plan if ids is None or x['id'] in ids]
    with concurrent.futures.ThreadPoolExecutor(max_workers=min(args.workers,3)) as pool:
        futures=[pool.submit(run_one,x) for x in selected]
        for future in concurrent.futures.as_completed(futures):
            try: future.result()
            except Exception as exc: log(f'Runner error: {type(exc).__name__}: {exc}')
    save(ROOT/'balance-latest.json',api('GET','/balance'))
