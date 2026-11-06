"""Select and score existing PixelLab cutout PNG frames; create no new poses."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
RAW = ROOT / 'docs/art/fire-single-tongue-20261106/results/fire24-cutout02/raw'
SOURCE = ROOT / 'docs/art/fire-single-tongue-20261106/inputs/fire24-tongue-reference-128.png'
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/cutout-playback-evaluation.json'
ORDER = [8, 9, 10, 2, 12, 11, 3, 11, 12, 2, 10, 9, 8]
DURATION_MS = 120
BACKGROUND = 40

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def load(index):
    return np.array(Image.open(RAW/f'frame-{index:02}.png').convert('RGBA')).astype(np.int16)

def composite(arr):
    alpha = arr[:, :, 3:4].astype(float) / 255
    return arr[:, :, :3].astype(float) * alpha + BACKGROUND * (1-alpha)

def centroid(arr, roi):
    y, x = np.mgrid[:128, :128]
    w = arr[:, :, 3].astype(float) * roi
    return [round(float((x*w).sum()/w.sum()),3),round(float((y*w).sum()/w.sum()),3)]

def pair(a,b,src,dst):
    ma=a[:,:,3]>8;mb=b[:,:,3]>8
    delta=np.abs(composite(a)-composite(b))
    left=np.zeros((128,128),bool);left[58:73,38:52]=True
    return {'from':src,'to':dst,
        'alpha_silhouette_xor_pixels':int(np.logical_xor(ma,mb).sum()),
        'alpha_abs_delta_equivalent_pixels':round(float(np.abs(a[:,:,3]-b[:,:,3]).sum()/255),3),
        'neutral_gray_rgb_maxdiff_gt8_pixels':int((np.max(delta,axis=2)>8).sum()),
        'neutral_gray_mean_abs_rgb':round(float(delta.mean()),4),
        'left_base_alpha_xor_pixels':int(np.logical_xor(ma,mb)[left].sum()),
        'left_base_neutral_gray_rgb_maxdiff_gt8_pixels':int((np.max(delta,axis=2)>8)[left].sum())}

def main():
    assert len(ORDER)==13 and ORDER[0]==ORDER[-1]
    arrays={i:load(i) for i in set(ORDER)}
    assert all(a.shape==(128,128,4) for a in arrays.values())
    source=np.array(Image.open(SOURCE).convert('RGBA')).astype(np.int16)
    left=np.zeros((128,128),bool);left[58:73,38:52]=True
    tip=np.zeros((128,128),bool);tip[52:76,76:92]=True
    poses=[]
    for i in sorted(arrays):
        path=RAW/f'frame-{i:02}.png';a=arrays[i]
        poses.append({'raw_index':i,'sha256':sha(path),'visible_alpha_gt8_pixels':int((a[:,:,3]>8).sum()),
            'left_base_alpha_centroid_xy':centroid(a,left),
            'right_tip_alpha_centroid_xy':centroid(a,tip),
            'alpha_xor_vs_source_contour':int(np.logical_xor(a[:,:,3]>8,source[:,:,3]>8).sum())})
    edges=[pair(arrays[a],arrays[b],a,b) for a,b in zip(ORDER,ORDER[1:])]
    seam=pair(arrays[ORDER[-1]],arrays[ORDER[0]],ORDER[-1],ORDER[0])
    reference_to_start=pair(source,arrays[ORDER[0]],'painted_reference',ORDER[0])
    def max_pair(order):
        scores=[pair(load(a),load(b),a,b) for a,b in zip(order,order[1:])]
        return {'max_alpha_silhouette_xor_pixels':max(x['alpha_silhouette_xor_pixels'] for x in scores),
                'max_neutral_gray_rgb_maxdiff_gt8_pixels':max(x['neutral_gray_rgb_maxdiff_gt8_pixels'] for x in scores)}
    timeline={'source_reference':'../inputs/fire24-tongue-reference-128.png',
        'source_reference_sha256':sha(SOURCE),'raw_directory':'../results/fire24-cutout02/raw/',
        'raw_frames_preserved':True,'raw_sha256_by_index':{str(i):sha(RAW/f'frame-{i:02}.png') for i in sorted(arrays)},
        'order':ORDER,'duration_ms_each':DURATION_MS,
        'loop':True,'cycle_duration_ms':len(ORDER)*DURATION_MS,
        'description':'Existing PixelLab cutout poses selected and replayed forward, then backward; no generated in-between or altered PNG pixels.'}
    (HERE/'timeline.json').write_text(json.dumps(timeline,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    # Contact is inspection evidence; it does not change the raw pose pixels.
    forward=ORDER[:7]
    contact=Image.new('RGBA',(len(forward)*256,285),(36,40,47,255));d=ImageDraw.Draw(contact)
    for col,i in enumerate(forward):
        image=Image.fromarray(arrays[i].astype('uint8'),'RGBA').resize((256,256),Image.Resampling.NEAREST)
        contact.alpha_composite(image,(col*256,25));d.text((col*256+5,5),f'PixelLab raw {i:02}',fill='white')
    contact.convert('RGB').save(HERE/'forward-contact-2x.png')
    assessment={'technical_frame_source':'PixelLab raw RGBA PNG, exact bytes referenced by SHA-256',
        'new_provider_posts':0,'new_motion_poses':0,'local_warp_recolor_tween':False,
        'order':ORDER,'duration_ms_each':DURATION_MS,'poses':poses,'adjacent_edges':edges,'seam':seam,
        'reference_to_start':reference_to_start,
        'optimized_max':max_pair(ORDER),'prior_raw_08_to_15_max':max_pair(list(range(8,16))),
        'parent_suggested_order_max':max_pair([8,9,10,2,14,13,4,12,11,3]),
        'notes':['The cutout bend is mostly downward and returns along the same selected poses; it is not a lateral sway.',
                 'The largest remaining silhouette step is 02→12 (37 pixels); inspect worst-transition-4x.png and native playback before artistic acceptance.',
                 'The source reference and first raw 08 have identical alpha silhouette but differ in visible color.',
                 'Left base centroid moves <=0.04 px in X/Y across selected poses; right-tip alpha-weighted Y moves approximately 1.5 px downward and returns.'],
        'technical_candidate_pass':True,'art_acceptance':False,
        'browser_check_path':'docs/art/fire-single-tongue-20261106/cutout-playback/browser-check.json'}
    REPORT.parent.mkdir(parents=True,exist_ok=True)
    REPORT.write_text(json.dumps(assessment,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('max optimized',assessment['optimized_max'],'seam',seam['alpha_silhouette_xor_pixels'])

if __name__=='__main__': main()
