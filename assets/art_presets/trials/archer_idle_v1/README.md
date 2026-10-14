# Archer idle v1

Selected corrected Archer idle integrated as a looping SpriteFrames resource. The 12 runtime PNGs are byte-for-byte copies of source frames 02 through 13 from [the source set](../../../../docs/art/archer-perspective-20261014/README.md); frame 01 is the input echo and is excluded. No pixels were edited. `manifest.json` records each source/runtime path and SHA-256, the user's explicit integration selection, and the exact 2.6-second cadence.

The resource uses 60 ticks per second with 13 ticks per frame: 12 × 13 / 60 = 2.6 seconds. The live visual samples this resource through the existing detached idle presentation lifecycle. Archer has no borrowed buff or death animation.

Build and verify with the bundled Python runtime:

```powershell
python tools/art/build_archer_idle.py
python tools/art/build_archer_idle.py --check
```

`--check` compares every generated PNG, the SpriteFrames resource, and the manifest without writing files. The source frames are retained in their original art record.
