"""Экспортирует готовые кадры PixelLab для автономного художественного просмотра."""
from __future__ import annotations

import base64
import hashlib
import io
import json
from pathlib import Path
from typing import Any

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
JOBS = Path(r"D:\Codex\home\generated_images\modular-equipment-animation-20261118\items")
OUT = ROOT / "preview"
SIZE = (256, 256)


def read_json(path: Path) -> Any:
	return json.loads(path.read_text(encoding="utf-8-sig"))


def digest(data: bytes) -> str:
	return hashlib.sha256(data).hexdigest()


def image_bbox(image: Image.Image, threshold: int = 1) -> list[int] | None:
	alpha = image.getchannel("A")
	if threshold > 1:
		alpha = alpha.point(lambda value: 255 if value >= threshold else 0)
	box = alpha.getbbox()
	return list(box) if box else None


def verify_request_binding(row: dict[str, Any], path: Path) -> None:
	"""Не позволяет переименовать результат чужого запроса в выбранный вариант."""
	if not path.is_file():
		raise ValueError("Нет сырого request.json для проверки происхождения")
	raw_request = read_json(path)
	if raw_request.get("endpoint") != row.get("endpoint"):
		raise ValueError("Endpoint сырого запроса не совпадает с манифестом")
	raw_body = raw_request.get("body")
	public_body = row.get("request")
	if not isinstance(raw_body, dict) or not isinstance(public_body, dict):
		raise ValueError("Некорректное тело сырого или публичного запроса")
	input_fields = {"image", "first_frame", "last_frame"}
	public_projection = {key: value for key, value in raw_body.items() if key not in input_fields}
	if public_projection != public_body:
		raise ValueError("Поля сырого тела запроса не совпадают с публичным манифестом")
	input_keys = ("image",) if row.get("kind") == "still" else ("first_frame", "last_frame")
	for key in input_keys:
		encoded = raw_body.get(key)
		if isinstance(encoded, dict):
			encoded = encoded.get("base64")
		if not isinstance(encoded, str):
			raise ValueError(f"В сыром запросе нет входного PNG {key}")
		if encoded.startswith("data:"):
			encoded = encoded.split(",", 1)[1]
		try:
			input_png = base64.b64decode(encoded, validate=True)
		except ValueError as error:
			raise ValueError(f"Некорректный base64 для {key}") from error
		if digest(input_png) != row.get("source_sha256"):
			raise ValueError(f"Хэш входного PNG {key} не совпадает с source_sha256")


