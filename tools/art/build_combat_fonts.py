"""Rebuild the selected combat font assets (requires fonttools==4.60.1)."""

from pathlib import Path
import hashlib
import json
import shutil

from fontTools import subset
from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/jersey20-letters-preview-20261027/fonts"
OUTPUT = ROOT / "assets/ui/combat_fonts"
NUMERIC = "0123456789.,+-%\u2212"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    # Сверка с выбранным превью не позволяет незаметно заменить исходный рисунок.
    provenance = json.loads((SOURCE.parent / "provenance.json").read_text(encoding="utf-8"))
    for entry in provenance["fonts"]:
        if entry["id"] in ("play", "jersey20"):
            for source in entry["sources"]:
                path = SOURCE.parent / source["file"]
                if sha256(path) != source["sha256"]:
                    raise ValueError(f"Source hash mismatch: {path}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / "play-OFL.txt", OUTPUT / "play-OFL.txt")
    shutil.copyfile(SOURCE / "jersey20-OFL.txt", OUTPUT / "jersey20-OFL.txt")

    font = TTFont(SOURCE / "play.ttf", recalcTimestamp=False)
    if font["OS/2"].usWeightClass != 700 or "fvar" in font:
        raise ValueError("Expected the selected static Play Bold")
    required_letters = set(range(0x410, 0x450)) | set(map(ord, "Ёё HP·×—:()/"))
    missing = required_letters - set(font.getBestCmap())
    if missing:
        raise ValueError(f"Missing feedback letter glyphs: {sorted(missing)}")
    # Em 1113 вместо 1000 даёт заглавные около 14 px рядом с прежними цифрами.
    # Контуры/интервалы прежние; новое имя соблюдает Reserved Font Names исходной OFL.
    font["head"].unitsPerEm = 1113
    rename_font(font, "Combat Lettering", "Bold", "CombatLettering-Bold")
    font.save(OUTPUT / "combat_letters.ttf")
    font.close()

    numbers = TTFont(SOURCE / "jersey20.ttf", recalcTimestamp=False)
    missing = set(map(ord, NUMERIC)) - set(numbers.getBestCmap())
    if missing:
        raise ValueError(f"Missing Jersey 20 numeric glyphs: {sorted(missing)}")
    options = subset.Options()
    options.recalc_timestamp = False
    options.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
    options.name_legacy = True
    options.name_languages = [0x409]
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(text=NUMERIC)
    subsetter.subset(numbers)
    # Без букв в основном шрифте Label выбирает Play также для латинского HP.
    # Контуры, em и метрики Jersey 20 остаются исходными, включая поле под запятую.
    rename_font(numbers, "Combat Jersey 20 Numbers", "Regular", "CombatJersey20Numbers-Regular")
    numbers.save(OUTPUT / "jersey20_numbers.ttf")
    numbers.close()
    print(json.dumps({p.name: sha256(p) for p in sorted(OUTPUT.glob("*.ttf"))}, indent=2))


def rename_font(font: TTFont, family: str, style: str, postscript: str) -> None:
    names = {1: family, 2: style, 3: postscript + "-1", 4: family + " " + style, 6: postscript,
             16: family, 17: style}
    for record in font["name"].names:
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())


if __name__ == "__main__":
    main()
