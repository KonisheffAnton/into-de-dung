"""Diagnostic assembly of PixelLab raw 07–09; never synthesizes motion pixels."""
from pathlib import Path
from PIL import Image, ImageDraw
import hashlib
import json
import numpy as np

ROOT = Path(__file__).resolve().parents[4]
HERE = Path(__file__).resolve().parent
REPORT = ROOT / 'test_reports/fire-single-tongue-20261106/candidate-evaluation.json'
SOURCE = ROOT / 'docs/art/fire-low-styles-20261104/fire-low-24.png'
CROP = ROOT / 'docs/art/fire-single-tongue-20261106/inputs/fire24-input-128.png'
MASK = ROOT / 'docs/art/fire-single-tongue-20261106/inputs/fire24-motion-guide-mask-128.png'
RAW = ROOT / 'docs/art/fire-single-tongue-20261106/results/fire24-single01/raw'
BOX = (664, 436, 792, 564)
SELECTED = (7, 8, 9)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def hot(arr):
    return (arr[:, :, 0] > 230) & (arr[:, :, 1] > 135) & (arr[:, :, 2] < 125) & (arr[:, :, 3] > 200)

def bbox(mask):
    y, x = np.where(mask)
    return [int(x.min()), int(y.min()), int(x.max()+1), int(y.max()+1)] if len(x) else None

