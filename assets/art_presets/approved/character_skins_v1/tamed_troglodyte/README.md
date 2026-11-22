# Прирученный троглодит

Approved `tamed_troglodyte` enemy skin built from the listed source PNG bytes. All clips use 33 frames, 256×256 cells, runtime support anchor (128,184), shadow scale 1.25, on 2048×1280 sheets; frames are atlas regions without normalization or editing.

- `idle`: 2640 ms; loop `true`; per-frame durations are in manifest.
- `idle_secondary`: 2640 ms; loop `true`; per-frame durations are in manifest.
- `buff`: 2640 ms; loop `false`; per-frame durations are in manifest.
- `death`: 2640 ms; loop `false`; per-frame durations are in manifest.

O3 primary idle, O2 rare idle and C2 death are user selections (C2 replaces C1). R2 furious roar is the integration proposal from three new PixelLab variants. All source frames remain unchanged. Source and destination SHA-256 values are recorded in `manifest.json`.

Run `python tools/art/build_troglodyte_skin.py` to build, or `--check` for deterministic no-write validation.
