"""Проверяет полноту, происхождение PNG, листы и тайминг готового пакета."""
from pathlib import Path
from PIL import Image
import json,hashlib,numpy as np
ROOT=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def visible_equal(a,b):
    a=np.array(a);b=np.array(b)
    return bool(np.array_equal(a[:,:,3],b[:,:,3]) and not np.any(np.any(a!=b,axis=2)&((a[:,:,3]>0)|(b[:,:,3]>0))))
def main():
    errors=[];models=read(ROOT/'models.json');requests=read(ROOT/'requests.json');pv=read(ROOT/'pixellab-validation.json');local=read(ROOT/'local-validation.json')
    checked_frames=0;sheet_cells=0;gif_count=0;return_diagnostics=[]
    def check(test,label):
        if not test:errors.append(label)
    check(len(models)==6,'model_count');check(len(requests)==54,'request_count')
    check(len({r['key'] for r in requests})==54,'unique_requests')
    check(pv['complete'] and pv['completed']==54,'pixellab_complete');check(local['passed'],'local_validation')
    for m in models:
        folder=ROOT/'models'/('warrior-'+m['id'])
        check(sha(folder/'source-full.png')==m['source_sha256'],'source_sha_'+m['id'])
        check(sha(folder/'input-256.png')==m['input_sha256'],'input_sha_'+m['id'])
    clips=[(ROOT/'pixellab'/r['key'],r) for r in pv['clips']]
    for id in ('02','05','11','12','17','18'):
        for kind in ('idle','death','ability'):
            p=ROOT/'local'/id/kind;clips.append((p,read(p/'clip.json')))
    check(len(clips)==72,'total_clips')
    for folder,c in clips:
        count=c['actual_frames'];kind=c.get('kind',c.get('animation'));id=c.get('id',c.get('warrior'))
        frames=list(sorted((folder/'frames').glob('frame-*.png')))
        check(len(frames)==count,'frame_count_'+str(folder))
        check(c['loop']==(kind=='idle'),'loop_'+str(folder))
        check(len(c['durations_ms'])==count,'duration_count_'+str(folder))
        sheet=Image.open(folder/'spritesheet.png').convert('RGBA')
        for i,p in enumerate(frames):
            im=Image.open(p).convert('RGBA');check(im.size==(256,256),'canvas_'+str(p))
            check(im.getchannel('A').getbbox() is not None,'empty_'+str(p))
            if 'frame_sha256' in c:check(sha(p)==c['frame_sha256'][i],'frame_sha_'+str(p))
            cell=sheet.crop(((i%8)*256,(i//8)*256,(i%8+1)*256,(i//8+1)*256))
            check(visible_equal(im,cell),'sheet_'+str(p));checked_frames+=1;sheet_cells+=1
        source=Image.open(ROOT/'models'/('warrior-'+id)/'input-256.png').convert('RGBA')
        check(visible_equal(source,Image.open(frames[0]).convert('RGBA')),'visible_first_'+str(folder))
        if kind=='ability' or ('provider' in c and kind=='idle'):
            last=Image.open(frames[-1]).convert('RGBA');exact=visible_equal(source,last)
            if 'provider' not in c:
                check(exact,'visible_return_'+str(folder))
            else:
                # API называет last_frame направляющей позой, не обещает точный RGBA.
                # Проверка сохраняется как открытая художественная приёмка, без ретуши.
                a=np.array(source);b=np.array(last);visible=(a[:,:,3]>0)|(b[:,:,3]>0)
                changed=np.any(a!=b,axis=2)&visible
                return_diagnostics.append({'key':c['key'],'visible_exact':exact,'changed_pixels':int(changed.sum()),'alpha_changed_pixels':int((a[:,:,3]!=b[:,:,3]).sum())})
        with Image.open(folder/'preview.gif') as gif:
            duration=0
            for i in range(gif.n_frames):gif.seek(i);duration+=gif.info.get('duration',0)
        check(duration==sum(c['durations_ms']),'gif_duration_'+str(folder));gif_count+=1
    report={'pass':not errors,'model_count':len(models),'pixellab_clips':pv['completed'],'local_clips':len(clips)-pv['completed'],'checked_png_frames':checked_frames,'checked_sheet_cells':sheet_cells,'checked_gifs':gif_count,'pixellab_generations':sum(c.get('usage',{}).get('generations',0) for c in pv['clips']),'edge_clips':[c['key'] for c in pv['clips'] if c['edge_frames']],'margin_clips':[c['key'] for c in pv['clips'] if c['margin_violation_frames']],'errors':errors,'integration':False,'art_acceptance':False,'runtime_validation':False}
    report['pass_meaning']='structural/source/export checks only; not loop, artistic or runtime acceptance'
    report['pixellab_return_diagnostics']=return_diagnostics
    report['pixellab_return_mismatches']=[r['key'] for r in return_diagnostics if not r['visible_exact']]
    (ROOT/'validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
    if errors:raise SystemExit(1)
if __name__=='__main__':main()
