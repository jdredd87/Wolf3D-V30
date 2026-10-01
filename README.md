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
| speed | **5.32 fps** over all four demos, **5.38 in play** (was 4.05 before steps 27-76); demo 0 in full **2.75 -> 4.99 fps, 1.81x**; the 200-frame benchmark 4.87 fps in play |
| picture | identical to id's renderer over the whole attract loop -- all four demos, 5,386 frames, every 50th checksummed, the 3-D view and the whole screen (`ab.py --full`, on the 486) |
| music | identical to id's: the same register writes on the same ticks (`MUSICLOG`) |
| detail switches | optional, in any combination, none on by default: `LOWWALLS` casts one ray per two screen columns (walls in two-pixel columns), `LOWSPRITES` draws enemies and items in two-pixel columns, `LOWDETAIL` is both, and `FLATWALLS` draws every wall in one solid colour, each texture's average, kept apart from the floor and ceiling, with the artwork -- portraits, banners, signs, the walls secrets hide behind -- painted on a flat wall (`FLATART` makes the artwork solid too) (**5.98 fps over all four demos, 6.14 in play** on its own; 7.50 on the benchmark with `LOWDETAIL` too). `LOWVERT` halves the vertical resolution -- the VGA shows every other row, each twice as tall, and the 3D view is drawn on those rows only (**6.31 fps over all four demos, 6.39 in play** on its own; the status bar and border are drawn as ever and lose every other row). With all four, 8.15 on the benchmark. With `LOWDETAIL`, **7.56 fps over all four demos, 7.68 in play**; on the benchmark 6.95 (`LOWDETAIL`), 6.57 (`LOWWALLS`), 5.65 (`FLATWALLS`), 5.68 (`LOWVERT`) and 5.01 (`LOWSPRITES`) against 4.88. Not id's picture: the weapon and status bar stay full resolution, and with `LOWWALLS` a narrow tile far off can go unseen for a frame, so an enemy there may notice you a little later |
| optimisations | 84 steps so far -- see [V30NOTES.md](V30NOTES.md) |

## Running it

On the V30, in `C:\WOLF3D` beside the game data:

```
WOLF3DV
```

Optional switches trade picture for speed, in any combination: `LOWWALLS`, `LOWSPRITES`, `FLATWALLS`, `FLATART`, `LOWVERT`, or `LOWDETAIL` for the first two (`WOLF3DV LOWDETAIL` is about 40% faster) -- see Status. Without them the game draws exactly what id's does.

Or type `PLAY` for a menu of them: a key turns each switch on or off (`A` all, `N` none), `P` plays, `B` runs the 200-frame benchmark with them, `Q` quits, and quitting the game comes back to the menu. It remembers the last choice (`W3MENU.CFG`), and with no key for 30 seconds it quits by itself (`PLAY /T:60` changes that, `/T:0` waits for ever, `/PLAY` makes it start the game instead). The menu is `W3MENU.EXE` (`launcher/w3menu.pas`, built with FPC by `w3dbuild.py deploy`); it writes the game's command line into `W3RUN.BAT` and exits before the game starts, so it takes none of the memory the game's page cache could use.

**Memory: XMS is the default, and the fastest setup on this machine** (step
29). The page manager keeps textures in conventional memory and XMS (served
by XMSSC over the PicoMEM's EMS) instead of remapping EMS pages every frame:
3.78 fps against 3.59 for id's EMS+XMS. EMS is used only when there is no
XMS, or when `EMS` asks for id's original setup; id's `NOEMS` and `NOXMS`
still work. Everything else is the game as id made it.

For measuring, `WOLF3DV TIMEDEMO QUICK PRELOAD` plays demo 0's first 200
frames flat out and prints the frame rate; `CRC` adds checksums of the picture,
`PROFILE` a sampled profile. It always measures the 240x120 view (size 15), whatever
size the game was left at; `MYVIEW` uses yours instead. [V30NOTES.md](V30NOTES.md) explains them all.

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
