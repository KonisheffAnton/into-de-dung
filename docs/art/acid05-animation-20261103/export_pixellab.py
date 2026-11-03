"""Экспортирует принятые кадры PixelLab побайтно и собирает превью циклов."""
from pathlib import Path
import base64
import hashlib
import io
import json

from PIL import Image
import numpy as np

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/acid05-animation-20261103")
FRAME_SIZE = (256, 256)
FRAME_COUNT = 33


def sha(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def load_json(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def main() -> None:
	rows = load_json(ROOT / "requests.json")
	if len(rows) != 10 or [row.get("key") for row in rows] != [f"acid-{index:02d}" for index in range(1, 11)]:
		raise SystemExit("Ожидаются ровно десять запросов acid-01…acid-10 в заданном порядке")
	results = []
	for row in rows:
		if (row.get("kind") != "acid" or row.get("frame_count") != 32
				or row.get("expected_frames") != FRAME_COUNT or not row.get("loop")
				or not row.get("return_to_first")):
			raise SystemExit(f"Некорректный контракт запроса: {row.get('key')}")
		folder = JOBS / "pixellab" / row["key"]
		job_file, admission_file = folder / "job-latest.json", folder / "admission.json"
		if not job_file.is_file() or not admission_file.is_file():
			raise SystemExit(f"Нет завершённого admitted job для {row['key']}")
		job, admission = load_json(job_file), load_json(admission_file)
		if job.get("status") != "completed":
			raise SystemExit(f"Job не завершён для {row['key']}: {job.get('status')}")
		if job.get("id") != admission.get("background_job_id"):
			raise SystemExit(f"Job/admission ID mismatch for {row['key']}")
		response = job["last_response"]
		images = response.get("images", [])
		if len(images) != FRAME_COUNT:
			raise SystemExit(f"Ожидалось {FRAME_COUNT} исходных кадров {row['key']}, получено {len(images)}")
		out = ROOT / "pixellab" / row["key"]
		frames_dir = out / "frames"
		frames_dir.mkdir(parents=True, exist_ok=True)
		frames, raw_bytes, frame_hashes, alpha_boxes = [], [], [], []
		for index, item in enumerate(images):
			encoded = item["base64"]
			if encoded.startswith("data:"):
				encoded = encoded.split(",", 1)[1]
			raw = base64.b64decode(encoded, validate=True)
			image = Image.open(io.BytesIO(raw)).convert("RGBA")
			if image.size != FRAME_SIZE:
				raise SystemExit(f"Неверный размер кадра {image.size}: {row['key']}:{index}")
			frame_path = frames_dir / f"frame-{index:02d}.png"
			if frame_path.exists() and frame_path.read_bytes() != raw:
				raise SystemExit(f"Существующий исходный кадр отличается: {frame_path}")
			frame_path.write_bytes(raw)
			frames.append(image)
			raw_bytes.append(raw)
			frame_hashes.append(sha(raw))
			alpha_boxes.append(image.getchannel("A").getbbox())
		input_path = ROOT / row["input"]
		input_bytes = input_path.read_bytes()
		if sha(input_bytes) != row.get("input_sha256"):
			raise SystemExit(f"SHA-256 входного файла не совпадает с запросом: {row['key']}")
		if input_bytes != (ROOT / "model" / "input-256.png").read_bytes():
			raise SystemExit(f"Вход запроса отличается от согласованного input-256.png: {row['key']}")
		original = Image.open(input_path).convert("RGBA")
		if original.size != FRAME_SIZE:
			raise SystemExit(f"Вход должен быть 256×256: {row['key']}")
		first_diff = np.any(np.asarray(frames[0]) != np.asarray(original), axis=2)
		first_alpha_diff = np.asarray(frames[0])[:, :, 3] != np.asarray(original)[:, :, 3]
		visible = (np.asarray(frames[0])[:, :, 3] > 0) | (np.asarray(original)[:, :, 3] > 0)
		first_rgba_differing = int(np.count_nonzero(first_diff))
		first_alpha_differing = int(np.count_nonzero(first_alpha_diff))
		first_visible_differing = int(np.count_nonzero(first_diff & visible))
		if first_alpha_differing or first_visible_differing:
			raise SystemExit(f"Альфа-канал и видимые пиксели первого кадра должны совпадать со входом: {row['key']}")
		durations = [100] * FRAME_COUNT
		sheet = Image.new("RGBA", (FRAME_SIZE[0] * 8, FRAME_SIZE[1] * 5))
		for index, image in enumerate(frames):
			sheet.paste(image, ((index % 8) * 256, (index // 8) * 256))
		sheet.save(out / "sheet.png")
		preview_frames = []
		for image in frames:
			background = Image.new("RGBA", FRAME_SIZE, "#182131")
			background.alpha_composite(image)
			preview_frames.append(background.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
		preview_frames[0].save(out / "preview.gif", save_all=True, append_images=preview_frames[1:], duration=durations, loop=0, disposal=2)
		gif_durations = []
		with Image.open(out / "preview.gif") as gif:
			for index in range(gif.n_frames):
				gif.seek(index)
				gif_durations.append(gif.info.get("duration", 0))
		if gif.n_frames != FRAME_COUNT or gif_durations != durations:
			raise SystemExit(f"GIF превью изменило число кадров или тайминг для {row['key']}")
		filmstrip = Image.new("RGB", (FRAME_SIZE[0] * 5, FRAME_SIZE[1]), "#182131")
		for column, index in enumerate((0, 8, 16, 24, 32)):
			filmstrip.paste(frames[index], (column * 256, 0), frames[index])
		filmstrip.save(out / "filmstrip.png")
		artifact_hashes = {
			name: sha((out / name).read_bytes())
			for name in ("sheet.png", "preview.gif", "filmstrip.png")
		}
		result = {
			**row, "provider": "PixelLab PixMiniMax", "job_id": job["id"],
			"actual_frames": len(frames), "usage": response.get("billing_usage") or response.get("usage") or job.get("usage"),
			"canvas": [256, 256], "durations_ms": durations,
			"timing_origin": "Только для просмотра: 100 мс на кадр, около 10 кадров/с",
			"loop": True, "return_to_first": True,
			"first_frame_rgba_equal": first_rgba_differing == 0,
			"first_frame_render_equal": first_alpha_differing == 0 and first_visible_differing == 0,
			"first_frame_rgba_differing_pixels": first_rgba_differing,
			"first_frame_alpha_differing_pixels": first_alpha_differing,
			"first_frame_visible_differing_pixels": first_visible_differing,
			"first_frame_png_byte_equal": raw_bytes[0] == input_path.read_bytes(),
			"endpoint_frame_rgba_equal": frames[-1].tobytes() == original.tobytes(),
			"frame_sha256": frame_hashes,
			"artifact_sha256": artifact_hashes,
			"alpha_bboxes": alpha_boxes,
			"edge_frames": [index for index, box in enumerate(alpha_boxes) if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256)],
			"margin_violation_frames": [index for index, box in enumerate(alpha_boxes) if box and (box[0] < 8 or box[1] < 8 or box[2] > 248 or box[3] > 248)],
			"gif_actual_durations_ms": gif_durations,
			"integration": False,
		}
		(out / "clip.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
		results.append(result)
	(ROOT / "pixellab-validation.json").write_text(json.dumps({
		"expected": 10, "completed": len(results), "complete": len(results) == 10,
		"first_frame_policy": "Первый кадр должен совпадать по альфа-каналу и видимым пикселям. RGB-различия полностью прозрачных пикселей учитываются отдельно и не меняют отображение.",
		"complete_meaning": "Количество экспортированных admitted клипов; не подтверждает художественную приёмку или интеграцию",
		"clips": results,
	}, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({
		"expected": 10, "exported": len(results),
		"edge_clips": [result["key"] for result in results if result["edge_frames"]],
		"first_frame_png_byte_mismatches": [result["key"] for result in results if not result["first_frame_png_byte_equal"]],
		"first_frame_rgba_mismatches": [result["key"] for result in results if not result["first_frame_rgba_equal"]],
		"endpoint_frame_rgba_mismatches": [result["key"] for result in results if not result["endpoint_frame_rgba_equal"]],
		"usage": [result["usage"] for result in results],
	}, ensure_ascii=False))


if __name__ == "__main__":
	main()
