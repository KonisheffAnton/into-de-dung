"""Подготовка входа и десяти запросов без сети; исходный полный кадр сохранён."""
from pathlib import Path
import base64
import hashlib
import json
import shutil
from PIL import Image

ROOT = Path(__file__).resolve().parent
JOBS = Path('C:/Users/Aston/.codex/generated_images/acid05-animation-20261103')
CAPTIONS = {
    'direction':'south-east', 'view':'low top-down',
    'subject_description':'A stationary blue-grey cracked stone tile block with masonry side faces and bright bubbling yellow-green acid covering its entire diamond-shaped top',
    'initial_pose':'Fixed isometric stone block, diamond top completely coated in flat acid with round bubbles; all brick side faces are exposed and motionless',
}
def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    spec=json.loads((ROOT/'clip-prompts.json').read_text(encoding='utf-8'))
    rows=spec['variants']
    expected=[f'acid-{i:02d}' for i in range(1,11)]
    assert [r['key'] for r in rows]==expected
    assert all(0<len(r['prompt'])<=1000 for r in rows)
    assert not any((JOBS/'pixellab'/key/'submit-started.json').exists() for key in expected), 'Do not overwrite an attempted request'
    source=(ROOT/spec['source']).resolve()
    assert digest(source)==spec['source_sha256']
    model=ROOT/'model'; model.mkdir(exist_ok=True)
    shutil.copyfile(source,model/'source-original.png')
    with Image.open(source) as original:
        assert original.mode=='RGBA' and original.size==(1254,1254)
        # Полный кадр уменьшен один раз для лимита API. Не обрезаем тайл и не
        # меняем alpha/палитру вручную; LANCZOS не добавляет крупную пиксельную сетку.
        original.resize((256,256),Image.Resampling.LANCZOS).save(model/'input-256.png')
    transform={'source':spec['source'],'source_sha256':digest(source),'original_copy':'model/source-original.png','input':'model/input-256.png','input_sha256':digest(model/'input-256.png'),'source_size':[1254,1254],'input_size':[256,256],'crop':None,'resize':'Pillow LANCZOS, whole frame','pixel_retouch':False,'integration':False}
    (model/'transform.json').write_text(json.dumps(transform,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    frame={'base64':base64.b64encode((model/'input-256.png').read_bytes()).decode('ascii'),'format':'png'}
    prepared=[]
    for index,row in enumerate(rows):
        folder=JOBS/'pixellab'/row['key'];folder.mkdir(parents=True,exist_ok=True)
        request={'first_frame':frame,'last_frame':frame,'description':row['prompt'],'frame_count':32,'seed':20261103101+index,'no_background':True,'enhance_prompt':False,**CAPTIONS}
        (folder/'request.json').write_text(json.dumps(request),encoding='utf-8')
        (folder/'prompt.txt').write_text(row['prompt'],encoding='utf-8')
        prepared.append({**row,'seed':request['seed'],'frame_count':32,'expected_frames':33,'endpoint':'animate-pixminimax','loop':True,'return_to_first':True,'input':'model/input-256.png','captions':CAPTIONS,'input_sha256':transform['input_sha256'],'request_sha256':digest(folder/'request.json')})
    (ROOT/'requests.json').write_text(json.dumps(prepared,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Prepared 10 requests and full-frame 256x256 input; no network submissions')
if __name__=='__main__': main()
