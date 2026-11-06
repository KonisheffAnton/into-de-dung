"""Три крупных мазка: усиливаем существующий изгиб без ускорения всей анимации."""
from pathlib import Path
import hashlib
import json
import os

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[2]
OLD=ROOT.parent/'fire-single-tongue-20261106'
EXTERNAL=Path('C:/Users/Aston/.codex/generated_images/fire29-readable-20261106')
DESCRIPTION=(
    'Animate only the EXISTING low curved painted flame tips. Make their gentle SIDEWAYS SWAY '
    'clearly readable: existing curved ends bend 10 to 12 pixels sideways and return, with '
    'several smooth intermediate curved poses. Keep the broad roots and lower bodies firmly pinned. '
    'Preserve the exact original low flattened height, number of tongues, curled silhouette, '
    'painted texture and yellow orange ochre colors. Do not extend tips upward, shoot out new '
    'tongues, flash, pulse brightness, add sparks, grow branches or split curls. '
    'Constant brightness and opacity. Existing fire simply burns with wider slow sideways bends. '
    'Fixed camera. Transparent background.')

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def main():
    for old_key,key in [('fire29-short01','fire29-visible01'),('fire29-field14','fire29-visible02'),('fire29-field22','fire29-visible03')]:
        old_path=OLD/'requests'/old_key/'request.json'
        before=json.loads(old_path.read_text())
        request={**before,'description':DESCRIPTION,'frame_count':16}
        meta=json.loads((old_path.parent/'request-metadata.json').read_text())
        changed=[k for k in request if request[k]!=before[k]]
        assert set(changed)<= {'description','frame_count'}
        target=ROOT/'requests'/key;job=EXTERNAL/'pixellab'/key
        assert not target.exists() and not job.exists()
        target.mkdir(parents=True);job.mkdir(parents=True)
        payload=(json.dumps(request,indent=2)+'\n').encode()
        (target/'request.json').write_bytes(payload);(job/'request.json').write_bytes(payload)
        inp=REPO/meta['group']['input_path']
        assert sha(inp)==meta['input_sha256']
        result={'key':key,'group':meta['group'],'endpoint':'animate-pixminimax',
                'input':Path(os.path.relpath(inp,ROOT)).as_posix(),'input_sha256':sha(inp),
                'input_size':meta['input_size'],'source_sha256':meta['source_sha256'],
                'request_sha256':sha(target/'request.json'),'requested_frames':16,
                'controlled_comparison_to':old_key,'old_request_sha256':sha(old_path),
                'changed_payload_fields':changed,'requested_tip_sideways_native_px':[10,12],
                'native_crop_no_resize':True,'local_motion_generation':False}
        (target/'request-metadata.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n')
        print(json.dumps({'key':key,'changed':changed}))

if __name__=='__main__':main()