def main() -> None:
	requests = read_json(ROOT / "requests.json")
	variants = read_json(ROOT / "variants.json")
	by_still = {item["still_id"]: item for item in variants}
	results: list[dict[str, Any]] = []
	missing: list[dict[str, Any]] = []
	failed: list[dict[str, Any]] = []
	for request in requests:
		job_id = request["id"]
		selected_job_id = request.get("selected_job_id", job_id)
		if isinstance(selected_job_id, bool) or not isinstance(selected_job_id, int) or selected_job_id <= 0:
			raise ValueError(f"selected_job_id должен быть положительным целым ID: {selected_job_id!r}")
		if request.get("kind") == "still":
			variant = by_still[job_id]
			item = {**request, **variant, "kind": "still"}
		else:
			still_id = (job_id - 100) // 2
			variant = by_still[still_id]
			kind = "idle" if job_id % 2 == 0 else "attack"
			item = {**request, **variant, "kind": kind}
		folder = JOBS / f"{selected_job_id:03d}"
		response_path, result_path = folder / "response.json", folder / "result.json"
		if not response_path.is_file() or not result_path.is_file():
			missing.append({"id": job_id, "key": item["key"], "kind": item["kind"], "paths": [str(response_path), str(result_path)]})
			continue
		try:
			result = read_json(result_path)
			response = read_json(response_path)
			if result.get("status") != "completed":
				missing.append({"id": job_id, "key": item["key"], "kind": item["kind"], "status": result.get("status")})
				continue
			if not result.get("job_id") or response.get("id") != result["job_id"]:
				raise ValueError("ID задания в response.json не совпадает с result.json")
			verify_request_binding(request, folder / "request.json")
			images = response.get("last_response", {}).get("images", [])
			expected = 17 if item["kind"] == "idle" else 25
			if item["kind"] == "still":
				encoded_outputs = ["original.png"]
				raw_images: list[bytes] = []
				for filename in encoded_outputs:
					image_bytes = (folder / filename).read_bytes()
					output = next((entry for entry in result.get("outputs", []) if Path(entry.get("path", "")).name == filename), None)
					if output is None or output.get("sha256") != digest(image_bytes):
						raise ValueError(f"Хэш файла результата не совпадает: {filename}")
					raw_images.append(image_bytes)
			else:
				if len(images) != expected:
					raise ValueError(f"Ожидалось кадров {expected}, получено {len(images)}")
				outputs = result.get("outputs", [])
				if len(outputs) != expected:
					raise ValueError(f"Ожидалось записей outputs {expected}, получено {len(outputs)}")
				raw_images = []
				for index, frame in enumerate(images):
					encoded = frame["base64"]
					if encoded.startswith("data:"):
						encoded = encoded.split(",", 1)[1]
					raw = base64.b64decode(encoded, validate=True)
					if outputs[index].get("sha256") != digest(raw):
						raise ValueError(f"Хэш PNG кадра не совпадает с result.outputs[{index}]")
					raw_images.append(raw)
			frames = [Image.open(io.BytesIO(raw)).convert("RGBA") for raw in raw_images]
			if any(frame.size != SIZE for frame in frames):
				raise ValueError("Кадр имеет размер, отличный от 256×256")
			if item["kind"] == "still":
				out_file = OUT / "inputs" / f"{item['key']}.png"
				out_file.parent.mkdir(parents=True, exist_ok=True)
				out_file.write_bytes(raw_images[0])
				results.append({"id": job_id, "key": item["key"], "kind": "still", "path": out_file.relative_to(ROOT).as_posix(), "sha256": digest(raw_images[0]), "canvas": list(SIZE), "usage": response.get("last_response", {}).get("billing_usage") or response.get("last_response", {}).get("usage") or result.get("usage")})
				continue
			clip_dir = OUT / "clips" / item["key"] / item["kind"]
			frames_dir = clip_dir / "frames"
			frames_dir.mkdir(parents=True, exist_ok=True)
			bboxes: list[list[int] | None] = []
			edges: list[int] = []
			for index, (raw, frame) in enumerate(zip(raw_images, frames)):
				( frames_dir / f"frame-{index:02d}.png").write_bytes(raw)
				box = image_bbox(frame)
				bboxes.append(box)
				if box and (box[0] == 0 or box[1] == 0 or box[2] == 256 or box[3] == 256):
					edges.append(index)
			source_path = OUT / "inputs" / f"{item['key']}.png"
			if request.get("source_sha256") != digest(source_path.read_bytes()):
				raise ValueError("Хэш исходного спрайта клипа не совпадает с манифестом")
			source = Image.open(source_path).convert("RGBA")
			durations = ([120] * len(frames)) if item["kind"] == "idle" else ([70] * (len(frames) - 1) + [500])
			cols = 8
			sheet = Image.new("RGBA", (256 * cols, 256 * ((len(frames) + cols - 1) // cols)))
			for index, frame in enumerate(frames):
				sheet.paste(frame, ((index % cols) * 256, (index // cols) * 256))
			sheet.save(clip_dir / "spritesheet.png")
			preview = []
			for frame in frames:
				bg = Image.new("RGBA", SIZE, "#252b34")
				bg.alpha_composite(frame)
				preview.append(bg.convert("RGB").resize((512, 512), Image.Resampling.NEAREST))
			preview[0].save(clip_dir / "preview.gif", save_all=True, append_images=preview[1:], duration=durations, loop=0, disposal=2)
			with Image.open(clip_dir / "preview.gif") as gif:
				gif_durations: list[int] = []
				for gif_index in range(gif.n_frames):
					gif.seek(gif_index)
					gif_durations.append(int(gif.info.get("duration", 0)))
			samples = sorted(set([0, len(frames) // 4, len(frames) // 2, 3 * len(frames) // 4, len(frames) - 1]))
			strip = Image.new("RGB", (256 * len(samples), 256), "#252b34")
			for column, frame_index in enumerate(samples):
				strip.paste(frames[frame_index], (column * 256, 0), frames[frame_index])
			strip.save(clip_dir / "filmstrip.png")
			meta = {**item, "provider": "PixelLab", "provider_job_id": result["job_id"], "usage": response.get("last_response", {}).get("billing_usage") or response.get("last_response", {}).get("usage") or result.get("usage"), "canvas": list(SIZE), "actual_frames": len(frames), "durations_ms": durations, "gif_actual_frames": len(gif_durations), "gif_actual_durations_ms": gif_durations, "gif_total_duration_ms": sum(gif_durations), "timing_origin": "Локальный тайминг просмотра; PixelLab задаёт только позы", "frame_sha256": [digest(raw) for raw in raw_images], "alpha_bboxes": [image_bbox(frame, 128) for frame in frames], "raw_alpha_bboxes": bboxes, "edge_frames": edges, "first_frame_rgba_equal_source": frames[0].tobytes() == source.tobytes(), "first_frame_png_byte_equal_source": raw_images[0] == source_path.read_bytes(), "last_frame_rgba_equal_source": frames[-1].tobytes() == source.tobytes(), "gif": "preview.gif", "integration": False}
			(clip_dir / "clip.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
			results.append({"id": job_id, "key": item["key"], "kind": item["kind"], "path": clip_dir.relative_to(ROOT).as_posix(), "actual_frames": len(frames), "edge_frames": edges, "usage": meta["usage"], "gif_actual_frames": len(gif_durations), "gif_total_duration_ms": sum(gif_durations)})
		except (OSError, KeyError, ValueError, TypeError, json.JSONDecodeError) as error:
			failed.append({"id": job_id, "key": item["key"], "kind": item["kind"], "error": str(error)})
		# IDs map to each independent request; stills are consumed by matching animation clips.
	counts = {kind: sum(1 for row in results if row["kind"] == kind) for kind in ("still", "idle", "attack")}
	complete = counts == {"still": 6, "idle": 6, "attack": 6} and not missing and not failed
	usage_totals: dict[str, float] = {}
	for row in results:
		usage = row.get("usage")
		if isinstance(usage, dict):
			for name, value in usage.items():
				if isinstance(value, (int, float)) and not isinstance(value, bool):
					usage_totals[name] = usage_totals.get(name, 0) + value
	validation = {"structural_pass": not failed, "complete": complete, "exported_counts": counts, "expected_counts": {"still": 6, "idle": 6, "attack": 6}, "usage_totals": usage_totals, "usage_by_job": [{"id": row["id"], "kind": row["kind"], "usage": row.get("usage")} for row in results], "visual_acceptance": "pending", "runtime_integration": False, "expected_jobs": len(requests), "exported_jobs": len(results), "missing_or_pending": missing, "failed_jobs": failed, "exports": results, "note": "Наличие и структура файлов не подтверждают художественную приемку; проверьте персонажа, экипировку, обрезку и край холста визуально."}
	(OUT / "validation.json").parent.mkdir(parents=True, exist_ok=True)
	(OUT / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2), encoding="utf-8")
	# Обзор собирается только при наличии полного набора: частичный лист искажает сравнение.
	clip_meta: dict[tuple[str, str], tuple[dict[str, Any], list[Image.Image]]] = {}
	for entry in results:
		if entry.get("kind") not in ("idle", "attack"):
			continue
		folder = ROOT / entry["path"]
		meta = read_json(folder / "clip.json")
		frames_dir = folder / "frames"
		frames = [Image.open(frames_dir / f"frame-{index:02d}.png").convert("RGBA") for index in range(meta["actual_frames"])]
		clip_meta[(entry["key"], entry["kind"])] = (meta, frames)
	if validation["complete"] and len(clip_meta) == 12:
		try:
			font = ImageFont.truetype("C:/Windows/Fonts/arial.ttf", 14)
		except OSError:
			font = ImageFont.load_default()
		variants = read_json(ROOT / "variants.json")
		cell_w, cell_h, header_h = 256, 256, 36
		background = "#252b34"
		composites: list[Image.Image] = []
		durations: list[int] = []
		for phase, frame_count in (("idle", 17), ("attack", 25)):
			for index in range(frame_count):
				canvas = Image.new("RGB", (cell_w * 3, (cell_h + header_h) * 2), background)
				draw = ImageDraw.Draw(canvas)
				for card_index, variant in enumerate(variants):
					meta, frames = clip_meta[(variant["key"], phase)]
					frame_index = index if index < len(frames) else 0
					x, y = (card_index % 3) * cell_w, (card_index // 3) * (cell_h + header_h)
					for line, line_y in ((variant["title"], y + 2), ("Дыхание" if phase == "idle" else "Удар", y + 19)):
						bounds = draw.textbbox((0, 0), line, font=font)
						draw.text((x + max(2, (cell_w - (bounds[2] - bounds[0])) // 2), line_y), line, fill="#f3f1e9", font=font)
					cell = Image.new("RGBA", SIZE, background)
					cell.alpha_composite(frames[frame_index])
					canvas.paste(cell.convert("RGB").resize(SIZE, Image.Resampling.NEAREST), (x, y + header_h))
				composites.append(canvas)
				durations.append(120 if phase == "idle" else (500 if index == frame_count - 1 else 70))
		composites[0].save(OUT / "overview.gif", save_all=True, append_images=composites[1:], duration=durations, loop=0, disposal=2)
		composites[0].save(OUT / "overview.png")
		validation["overview"] = {"gif": "overview.gif", "snapshot": "overview.png", "variants": 6, "layout": "3 колонки оружия × 2 строки доспеха", "phase_frames": {"idle": 17, "attack": 25}, "durations_ms": durations, "synchronized": True, "ready": True}
	else:
		validation["overview"] = {"ready": False, "expected_clips": 12, "available_clips": len(clip_meta), "reason": "Для обзора нужны все шесть вариантов покоя и атаки."}
		# При неполном наборе старые агрегаты нельзя оставлять рядом с новой проверкой.
		for aggregate in (OUT / "overview.gif", OUT / "overview.png", ROOT / "gallery.html"):
			if aggregate.is_file():
				aggregate.unlink()
	(OUT / "validation.json").write_text(json.dumps(validation, ensure_ascii=False, indent=2), encoding="utf-8")
	print(json.dumps({"expected": len(requests), "exported": len(results), "missing": len(missing), "failed": len(failed), "visual_acceptance": "pending"}, ensure_ascii=False))


if __name__ == "__main__":
	main()
