"""Экспортирует только завершённые ответы, сохраняя PNG провайдера побайтно."""
from pathlib import Path
from PIL import Image,ImageDraw
import json,base64,hashlib,io
ROOT=Path(__file__).resolve().parent
JOBS=Path('C:/Users/Aston/.codex/generated_images/rogue-animation-02-20261101')
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
    rows=json.loads((ROOT/'requests.json').read_text(encoding='utf-8'));results=[]
    for row in rows:
        d=JOBS/'pixellab'/row['key'];jobfile=d/'job-latest.json'
        if not jobfile.exists():continue
        job=json.loads(jobfile.read_text(encoding='utf-8-sig'))
        if job.get('status')!='completed':continue
        admission=json.loads((d/'admission.json').read_text(encoding='utf-8-sig'))
        assert job['id']==admission['background_job_id']
        response=job['last_response'];images=response['images'];assert images
        out=ROOT/'pixellab'/row['key'];fd=out/'frames';fd.mkdir(parents=True,exist_ok=True)
        frames=[];hashes=[];boxes=[];raw_boxes=[]
        for i,item in enumerate(images):
            encoded=item['base64'];encoded=encoded.split(',',1)[-1] if encoded.startswith('data:') else encoded
            raw=base64.b64decode(encoded,validate=True);im=Image.open(io.BytesIO(raw)).convert('RGBA')
            assert im.size==(256,256)
            p=fd/f'frame-{i:02d}.png'
            if p.exists():assert p.read_bytes()==raw
            else:p.write_bytes(raw)
            hashes.append(sha(raw));frames.append(im);boxes.append(im.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox());raw_boxes.append(im.getchannel('A').getbbox())
        original=Image.open(ROOT/row['input']).convert('RGBA')
        timing=[90]*len(frames) if row['kind']=='idle' else [70]*len(frames)
        if row['kind']=='death':timing[-1]=1500
        sheet=Image.new('RGBA',(256*8,256*((len(frames)+7)//8)))
        for i,im in enumerate(frames):sheet.paste(im,((i%8)*256,(i//8)*256))
        sheet.save(out/'spritesheet.png')
        preview=[]
        for im in frames:
            bg=Image.new('RGBA',(256,256),'#182131');bg.alpha_composite(im);preview.append(bg.convert('RGB').resize((512,512),Image.Resampling.NEAREST))
        preview[0].save(out/'preview.gif',save_all=True,append_images=preview[1:],duration=timing,loop=0,disposal=2)
        with Image.open(out/'preview.gif') as gif:
            gif_timing=[]
            for i in range(gif.n_frames):gif.seek(i);gif_timing.append(gif.info.get('duration',0))
        assert sum(gif_timing)==sum(timing)
        film=Image.new('RGB',(256*5,256),'#182131')
        for x,i in enumerate([0,len(frames)//4,len(frames)//2,3*len(frames)//4,len(frames)-1]):film.paste(frames[i],(x*256,0),frames[i])
        film.save(out/'filmstrip.png')
        result={**row,'provider':'PixelLab PixMiniMax','job_id':job['id'],'actual_frames':len(frames),'usage':response.get('billing_usage') or response.get('usage') or job.get('usage'),'canvas':[256,256],'anchor':[128,200],'durations_ms':timing,'timing_origin':'authored preview timing; provider supplies poses only','gif_replay':True,'death_replay_note':'GIF replays for comparison; animation clip itself is nonlooping','first_frame_rgba_equal':frames[0].tobytes()==original.tobytes(),'last_frame_rgba_equal':frames[-1].tobytes()==original.tobytes(),'edge_frames':[i for i,b in enumerate(boxes) if b and (b[0]==0 or b[1]==0 or b[2]==256 or b[3]==256)],'rgba_unique':len({sha(im.tobytes()) for im in frames}),'frame_sha256':hashes,'bboxes':boxes,'integration':False}
        import numpy as np
        a=np.array(original);b=np.array(frames[0]);changed=np.any(a!=b,axis=2)
        result['first_frame_differing_pixels']=int(changed.sum())
        result['first_frame_visible_differing_pixels']=int((changed&((a[:,:,3]>0)|(b[:,:,3]>0))).sum())
        result['first_frame_alpha_equal']=bool(np.array_equal(a[:,:,3],b[:,:,3]))
        results.append(result)
        result['gif_actual_durations_ms']=gif_timing
        result['raw_alpha_bboxes']=raw_boxes
        result['edge_frames']=[i for i,b in enumerate(raw_boxes) if b and (b[0]==0 or b[1]==0 or b[2]==256 or b[3]==256)]
        result['margin_violation_frames']=[i for i,b in enumerate(raw_boxes) if b and (b[0]<8 or b[1]<8 or b[2]>248 or b[3]>248)]
        result['strong_margin_violation_frames']=[i for i,b in enumerate(boxes) if b and (b[0]<8 or b[1]<8 or b[2]>248 or b[3]>248)]
        (out/'clip.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    (ROOT/'pixellab-validation.json').write_text(json.dumps({'expected':9,'completed':len(results),'complete':len(results)==9,'complete_meaning':'count only; not artistic acceptance or runtime validation','clips':results},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'exported':len(results),'edge_clips':[r['key'] for r in results if r['edge_frames']],'first_frame_mismatches':[r['key'] for r in results if not r['first_frame_rgba_equal']],'usage':[r['usage'] for r in results]}))
if __name__=='__main__':main()
