# Wolf3D-V30

**Wolfenstein 3-D, from id Software's source, made to run -- and run as fast
as it can -- on a NEC V30.** VGA, AdLib music, sound, the whole game: nothing
removed, nothing simplified, every frame the same picture id's code draws.

Written by **StevenC** and **Claude** (Anthropic), 2026. StevenC set the goal
and runs the hardware; Claude did the porting, the tools, the measurements and
the optimisation, over [DOS Bridge](https://github.com/jdredd87/DOSBridge),
which lets a Windows PC build and run programs on a real DOS machine as if it
were a test suite.

## Goals

1. **Run on the V30.** id's `WOLF3D.EXE` refuses to start on it -- its startup
   code demands a 286 -- although the game only needs the 80186 instruction
   set, which the V30 has. *Done.*
2. **Keep everything.** VGA, AdLib, the menus, save games, the demos. An
   optimisation that changes what you see or hear is not an optimisation.
3. **As fast as the V30 allows.** Measure, find where the time goes, move it
   to hand-written 8086/80186 assembly or remove it -- one change at a time,
   each proven to draw exactly id's picture and each timed.

## Status

| | |
|---|---|
| runs on the V30 | yes -- `WOLF3DV.EXE`, alongside the registered 1.4 WL6 data |
| speed | **3.49 fps** in play (QUICK PRELOAD NOEMS); like for like with the start, 2.39 -> 3.07 fps, 28% faster; all four demos 3.88 fps |
| picture | identical to id's renderer at every checked frame |
| optimisations | 21 steps so far -- see [V30NOTES.md](V30NOTES.md) |

## Running it

On the V30, in `C:\WOLF3D` beside the game data:

```
WOLF3DV NOEMS
```

`NOEMS` is id's own switch and the fastest memory setup on this machine: the
page manager then keeps textures in conventional memory and XMS (served by
XMSSC over the PicoMEM's EMS) instead of remapping EMS pages every frame.
Everything else is the game as id made it.

For measuring, `WOLF3DV TIMEDEMO QUICK PRELOAD NOEMS` plays demo 0's first 200
frames flat out and prints the frame rate; `CRC` adds checksums of the picture,
`PROFILE` a sampled profile. [V30NOTES.md](V30NOTES.md) explains them all.

## Building

Borland C++ 3.1 and TASM 3.1, as id used. The compiler needs a 286, so it runs
on a 486 on the same DOS Bridge and the V30 only runs the result:

```
python w3dbuild.py bcpp      once: ship the Borland C++ subset to the 486
python w3dbuild.py all       build there, deploy WOLF3DV.EXE to the V30
```

## This repository

| | |
|---|---|
| `v30-8086` | the work (default branch) |
| `master` | id's source exactly as released, for diffing |
| `upstream` remote | https://github.com/id-Software/wolf3d |

The source is id Software's, under the licence in
[WOLFSRC/README/LICENSE.DOC](WOLFSRC/README/LICENSE.DOC); the game data is not
included and never will be.
