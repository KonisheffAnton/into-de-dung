"""Package Godot captures for review; no animation poses are generated here."""
from pathlib import Path
import argparse
import json
from PIL import Image, ImageDraw

parser=argparse.ArgumentParser()
parser.add_argument('captures',type=Path)
args=parser.parse_args()
out=args.captures.parent
for kind,durations in [('buff',[120,240,60,320,120,160]),('death',[50]*34)]:
    frames=[Image.open(args.captures/f'{kind}-{i:02d}.png').convert('RGB') for i in range(len(durations))]
    # Одна палитра на весь GIF без dithering, чтобы упаковка не добавляла мерцающий шум.
    all_pixels=Image.new('RGB',(frames[0].width*len(frames),frames[0].height))
    for i,im in enumerate(frames): all_pixels.paste(im,(i*im.width,0))
    palette=all_pixels.quantize(colors=256,dither=Image.Dither.NONE)
    packed=[im.quantize(palette=palette,dither=Image.Dither.NONE).resize((384,320),Image.Resampling.NEAREST) for im in frames]
    packed[0].save(out/f'game-{kind}.gif',save_all=True,append_images=packed[1:],duration=durations,loop=0,disposal=2,optimize=False)
    selected=list(range(6)) if kind=='buff' else [0,8,12,17,25,33]
    sheet=Image.new('RGB',(1152,688),(50,55,52)); draw=ImageDraw.Draw(sheet)
    for j,i in enumerate(selected):
        x=(j%3)*384;y=(j//3)*344
        sheet.paste(frames[i].resize((384,320),Image.Resampling.NEAREST),(x,y+24))
        draw.text((x+8,y+6),f'{kind} {i+1:02d} / '+(f'{i*50+25}ms' if kind=='death' else f'{durations[i]}ms'),fill='white')
    sheet.save(out/f'game-{kind}-filmstrip.png')
    gif=Image.open(out/f'game-{kind}.gif'); total=0
    for i in range(gif.n_frames):gif.seek(i);total+=gif.info['duration']
    assert total==sum(durations)
    print(kind,len(frames),'source captures;',total,'ms; GIF shared256 palette, no dithering')
