"""Mechanical layout of original PixelLab panels and unchanged approved A icons.

No generated art is repainted. Preview sheets are design mockups, not game captures.
Run from any directory: python <this file>.
"""
import hashlib
import json
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
ICONS = ROOT / 'assets/art_presets/approved/status_icons_a_v1/16'
BATTLE = ROOT / 'docs/art/status-icon-frame-20261108/idle-100.png'
NN = Image.Resampling.NEAREST
VARIANTS = json.loads((OUT / 'variants.json').read_text(encoding='utf-8'))
SAMPLES = [('bleeding', 2, 3), ('poison', 2, 3), ('acid', 0, 2),
           ('stunned', 0, 1), ('entangled', 0, 2), ('frozen', 0, 2)]
COUNTER = ImageFont.truetype(str(ROOT / 'assets/ui/combat_fonts/jersey20_numbers.ttf'), 10)
LETTERS = ImageFont.truetype(str(ROOT / 'assets/ui/combat_fonts/combat_letters.ttf'), 10)
FONT = Path('C:/Windows/Fonts/arial.ttf')
BOLD = Path('C:/Windows/Fonts/arialbd.ttf')


def text(draw, xy, value, size=22, color='#dad9ce', bold=False):
    draw.text(xy, value, font=ImageFont.truetype(str(BOLD if bold else FONT), size), fill=color)


def backing(slug, width):
    src = Image.open(OUT / f'{slug}.png').convert('RGBA')
    bbox = src.getbbox()
    # Crop transparent margins before slicing so narrow source silhouettes keep both caps.
    src = src.crop(bbox)
    plate = Image.new('RGBA', (width, 32))
    y = (32 - src.height) // 2
    cap = 12
    plate.alpha_composite(src.crop((0, 0, cap, src.height)), (0, y))
    plate.alpha_composite(src.crop((cap, 0, src.width-cap, src.height)).resize((width-2*cap, src.height), NN), (cap, y))
    plate.alpha_composite(src.crop((src.width-cap, 0, src.width, src.height)), (width-cap, y))
    return plate


def sample(slug, count):
    overlap = {1: 0, 3: 2, 6: 4}[count]
    stride = 16-overlap
    width = 24+16+(count-1)*stride
    plate = backing(slug, width)
    # Draw all motifs first so a later icon cannot cover an earlier counter.
    for index, (icon_id, _, _) in enumerate(SAMPLES[:count]):
        plate.alpha_composite(Image.open(ICONS / f'{icon_id}.png').convert('RGBA'), (12+index*stride, 8))
    draw = ImageDraw.Draw(plate)
    draw.fontmode = '1'
    for index, (_, stacks, ticks) in enumerate(SAMPLES[:count]):
        x = 12+index*stride
        if stacks:
            # Jersey is a number-only subset; use the same Play fallback as the game.
            draw.text((x+1, 7), '×', font=LETTERS, fill='#fff0be', stroke_width=1, stroke_fill='#171514')
            draw.text((x+1+round(LETTERS.getlength('×')), 7), str(stacks), font=COUNTER,
                      fill='#fff0be', stroke_width=1, stroke_fill='#171514')
        value = str(ticks)
        draw.text((x+15-round(draw.textlength(value, font=COUNTER)), 16), value,
                  font=COUNTER, fill='#f1eee4', stroke_width=1, stroke_fill='#171514')
    plate.save(OUT / f'{slug}-{count}-effects.png')
    return plate, dict(count=count, icon_size=16, overlap_px=overlap,
                       stride_px=stride, backing_width=width, canvas_height=32)


def build():
    sheet = Image.new('RGB', (1320, 1110), '#171b1c')
    draw = ImageDraw.Draw(sheet)
    text(draw, (38, 26), 'ПОДЛОЖКА ПРИ НАВЕДЕНИИ', 31, bold=True)
    text(draw, (38, 71), 'Пять материалов · один набор значков A · числа без отдельных плашек', 21, '#a9b2b0')
    columns = [(445, 1), (720, 3), (1082, 6)]
    for x, count in columns:
        label = {1: '1 эффект', 3: '3 эффекта', 6: '6 эффектов'}[count]
        text(draw, (x-55, 119), label, 21, bold=True)
        text(draw, (x-68, 148), {1:'без нахлёста',3:'нахлёст 2 px',6:'нахлёст 4 px'}[count], 18, '#9ca9a5')
    battle = Image.open(BATTLE).convert('RGBA')
    tile = battle.crop((730, 276, 842, 318)).resize((448,168), NN)
    geometry = []
    for row, variant in enumerate(VARIANTS):
        y = 186 + row*168
        draw.rounded_rectangle((24, y, 1296, y+151), radius=5, fill='#202728')
        text(draw, (42,y+22), f"0{row+1}", 30, '#d7b777', True)
        title = variant['title'].split(' ')
        text(draw, (42, y+67), title[0], 24, bold=True)
        text(draw, (42, y+98), ' '.join(title[1:]), 22, bold=True)
        for x,count in columns:
            panel, layout = sample(variant['id'], count)
            display = panel.resize((panel.width*4, 128), NN)
            field_width = display.width+8
            field = tile.crop(((448-field_width)//2, 0, (448+field_width)//2, 128)).copy()
            field.alpha_composite(display, (4, 0))
            sheet.paste(field.convert('RGB'), (x-field_width//2, y+10))
            if row == 0:
                geometry.append(layout)
    text(draw, (38, 1047), 'Масштаб ×4 для сравнения. Подложка растёт: 40 → 68 → 100 px. Значки остаются 16 px.', 20, '#a9b2b0')
    text(draw, (38, 1078), 'Концепты: в игру ещё не подключены. Шесть эффектов — пример плотного ряда.', 18, '#85928f')
    sheet.save(OUT / 'five-concepts.png')

    context = Image.new('RGB', (1320, 489), '#171b1c')
    draw = ImageDraw.Draw(context)
    text(draw, (28, 20), 'ПРИМЕР НАД ПЕРСОНАЖЕМ ПРИ НАВЕДЕНИИ', 25, bold=True)
    text(draw, (28, 58), 'Макет поверх кадра боя · 6 эффектов · увеличение ×2 без сглаживания', 19, '#a9b2b0')
    for index, variant in enumerate(VARIANTS):
        field = battle.crop((575, 297, 705, 467)).copy()
        panel, _ = sample(variant['id'], 6)
        field.alpha_composite(panel, ((130-panel.width)//2, 8))
        context.paste(field.resize((260,340), NN).convert('RGB'), (2+index*264,112))
        text(draw, (16+index*264, 461), f"0{index+1} · {variant['title'].split(' ')[0]}", 17, '#dad9ce', True)
    context.save(OUT / 'character-hover-concepts.png')
    inputs = [BATTLE, ROOT / 'assets/ui/combat_fonts/jersey20_numbers.ttf',
              ROOT / 'assets/ui/combat_fonts/combat_letters.ttf']
    inputs += [ICONS / f'{icon_id}.png' for icon_id,_,_ in SAMPLES]
    inputs += [OUT / f"{v['id']}.png" for v in VARIANTS]
    manifest = dict(kind='art-proposal-not-runtime', geometry=geometry,
                    counter_font_size=10, fixed_endcaps_px=12, counter_draw_order='after all icons',
                    sources={str(p.relative_to(ROOT)).replace('\\','/'):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs})
    (OUT / 'layout.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('Built five-concepts.png, character-hover-concepts.png and 15 sample PNGs.')


if __name__ == '__main__':
    build()
