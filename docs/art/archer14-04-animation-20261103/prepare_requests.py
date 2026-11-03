"""Готовит транспортные JSON-запросы из утверждённых motion prompts без сети."""
from pathlib import Path
import base64
import json

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/archer14-04-animation-20261103")
CAPTIONS = {
	"direction": "south-east",
	"view": "low top-down",
	"subject_description": "A compact silver-haired adult female archer in olive cape and brown leather armor with one wooden bow and a quiver",
	"initial_pose": "Standing with both boots planted, bow held vertically at rest beside the body, free hand relaxed near waist",
}


def main() -> None:
	source = ROOT / "model" / "input-256.png"
	prompt_manifest = ROOT / "clip-prompts.json"
	if not source.is_file():
		raise SystemExit("Prepare and confirm model/input-256.png first")
	if not prompt_manifest.is_file():
		raise SystemExit("Root-owned clip-prompts.json is required")
	manifest = json.loads(prompt_manifest.read_text(encoding="utf-8"))
	rows = next((manifest[key] for key in ("clips", "variants", "prompts") if key in manifest), []) \
		if isinstance(manifest, dict) else manifest
	if len(rows) != 15:
		raise SystemExit(f"Expected 15 approved prompts, found {len(rows)}")
	frame = {"base64": base64.b64encode(source.read_bytes()).decode("ascii"), "format": "png"}
	prepared = []
	seen = set()
	kind_order = {"idle": 0, "death": 1, "ability": 2}
	for row in rows:
		kind = str(row["kind"])
		variant = int(row["variant"])
		if kind not in ("idle", "death", "ability") or not 1 <= variant <= 5:
			raise SystemExit(f"Invalid clip row: {row}")
		key = f"{kind}-{variant}"
		if key in seen:
			raise SystemExit(f"Duplicate clip row: {key}")
		seen.add(key)
		prompt = str(row["prompt"])
		if not prompt or len(prompt) > 1000:
			raise SystemExit(f"Motion prompt must be 1–1000 characters: {key}")
		seed = 2026110301 + kind_order[kind] * 5 + variant - 1
		folder = JOBS / "pixellab" / key
		folder.mkdir(parents=True, exist_ok=True)
		if (folder / "submit-started.json").exists():
			raise SystemExit(f"Already attempted {key}")
		request = {
			"first_frame": frame,
			"description": prompt,
			"frame_count": 32,
			"seed": seed,
			"no_background": True,
			"enhance_prompt": False,
			**CAPTIONS,
		}
		if kind != "death":
			request["last_frame"] = frame
		(folder / "request.json").write_text(json.dumps(request), encoding="utf-8")
		(folder / "prompt.txt").write_text(prompt, encoding="utf-8")
		prepared.append({
			"key": key, "kind": kind, "variant": variant,
			"name": str(row.get("name", f"{kind} {variant}")),
			"prompt": prompt, "seed": seed, "frame_count": 32,
			"expected_frames": 33, "endpoint": "animate-pixminimax",
			"loop": kind == "idle", "return_to_first": kind != "death",
			"input": "model/input-256.png", "captions": CAPTIONS,
		})
	expected = {f"{kind}-{variant}" for kind in ("idle", "death", "ability") for variant in range(1, 6)}
	if seen != expected:
		raise SystemExit("Prompt rows must cover variants 1–5 of idle, death and ability exactly once")
	(ROOT / "requests.json").write_text(json.dumps(prepared, ensure_ascii=False, indent=2), encoding="utf-8")
	print(f"Prepared {len(prepared)} requests; no submissions")


if __name__ == "__main__":
	main()
