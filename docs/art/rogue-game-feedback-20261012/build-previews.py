"""Compose review artifacts from complete PNG poses; no drawing or interpolation."""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
BACKGROUND = (63,75,67,255)
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

death = OUT/'death-final'
death.mkdir(exist_ok=True)
sources = [OUT/'inputs/ready.png'] + [OUT/f'death-fast/pixellab/frame-{i:02d}.png' for i in range(2,14)]
manifest = {'base':'d16bd004a5ab91a44e33965fc8515f16106f388b', 'provider_job':'d6743634-9796-4c96-a5ae-b991bcc9872f', 'frames':[{'source':p.relative_to(OUT).as_posix(),'sha256':sha(p),'duration_ms':100} for p in sources], 'duration_ms':1300,'pixelOperations':'Complete PNG selection only: original reference restores exact first pose; frames2-13 are raw PixelLab. No rotation, warp, painting, color edits or interpolation.'}
(death/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')

def preview(name):
    target=OUT/name
    manifest=json.loads((target/'manifest.json').read_text(encoding='utf-8'))
    frames=[]
    durations=[]
    records=[]
    for entry in manifest['frames']:
        p=OUT/entry['source']
        assert sha(p)==entry['sha256']
        im=Image.open(p).convert('RGBA')
        assert im.size==(128,128)
        frames.append(im)
        durations.append(entry['duration_ms'])
        records.append({'path':entry['source'],'size':im.size,'alpha_bounds':im.getchannel('A').getbbox(),'colors':len(set(im.get_flattened_data())),'sha256':entry['sha256']})
    composed=[Image.alpha_composite(Image.new('RGBA',(128,128),BACKGROUND),im).convert('RGB').resize((512,512),Image.Resampling.NEAREST) for im in frames]
    indexed=[im.quantize(colors=256,dither=Image.Dither.NONE) for im in composed]
    indexed[0].save(target/'preview.gif',save_all=True,append_images=indexed[1:],duration=durations,loop=0,disposal=2,optimize=False)
    columns=min(5,len(frames)); rows=(len(frames)+columns-1)//columns
    sheet=Image.new('RGBA',(columns*256,rows*280),BACKGROUND)
    draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
    for index,im in enumerate(frames):
        x=(index%columns)*256; y=(index//columns)*280
        sheet.alpha_composite(im.resize((256,256),Image.Resampling.NEAREST),(x,y))
        draw.text((x+8,y+257),f'{index+1:02d} / {durations[index]}ms',font=font,fill=(240,243,236,255))
    sheet.save(target/'filmstrip.png')
    gif=Image.open(target/'preview.gif'); decoded=[]; elapsed=0
    for i in range(gif.n_frames):
        gif.seek(i); duration=gif.info['duration']; decoded.append((elapsed,elapsed+duration,gif.convert('RGB'))); elapsed+=duration
    assert elapsed==sum(durations)
    parity=[]; start=0
    for index,(im,d) in enumerate(zip(composed,durations)):
        candidate=next(x for lo,hi,x in decoded if lo<=start+d//2<hi)
        parity.append(candidate.tobytes()==im.tobytes()); start+=d
    report={'frames':records,'duration_ms':sum(durations),'gif_exact_rgb_per_frame':parity,'frame_count':len(frames),'gif_stored_frames':gif.n_frames,'no_local_pose_edits':True}
    (target/'validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    print(name, len(frames),'frames',sum(durations),'ms; GIF exact RGB',sum(parity),'/',len(parity))

preview('buff-final')
preview('death-final')
