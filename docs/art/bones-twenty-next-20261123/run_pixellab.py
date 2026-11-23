"""Одна независимая PixelLab-партия костяных кучек без повторного POST."""
from pathlib import Path
import argparse
import base64
import importlib.util
import json
from concurrent.futures import ThreadPoolExecutor

ROOT = Path(__file__).resolve().parent
CLIENT_PATH = ROOT.parent / "battle-remains-variants-20261122/pixellab/run.py"
spec = importlib.util.spec_from_file_location("remains_client", CLIENT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("Не найден проверенный PixelLab клиент")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT / "pixellab"

REFERENCE = ROOT.parent / "bones-twenty-more-20261123/pixellab/fragments/image.png"
COMPOSITIONS = [
    "low oval",
    "flattened triangle",
    "short curved bean",
    "two touching low lobes, one pile",
    "short diagonal wedge",
    "small round heap",
    "wide flat trapezoid",
    "asymmetric knot",
    "flat diamond",
    "short horizontal heap",
]
DESCRIPTION = (
    "One tiny dry universal bone heap sprite for a dark fantasy pixel art tactics game. "
    "Make a low compact broad pile, footprint about 34 by 18 pixels on a 64x64 canvas. "
    "Inside each pile use 8 to 12 DIFFERENT small short fragments: thin gently curved snapped segments, "
    "short hollow tubular stubs with broken ends, tiny rounded joint knobs, and a few flat tapered flakes. "
    "Every fragment is short and irregular; vary lengths and shapes within the same pile. "
    "Overlap in a low dense cluster with a few narrow dark gaps. All pieces lie flat. "
    "Make unmistakable little bone fragments, not pebbles, stones, spikes, or a repeated row of dumbbells. "
    "Explore distinct asymmetric arrangements and silhouettes across the batch. "
    "Crisp 64x64 pixel art with small clear pixel clusters, 6 to 8 muted dirty ivory, warm taupe, "
    "and dark purple-gray colors, restrained upper-left lighting. Dry bare anonymous bones, "
    "impossible to tell human or monster. NO skull, face, jaw, teeth, ribcage, whole skeleton, "
    "flesh, blood, clothes, equipment, floor, rocks, podium, pedestal, halo, or background. "
    "Transparent background and generous empty margins. Use the reference only for pixel-art style and palette; "
    "invent new small varied fragments and compositions."
)
DESCRIPTION_REDESIGN = (
    "A small compact low heap of tiny DRY BROKEN BONE FRAGMENTS, a battle-remains ground prop for a muted dark fantasy pixel art game. "
    "Draw 12 to 16 small unequal bone fragments packed close together in two flat overlapping layers: short snapped tubular bits with chipped hollow ends, tiny irregular knuckly joint chips, thin gently bent segments and small flat flakes. "
    "Each fragment only 3 to 7 pixels long and at most one fifth of the heap width. "
    "Flat broad uneven oval footprint occupying 36x18 pixels centered inside a 64x64 transparent canvas, generous empty transparent space on all sides. "
    "Anonymous small bony fragments, different lengths and shapes WITHIN each heap. Crisp simple low-detail pixel clusters; dirty pale ivory, gray-taupe middle tones and purple-gray dark crevices; light from upper left. "
    "A connected low pile resting flat, viewed from above at shallow three-quarter angle. "
    "ONLY the small loose broken fragments, no skull or face, no intact long bones, no display base, no ground, no other objects. New compact arrangement for each candidate."
)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "poll", "generate-individual", "poll-individual", "generate-redesign", "poll-redesign"])
    args = parser.parse_args()
    if args.action in ("generate-redesign", "poll-redesign"):
        directory = client.ROOT / "fragment-redesign"
        if args.action == "generate-redesign":
            if (directory / "request.json").exists() or (directory / "response.json").exists():
                raise RuntimeError("Existing redesign receipt; refusing another POST")
            client.ROOT.mkdir(parents=True, exist_ok=True)
            client.submit("fragment-redesign", "/generate-image-v2", {
                "description": DESCRIPTION_REDESIGN,
                "image_size": {"width": 64, "height": 64},
                "seed": 202611839,
                "no_background": True,
                "style_options": {"color_palette": False, "outline": False, "detail": False, "shading": False},
                "target_palette": {
                    "colors": ["#e0d6be", "#c6bba7", "#aa9f90", "#8c8179", "#71676b", "#564c59", "#3e3544", "#28232e"],
                    "max_colors": 8,
                    "name": "muted ivory bone fragments",
                },
            })
            return
        receipt_path = directory / "response.json"
        if not receipt_path.is_file():
            raise FileNotFoundError("No redesign batch receipt to poll")
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        result = client.request("GET", "/background-jobs/" + receipt["background_job_id"])
        client.save(directory / "status.json", result)
        paths = client.decode(result, directory) if result.get("status") == "completed" else []
        print(json.dumps({"status": result.get("status"), "files": paths, "usage": result.get("usage")}, ensure_ascii=False))
        return
    if args.action in ("generate-individual", "poll-individual"):
        client.ROOT.mkdir(parents=True, exist_ok=True)
        individual_root = client.ROOT / "individual"
        individual_root.mkdir(parents=True, exist_ok=True)
        identifiers = [f"PL{i}" for i in range(39, 49)]
        if args.action == "generate-individual":
            # Запись request без response тоже блокирует повтор, если первый POST оборвался на сети.
            existing = [name for name in identifiers if any(
                (individual_root / name / receipt).exists() for receipt in ("request.json", "response.json")
            )]
            if existing:
                raise RuntimeError("Existing receipt(s); refusing any repeated POST: " + ", ".join(existing))

            def submit_individual(item: tuple[int, str]) -> None:
                index, identifier = item
                description = (
                    "64px crisp pixel art, transparent, top-down. Dry low bone heap, ~34x18px. "
                    "9-12 varied fragments, 4-8px each: curved chips, hollow snapped stubs, tiny joint knobs, flat flakes. "
                    "Mix shapes, lengths, angles. Dirty ivory, taupe, purple-gray; 6-8 colors, selective outline, sparse shading. "
                    f"Composition: {COMPOSITIONS[index]}. "
                    "No skull, face, jaw, flesh, blood, floor, stones, whole long bones, identical dumbbells, pedestal, background."
                )
                client.submit(f"individual/{identifier}", "/create-image-pixen", {
                    "description": description,
                    "image_size": {"width": 64, "height": 64},
                    "outline": "selective outline",
                    "detail": "low detail",
                    "view": "high top-down",
                    "no_background": True,
                    "enhance_prompt": False,
                    "seed": 202611739 + index,
                })

            with ThreadPoolExecutor(max_workers=3) as pool:
                list(pool.map(submit_individual, enumerate(identifiers)))
            return

        def poll_individual(identifier: str) -> None:
            directory = individual_root / identifier
            if (directory / "image.png").exists():
                return
            receipt_path = directory / "response.json"
            if not receipt_path.is_file():
                print(json.dumps({"id": identifier, "status": "missing receipt"}), flush=True)
                return
            receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
            status = client.request("GET", "/background-jobs/" + receipt["background_job_id"])
            client.save(directory / "status.json", status)
            paths = client.decode(status, directory) if status.get("status") == "completed" else []
            print(json.dumps({"id": identifier, "status": status.get("status"), "files": paths,
                              "usage": status.get("usage")}, ensure_ascii=False), flush=True)

        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(poll_individual, identifiers))
        return
    directory = client.ROOT / "mixed-small"
    if args.action == "generate":
        if (directory / "response.json").exists():
            raise RuntimeError("Existing receipt: inspect it; refusing another POST")
        if not REFERENCE.is_file():
            raise FileNotFoundError(REFERENCE)
        # Клиент batch умеет создать только конечную папку, поэтому заранее готовим родителя.
        directory.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "description": DESCRIPTION,
            "image_size": {"width": 64, "height": 64},
            "seed": 202611639,
            "no_background": True,
            "style_image": {
                "image": {"base64": base64.b64encode(REFERENCE.read_bytes()).decode("ascii")},
                "size": {"width": 64, "height": 64},
                "usage_description": "Pixel-art style and muted palette only; invent a new small varied fragment pile.",
            },
            "style_options": {"color_palette": False, "outline": True, "detail": True, "shading": True},
            "target_palette": {
                "colors": ["#e0d6be", "#c6bba7", "#aa9f90", "#8c8179", "#71676b", "#564c59", "#3e3544", "#28232e"],
                "max_colors": 8,
                "name": "muted ivory bone fragments",
            },
        }
        client.submit("mixed-small", "/generate-image-v2", payload)
        return
    receipt_path = directory / "response.json"
    if not receipt_path.is_file():
        raise FileNotFoundError("No batch receipt to poll")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    result = client.request("GET", "/background-jobs/" + receipt["background_job_id"])
    client.save(directory / "status.json", result)
    paths = client.decode(result, directory) if result.get("status") == "completed" else []
    print(json.dumps({"status": result.get("status"), "files": paths, "usage": result.get("usage")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
