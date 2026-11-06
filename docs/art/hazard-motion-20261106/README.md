# Hazard motion — 2026-11-06

Scope: fire **24 and 29**, retractable trap **01**, and static caltrops **03**.
User requires PixelLab-created motion frames. Static input segmentation, selection
and retiming of provider poses are permitted; no locally drawn, warped or
interpolated motion poses are used. No candidate is integrated into runtime.

[Gallery](gallery.html) shows two spike candidates and explicitly unfinished fire.
[Trap candidate](trap/README.md) uses three existing provider poses on a fixed
plate. [Caltrops candidate](caltrops/README.md) keeps two 300 ms glints in a 15.6 s
cycle, with long quiet intervals and a source-to-source seam. These candidates
passed independent technical review; user art selection remains open.

## Fire experiments

`long01`: seven legacy masked calls produced 28 raw 64² PNGs: 16 for fire24,
12 for fire29. A full native-scale ROI was inserted unchanged onto the original
256² working tile. All raw files match the API response bytes. Areas outside the
mask are temporally fixed; 7/8 alpha0–1 pixels per source were normalized by the
provider consistently. Fire24 first/last RGBA matches. These are **rejected
experiments**, not usable animation: chunk boundaries change texture/brightness,
and the existing tips do not show convincing sideways sway. Fire29 was stopped
before its fourth chunk. [Provenance and transitions](fire/validation.json).

`layer01`: the input isolates warm painted strokes on transparency while keeping
source RGB. The V3 request for 16 frames at 256² was explicitly rejected (422:
maximum 8 frames at this size); no generation was admitted for this request.
`layer02`: the same isolated input produced 9 raw frames (8 billed generations).
The model invented side loops and restructured the strokes. Rejected internally.
`mask02`: one legacy call without init-image conditioning produced 4 raw frames;
the stronger redraw changes the painted texture without clear sway. Rejected.

`keypose01` is an **unsubmitted preparation draft**. Its tip rectangles were
corrected before submission. `keypose02` used inpaint-v3 for a constrained
right-leaning pose of nine tips: the provider drew new taller flame icons, changed
the outside background to white and changed 64,435 pixels outside the 768-pixel
mask. Rejected; [comparison](fire/fire24/keypose02/comparison.png).

`interpolate01` uses native 128² crops of V3 raw poses 00 and 07, without local
deformation. The API returned **two**, not an assumed 4–8, intermediate images.
They redraw the texture and simplify its palette rather than supply convincing
tip sway. Rejected; [contact](fire/fire24/interpolate01/contact.png).

All 11 admitted calls completed; one additional V3 request was explicitly rejected
before admission. **44 raw PNGs, 36 subscription generations**, balance 4597 → 4561.
The overall fire goal is **not achieved**. No further requests are pending, and no
failed fire is presented as a finished candidate. A new iteration needs a concrete
new control method or usable PixelLab poses; repeating these prompts is not evidence
of progress. The user's PixelLab-only restriction remains in force.

Raw responses, rejected responses and derived assemblies remain separate.
Technical provenance checks do not constitute visual acceptance.

## Verification

- `validate_package.py`: 44/44 PNGs match archived provider base64 bytes; all 4,610
  baseline files and the prior HANDOFF archive match byte-for-byte.
- Trap/caltrops: independent technical APPROVE; no changed pixels outside masks.
  Three trap states are deliberately stepped. The upper caltrop second pose is a
  hold, not a fade. Both glint events and the quiet loop boundary were exercised.
- `check_gallery.cjs`: desktop 1280 px and mobile 390 px, images, no overflow,
  play/pause/replay/seek, full glint timing, and honest fire-pending state PASS.
- Reports: `test_reports/hazard-motion-20261106/`. Godot/core/full and manual F5,
  zoom/DPI/GPU/performance were not run. Prior runtime checks were not repeated.

Provider `job-latest.json` for V3 layer02 was parsed and reserialized by the bridge;
the PNG bytes are unchanged. Other archived raw HTTP responses remain separate.
Input masks/alpha preparation are not claimed to be provider motion frames.
