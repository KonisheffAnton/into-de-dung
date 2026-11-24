"""Одна партия PixelLab для концепта костей, рёбер и малого фрагмента черепа."""
from pathlib import Path
import argparse
import importlib.util
import json

ROOT = Path(__file__).resolve().parent
CLIENT_PATH = ROOT.parent / "battle-remains-variants-20261122/pixellab/run.py"
spec = importlib.util.spec_from_file_location("remains_client", CLIENT_PATH)
if spec is None or spec.loader is None:
    raise RuntimeError("Не найден проверенный PixelLab клиент")
client = importlib.util.module_from_spec(spec)
spec.loader.exec_module(client)
client.ROOT = ROOT / "pixellab"

DESCRIPTION = (
    "One low compact universal dry bone heap; 10-14 different SMALL fragments; "
    "2-3 short thin curved BROKEN RIB pieces in a loose partial fan, plus one small BROKEN CRANIUM DOME fragment "
    "partly buried under bones near back edge, only a 5-7 pixel chipped curved rim visible, subtle, not central focus; "
    "rest short unequal tubes, joint chips, flat flakes; anonymous species, skull fragment secondary, no frontal face, "
    "no paired empty eyeholes, no head/teeth/jaw/whole cage/no human or creature identifier. "
    "Low 44x24 footprint centered in 64x64 with generous margins, shallow overhead three-quarter, flat pixel clusters, "
    "dirty ivory/taupe/purple-gray, upper-left light; no floor/pedestal/grass/halo/meat/blood. "
    "Different arrangements each candidate, fragment length 3-9px, all lying flat."
)
PALETTE = {
    "colors": ["#e0d6be", "#c6bba7", "#aa9f90", "#8c8179", "#71676b", "#564c59", "#3e3544", "#28232e"],
    "max_colors": 8,
    "name": "muted ivory bone fragments",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["generate", "poll"])
    args = parser.parse_args()
    directory = client.ROOT / "ribs-skull"
    if args.action == "generate":
        # request.json фиксирует попытку даже при сетевом обрыве, чтобы команда не повторила POST.
        if (directory / "request.json").exists() or (directory / "response.json").exists():
            raise RuntimeError("Existing request or receipt; refusing another POST")
        client.ROOT.mkdir(parents=True, exist_ok=True)
        client.submit("ribs-skull", "/generate-image-v2", {
            "description": DESCRIPTION,
            "image_size": {"width": 64, "height": 64},
            "seed": 202611949,
            "no_background": True,
            "style_options": {"color_palette": False, "outline": False, "detail": False, "shading": False},
            "target_palette": PALETTE,
        })
        return

    receipt_path = directory / "response.json"
    if not receipt_path.is_file():
        raise FileNotFoundError("No ribs-skull batch receipt to poll")
    receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
    result = client.request("GET", "/background-jobs/" + receipt["background_job_id"])
    client.save(directory / "status.json", result)
    paths = client.decode(result, directory) if result.get("status") == "completed" else []
    print(json.dumps({"status": result.get("status"), "files": paths, "usage": result.get("usage")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
