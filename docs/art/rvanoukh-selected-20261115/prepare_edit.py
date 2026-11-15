"""Build PixelLab inpainting input/mask; never paint replacement artwork locally."""
from pathlib import Path
import base64
import hashlib
import json
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT.parent / 'rvanoukh-animation-20261115'
JOBS = Path('D:/Codex/home/generated_images/rvanoukh-selected-20261115')
EYES = {
    9: [[161,176,171,184], [178,172,188,181]],
    10: [[161,172,172,180], [178,168,188,177]],
    11: [[161,175,172,183], [178,171,188,180]],
    12: [[161,177,172,185], [178,174,188,183]],
}
PROMPT = ('This is a 2 by 2 grid of four consecutive frames of the SAME small pale grey goblin dying, '
          'slumping forward onto the ground. Make only the masked edits. In the small masks over BOTH '
          'eyes in each sprite, replace the yellow open eyes with firmly CLOSED EYELIDS: thin dark '
          'closed eye lines under the same heavy brow, with grey skin covering the eyeballs. '
          'No visible yellow iris, pupil, white eyeball or eye glow. He is dead, not looking or smiling. '
          'Keep the brow, facial silhouette and nose unchanged. The separate tiny masks at the top-left '
          'corner of each 256x256 cell contain stray pixels: remove those pixels completely to transparent '
          'empty background. All other pixels must stay exactly unchanged: same pose, limbs, head position, '
          'torn loincloth, blisters, club, palette, scale and framing. No new effects or text.')


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def main():
    folder = JOBS / 'pixellab/edit-1'
    if (folder/'submit-started.json').exists():
        raise SystemExit('Edit already attempted; do not replace its request')
    input_dir = ROOT/'inputs'
    input_dir.mkdir(parents=True, exist_ok=True)
    atlas = Image.new('RGBA',(512,512))
    mask = Image.new('RGB',(512,512),'black')
    draw = ImageDraw.Draw(mask)
    sources=[]
    for quadrant, frame in enumerate(EYES):
        x,y=(quadrant%2)*256,(quadrant//2)*256
        source = SOURCE/f'pixellab/death-1/frames/frame-{frame:02d}.png'
        atlas.paste(Image.open(source),(x,y))
        boxes=[[0,0,4,4], *EYES[frame]]
        for left,top,right,bottom in boxes:
            draw.rectangle((x+left,y+top,x+right-1,y+bottom-1), fill='white')
        sources.append({'quadrant':quadrant,'source_frame':frame,'offset':[x,y],
                        'source':source.relative_to(ROOT.parent).as_posix(),'source_sha256':sha(source),
                        'eye_boxes_xyxy':EYES[frame],'corner_box_xyxy':[0,0,4,4]})
    atlas.save(input_dir/'inpaint-atlas.png');mask.save(input_dir/'inpaint-mask.png')
    def payload(path):
        return {'image':{'base64':base64.b64encode(path.read_bytes()).decode('ascii'),'format':'png'},
                'size':{'width':512,'height':512}}
    request={'description':PROMPT, 'inpainting_image':payload(input_dir/'inpaint-atlas.png'),
             'mask_image':payload(input_dir/'inpaint-mask.png'),'no_background':True,
             'crop_to_mask':True,'seed':2026111519}
    folder.mkdir(parents=True,exist_ok=True)
    (folder/'request.json').write_text(json.dumps(request),encoding='utf-8')
    (ROOT/'prompt.txt').write_text(PROMPT,encoding='utf-8')
    manifest={'endpoint':'inpaint-v3','input':'inputs/inpaint-atlas.png','mask':'inputs/inpaint-mask.png',
              'input_sha256':sha(input_dir/'inpaint-atlas.png'),'mask_sha256':sha(input_dir/'inpaint-mask.png'),
              'seed':request['seed'],'no_background':True,'crop_to_mask':True,'quadrants':sources,
              'assembly_policy':'Use only PixelLab-generated eye/corner pixels within recorded masks. Preserve all other source pixels exactly. No manual eyelid drawing.',
              'frame_mapping':{str(i):{'eyes_from':None if i<9 else min(i,12),'corner_from':None if i==0 else 10} for i in range(33)}}
    (ROOT/'edit-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    selection={'main_idle':{'source':'../rvanoukh-animation-20261115/pixellab/idle-3','variant':3},
               'rare_idle':{'source':'../rvanoukh-animation-20261115/pixellab/idle-2','variant':2},
               'death':{'source':'../rvanoukh-animation-20261115/pixellab/death-1','variant':1,'correction':'Close eyes at collapse; remove corner artifact'},
               'ability':{'status':'deferred_by_user','generate':False,'integrate':False},
               'runtime_integration':False,'rare_idle_frequency':'not specified; do not invent a gameplay probability'}
    (ROOT/'selection.json').write_text(json.dumps(selection,ensure_ascii=False,indent=2),encoding='utf-8')
    print('Prepared one masked PixelLab edit, four source poses; no submission')


if __name__=='__main__':
    main()
