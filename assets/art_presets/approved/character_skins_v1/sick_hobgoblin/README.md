# Нездоровый хоб-гоблин

Approved `sick_hobgoblin` enemy skin built from the listed source PNG bytes. All clips use 33 frames, 256×256 cells, anchor (128,200), on 2048×1280 sheets; frames are atlas regions without normalization or editing.

- `idle`: 2970 ms; loop `true`; per-frame durations are in manifest.
- `idle_secondary`: 2970 ms; loop `true`; per-frame durations are in manifest.
- `buff`: 2740 ms; loop `false`; per-frame durations are in manifest.
- `death`: 3740 ms; loop `false`; per-frame durations are in manifest.

`death.png` comes from `rvanoukh-selected-20261115/death-1-closed-eyes`; it is a derived PixelLab patch selection, not raw provider output. Source and destination SHA-256 values are recorded in `manifest.json`.

Run `python tools/art/build_hobgoblin_skin.py` to build, or `--check` for deterministic no-write validation.
