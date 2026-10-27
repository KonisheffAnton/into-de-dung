"""Rebuild the selected combat font assets (requires fonttools==4.60.1)."""

from pathlib import Path
import hashlib
import json
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/combat-font-pairs-preview-20261027/fonts"
OUTPUT = ROOT / "assets/ui/combat_fonts"
NUMERIC = "0123456789.,+-%\u2212"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    # Сверка с выбранным превью не позволяет незаметно заменить исходный рисунок.
    provenance = json.loads((SOURCE.parent / "provenance.json").read_text(encoding="utf-8"))
    for entry in provenance["fonts"]:
        if entry["id"] in ("monogram", "pixelify"):
            for source in entry["sources"]:
                path = SOURCE.parent / source["file"]
                if sha256(path) != source["sha256"]:
                    raise ValueError(f"Source hash mismatch: {path}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ("monogram-CC0.txt", "monogram-license-source.txt", "pixelify-OFL.txt"):
        shutil.copyfile(SOURCE / name, OUTPUT / name)

    letters = TTFont(SOURCE / "monogram.ttf", recalcTimestamp=False)
    # У Monogram низкая видимая высота: 4/3 масштаба через em сохраняет рисунок и интервалы.
    # При кегле 24 его исходная сетка 64 units становится ровно 2 px.
    letters["head"].unitsPerEm = 768
    rename_font(letters, "Combat Monogram Letters", "Regular", "CombatMonogramLetters-Regular")
    letters.save(OUTPUT / "monogram_letters.ttf")
    letters.close()

    font = TTFont(SOURCE / "pixelify.ttf", recalcTimestamp=False)
    # В выбранном превью цифры Bold, а исходный variable TTF по умолчанию Regular.
    instantiateVariableFont(font, {"wght": 700}, inplace=True)
    missing = set(map(ord, NUMERIC)) - set(font.getBestCmap())
    if missing:
        raise ValueError(f"Missing numeric glyphs: {sorted(missing)}")
    options = subset.Options()
    options.recalc_timestamp = False
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.name_legacy = True
    options.name_languages = [0x409]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=NUMERIC)
    subsetter.subset(font)
    # Числовому подмножеству не нужны поля полного алфавита: они вытесняли подписи за кадр.
    # Диапазон контуров -85..638 помещается в метрики -200..800 без обрезки.
    font["hhea"].ascent = 800
    font["hhea"].descent = -200
    font["hhea"].lineGap = 0
    font["OS/2"].sTypoAscender = 800
    font["OS/2"].sTypoDescender = -200
    font["OS/2"].sTypoLineGap = 0
    font["OS/2"].usWinAscent = 800
    font["OS/2"].usWinDescent = 200
    # Подмножество без букв заставляет Label выбирать Monogram и для латинского HP.
    rename_font(font, "Combat Pixelify Numbers", "Bold", "CombatPixelifyNumbers-Bold")
    font.save(OUTPUT / "pixelify_numbers.ttf")
    font.close()
    print(json.dumps({p.name: sha256(p) for p in sorted(OUTPUT.glob("*.ttf"))}, indent=2))


def rename_font(font: TTFont, family: str, style: str, postscript: str) -> None:
    names = {1: family, 2: style, 3: postscript + "-1", 4: family + " " + style, 6: postscript,
             16: family, 17: style}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())


if __name__ == "__main__":
    main()
