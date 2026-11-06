"""Extract static, source-pixel-exact fire strokes for later PixelLab selection.

No moving pixels are generated. All RGB in each context and transparent input
comes unchanged from the original 1254-square painting. Masks are binary alpha
guides over existing source pixels only.
"""
from pathlib import Path
from collections import deque
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
REPORT = ROOT/'test_reports/fire-single-tongue-20261106/field-inputs.json'
SIZE = 1254
MIN_CORE = 100
HALO_RADIUS = 3
TOP_VERTICES = [(627,245),(954,493),(627,734),(300,493)]
STYLES = {
    '24': {'source':'docs/art/fire-low-styles-20261104/fire-low-24.png',
           'core':'R>230 and G>135 and B<125',
           'medium':'R>220 and G>110 and B<150'},
    '29': {'source':'docs/art/fire-low-styles-20261104/fire-low-29.png',
           'core':'R>205 and G>95 and B<110 and R-G>75',
           'medium':'R>200 and G>92 and B<115 and R-G>70'},
}

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def components(mask):
    """Eight-connected regions, retaining exact pixel coordinates for extraction."""
    labels = np.zeros(mask.shape, np.int32)
    groups = []
    for y0,x0 in zip(*np.where(mask)):
        if labels[y0,x0]: continue
        index=len(groups)+1
        labels[y0,x0]=index
        queue=deque([(int(x0),int(y0))]);pixels=[]
        while queue:
            x,y=queue.popleft();pixels.append((x,y))
            for dy in (-1,0,1):
                for dx in (-1,0,1):
                    xx,yy=x+dx,y+dy
                    if 0<=xx<SIZE and 0<=yy<SIZE and mask[yy,xx] and not labels[yy,xx]:
                        labels[yy,xx]=index;queue.append((xx,yy))
        xs=[x for x,_ in pixels];ys=[y for _,y in pixels]
        groups.append({'index':index,'pixels':pixels,
                       'bbox':[min(xs),min(ys),max(xs)+1,max(ys)+1],
                       'centroid':[sum(xs)/len(xs),sum(ys)/len(ys)]})
    return labels,groups

