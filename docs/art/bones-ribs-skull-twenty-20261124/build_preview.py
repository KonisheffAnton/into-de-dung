"""Comparison layouts only; provider RGBA files remain byte-exact and untouched."""
from pathlib import Path
import json
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent


def label(draw, xy, value, size=20, bold=False):
    font = ImageFont.truetype("C:/Windows/Fonts/segoeui" + ("b" if bold else "") + ".ttf", size)
    draw.text(xy, value, font=font, fill="#ded8c9")


def build(provider):
    pl = provider == "pixellab"
    if pl:
        choices = json.loads((ROOT / "selection.json").read_text(encoding="utf-8-sig"))
    else:
        choices = {row["id"]: row["destination"] for row in
                   json.loads((ROOT / "imagegen-sources.json").read_text(encoding="utf-8-sig"))}
    sheet = Image.new("RGBA", (1400, 740), "#202127")
    draw = ImageDraw.Draw(sheet)
    label(draw, (24, 16), "PixelLab · PL49–PL58" if pl else "Мои варианты · G41–G50", 30, True)
    label(draw, (24, 63), "Мелкие кости · элементы рёбер · едва заметный фрагмент черепа")
    previews = []
    for index in range(10):
        name = f"PL{index + 49}" if pl else f"G{index + 41}"
        path = ROOT / choices[name]
        original = Image.open(path).convert("RGBA")
        tile = Image.new("RGBA", (64, 64))
        if pl:
            assert original.size == (64, 64)
            tile.alpha_composite(original)
            box = None
            shown_size = list(original.size)
        else:
            box = original.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
            assert box
            fragment = original.crop(box)
            fragment.thumbnail((48, 30), Image.Resampling.NEAREST)
            shown_size = list(fragment.size)
            tile.alpha_composite(fragment, ((64 - fragment.width) // 2, (64 - fragment.height) // 2))
        cx, top = 140 + (index % 5) * 280, 105 + (index // 5) * 285
        label(draw, (cx - 32, top), name, 26, True)
        sheet.alpha_composite(tile.resize((256, 256), Image.Resampling.NEAREST), (cx - 128, top + 32))
        previews.append({"id": name, "source": choices[name], "source_size": list(original.size),
                         "crop_alpha_128": box, "shown_size_before_4x": shown_size})
    label(draw, (24, 704), "Исходные 64×64 · увеличение ×4 без сглаживания" if pl else
          "Imagegen-концепты · уменьшены для сравнения, затем увеличены ×4 без сглаживания", 18)
    sheet.convert("RGB").save(ROOT / (provider + "-ten.png"))
    (ROOT / (provider + "-preview.json")).write_text(json.dumps(previews, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    for provider in sys.argv[1:] or ["imagegen", "pixellab"]:
        build(provider)
