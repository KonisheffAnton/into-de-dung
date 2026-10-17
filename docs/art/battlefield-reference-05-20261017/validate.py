"""Проверяет переносимый набор PNG, ссылки и неизменность ориентиров."""
import hashlib
import json
import os
import re
import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parent
EXPECTED = [f"G{i:02d}" for i in range(1, 11)]
REFERENCE_SHA256 = {
    "reference.png": "b0a99681e24040629f3b212e88101782e906f32702a3bc98116b09754b95aa9a",
    "palette-reference.png": "ecbbefee3ae510bde86984b1d6f16cdc4e46e96ae5dfc4c477c79c7636b07e4d",
    "projection-reference.png": "3a444db1efbf7dd949d123ffd724f1a7e0a6eeb069066f320d84e707798f7dbb",
    "monster-reference.png": "e8fe9bb7fa4babe3a5bc46582a48632a746e32e6d34e312c81641b1040a12cd3",
    "defender-benchmark.png": "af95a196244b133a7d11933475fc9d6847241068c402c7220406b28b1499d7cb",
}
MAIN_MENU_SHA256 = "a64c270256ebf2ea073081200be23028f792f42c3ca98f83a6499c1300a68668"


def require(condition, message):
    if not condition:
        raise SystemExit("FAIL: " + message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def normalized_path_key(path):
    return os.path.normcase(os.path.normpath(str(path)))


def verify_png(path):
    data = path.read_bytes()
    require(data[:8] == b"\x89PNG\r\n\x1a\n", f"не PNG: {path.name}")
    require(len(data) >= 33, f"обрезан PNG: {path.name}")
    width, height = struct.unpack(">II", data[16:24])
    require(width > 0 and height > 0, f"неверные размеры PNG: {path.name}")
    pos = 8
    ended = False
    while pos < len(data):
        require(pos + 12 <= len(data), f"обрезан чанк PNG: {path.name}")
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        chunk_end = pos + length + 12
        require(chunk_end <= len(data), f"обрезано содержимое чанка PNG: {path.name}")
        chunk = data[pos + 4:pos + 8 + length]
        crc = struct.unpack(">I", data[pos + 8 + length:chunk_end])[0]
        require(zlib.crc32(chunk) & 0xffffffff == crc, f"неверный CRC PNG: {path.name}")
        ended = data[pos + 4:pos + 8] == b"IEND"
        pos = chunk_end
        if ended:
            break
    require(ended and pos == len(data), f"некорректное окончание PNG: {path.name}")
    return data, width, height


def main():
    manifest_path, ratings_path, gallery_path = (ROOT / name for name in ("manifest.json", "ratings.json", "gallery.html"))
    for path in (manifest_path, ratings_path, gallery_path):
        require(path.is_file(), f"не найден обязательный файл: {path}")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    ratings = json.loads(ratings_path.read_text(encoding="utf-8"))
    gallery = gallery_path.read_text(encoding="utf-8")
    require([item.get("id") for item in manifest.get("items", [])] == EXPECTED,
            "manifest.json должен содержать G01–G10 по порядку")
    require([item.get("id") for item in ratings.get("items", [])] == EXPECTED,
            "ratings.json должен содержать оценки G01–G10 по порядку")
    require(manifest.get("imagegen_calls") == 18, "manifest imagegen_calls должен быть 18")

    input_snapshots = dict(manifest.get("input_snapshots", {}))
    for item in manifest["items"]:
        for original, snapshot in item.get("input_snapshots", {}).items():
            key = normalized_path_key(original)
            previous = input_snapshots.get(key)
            require(previous is None or normalized_path_key(previous) == normalized_path_key(snapshot),
                    f"конфликт input_snapshots для {original}")
            input_snapshots[key] = snapshot
    normalized_snapshots = {normalized_path_key(original): snapshot
                            for original, snapshot in input_snapshots.items()}
    input_image_hashes = {}
    for item in manifest["items"]:
        request = item.get("request", {})
        references = request.get("referenced_image_paths", []) if isinstance(request, dict) else []
        require(isinstance(references, list), f"referenced_image_paths должен быть списком: {item['id']}")
        for original in references:
            key = normalized_path_key(original)
            snapshot = normalized_snapshots.get(key)
            if snapshot is not None:
                actual = Path(snapshot)
                require(actual.is_absolute(), f"путь input snapshot должен быть абсолютным: {snapshot}")
                require(actual.is_file(), f"не найдена сохранённая входная картинка: {actual}")
                is_snapshot = True
            else:
                actual = Path(original)
                require(actual.is_file(), f"не найдена входная картинка {item['id']}: {actual}")
                is_snapshot = False
            data, _, _ = verify_png(actual)
            input_image_hashes[str(original)] = {
                "used_path": str(actual), "sha256": sha256(data), "snapshot_used": is_snapshot,
            }

    outputs = []
    for item, rating in zip(manifest["items"], ratings["items"]):
        code = item["id"]
        image_path = ROOT / f"{code}.png"
        require(image_path.is_file(), f"не найден результат {code}.png")
        data, width, height = verify_png(image_path)
        source = Path(item["source"])
        require(source.is_file(), f"не найден manifest source для {code}: {source}")
        require(data == source.read_bytes(), f"байты {code}.png отличаются от manifest source")
        require(isinstance(rating.get("score"), int) and 1 <= rating["score"] <= 10,
                f"оценка {code} вне диапазона 1–10")
        require(bool(rating.get("reason")), f"нет причины оценки для {code}")
        require(rating.get("heroes_score") == 3, f"heroes_score для {code} должен быть 3")
        monsters = rating.get("monsters")
        require(isinstance(monsters, list) and len(monsters) == 2,
                f"для {code} требуются ровно две оценки монстров")
        sizes = set()
        figure_scores = [rating["heroes_score"]]
        for monster in monsters:
            require(bool(monster.get("name")), f"для {code} у монстра не указано имя")
            require(monster.get("size") in ("large", "small"),
                    f"неверный размер монстра в {code}: {monster.get('size')}")
            sizes.add(monster["size"])
            require(isinstance(monster.get("score"), int) and 2 <= monster["score"] <= 6,
                    f"оценка монстра в {code} должна быть от 2 до 6")
            require(bool(monster.get("reason")), f"для монстра в {code} нет причины оценки")
            figure_scores.append(monster["score"])
            require(monster["name"] in gallery and f'{monster["score"]}/10' in gallery,
                    f"галерея не показывает оценку монстра из {code}")
        require(sizes == {"large", "small"}, f"монстры в {code} должны быть двух разных размеров")
        require(rating["score"] == max(figure_scores),
                f"общая оценка {code} должна совпадать с максимумом сложности фигур")
        require(f'{rating["heroes_score"]}/10' in gallery,
                f"галерея не показывает оценку героев из {code}")
        require(f"{code}.png" in gallery, f"галерея не ссылается на {code}.png")
        outputs.append({"id": code, "width": width, "height": height,
                        "color_type": data[25], "sha256": sha256(data), "source_byte_exact": True,
                        "heroes_score": rating["heroes_score"], "max_figure_score": rating["score"],
                        "monsters": [{"name": monster["name"], "size": monster["size"],
                                      "score": monster["score"]} for monster in monsters]})

    benchmark = ratings.get("benchmark", {})
    require(isinstance(benchmark.get("score"), int) and 1 <= benchmark["score"] <= 10,
            "оценка benchmark вне диапазона 1–10")
    require(bool(benchmark.get("reason")), "нет причины оценки benchmark")
    input_hashes = {}
    for name, expected_hash in REFERENCE_SHA256.items():
        path = ROOT / name
        require(path.is_file(), f"не найден визуальный ориентир: {name}")
        actual_hash = sha256(path.read_bytes())
        require(actual_hash == expected_hash, f"SHA-256 визуального ориентира не совпал: {name}")
        input_hashes[name] = actual_hash

    for link in re.findall(r'(?:src|href)="([^\"]+)"', gallery):
        require((ROOT / link).is_file(), f"битая ссылка галереи: {link}")
    menu = ROOT.parents[2] / "scenes" / "demo" / "main_menu.tscn"
    require(menu.is_file() and sha256(menu.read_bytes()) == MAIN_MENU_SHA256,
            "main_menu.tscn отсутствует или изменён")

    report = {"status": "PASS", "output_count": len(outputs), "outputs": outputs,
              "input_reference_sha256": input_hashes,
              "request_input_image_sha256": input_image_hashes,
              "main_menu_sha256": MAIN_MENU_SHA256,
              "main_menu_unchanged": True,
              "scope": "PNG chunk CRC and dimensions, byte equality to manifest sources, reference SHA-256, per-figure and maximum-complexity scores, local gallery links; geometry and game anchors are not measured; monster sizes are visual suggestions, not game footprints"}
    (ROOT / "validation.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("PASS: 10 PNGs, input snapshots, CRC, source bytes, five reference SHA-256 values, figure scores, links, and main_menu hash")


if __name__ == "__main__":
    main()
