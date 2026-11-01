"""Подготавливает девять фиксированных запросов без сети и секретов."""
from pathlib import Path
import base64
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/rogue-animation-02-20261101")
COMMON = ("Animate the EXACT reference rogue, preserving the charcoal hood, red scarf, brown leather, "
          "two knives, proportions, pixel clusters and palette. Fixed camera and facing right; no zoom, turn, "
          "redesign, extra limbs or weapons, VFX, ground or shadow. Transparent 256x256 canvas, starting soles "
          "near (128,200). Keep the entire body and both blades inside x8..248,y8..248. ")
MOTIONS = {
    "idle": [
        "Very quiet breathing loop. Feet and pelvis locked; chest rises slightly, shoulders and hood follow with tiny delayed movement. Both knives stay controlled. No hopping, body scaling, stepping or foot slide. Return smoothly to starting pose.",
        "Alert idle loop: tiny weight shift through torso and one small knife grip adjustment. Both soles remain planted. No attack, step, turn or travel. Ease back to starting pose.",
        "Subtle breathing with a small delayed sway of the red scarf. Boots and blades stay stable; no flourish, bounce, step or travel. Return smoothly to starting pose.",
    ],
    "death": [
        "One death: knees buckle and body collapses sideways beside original feet. Keep both knives attached. End fully lying on side, still. No get-up or loop.",
        "One death: knees give way, torso tips backward and lands on back beside original feet. Both knives stay with the rogue. Hold the fallen pose motionless; no recovery or loop.",
        "One death: shoulders sag, body folds forward through knees and collapses near original feet. End fully fallen, not merely kneeling, and hold still. No get-up or loop.",
    ],
    "ability": [
        "Cross both daggers briefly at the chest, then make one forceful outward blade flourish. Clear anticipation, short accent, soft recovery to the starting guard. Stay in place with feet planted.",
        "One short paired-blade flourish: lift both knives into a tight crossing arc, make a quick decisive motion, then settle into ready focus and starting guard. Feet planted, no travel.",
        "Lower into a compact crouched preparation, cross both blades in front of the chest, then rise and settle back into starting guard. Keep feet in place, no travel.",
    ],
}


def main() -> None:
    source = ROOT / "model" / "input-256.png"
    if not source.is_file():
        raise SystemExit("Prepare and confirm model/input-256.png first")
    frame = {"base64": base64.b64encode(source.read_bytes()).decode("ascii"), "format": "png"}
    rows = []
    for kind in ("idle", "death", "ability"):
        for variant, motion in enumerate(MOTIONS[kind], 1):
            key = f"{kind}-{variant}"
            folder = JOBS / "pixellab" / key
            folder.mkdir(parents=True, exist_ok=True)
            if (folder / "submit-started.json").exists():
                raise SystemExit(f"Already attempted {key}")
            prompt = COMMON + motion
            assert len(prompt) <= 1000
            request = {"first_frame": frame, "description": prompt, "frame_count": 32,
                       "seed": 2026110100 + ("idle", "death", "ability").index(kind) * 3 + variant,
                       "no_background": True, "enhance_prompt": False}
            if kind != "death":
                request["last_frame"] = frame
            (folder / "request.json").write_text(json.dumps(request), encoding="utf-8")
            (folder / "prompt.txt").write_text(prompt, encoding="utf-8")
            rows.append({"key": key, "kind": kind, "variant": variant, "prompt": prompt,
                         "seed": request["seed"], "frame_count": 32, "endpoint": "animate-pixminimax",
                         "loop": kind == "idle", "return_to_first": kind != "death",
                         "input": "model/input-256.png"})
    (ROOT / "requests.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Prepared {len(rows)} requests; no submissions")


if __name__ == "__main__":
    main()
