"""Build a file:// gallery catalog from completed, byte-checked PixelLab field jobs.

The builder never edits raw frames or source art. It only writes data.js here.
"""
from pathlib import Path
from PIL import Image
import hashlib
import json
import os
import numpy as np

ROOT=Path(__file__).resolve().parents[4]
PACKAGE=ROOT/'docs/art/fire-single-tongue-20261106'
HERE=Path(__file__).resolve().parent
REQUESTS=PACKAGE/'requests'
RESULTS=PACKAGE/'results'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def link(path):
    return Path(os.path.relpath(path,HERE)).as_posix()

def rgba(path):
    with Image.open(path) as image:
        return np.array(image.convert('RGBA'))

def seam_metrics(first,last):
    alpha_first=first[:,:,3].astype(np.int16)
    alpha_last=last[:,:,3].astype(np.int16)
    gray=40.0
    def composite(arr):
        a=arr[:,:,3:4].astype(float)/255.0
        return arr[:,:,:3].astype(float)*a+gray*(1-a)
    rgb=np.max(np.abs(composite(first)-composite(last)),axis=2)
    return {'rgba_different_pixels':int(np.any(first!=last,axis=2).sum()),
            'alpha_gt8_silhouette_xor_pixels':int(np.logical_xor(alpha_first>8,alpha_last>8).sum()),
            'gray_composite_rgb_maxdiff_gt8_pixels':int((rgb>8).sum()),
            'exact_rgba':bool(np.array_equal(first,last))}

def inspect(request_path):
    meta=json.loads(request_path.read_text(encoding='utf-8'))
    key=meta['key'];result_dir=RESULTS/key;manifest_path=result_dir/'manifest.json'
    if not manifest_path.is_file():return None,{'key':key,'reason':'completed manifest ещё отсутствует'}
    try:
        manifest=json.loads(manifest_path.read_text(encoding='utf-8'))
        count=int(manifest['returned_frames'])
        assert manifest['key']==key and count>=2
        assert len(manifest['frames'])==count
        assert [int(row['frame']) for row in manifest['frames']]==list(range(count))
        box=[int(v) for v in meta['group']['crop_xyxy']]
        size=int(meta['group']['crop_size'])
        assert box[2]-box[0]==size and box[3]-box[1]==size and size in (128,256)
        source=ROOT/f"docs/art/fire-low-styles-20261104/fire-low-{key[4:6]}.png"
        input_path=ROOT/meta['group']['input_path']
        context_path=ROOT/meta['group']['context_path']
        assert source.is_file() and input_path.is_file() and context_path.is_file()
        assert sha(source)==meta['source_sha256']
        assert sha(input_path)==meta['input_sha256']==meta['group']['input_sha256']
        assert sha(context_path)==meta['group']['context_sha256']
        assert Image.open(source).size==(1254,1254)
        assert Image.open(input_path).size==(size,size)
        assert Image.open(context_path).size==(size,size)
        raw_paths=[]
        for i,row in enumerate(manifest['frames']):
            path=result_dir/'raw'/f'frame-{i:02}.png'
            assert path.is_file() and sha(path)==row['sha256']
            assert Image.open(path).size==(size,size)
            raw_paths.append(path)
        first,last=rgba(raw_paths[0]),rgba(raw_paths[-1])
        clip={'key':key,'style':key[4:6],'group_key':meta['group']['key'],
              'box_xyxy':box,'native_size':size,'count':count,
              'source':link(source),'source_sha256':sha(source),
              'context':link(context_path),'input':link(input_path),
              'input_sha256':sha(input_path),'manifest':link(manifest_path),
              'request_metadata':link(request_path),
              'frames':[link(p) for p in raw_paths],
              'frame_sha256':[row['sha256'] for row in manifest['frames']],
              'seam':seam_metrics(first,last),
              'preview_only':True,'art_acceptance':False}
        return clip,None
    except (OSError,KeyError,ValueError,AssertionError,TypeError,IndexError) as error:
        return None,{'key':key,'reason':'result ещё не прошёл проверку полноты и SHA','detail':str(error)[:160]}

def main():
    clips=[];pending=[]
    for request_path in sorted(REQUESTS.glob('fire*-field*/request-metadata.json')):
        clip,waiting=inspect(request_path)
        if clip:clips.append(clip)
        else:pending.append(waiting)
    catalog={'purpose':'Diagnostic file-local comparison; not completed full-tile fire art',
             'clips':clips,'pending':pending,
             'full_tile_compositing':'Canvas draws original 1254x1254 at 1:1, then raw RGBA at unchanged crop XY; no warp, tween, recolor or extra motion pixels.',
             'frame_duration_ms':120}
    (HERE/'data.js').write_text('window.FIELD_REVIEW_DATA='+json.dumps(catalog,ensure_ascii=False,separators=(',',':'))+';\n',encoding='utf-8')
    print(json.dumps({'included':[x['key'] for x in clips],'pending':[x['key'] for x in pending]},ensure_ascii=False))

if __name__=='__main__':main()
