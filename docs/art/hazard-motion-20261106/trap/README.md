# Spike trap 01: selected three-pose transition

This is a **derived assembly**, not three complete raw PixelLab frames. It uses the immutable retracted plate from `docs/art/fire-spikes-animation-20261105/model/spike01/retracted-input-256.png` and metal pixels from that package's `spike01-01` PixelLab frames 00, 03, 08. No new provider call was made; no pixel was painted, recolored, interpolated, resized, or warped. The assembled images are 256×256 RGBA.

| Pose | Full raw PixelLab frame | Output | Pixel mask |
| --- | --- | --- | --- |
| Closed | 00 | [closed.png](closed.png) | [closed-mask.png](closed-mask.png) |
| Half | 03 | [half.png](half.png) | [half-mask.png](half-mask.png) |
| Extended | 08 | [extended.png](extended.png) | [extended-mask.png](extended-mask.png) |

Nine fixed socket centers define narrow metal-only polygons. Each assembled pixel inside a mask equals the corresponding raw PixelLab pixel; every pixel outside equals the original retracted plate. The closed output is byte-for-byte the input/source frame 00. [Candidate metrics and SHA-256](candidate-metrics.json) record 504 and 864 copied pixels in the moving poses and zero changes outside masks. The plate, sides, camera, and outer alpha remain fixed.

[Candidate contact](candidate-contact.png) shows assembly above complete raw frames; [10× socket detail](socket-assembled-10x.png) exposes the mask joins. [Source pose contact](trap-pose-contact.jpg) includes the original extended still for comparison. [Playable preview](preview.html) presents closed → half → extended and stops on extended until Reset. It does not loop back through retraction.

The middle and final metal contours come from PixelLab and remain visually legible at native size. This is a local candidate for art selection, not user acceptance or runtime integration. It intentionally uses one middle pose; the step between states is visible. The final assembled spikes may differ from the separately painted extended still.

Rebuild: `python docs/art/hazard-motion-20261106/trap/build_candidate.py`.
Browser check: `node docs/art/hazard-motion-20261106/trap/check_preview.cjs`; evidence in `test_reports/hazard-motion-20261106/trap/`.
