"""Rebuild the selected combat font assets (requires fonttools==4.60.1)."""

from pathlib import Path
import hashlib
import json
import shutil

from fontTools.ttLib import TTFont


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs/art/jersey-cyrillic-preview-20261027/fonts"
OUTPUT = ROOT / "assets/ui/combat_fonts"
NUMERIC = "0123456789.,+-%\u2212"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    # Сверка с выбранным превью не позволяет незаметно заменить исходный рисунок.
    provenance = json.loads((SOURCE.parent / "provenance.json").read_text(encoding="utf-8"))
    for entry in provenance["fonts"]:
        if entry["id"] == "pixeloid":
            for source in entry["sources"]:
                path = SOURCE.parent / source["file"]
                if sha256(path) != source["sha256"]:
                    raise ValueError(f"Source hash mismatch: {path}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / "pixeloid-LICENSE.txt", OUTPUT / "pixeloid-OFL.txt")

    font = TTFont(SOURCE / "pixeloid.ttf", recalcTimestamp=False)
    if font["OS/2"].usWeightClass != 700 or "fvar" in font:
        raise ValueError("Expected the selected static Pixeloid Sans Bold")
    missing = set(map(ord, NUMERIC)) - set(font.getBestCmap())
    if missing:
        raise ValueError(f"Missing numeric glyphs: {sorted(missing)}")
    # Em 2448 вместо 1836 сохраняет высоту заглавных 14 px при кегле 24.
    # Одна сетка 204 units = 2 px теперь общая и для букв, и для цифр.
    font["head"].unitsPerEm = 2448
    rename_font(font, "Combat Pixeloid", "Bold", "CombatPixeloid-Bold")
    font.save(OUTPUT / "pixeloid.ttf")
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
