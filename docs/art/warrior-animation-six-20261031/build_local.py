#!/usr/bin/env python3
"""Собирает детерминированные прототипы анимации из вырезанных частей исходника."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent
IDS = ("02", "05", "11", "12", "17", "18")
SIZE = 256
ANCHOR = [128, 200]
FPS_DURATIONS = {"idle": 100, "death": 90, "ability": 80}
COUNT = 32


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def smooth(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3.0 - 2.0 * t)


def alpha_bbox(im: Image.Image) -> tuple[int, int, int, int] | None:
    return im.getchannel("A").getbbox()


def mask_polygon(size: tuple[int, int], points: list[tuple[float, float]]) -> Image.Image:
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).polygon(points, fill=255)
    return m.filter(ImageFilter.GaussianBlur(0.35))


def cut_region(src: Image.Image, box: tuple[float, float, float, float], pad: float = 4.0) -> tuple[Image.Image, tuple[int, int]]:
    """Перекрывает вырезы, чтобы у сочленения не появлялся прозрачный шов."""
    l, t, r, b = box
    l, t, r, b = math.floor(l - pad), math.floor(t - pad), math.ceil(r + pad), math.ceil(b + pad)
    layer = Image.new("RGBA", src.size, (0, 0, 0, 0))
    layer.paste(src.crop((l, t, r, b)), (l, t))
    mask = Image.new("L", src.size, 0)
    ImageDraw.Draw(mask).rectangle((l, t, r, b), fill=255)
    alpha = ImageChops.multiply(layer.getchannel("A"), mask)
    # Нулевой альфа-канал должен иметь нулевой RGB, иначе фильтр интерполяции даст ореол.
    visible = alpha.point(lambda a: 255 if a > 0 else 0)
    rgb = Image.new("RGB", src.size, (0, 0, 0))
    rgb.paste(layer.convert("RGB"), (0, 0), visible)
    layer = rgb.convert("RGBA")
    layer.putalpha(alpha)
    return layer, (l, t)


def rotate_layer(layer: Image.Image, pivot: tuple[float, float], degrees: float, shift: tuple[float, float] = (0, 0)) -> Image.Image:
    # Поворот вокруг заданного пиксельного сустава сглаживает рваные края вырезанной детали.
    cx, cy = pivot
    expanded = layer.rotate(degrees, resample=Image.Resampling.BICUBIC, center=(cx, cy))
    if shift != (0, 0):
        expanded = expanded.transform(expanded.size, Image.Transform.AFFINE,
                                      (1, 0, -shift[0], 0, 1, -shift[1]),
                                      resample=Image.Resampling.BICUBIC)
    return expanded


def paste_over(base: Image.Image, layer: Image.Image) -> Image.Image:
    return Image.alpha_composite(base, layer)


def replace_cutout(base: Image.Image, source: Image.Image,
                   box: tuple[float, float, float, float], pivot: tuple[float, float],
                   degrees: float, shift: tuple[float, float] = (0, 0)) -> Image.Image:
    """Удаляет исходные пиксели детали перед переносом, чтобы не оставался двойной контур."""
    layer, _ = cut_region(source, box, 5)
    cleared = base.copy()
    cleared.putalpha(ImageChops.subtract(cleared.getchannel("A"), layer.getchannel("A")))
    return paste_over(cleared, rotate_layer(layer, pivot, degrees, shift))


def body_box(box: tuple[int, int, int, int], warrior: str) -> dict[str, Any]:
    l, t, r, b = box
    w, h = r - l, b - t
    # Координаты частей привязаны к силуэту и уточняются отдельно по каждому исходнику.
    rig = {"bbox": box, "head": (l + .29*w, t + .03*h, l + .73*w, t + .34*h),
            "torso": (l + .19*w, t + .25*h, l + .82*w, t + .76*h),
            "arm_l": (l + .04*w, t + .34*h, l + .43*w, t + .74*h),
            "arm_r": (l + .57*w, t + .32*h, l + .97*w, t + .73*h),
            # Нижний край плаща не захватывает обувь, чтобы она оставалась опорой в idle.
            "cape": (l + .16*w, t + .32*h, l + .85*w, t + .76*h),
            "soles": (l + .12*w, t + .84*h, l + .89*w, b)}
    rig["ability_arm_l"] = rig["arm_l"]
    rig["ability_arm_r"] = rig["arm_r"]
    if warrior in ("02", "12", "17"):
        # Щит опускается ниже локтя, поэтому защитный жест двигает его целиком.
        rig["ability_arm_r"] = (l + .55*w, t + .27*h, r + .015*w, t + .87*h)
    elif warrior == "05":
        # Длинный меч поднимается над кистями, поэтому клинок включён в верхнюю дугу удара.
        rig["ability_arm_r"] = (l + .50*w, t - .015*h, r + .02*w, t + .76*h)
    elif warrior == "11":
        # У бойца 11 меч в исходной позе смотрит вниз-влево; для подъёма нужна вся длина клинка.
        rig["ability_arm_l"] = (l + .015*w, t + .30*h, l + .48*w, t + .99*h)
    elif warrior == "18":
        # Во время взмаха длинный клинок справа сверху движется вместе с оружейной рукой.
        rig["ability_arm_r"] = (l + .58*w, t - .01*h, r + .015*w, t + .76*h)
    return rig


def pose(src: Image.Image, rig: dict[str, Any], kind: str, i: int, n: int, warrior: str) -> Image.Image:
    # Первый кадр побайтно сохраняет исходную позу, чтобы клип начинался без скачка.
    if i == 0:
        return src.copy()
    p = i / n
    phase = 2 * math.pi * p
    l, t, r, b = rig["bbox"]
    cx, cy = (l + r) / 2, (t + b) / 2
    h, w = b - t, r - l
    result = src.copy()
    if kind == "idle":
        breath = math.sin(phase) * 1.15
        # Верх тела заменяет старые пиксели до сдвига, чтобы контур не задваивался.
        upper = (l-3, t-3, r+3, t+h*.62)
        result = replace_cutout(src, src, upper, (cx, t+h*.62), 0, (0, -breath))
        # Руки и плащ слегка отстают друг от друга, сохраняя направление бойца.
        for key, amp, pivot in (("arm_l", .65, (l+w*.30, t+h*.50)),
                                ("arm_r", -.65, (l+w*.70, t+h*.50)),
                                ("cape", .55, (cx, t+h*.38))):
            box = rig[key]
            sway = math.sin(phase + (0.55 if key == "cape" else 0)) * amp
            result = replace_cutout(result, src, box, pivot, sway)
        return result
    if kind == "death":
        u = smooth(min(1.0, p / .78))
        # Весь боец заваливается вокруг таза: единый слой не оставляет дыр между частями.
        pivot = (cx, t + h*.82)
        result = rotate_layer(src, pivot, 74*u, (0, -12*u))
        bounds = alpha_bbox(result)
        if bounds:
            dx = max(1-bounds[0], min(0, SIZE-1-bounds[2]))
            dy = max(1-bounds[1], min(0, SIZE-1-bounds[3]))
            if dx or dy:
                result = result.transform(result.size, Image.Transform.AFFINE,
                                          (1, 0, -dx, 0, 1, -dy),
                                          resample=Image.Resampling.BICUBIC)
        return result
    if i == n - 1:
        # Одноразовое действие завершается точно в исходной стойке.
        return src.copy()
    # У каждого жеста есть подготовка, действие и возврат в исходную стойку.
    shield = warrior in ("02", "12", "17")
    if warrior == "02":  # удар щитом
        wind = math.sin(min(1, p/.24)*math.pi/2)
        hit = smooth((p-.25)/.12) - smooth((p-.40)/.12)
        recoil = smooth((p-.40)/.20) - smooth((p-.63)/.20)
        settle = smooth((p-.68)/.25)
        body_shift = (0, -1.1*wind + .8*recoil)
        item_angle = -8*wind + 28*hit + 8*settle
    elif warrior == "05":  # тяжёлый удар мечом сверху
        wind = smooth(p/.30)
        chop = smooth((p-.30)/.18)
        recovery = smooth((p-.55)/.30)
        body_shift = (0, -1.6*wind + 1.2*chop - .3*recovery)
        item_angle = 25*wind - 125*chop + 100*recovery
    elif warrior == "11":  # поднятие меча для сигнала союзникам
        lift = smooth(p/.32)
        lower = smooth((p-.65)/.26)
        body_shift = (0, -1.0*lift + .7*lower)
        item_angle = 180*lift - 180*lower
    elif warrior == "12":  # постановка щита в защитную стойку
        brace = smooth(p/.22)
        release = smooth((p-.68)/.25)
        body_shift = (0, .8*brace - .6*release)
        item_angle = 20*brace - 20*release
    elif warrior == "17":  # короткий провоцирующий жест щитом
        present = smooth(p/.24)
        beat = math.sin(max(0, min(1, (p-.25)/.28))*math.pi)
        release = smooth((p-.65)/.24)
        body_shift = (0, -0.5*present + .5*release)
        item_angle = -26*present + 15*beat + 26*release
    else:  # размашистый взмах мечом бойца 18
        wind = smooth(p/.24)
        slash = smooth((p-.24)/.17)
        return_swing = smooth((p-.48)/.30)
        body_shift = (-1.0*wind + 1.4*slash - .4*return_swing, 0)
        item_angle = -10*wind + 125*slash - 115*return_swing
    # У всех действий хвост последних кадров плавно доворачивает предмет в исходный угол.
    settle = 1.0 - smooth((p-.78)/.20)
    item_angle *= settle
    body_shift = (body_shift[0]*settle, body_shift[1]*settle)
    # Стабильная база позволяет удалить исходный предмет точно по маске и не получить двойник.
    result = src.copy()
    polygons = {
        "02": [(l+.73*w,t+.31*h),(l+.96*w,t+.25*h),(l+1.00*w,t+.72*h),(l+.84*w,t+.83*h),(l+.72*w,t+.72*h)],
        # Узкий контур 05 охватывает меч вдоль лезвия и рукояти, не задевая нагрудник.
        "05": [(l+.54*w,t+.49*h),(l+.60*w,t+.54*h),(l+.68*w,t+.45*h),
               (l+1.06*w,t+.015*h),(l+1.00*w,t-.03*h),(l+.94*w,t-.005*h),
               (l+.57*w,t+.39*h)],
        # Маска 11 включает кисть и предплечье, чтобы меч не отделялся при подъёме.
        "11": [(74,150),(96,143),(101,148),(98,153),(109,175),
               (124,201),(122,205),(109,194),(93,178),(80,162),(73,164)],
        "12": [(l+.75*w,t+.48*h),(l+.97*w,t+.44*h),(l+1.00*w,t+.79*h),(l+.82*w,t+.83*h),(l+.74*w,t+.77*h)],
        "17": [(l+.78*w,t+.34*h),(l+.98*w,t+.32*h),(l+1.00*w,t+.66*h),(l+.83*w,t+.70*h),(l+.76*w,t+.64*h)],
        # Узкая маска 18 следует по мечу и захватывает гарду, не двигая плечевую броню.
        "18": [(l+.58*w,t+.52*h),(l+.65*w,t+.58*h),(l+.72*w,t+.50*h),
               (l+1.04*w,t+.015*h),(l+.98*w,t-.03*h),(l+.93*w,t-.005*h),
               (l+.62*w,t+.43*h)],
    }
    pivots = {"02":(l+.84*w,t+.50*h), "05":(l+.66*w,t+.47*h),
              "11":(82,146), "12":(l+.84*w,t+.62*h),
              "17":(l+.85*w,t+.52*h), "18":(l+.66*w,t+.54*h)}
    item_mask = mask_polygon(src.size, polygons[warrior])
    if warrior in ("05", "18"):
        # Расширение на три пикселя убирает сглаженную кайму клинка, иначе остаётся светлый след.
        item_mask = item_mask.filter(ImageFilter.MaxFilter(7))
    elif warrior == "11":
        item_mask = item_mask.filter(ImageFilter.MaxFilter(5))
    item_alpha = ImageChops.multiply(src.getchannel("A"), item_mask)
    # Скрытые RGB за прозрачной маской нельзя оставлять: BICUBIC иначе вытягивает их каймой.
    visible = item_alpha.point(lambda a: 255 if a > 0 else 0)
    item_rgb = Image.new("RGB", src.size, (0, 0, 0))
    item_rgb.paste(src.convert("RGB"), (0, 0), visible)
    item = item_rgb.convert("RGBA")
    item.putalpha(item_alpha)
    base = result.copy()
    base.putalpha(ImageChops.subtract(base.getchannel("A"), item_alpha))
    if warrior == "11":
        # Клинок скрывает ногу в единственном исходнике. Под ним нужен простой
        # подклад брюк цветами той же ноги, иначе после подъёма появляется дыра.
        under = Image.new("RGBA", src.size)
        draw = ImageDraw.Draw(under)
        draw.polygon([(88,160),(107,158),(111,175),(101,185),(88,184)], fill=src.getpixel((103,161)))
        draw.polygon([(90,168),(99,167),(104,179),(97,185),(88,184)], fill=src.getpixel((110,167)))
        draw.polygon([(94,181),(108,182),(113,193),(105,198),(90,198),(87,190)], fill=src.getpixel((100,191)))
        base = Image.alpha_composite(under, base)
    # Предмет вращается вокруг хвата; исходные пиксели удаляются, чтобы не оставалось двойного клинка или щита.
    moved = rotate_layer(item, pivots[warrior], item_angle)
    result = paste_over(base, moved)
    return rotate_layer(result, (cx, t+h*.72), -.75*math.sin(phase)*settle, body_shift)


def save_gif(frames: list[Image.Image], path: Path, durations: list[int]) -> None:
    # Увеличение nearest-neighbor сохраняет исходные пиксельные границы в контактном просмотре.
    enlarged = []
    for frame in frames:
        bg = Image.new("RGBA", frame.size, "#182131")
        bg.alpha_composite(frame)
        enlarged.append(bg.convert("RGB").resize((SIZE * 2, SIZE * 2), Image.Resampling.NEAREST))
    enlarged[0].save(path, save_all=True, append_images=enlarged[1:], duration=durations,
                   loop=0, disposal=2)


def validate(source: Image.Image, frames: list[Image.Image], kind: str) -> dict[str, Any]:
    errors: list[str] = []
    if frames[0].tobytes() != source.tobytes():
        errors.append("first_frame_not_exact_source")
    for idx, frame in enumerate(frames):
        if frame.size != (SIZE, SIZE): errors.append(f"frame_{idx}_canvas")
        box = alpha_bbox(frame)
        if box and (box[0] <= 0 or box[1] <= 0 or box[2] >= SIZE or box[3] >= SIZE):
            errors.append(f"frame_{idx}_alpha_touches_canvas_edge")
    deltas = [ImageChops.difference(frames[0], f).getbbox() is not None for f in frames[1:]]
    if not any(deltas): errors.append("no_frame_changes")
    sole_delta: list[int] = []
    if kind == "idle":
        x0, y0, x1, y1 = source.getchannel("A").getbbox() or (0, 0, SIZE, SIZE)
        y0 = max(0, y1-9)
        base = source.crop((0, y0, SIZE, y1))
        for i, f in enumerate(frames):
            cur = f.crop((0, y0, SIZE, y1))
            sole_delta.append(ImageChops.difference(base, cur).getbbox() or 0)
        if any(sole_delta): errors.append("idle_soles_not_locked")
    if kind == "death" and ImageChops.difference(frames[-1].getchannel("A"), frames[0].getchannel("A")).getbbox() is None:
        errors.append("death_final_silhouette_unchanged")
    if kind == "ability" and frames[-1].tobytes() != source.tobytes():
        errors.append("ability_last_frame_not_exact_source")
    return {"passed": not errors, "errors": errors, "frames": len(frames),
            "changed_frames": sum(deltas), "first_frame_exact": frames[0].tobytes() == source.tobytes(),
            "last_frame_exact": frames[-1].tobytes() == source.tobytes(),
            "idle_sole_checks": len(sole_delta), "idle_sole_changed_pixels": sum(bool(x) for x in sole_delta)}


def build_one(warrior: str, source_path: Path) -> dict[str, Any]:
    src = Image.open(source_path).convert("RGBA")
    if src.size != (SIZE, SIZE): raise ValueError(f"{source_path}: expected 256x256, got {src.size}")
    bbox = alpha_bbox(src)
    if bbox is None: raise ValueError(f"{source_path}: transparent source")
    rig = body_box(bbox, warrior)
    records: dict[str, Any] = {"source": str(source_path.relative_to(ROOT)), "source_bbox": list(bbox), "clips": {}}
    for kind in ("idle", "death", "ability"):
        out = ROOT / "local" / warrior / kind
        frames_dir = out / "frames"
        frames_dir.mkdir(parents=True, exist_ok=True)
        n = 32 if kind != "death" else 30
        frames = [pose(src, rig, kind, i, n, warrior) for i in range(n)]
        for old in frames_dir.glob("frame-*.png"): old.unlink()
        for i, frame in enumerate(frames): frame.save(frames_dir / f"frame-{i:02d}.png")
        sheet = Image.new("RGBA", (SIZE*8, SIZE*((n+7)//8)), (0, 0, 0, 0))
        for i, frame in enumerate(frames): sheet.alpha_composite(frame, ((i%8)*SIZE, (i//8)*SIZE))
        sheet.save(out / "spritesheet.png")
        durations = [FPS_DURATIONS[kind]] * n
        if kind in ("death", "ability"): durations[-1] = 1500
        save_gif(frames, out / "preview.gif", durations)
        gif = Image.open(out / "preview.gif")
        gif_durations: list[int | None] = []
        for gif_index in range(gif.n_frames):
            gif.seek(gif_index)
            gif_durations.append(gif.info.get("duration"))
        clip = {"label": "local cutout prototype", "warrior": warrior, "animation": kind,
                "canvas": [SIZE, SIZE], "anchor": ANCHOR, "actual_frames": n,
                "durations_ms": durations,
                "loop": kind == "idle", "frame_count": n, "source_frame": "frame-00.png",
                "gif_replay": True,
                "gif_replay_note": "GIF repeats for comparison; clip itself is nonlooping. Source final frame lasts 1500 ms; identical GIF poses merge their delays, listed in gif_durations_ms."
                    if kind in ("death", "ability") else "GIF repeats to preview the idle loop; identical GIF poses merge their delays, listed in gif_durations_ms.",
                "gif_actual_frames": gif.n_frames, "gif_durations_ms": gif_durations,
                "gif_coalesces_identical_frames": gif.n_frames < n,
                "source_bbox": list(bbox), "rig_method": "deterministic layered pixel cutout; source pixels repositioned; warrior11 ability uses a simple occluded-trouser underlay sampled from source colors"}
        (out / "clip.json").write_text(json.dumps(clip, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
        records["clips"][kind] = validate(src, frames, kind)
    return records


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models-root", type=Path, default=ROOT / "models")
    ap.add_argument("--ids", nargs="*", default=list(IDS))
    args = ap.parse_args()
    report: dict[str, Any] = {"label": "local cutout prototype validation", "base": "db3d831028efdb804ea235ffc621d59c812314c7", "warriors": {}, "passed": False}
    for warrior in args.ids:
        source = args.models_root / f"warrior-{warrior}" / "input-256.png"
        if not source.is_file():
            report["warriors"][warrior] = {"passed": False, "errors": [f"missing_source:{source}"]}
            continue
        report["warriors"][warrior] = build_one(warrior, source)
    report["passed"] = all(all(c.get("passed", False) for c in entry.get("clips", {}).values())
                           for entry in report["warriors"].values()) and len(report["warriors"]) == 6
    (ROOT / "local-validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(json.dumps({"passed": report["passed"], "warriors": report["warriors"]}, ensure_ascii=False))
    if not report["passed"]: raise SystemExit(1)


if __name__ == "__main__":
    main()
