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
previous = OUT.parent/'rogue-game-feedback-20261012'
old_manifest=json.loads((previous/'death-final/manifest.json').read_text(encoding='utf-8'))
sources=[]
for index,item in enumerate(old_manifest['frames'],1):
    source=previous/item['source']; assert sha(source)==item['sha256']
    target=OUT/f'inputs/death/frame-{index:02d}.png'; target.parent.mkdir(exist_ok=True,parents=True)
    target.write_bytes(source.read_bytes()); sources.append(target)
manifest = {'base':'c464c03d99f316dcebe231dc00794c984e84f197','provider_job':old_manifest['provider_job'],
    'frames':[{'source':p.relative_to(OUT).as_posix(),'sha256':sha(p),'duration_ms':50} for p in sources],
    'duration_ms':650,'runtime_hold_ms':250,'runtime_fade_ms':800,'runtime_total_ms':1700,
    'pixelOperations':'Original whole PNGs unchanged. Runtime sprite alpha fades only after fall and hold; clip-only GIF has no fade.'}
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
