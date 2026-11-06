"""Compare provider color controls without modifying any returned pose."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw

ROOT=Path(__file__).resolve().parent;REPO=ROOT.parents[2]
KEYS=('fire24-field29','fire24-drift01','fire24-alpha01')
OUT=ROOT/'color-control-comparison';OUT.mkdir(exist_ok=True)
base_meta=json.loads((ROOT/'requests'/KEYS[0]/'request-metadata.json').read_text())
base=np.array(Image.open(ROOT/base_meta['input']).convert('RGBA'))
core=np.array(Image.open(REPO/base_meta['group']['core_mask_path']).convert('L'))>0
source=Image.open(ROOT.parent/'fire-low-styles-20261104/fire-low-24.png').convert('RGBA')
roi=tuple(base_meta['group']['crop_xyxy']);crop=source.crop(roi)

def colors(a):
    mean=a[core,:3].astype(float).mean(axis=0)
    premul=a[:,:,:3].astype(float)*a[:,:,3,None]/255
    light=premul@np.array([.2126,.7152,.0722])
    return {'core_mean_rgb':mean.round(4).tolist(),'core_gr_br':(mean[1:]/max(mean[0],1)).round(5).tolist(),
            'premul_luma':round(float(light.sum()),3),
            'visible_unique_rgb_colors':int(len(np.unique(a[a[:,:,3]>0,:3],axis=0)))}

reference=colors(base);rows=[];sheet=Image.new('RGBA',(1024,3*286),(30,34,43,255));d=ImageDraw.Draw(sheet)
for row,frame in enumerate((3,16,32)):
    sheet.alpha_composite(crop,(0,row*286));d.text((5,row*286+260),'original crop',fill='white')
    for col,key in enumerate(KEYS,1):
        path=ROOT/'results'/key/'raw'/f'frame-{frame:02d}.png'
        im=Image.open(path).convert('RGBA');a=np.array(im);stats=colors(a)
        assembled=Image.alpha_composite(crop,im)
        sheet.alpha_composite(assembled,(col*256,row*286));d.text((col*256+5,row*286+260),f'{key} raw{frame}',fill='white')
        rows.append({'key':key,'frame':frame,'raw_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                     **stats,'luma_ratio_to_input':round(stats['premul_luma']/reference['premul_luma'],5),
                     'absolute_core_gr_br_delta':np.abs(np.array(stats['core_gr_br'])-reference['core_gr_br']).round(5).tolist()})
sheet.save(OUT/'comparison.png')
report={'reference':reference,'controlled_source':'fire24-field29','frame_comparisons':rows,
        'contact':'docs/art/fire-single-tongue-20261106/color-control-comparison/comparison.png',
        'no_local_color_or_motion_edit':True,'art_acceptance':False}
(OUT/'report.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print(json.dumps({'comparisons':[{k:r[k] for k in ['key','frame','luma_ratio_to_input','absolute_core_gr_br_delta','visible_unique_rgb_colors']} for r in rows]}))
