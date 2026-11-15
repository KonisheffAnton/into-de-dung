"""Presentation only: compose existing frames at their recorded timings."""
from pathlib import Path
from bisect import bisect_right
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
SELECTION = [('idle-2', 'Ожидание №2'), ('ability-2', 'Атака №2'), ('death-3', 'Смерть №3')]


def main():
    clips = []
    for key, label in SELECTION:
        folder = ROOT / 'pixellab' / key
        meta = json.loads((folder / 'clip.json').read_text(encoding='utf-8'))
        ends, elapsed = [], 0
        for duration in meta['durations_ms']:
            elapsed += duration
            ends.append(elapsed)
        frames = [Image.open(ROOT / r['file']).convert('RGBA') for r in meta['frame_records']]
        clips.append({'key':key, 'label':label, 'frames':frames, 'ends':ends,
                      'total':elapsed, 'loop':meta['loop']})
    total = max(c['total'] for c in clips) + 500
    changes = {0, total}
    for clip in clips:
        offset = 0
        while offset < total:
            changes.update(offset + t for t in clip['ends'] if offset + t < total)
            if not clip['loop']:
                break
            offset += clip['total']
    times = sorted(changes)
    output = []
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 22)
    for time in times[:-1]:
        page = Image.new('RGB', (1536, 560), '#182131')
        draw = ImageDraw.Draw(page)
        for col, clip in enumerate(clips):
            local = time % clip['total'] if clip['loop'] else min(time, clip['total'] - 1)
            index = min(bisect_right(clip['ends'], local), len(clip['frames']) - 1)
            frame = clip['frames'][index].resize((512, 512), Image.Resampling.NEAREST)
            page.paste(frame, (512 * col, 48), frame)
            draw.text((512 * col + 24, 15), clip['label'], font=font, fill='#ecdca7')
        output.append(page)
    durations = [b-a for a,b in zip(times,times[1:])]
    output[0].save(ROOT / 'preview.gif', save_all=True, append_images=output[1:],
                   duration=durations, loop=0, disposal=2)
    (ROOT / 'preview.json').write_text(json.dumps({'selection':[x[0] for x in SELECTION],
        'meaning':'Illustrative selection by assistant, not user approval or runtime integration',
        'raw_frames_edited':False, 'scale':'nearest 2x', 'timeline_ms':total,
        'idle_loop':True, 'one_shots_hold':True, 'gif_repeats_entire_presentation':True,
        'durations_ms':durations}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'preview':'preview.gif','duration_ms':total,'composite_frames':len(output)}))


if __name__ == '__main__':
    main()
