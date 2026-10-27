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
        if entry["id"] in ("tiny5", "jersey"):
            for source in entry["sources"]:
                path = SOURCE.parent / source["file"]
                if sha256(path) != source["sha256"]:
                    raise ValueError(f"Source hash mismatch: {path}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(SOURCE / "tiny5.ttf", OUTPUT / "tiny5.ttf")
    for name in ("tiny5", "jersey"):
        shutil.copyfile(SOURCE / f"{name}-OFL.txt", OUTPUT / f"{name}-OFL.txt")

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
    # Подмножество без букв заставляет Label выбирать Tiny5 и для латинского HP.
    for record in font["name"].names:
        names = {1: "Combat Jersey Numbers", 2: "Regular", 3: "CombatJerseyNumbers-1",
                 4: "Combat Jersey Numbers", 6: "CombatJerseyNumbers-Regular"}
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.save(OUTPUT / "jersey_numbers.ttf")
    font.close()
    print(json.dumps({p.name: sha256(p) for p in sorted(OUTPUT.glob("*.ttf"))}, indent=2))


if __name__ == "__main__":
    main()
