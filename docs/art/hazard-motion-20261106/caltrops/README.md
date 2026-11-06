# Caltrops 03: two rare glints

This is a **derived assembly** from the accepted older PixelLab `caltrops03-01` frames under `docs/art/hazard-animations-20261104/pixellab/`. The fixed plate is the original `model/caltrops03/input-256.png`, copied byte-for-byte to [rest.png](rest.png). No new provider call was made and no pixel was painted, recolored, interpolated, resized, or warped.

For each glint, a small bounding region covers an existing metal point. A pixel is copied unchanged from its old PixelLab frame only when its mean RGB brightness exceeds raw frame 00 by more than 15. Other pixels retain the exact source plate, including the stone, side faces, camera, and outer alpha. Frame 00 itself differs from the source by 34 pixels with a maximum channel delta of 2; the rest pose uses the source, so these provider normalization differences do not flicker through the cycle.

| Glint | Peak | Second pose | Moved pixels in both poses |
| --- | --- | --- | --- |
| Lower metal point | raw 02 | raw 03 | 57 / 7 |
| Higher metal point | raw 05 | raw 06 (hold) | 47 / 47 |

The [candidate contact](candidate-contact.png) shows assembled poses above the complete raw frames. [8× detail](glints-assembled-8x.png) shows both actual glints and the unchanged surrounding stone. [Metrics and SHA-256](candidate-metrics.json) identify every source frame and mask. All changed pixels are exact raw PixelLab pixels; zero pixels change outside the two small masks.

[Playable preview](preview.html) uses the source rest pose for 5 s, lower peak/tail for 0.15 s each, rest for 5 s, higher peak/hold for 0.15 s each, then rest for 5 s. The upper raw 06 pose differs from peak raw 05 by only one assembled pixel, so it holds the glint rather than visibly fading it. A 15.6 s cycle has two 0.3 s glints and an exact still-to-still seam. Retiming and reuse of provider frames create the rarity; no new pose was generated. This is a local candidate for art selection, not user acceptance or runtime integration. At native 256 px, the highlights are modest; the 8× detail makes their placement clear.

Rebuild: `python docs/art/hazard-motion-20261106/caltrops/build_candidate.py`.
Browser check: `node docs/art/hazard-motion-20261106/caltrops/check_preview.cjs`; evidence in `test_reports/hazard-motion-20261106/caltrops/`.