def main():
    source = Image.open(SOURCE).convert('RGBA')
    original = np.array(source)
    crop = np.array(Image.open(CROP).convert('RGBA'))
    assert np.array_equal(crop, original[BOX[1]:BOX[3], BOX[0]:BOX[2]])
    mask = np.array(Image.open(MASK).convert('L')) > 0
    assert mask.shape == (128, 128)
    boundary = np.zeros(mask.shape, bool)
    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
        boundary |= mask & ~np.roll(mask, (dy,dx), (0,1))
    source_hot = hot(crop) & mask
    source_hot_bbox = bbox(source_hot)
    local = np.zeros(mask.shape, bool);local[45:83,35:105] = True
    root_band = np.zeros(mask.shape, bool);root_band[68:74,50:84] = True;root_band &= mask
    frames = [crop]
    frame_data = []
    contact = Image.new('RGBA', (4*256, 256), (32,35,40,255))
    contact.alpha_composite(source.resize((256,256), Image.Resampling.LANCZOS), (0,0))
    close = Image.new('RGBA', (4*512, 540), (32,35,40,255))
    draw = ImageDraw.Draw(close)
    for col, (label, arr) in enumerate([('source',crop)]+[(f'raw {i:02}',np.array(Image.open(RAW/f'frame-{i:02}.png').convert('RGBA'))) for i in SELECTED]):
        image = Image.fromarray(arr, 'RGBA').resize((512,512), Image.Resampling.NEAREST)
        close.alpha_composite(image, (col*512,28))
        draw.text((col*512+7,7),label,fill='white')
    close.convert('RGB').save(HERE/'roi-contact-4x.png')
    for col, i in enumerate(SELECTED,1):
        raw_path = RAW / f'frame-{i:02}.png'
        raw_arr = np.array(Image.open(raw_path).convert('RGBA'))
        frames.append(raw_arr)
        assembled = original.copy()
        region = assembled[BOX[1]:BOX[3], BOX[0]:BOX[2]]
        region[mask] = raw_arr[mask]
        assert np.array_equal(region[~mask], crop[~mask])
        assert np.array_equal(region[mask], raw_arr[mask])
        full_path = HERE / f'frame-{i:02}-full.png'
        view_path = HERE / f'frame-{i:02}-view-256.png'
        out = Image.fromarray(assembled, 'RGBA')
        out.save(full_path)
        out.resize((256,256), Image.Resampling.LANCZOS).save(view_path)
        contact.alpha_composite(Image.open(view_path).convert('RGBA'), (col*256,0))
        delta = np.max(np.abs(raw_arr[:,:,:3].astype(int)-crop[:,:,:3].astype(int)), axis=2)
        alpha_delta = np.abs(raw_arr[:,:,3].astype(int)-crop[:,:,3].astype(int))
        h = hot(raw_arr)&mask
        y,x=np.where(h)
        frame_data.append({'raw_frame':i,'raw_sha256':sha(raw_path),
            'assembled_full_sha256':sha(full_path),'view256_sha256':sha(view_path),
            'mask_pixels':int(mask.sum()),'outside_mask_changed_pixels':0,
            'hot_core_pixels':int(h.sum()),'hot_core_bbox_xyxy':bbox(h),
            'hot_core_centroid_xy':[round(float(x.mean()),3),round(float(y.mean()),3)],
            'hot_core_tip_y_roi':int(y.min()),
            'tip_upward_change_vs_source_px':int(source_hot_bbox[1]-y.min()),
            'hot_core_outside_mask_in_local_roi':int((hot(raw_arr)&local&~mask).sum()),
            'tongue_base_band_pixels':int(root_band.sum()),
            'tongue_base_band_rgb_maxdiff_gt8_vs_source':int((delta[root_band]>8).sum()),
            'inside_mask_rgb_maxdiff_gt8_vs_source':int((delta[mask]>8).sum()),
            'inside_mask_rgb_maxdiff_gt20_vs_source':int((delta[mask]>20).sum()),
            'inside_mask_alpha_changed_pixels':int((alpha_delta[mask]>0).sum()),
            'inside_mask_alpha_maxdiff_vs_source':int(alpha_delta[mask].max()),
            'boundary_rgb_maxdiff_gt8_vs_source':int((delta[boundary]>8).sum()),
            'boundary_rgb_maxdiff_gt20_vs_source':int((delta[boundary]>20).sum()),
            'boundary_rgb_maxdiff_max_vs_source':int(delta[boundary].max())})
    contact.convert('RGB').save(HERE/'full-contact-256.png')
    # The red outline is diagnostic only; assembled art files above stay untouched.
    diag = Image.new('RGBA',(4*512,540),(32,35,40,255)); dd=ImageDraw.Draw(diag)
    outline=mask & ~np.roll(mask,(1,0),(0,1)) | mask & ~np.roll(mask,(-1,0),(0,1)) | mask & ~np.roll(mask,(0,1),(0,1)) | mask & ~np.roll(mask,(0,-1),(0,1))
    for col,arr in enumerate(frames):
        marked=arr.copy(); marked[outline]=[255,30,30,255]
        diag.alpha_composite(Image.fromarray(marked,'RGBA').resize((512,512),Image.Resampling.NEAREST),(col*512,28))
        dd.text((col*512+7,7),'source' if col==0 else f'raw {SELECTED[col-1]:02}',fill='white')
    diag.convert('RGB').save(HERE/'mask-boundary-4x.png')
    pairs=[]
    for left,right,a,b in zip((7,8),(8,9),frames[1:-1],frames[2:]):
        ha=hot(a)&mask;hb=hot(b)&mask
        d=np.max(np.abs(a[:,:,:3].astype(int)-b[:,:,:3].astype(int)),axis=2)
        pairs.append({'from':left,'to':right,'hot_core_xor_pixels':int(np.logical_xor(ha,hb).sum()),
            'inside_mask_rgb_maxdiff_gt8':int((d[mask]>8).sum()),
            'inside_mask_rgb_maxdiff_gt20':int((d[mask]>20).sum())})
    result={'source_sha256':sha(SOURCE),'crop_sha256':sha(CROP),'mask_sha256':sha(MASK),
        'roi_xyxy':list(BOX),'raw_frames':[7,8,9],'proposed_playback':[7,8,9,8],
        'proposed_pose_duration_ms':120,'assembled_type':'fixed original 1254x1254 plate plus exact unmodified raw PixelLab pixels inside one fixed 128x128 mask',
        'view256_type':'full-frame proportional LANCZOS downscale for inspection only',
        'source_hot_core_bbox_xyxy':source_hot_bbox,'frames':frame_data,'adjacent_pairs':pairs,
        'assessment':'FAIL: the selected central highlight changes only a few hot-core pixels between 07,08,09; centroid and tip contour remain effectively still. This reads as brightness/texture flicker, not a useful sway. Raw alpha is 255 throughout the mask while the source is 252–254, creating a faint alpha boundary. No playable candidate polished.',
        'art_pass':False,'new_provider_posts':0,'new_motion_pixels':0}
    REPORT.parent.mkdir(parents=True,exist_ok=True)
    REPORT.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('FAIL candidate:',[(x['from'],x['to'],x['hot_core_xor_pixels']) for x in pairs])

if __name__ == '__main__':
    main()
