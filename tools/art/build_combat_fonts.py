"""Rebuild the selected combat font assets (requires fonttools==4.60.1)."""

from pathlib import Path
import hashlib
import json
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont


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
        if entry["id"] in ("monogram", "jersey"):
            for source in entry["sources"]:
                path = SOURCE.parent / source["file"]
                if sha256(path) != source["sha256"]:
                    raise ValueError(f"Source hash mismatch: {path}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name in ("monogram-CC0.txt", "monogram-license-source.txt", "jersey-OFL.txt"):
        shutil.copyfile(SOURCE / name, OUTPUT / name)

    letters = TTFont(SOURCE / "monogram.ttf", recalcTimestamp=False)
    # У Monogram низкая видимая высота: 4/3 масштаба через em сохраняет рисунок и интервалы.
    # При кегле 24 его исходная сетка 64 units становится ровно 2 px.
    letters["head"].unitsPerEm = 768
    rename_font(letters, "Combat Monogram Letters", "Regular", "CombatMonogramLetters-Regular")
    letters.save(OUTPUT / "monogram_letters.ttf")
    letters.close()

    font = TTFont(SOURCE / "jersey.ttf", recalcTimestamp=False)
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
    # В числовом наборе нижнее поле полного шрифта лишнее: оно вытесняло верхнюю подпись.
    # Сохраняем рисунок, em и горизонтальные интервалы; меняем только метрики строки.
    font["hhea"].descent = -280
    font["OS/2"].sTypoDescender = -280
    font["OS/2"].usWinDescent = 280
    # Подмножество без букв заставляет Label выбирать Monogram и для латинского HP.
    # Семейство сохраняет прежнее имя, чтобы проверить реальный выбор glyph в Godot.
    names = {1: "Combat Jersey Numbers", 2: "Regular", 3: "CombatJerseyNumbers-1",
             4: "Combat Jersey Numbers", 6: "CombatJerseyNumbers-Regular"}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.save(OUTPUT / "jersey_numbers.ttf")
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
