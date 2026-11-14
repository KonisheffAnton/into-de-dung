"""Запускает ограниченную очередь: каждая POST однократна, опросы повторяют GET."""
from pathlib import Path
import argparse
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parent
JOBS = Path("C:/Users/Aston/.codex/generated_images/warrior-attack-single-five-20261114")


def read(path: Path) -> dict:
	return json.loads(path.read_text(encoding="utf-8-sig")) if path.exists() else {}


def call(action: str, key: str) -> int:
	result = subprocess.run(
		["pwsh", "-NoProfile", "-File", str(JOBS / "invoke-pixellab.ps1"), "-Action", action, "-Variant", key],
		capture_output=True, text=True, encoding="utf-8", errors="replace")
	print(result.stdout.strip(), flush=True)
	if result.stderr.strip():
		print(result.stderr.strip(), flush=True)
	return result.returncode


def main() -> None:
	parser = argparse.ArgumentParser()
	parser.add_argument("--limit", type=int, default=5)
	parser.add_argument("--active", type=int, default=3)
	args = parser.parse_args()
	if args.limit < 0 or args.active < 1:
		raise SystemExit("--limit must be nonnegative and --active must be positive")
	rows = read(ROOT / "requests.json")[:args.limit]
	if not rows:
		raise SystemExit("No prepared requests; run prepare_requests.py first")
	while True:
		active, pending, completed, failed, cancelled, blocked = [], [], [], [], [], []
		for row in rows:
			key = row["key"]
			folder = JOBS / "pixellab" / key
			job = read(folder / "job-latest.json")
			admission = read(folder / "admission.json")
			if job.get("status") == "completed":
				completed.append(key)
			elif job.get("status") == "failed":
				failed.append(key)
			elif job.get("status") == "cancelled":
				cancelled.append(key)
			elif admission.get("background_job_id"):
				active.append(key)
			elif (folder / "submit-started.json").exists():
				blocked.append(key)
			else:
				pending.append(key)
		summary = {"expected_rows": len(rows), "completed": completed, "failed": failed,
			"cancelled": cancelled, "active": active, "pending": pending, "blocked": blocked}
		if not active and not pending:
			complete = len(completed) == len(rows) and not failed and not cancelled and not blocked
			summary["status"] = "DONE" if complete else "INCOMPLETE"
			(JOBS / "batch-status.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
			if complete:
				print("DONE", json.dumps(summary), flush=True)
				return
			print("INCOMPLETE", json.dumps(summary), flush=True)
			raise SystemExit(1)
		(JOBS / "batch-status.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
		for key in pending[:max(0, args.active - len(active))]:
			if call("Submit", key) != 0:
				# Неясный результат POST нельзя считать отказом: повтор может создать дубль.
				print("Submission blocked; inspect the saved attempt before continuing", key, flush=True)
				blocked.append(key)
				pending.remove(key)
				summary["pending"] = pending
				summary["blocked"] = blocked
				summary["status"] = "INCOMPLETE"
				(JOBS / "batch-status.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
				print("INCOMPLETE", json.dumps(summary), flush=True)
				raise SystemExit(1)
			active.append(key)
		for key in active:
			call("Poll", key)
		print("BATCH", len(completed), "completed;", len(failed), "failed;", len(cancelled),
			"cancelled;", len(blocked), "blocked;", len(active), "active;", len(pending), "pending", flush=True)
		time.sleep(20)


if __name__ == "__main__":
	main()
