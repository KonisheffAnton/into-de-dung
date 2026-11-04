"""Проверка исходных кадров, листов и происхождения; художественный шов оценивает U."""
import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/fire-painted-sway-20261105')
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def rgba(path):
    with Image.open(path) as image:
        image.load()
        assert image.format=='PNG'
        return np.asarray(image.convert('RGBA'))
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--verify-raw',action='store_true')
    parser.add_argument('--completed-only',action='store_true');args=parser.parse_args()
    requests=read(ROOT/'requests.json')
    expected=[f'{source}-{i:02d}' for source in ('fire22','fire23','fire24','fire29') for i in range(1,4)]
    assert [r['key'] for r in requests]==expected
    assert len({r['seed'] for r in requests})==12
    assert all(len([r for r in requests if r['source_key']==source])==3
               for source in ('fire22','fire23','fire24','fire29'))
    if args.completed_only:
        partial=read(ROOT/'pixellab-validation-partial.json')
        selected=[r for r in requests if (ROOT/'pixellab'/r['key']/'clip.json').exists()]
        assert partial['expected']==12 and partial['completed']==len(selected) and not partial['complete']
        assert [r['key'] for r in selected]==[r['key'] for r in partial['clips']]
    else:
        selected=requests
    results=[];total_frames=0;raw_count=0
    for row in selected:
        expected_request_count=4 if row['key'] in ('fire24-03','fire29-03') else 8
        assert row['endpoint']=='animate-with-text-v3' and row['frame_count']==expected_request_count and row['expected_frames'] is None
        model=ROOT/'model'/row['source_key'];transform=read(model/'transform.json')
        source=model/'source-original.png';input_file=model/'input-256.png'
        assert sha(source)==transform['source_sha256']==sha((ROOT/transform['source']).resolve())
        assert sha(input_file)==transform['input_sha256']==row['input_sha256']
        with Image.open(source) as original:
            reconstructed=original.resize((256,256),Image.Resampling.LANCZOS)
            assert np.array_equal(np.asarray(reconstructed),rgba(input_file))
        initial=rgba(input_file)
        side_mask=(np.indices((256,256))[0]>=160)&(initial[:,:,3]>200)
        directory=ROOT/'pixellab'/row['key'];meta=read(directory/'clip.json')
        count=meta['actual_frames']
        assert meta['key']==row['key'] and meta['job_id'] and row['frame_count']<=count<=16
        assert meta['input_sha256']==sha(input_file) and meta['integration'] is False
        assert meta['prompt']==row['prompt'] and meta['durations_ms']==[100]*count
        paths=sorted((directory/'frames').glob('frame-*.png'));assert len(paths)==count
        raw_frames=None
        if args.verify_raw:
            external=JOBS/'pixellab'/row['key'];job=read(external/'job-latest.json');admission=read(external/'admission.json')
            assert job['status']=='completed' and job['id']==admission['background_job_id']==meta['job_id']
            assert sha(external/'request.json')==row['request_sha256']
            transport=read(external/'request.json')
            assert base64.b64decode(transport['first_frame']['base64'])==input_file.read_bytes()
            assert transport['last_frame']==transport['first_frame']
            assert transport['action']==row['prompt'] and transport['frame_count']==row['frame_count']
            assert transport['drift_threshold']==0 and 'direction' not in transport
            raw_frames=job['last_response']['images'];assert len(raw_frames)==count
        sheet=rgba(directory/'sheet.png');assert sheet.shape==(((count+7)//8)*256,2048,4)
        frames=[];boxes=[];side_mae=[]
        for index,path in enumerate(paths):
            assert path.name==f'frame-{index:02d}.png' and sha(path)==meta['frame_sha256'][index]
            frame=rgba(path);assert frame.shape==(256,256,4)
            assert frame[:,:,3].min()==0 and frame[:,:,3].max()>128
            assert np.array_equal(frame,sheet[index//8*256:index//8*256+256,index%8*256:index%8*256+256])
            visible=frame[:,:,3]>8;ys,xs=np.where(visible);assert len(xs)>0
            boxes.append([int(xs.min()),int(ys.min()),int(xs.max()+1),int(ys.max()+1)])
            side_mae.append(float(np.abs(frame.astype(float)-initial.astype(float))[side_mask].mean()))
            if raw_frames is not None:
                encoded=raw_frames[index]['base64'];encoded=encoded.split(',',1)[1] if encoded.startswith('data:') else encoded
                assert path.read_bytes()==base64.b64decode(encoded,validate=True);raw_count+=1
            frames.append(frame);total_frames+=1
        first_diff=np.any(frames[0]!=initial,axis=2)
        first_visible=(frames[0][:,:,3]>0)|(initial[:,:,3]>0)
        last_delta=np.abs(frames[-1].astype(np.int16)-initial.astype(np.int16))
        last_visible=(frames[-1][:,:,3]>0)|(initial[:,:,3]>0)
        # PixelLab нормализует RGB полностью прозрачных пикселей; видимое изображение и alpha сохраняются.
        assert np.array_equal(frames[0][:,:,3],initial[:,:,3]) and not np.any(first_diff&first_visible)
        assert meta['first_frame_render_equal'] is True
        for index in range(count,((count+7)//8)*8):
            assert np.all(sheet[index//8*256:index//8*256+256,index%8*256:index%8*256+256,3]==0)
        for name,digest in meta['artifact_sha256'].items():assert sha(directory/name)==digest
        with Image.open(directory/'preview.gif') as gif:
            assert gif.n_frames==count
            for index in range(count):gif.seek(index);assert gif.info['duration']==100
        results.append({'key':row['key'],'frames':count,'first_render_equal':True,'first_rgba_equal':bool(np.array_equal(frames[0],initial)),
            'first_transparent_rgb_differing_pixels':int(np.count_nonzero(first_diff)),
            'last_rgba_equal':bool(np.array_equal(frames[-1],initial)),
            'last_visible_rgba_changed_pixels_gt8':int(np.count_nonzero(np.any(last_delta>8,axis=2)&last_visible)),
            'last_alpha_changed_pixels_gt8':int(np.count_nonzero(last_delta[:,:,3]>8)),
            'visible_edge_frames':[i for i,b in enumerate(boxes) if b[0]==0 or b[1]==0 or b[2]==256 or b[3]==256],
            'margin_violation_frames':meta['margin_violation_frames'],
            'visible_bboxes_alpha_gt8':boxes,'stone_side_rgba_mean_absolute_difference_max':max(side_mae),
            'measurement_note':'Side difference includes colour flicker and movement; this is observation, not proof of fixed geometry or artistic approval.'})
    result={'status':'PASS','clips':len(selected),'expected_clips':12,'complete':len(selected)==12,
        'original_png_frames':total_frames,'sheet_cells_verified':total_frames,'gif_frames_verified':total_frames,
        'raw_api_byte_matches':raw_count if args.verify_raw else 'not checked','source_and_input_unchanged':True,
        'first_render_frames_equal':len(selected),'first_rgba_frames_equal':sum(x['first_rgba_equal'] for x in results),
        'last_rgba_frames_equal':sum(x['last_rgba_equal'] for x in results),
        'edge_clips':[x['key'] for x in results if x['visible_edge_frames']],
        'transparent_margin_status':'FAIL' if any(x['margin_violation_frames'] for x in results) else 'PASS',
        'margin_violation_clips':{x['key']:x['margin_violation_frames'] for x in results if x['margin_violation_frames']},
        'max_last_alpha_changed_pixels_gt8':max(x['last_alpha_changed_pixels_gt8'] for x in results),
        'integration':False,
        'artistic_acceptance':'open','clips_detail':results}
    out=ROOT/('validation-partial.json' if args.completed_only else 'validation.json')
    out.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k!='clips_detail'}))
if __name__=='__main__':main()