def crop_box(bbox):
    x0,y0,x1,y1=bbox
    span=max(x1-x0,y1-y0)
    size=128 if span+20<=128 else 256
    if span+20>256: raise ValueError(f'Connected stroke too large for native crop: {bbox}')
    cx=(x0+x1)//2;cy=(y0+y1)//2
    left=max(0,min(SIZE-size,cx-size//2));top=max(0,min(SIZE-size,cy-size//2))
    box=[left,top,left+size,top+size]
    if x0-left<10 or box[2]-x1<10 or y0-top<10 or box[3]-y1<10:
        raise ValueError(f'Insufficient source margin {bbox} in {box}')
    return box

def style_masks(key,rgba,top):
    r,g,b,a=[rgba[:,:,i].astype(np.int16) for i in range(4)]
    if key=='24':
        core=(r>230)&(g>135)&(b<125)
        medium=(r>220)&(g>110)&(b<150)
    else:
        core=(r>205)&(g>95)&(b<110)&(r-g>75)
        medium=(r>200)&(g>92)&(b<115)&(r-g>70)
    valid=top&(a>200)
    core &= valid;medium &= valid
    assert not (core&~medium).any()
    return core,medium

def font():
    path=Path('C:/Windows/Fonts/arial.ttf')
    return ImageFont.truetype(str(path),18) if path.exists() else ImageFont.load_default()

def build_style(key,spec):
    source_path=ROOT/spec['source'];source=Image.open(source_path).convert('RGBA')
    source_array=np.array(source)
    top_image=Image.new('1',(SIZE,SIZE),0)
    ImageDraw.Draw(top_image).polygon(TOP_VERTICES,fill=1)
    top=np.array(top_image,dtype=bool)
    core,medium=style_masks(key,source_array,top)
    labels,all_components=components(medium)
    core_count=np.bincount(labels[core],minlength=len(all_components)+1)
    selected=[c for c in all_components if core_count[c['index']]>=MIN_CORE]
    selected.sort(key=lambda c:(c['centroid'][1],c['centroid'][0]))
    residual=[c for c in all_components if 0<core_count[c['index']]<MIN_CORE]
    coverage=np.zeros((SIZE,SIZE),np.uint16)
    selected_core=np.zeros((SIZE,SIZE),bool)
    group_rows=[]
    style_dir=HERE/f'fire{key}';style_dir.mkdir(parents=True,exist_ok=True)
    for ordinal,component in enumerate(selected,1):
        name=f'fire{key}-{ordinal:02}'
        group_dir=style_dir/name;group_dir.mkdir(parents=True,exist_ok=True)
        box=crop_box(component['bbox']);x0,y0,x1,y1=box
        size=x1-x0
        region=source_array[y0:y1,x0:x1]
        local=np.zeros((size,size),np.uint8)
        for x,y in component['pixels']:local[y-y0,x-x0]=255
        dilated=np.array(Image.fromarray(local,'L').filter(ImageFilter.MaxFilter(2*HALO_RADIUS+1)))>0
        alpha_mask=dilated&(region[:,:,3]>0)
        own_core=(labels[y0:y1,x0:x1]==component['index'])&core[y0:y1,x0:x1]
        assert not (own_core&~alpha_mask).any()
        selected_core[y0:y1,x0:x1] |= own_core
        coverage[y0:y1,x0:x1] += alpha_mask.astype(np.uint16)
        transparent=region.copy();transparent[:,:,3]=np.where(alpha_mask,region[:,:,3],0)
        assert np.array_equal(transparent[:,:,:3],region[:,:,:3])
        context_path=group_dir/'context.png';input_path=group_dir/'input-transparent.png'
        alpha_path=group_dir/'alpha-mask.png';core_path=group_dir/'core-mask.png'
        Image.fromarray(region,'RGBA').save(context_path)
        Image.fromarray(transparent,'RGBA').save(input_path)
        Image.fromarray((alpha_mask*255).astype('uint8'),'L').save(alpha_path)
        Image.fromarray((own_core*255).astype('uint8'),'L').save(core_path)
        border=np.zeros((size,size),bool)
        border[0,:]=True;border[-1,:]=True;border[:,0]=True;border[:,-1]=True
        group_rows.append({'key':name,'source_component_id':component['index'],
            'crop_xyxy':box,'crop_size':size,'stroke_bbox_xyxy':component['bbox'],
            'core_pixels':int(own_core.sum()),'medium_stroke_pixels':len(component['pixels']),
            'alpha_mask_pixels':int(alpha_mask.sum()),
            'core_clipped_by_alpha_mask_pixels':int((own_core&~alpha_mask).sum()),
            'core_on_crop_border_pixels':int((own_core&border).sum()),
            'alpha_mask_on_crop_border_pixels':int((alpha_mask&border).sum()),
            'foreign_core_pixels_inside_alpha_mask':int((alpha_mask&core[y0:y1,x0:x1]&~own_core).sum()),
            'context_path':str(context_path.relative_to(ROOT)).replace('\\','/'),
            'context_sha256':sha(context_path),
            'input_path':str(input_path.relative_to(ROOT)).replace('\\','/'),
            'input_sha256':sha(input_path),
            'alpha_mask_path':str(alpha_path.relative_to(ROOT)).replace('\\','/'),
            'alpha_mask_sha256':sha(alpha_path),
            'core_mask_path':str(core_path.relative_to(ROOT)).replace('\\','/'),
            'core_mask_sha256':sha(core_path)})
    candidate_overlap_pixels=int((coverage>1).sum())
    candidate_foreign_core_pixels=sum(r['foreign_core_pixels_inside_alpha_mask'] for r in group_rows)
    prepared=[]
    for row in group_rows:
        x0,y0,x1,y1=row['crop_xyxy']
        mask=np.array(Image.open(ROOT/row['alpha_mask_path']).convert('L'))>0
        own=np.array(Image.open(ROOT/row['core_mask_path']).convert('L'))>0
        # Residual cores belong to the unchanged source plate; another selected
        # core always belongs to its own group, never to this group's halo.
        mask &= ~core[y0:y1,x0:x1] | own
        cy,cx=np.where(own)
        coords=np.stack((cx.astype(np.int32)+x0,cy.astype(np.int32)+y0),axis=1)
        prepared.append({'row':row,'box':(x0,y0,x1,y1),'mask':mask,'own':own,'coords':coords})
    coverage=np.zeros((SIZE,SIZE),np.uint16)
    for item in prepared:
        x0,y0,x1,y1=item['box'];coverage[y0:y1,x0:x1]+=item['mask'].astype(np.uint16)
    for y,x in zip(*np.where(coverage>1)):
        contenders=[]
        for item in prepared:
            x0,y0,x1,y1=item['box']
            if x0<=x<x1 and y0<=y<y1 and item['mask'][y-y0,x-x0]:
                delta=item['coords']-np.array([x,y],dtype=np.int32)
                distance=int(np.min(np.sum(delta*delta,axis=1)))
                contenders.append((distance,item['row']['key'],item))
        winner=min(contenders,key=lambda entry:(entry[0],entry[1]))[2]
        for _,_,item in contenders:
            if item is winner:continue
            x0,y0,_,_=item['box'];item['mask'][y-y0,x-x0]=False
    coverage=np.zeros((SIZE,SIZE),np.uint16)
    for item in prepared:
        row=item['row'];x0,y0,x1,y1=item['box'];mask=item['mask'];own=item['own']
        region=source_array[y0:y1,x0:x1]
        assert not (own&~mask).any()
        assert not (mask&core[y0:y1,x0:x1]&~own).any()
        coverage[y0:y1,x0:x1]+=mask.astype(np.uint16)
        transparent=region.copy();transparent[:,:,3]=np.where(mask,region[:,:,3],0)
        assert np.array_equal(transparent[:,:,:3],region[:,:,:3])
        input_path=ROOT/row['input_path'];alpha_path=ROOT/row['alpha_mask_path']
        Image.fromarray(transparent,'RGBA').save(input_path)
        Image.fromarray((mask*255).astype('uint8'),'L').save(alpha_path)
        border=np.zeros(mask.shape,bool)
        border[0,:]=True;border[-1,:]=True;border[:,0]=True;border[:,-1]=True
        row['alpha_mask_pixels']=int(mask.sum())
        row['core_clipped_by_alpha_mask_pixels']=int((own&~mask).sum())
        row['alpha_mask_on_crop_border_pixels']=int((mask&border).sum())
        row['foreign_core_pixels_inside_alpha_mask']=int((mask&core[y0:y1,x0:x1]&~own).sum())
        row['input_sha256']=sha(input_path);row['alpha_mask_sha256']=sha(alpha_path)
    assert not (coverage>1).any()
    uncovered=core&(coverage==0)
    overlap=coverage>1
    overlap_pairs=[]
    for i,left in enumerate(group_rows):
        lx0,ly0,lx1,ly1=left['crop_xyxy']
        for right in group_rows[i+1:]:
            rx0,ry0,rx1,ry1=right['crop_xyxy']
            x0,y0,x1,y1=max(lx0,rx0),max(ly0,ry0),min(lx1,rx1),min(ly1,ry1)
            if x0>=x1 or y0>=y1:continue
            la=np.array(Image.open(ROOT/left['alpha_mask_path']).convert('L'))>0
            ra=np.array(Image.open(ROOT/right['alpha_mask_path']).convert('L'))>0
            shared=int((la[y0-ly0:y1-ly0,x0-lx0:x1-lx0]&
                        ra[y0-ry0:y1-ry0,x0-rx0:x1-rx0]).sum())
            if shared:overlap_pairs.append({'a':left['key'],'b':right['key'],'pixels':shared})
    # Full source remains visible; translucent colors and numbers are QA only.
    overview=source.copy()
    tint=Image.new('RGBA',(SIZE,SIZE),(0,0,0,0));tint_pixels=np.array(tint)
    tint_pixels[coverage==1]=[42,210,130,72]
    tint_pixels[overlap]=[240,70,170,140]
    tint_pixels[uncovered]=[255,225,40,190]
    overview=Image.alpha_composite(overview,Image.fromarray(tint_pixels,'RGBA'))
    draw=ImageDraw.Draw(overview);label_font=font()
    for ordinal,c in enumerate(selected,1):
        x,y=round(c['centroid'][0]),round(c['centroid'][1])
        label=f'{ordinal:02}'
        draw.rounded_rectangle((x-16,y-11,x+16,y+12),radius=4,fill=(17,24,35,225))
        draw.text((x-11,y-10),label,fill='white',font=label_font)
    overview_path=HERE/f'coverage-fire{key}.png';overview.save(overview_path)
    residual_rows=[{'core_pixels':int(core_count[c['index']]),'bbox_xyxy':c['bbox']}
                   for c in residual]
    residual_rows.sort(key=lambda x:x['core_pixels'],reverse=True)
    return {'source_path':spec['source'],'source_sha256':sha(source_path),
        'source_size':[SIZE,SIZE],'core_threshold':spec['core'],
        'medium_stroke_threshold':spec['medium'],
        'top_polygon_xy':TOP_VERTICES,'min_significant_core_pixels':MIN_CORE,
        'alpha_mask':'8-connected medium stroke dilated by 3 native pixels, intersected with original nonzero alpha; foreign cores excluded and shared halo assigned to nearest own core',
        'group_count':len(group_rows),'core_pixels_total':int(core.sum()),
        'selected_core_pixels':int(selected_core.sum()),
        'uncovered_core_pixels':int(uncovered.sum()),
        'uncovered_core_percent':round(float(uncovered.sum()/core.sum()*100),3),
        'alpha_mask_overlap_pixels':int(overlap.sum()),
        'alpha_mask_overlap_max_multiplicity':int(coverage.max()),
        'alpha_mask_overlap_pairs':overlap_pairs,
        'candidate_overlap_pixels_before_nearest_core_assignment':candidate_overlap_pixels,
        'candidate_foreign_core_pixels_before_assignment':candidate_foreign_core_pixels,
        'overlap_resolution':'Foreign cores removed from halos; shared non-core halo pixels assigned by minimum Euclidean distance to each candidate group own core (key tie-break). Residual cores remain on static original plate.',
        'foreign_core_pixels_inside_masks_total':sum(r['foreign_core_pixels_inside_alpha_mask'] for r in group_rows),
        'groups_with_foreign_core':[r['key'] for r in group_rows if r['foreign_core_pixels_inside_alpha_mask']>0],
        'full_source_alpha_or_rgb_modified':False,
        'all_inputs_rgb_exact_source_crop':True,
        'core_clip_pixels_total':sum(r['core_clipped_by_alpha_mask_pixels'] for r in group_rows),
        'core_crop_border_pixels_total':sum(r['core_on_crop_border_pixels'] for r in group_rows),
        'alpha_crop_border_pixels_total':sum(r['alpha_mask_on_crop_border_pixels'] for r in group_rows),
        'overview_path':str(overview_path.relative_to(ROOT)).replace('\\','/'),
        'overview_legend':'green=covered by one static alpha group; pink=overlapping static groups; yellow=uncovered threshold core; numbered groups are individual inputs',
        'groups':group_rows,'static_residual_core_components':residual_rows,
        'caveat':'Threshold core coverage measures selected source light strokes, not animated coverage or artistic acceptance. Diffuse red heat outside the core stays on the original static tile.'}

def main():
    result={'purpose':'Static PixelLab input candidates for later whole-fire composition; no animation generated here.',
        'native_crops_only':True,'rgb_recolor_or_warp':False,'moving_frames_created':0,'provider_posts':0,
        'styles':{key:build_style(key,spec) for key,spec in STYLES.items()}}
    sample_keys=[('fire24','fire24-07'),('fire24','fire24-30'),('fire29','fire29-01'),('fire29','fire29-26')]
    samples=Image.new('RGBA',(512,568),(32,36,42,255));draw=ImageDraw.Draw(samples)
    for i,(style,key) in enumerate(sample_keys):
        img=Image.open(HERE/style/key/'input-transparent.png').convert('RGBA')
        if img.size!=(256,256):img=img.resize((256,256),Image.Resampling.NEAREST)
        background=Image.new('RGBA',(256,256),(42,48,56,255));background.alpha_composite(img)
        x=i%2*256;y=i//2*284
        samples.alpha_composite(background,(x,y+24));draw.text((x+5,y+5),key,fill='white')
    samples.convert('RGB').save(HERE/'qa-transparent-samples.png')
    result['qa_sample_path']='docs/art/fire-single-tongue-20261106/field-inputs/qa-transparent-samples.png'
    result['qa_sample_note']='Preview-only: 128px samples enlarged with nearest-neighbor. PixelLab inputs are native and never resized.'
    REPORT.parent.mkdir(parents=True,exist_ok=True)
    REPORT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    for key,style in result['styles'].items():
        print(key,'groups',style['group_count'],'core',style['core_pixels_total'],
              'uncovered',style['uncovered_core_pixels'],'overlap',style['alpha_mask_overlap_pixels'],
              'clip',style['core_clip_pixels_total'])

if __name__=='__main__':main()
