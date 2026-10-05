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
| speed | **5.51 fps** over all four demos, **5.57 in play** (was 4.05 before steps 27-76); demo 0 in full **2.75 -> 5.17 fps, 1.88x**; the 200-frame benchmark 5.03 fps in play.  On the 486 at 66 MHz, 99.7 fps in play over all four demos.  The BSP version's default (`WOLF3DB`: id's rays, far walls in less detail) 6.15 on the V30, 105.5 on the 486; every option on both machines in [BENCHMARKS.md](BENCHMARKS.md) (2026-10-05) |
| picture | identical to id's renderer over the whole attract loop -- all four demos, 5,386 frames, every 50th checksummed, the 3-D view and the whole screen (`ab.py --full`, on the 486) -- and over 240 generated demos on all sixty maps (`gendemo.py`, `allmaps.py`: TIMEDEMO GEN, against `refsrc.py`'s build of id's renderer) |
| music | identical to id's: the same register writes on the same ticks (`MUSICLOG`) |
| detail switches | optional, in any combination, none on by default: `LOWWALLS` casts one ray per two screen columns (walls in two-pixel columns), `LOWSPRITES` draws enemies and items in two-pixel columns, `LOWDETAIL` is both, and `FLATWALLS` draws every wall in one solid colour, each texture's average, kept apart from the floor and ceiling, with the artwork -- portraits, banners, signs, the walls secrets hide behind -- painted on a flat wall (`FLATART` makes the artwork solid too) (**6.01 fps over all four demos, 6.17 in play** on its own; 7.40 on the benchmark with `LOWDETAIL` too). `FARBLOBS` (step 93) draws distant sprites as flat shapes -- 11% on a 486, nothing on the V30. `LOWVERT` halves the vertical resolution -- the VGA shows every other row, each twice as tall, and the 3D view is drawn on those rows only (**6.41 fps over all four demos, 6.49 in play** on its own; the status bar and border are drawn as ever and lose every other row). With all four, 8.05 on the benchmark. With `LOWDETAIL`, **7.79 fps over all four demos, 7.91 in play**; on the benchmark 7.13 (`LOWDETAIL`), 6.69 (`LOWWALLS`), 5.65 (`FLATWALLS`), 5.81 (`LOWVERT`) and 5.16 (`LOWSPRITES`) against 5.03. Not id's picture: the weapon and status bar stay full resolution, and with `LOWWALLS` a narrow tile far off can go unseen for a frame, so an enemy there may notice you a little later |
| optimisations | 98 steps so far, and two bigger ideas measured and set aside -- coherent rays (step 85, 27% slower) and a BSP, the SNES port's way (step 86, [bsp/](bsp/): 40-77% of the walk's time on the V30, but the walk decides which enemies are visible, which is game logic, so in the default mode it cannot go) -- see [V30NOTES.md](V30NOTES.md) |

## Running it

On the V30, in `C:\WOLF3D` beside the game data:

```
WOLF3DV
```

Optional switches trade picture for speed, in any combination: `LOWWALLS`, `LOWSPRITES`, `FLATWALLS`, `FLATART`, `LOWVERT`, or `LOWDETAIL` for the first two (`WOLF3DV LOWDETAIL` is about 40% faster) -- see Status. `FARBLOBS` draws distant enemies and items (under 16 pixels high; `FARBLOBS n` sets the height) as flat shapes, each opaque run in the colour of its middle pixel: 11% faster on a 486 (69 -> 76 fps in play over the attract loop), but not on the V30, where a distant sprite is already cheap to draw -- it is for faster machines. `FASTOPL` writes the AdLib's registers with no waits between them: an emulated chip such as the PicoMEM's needs none, and the music is the same (the same 1,000 register writes on the same ticks, `MUSICLOG`), 0.75% faster on the V30 -- but a real OPL2 chip needs its waits, so it is off by default. Without them the game draws exactly what id's does.

**TAB shows the map** (2026-10-05, StevenC's idea): a top-down map of what has been explored -- the rooms you have entered and everything the view has seen, walls, doors in their keys' colours, items, the enemies you have a line of sight to, and you, with the way you face.  The game goes on under it: move, turn and fire as ever.  It is faster than the 3D view (7.1 fps on the V30's benchmark, against 5.0), and it never touches a demo, so the game is still id's exactly.  `AUTOMAP` starts with it on, demos included, for showing it.  The Pause key freezes the game with the map left in full view (id's PAUSED sign is not drawn over it); any key goes on.  In both versions.

`VIEW n` sets the window, id's own Change View sizes 4 to 19 (16n x 8n pixels; the game's default is 15, 240x120) -- full detail and id's picture, only less of it, and it combines with the switches. On the V30's benchmark: size 19 (304x152) 3.95 fps, 17 4.42, **15 4.99**, 13 5.69, 11 6.53, 9 7.75. It is saved with the game's config, as id's menu saves it.

Or type `PLAY` for a menu of them: a key turns each switch on or off (`A` all, `N` none), `+` and `-` pick the window size (`0` leaves it to the game), `P` plays, `B` runs the 200-frame benchmark with them, `Q` quits, and quitting the game comes back to the menu. It remembers the last choice (`W3MENU.CFG`), and with no key for 30 seconds it quits by itself (`PLAY /T:60` changes that, `/T:0` waits for ever, `/PLAY` makes it start the game instead). The menu is `W3MENU.EXE` (`launcher/w3menu.pas`, built with FPC by `w3dbuild.py deploy`); it writes the game's command line into `W3RUN.BAT` and exits before the game starts, so it takes none of the memory the game's page cache could use.

`SHOWCASE` is a demo reel for recording (2026-10-05): pick `V` (WOLF3DV), `B` (WOLF3DB, far walls in less detail), `T` (WOLF3DB with the BSP tree) or `A` for all three in a row; then two questions, each answered for you after 15 seconds -- whether to start with id's code (Y) and whether to show the map too (N; the map's runs come last in each reel).  With Y it starts with **id Software's own 1992 code** (`WOLF3DO.EXE`: id's renderer and game code, rebuilt for the 8086 by `refsrc.py` -- id's own EXE needs a 286 -- with the same timing harness, and the same picture as WOLF3DV checksum for checksum), then every mode of the version: each a title screen saying what it shows and with which switches (8 seconds), three minutes of the game's demos with them (`TIMEDEMO PRELOAD SECS 180`, so a faster mode gets further; one minute, until 2026-10-05, left demo 0 near its start on a V30), and its speed report; at the end every run's speed together.  On the V30: id's code 2.81 fps, WOLF3DV 4.87, everything on 10.07, the map 7.46 -- `A` runs 29 segments, about an hour and 35 minutes (32 and an hour and 45 with the map); `V` alone about 40 minutes.  `S` skips a wait, `Q` quits.  `launcher/mkshow.py` writes the batch files; [BENCHMARKS.md](BENCHMARKS.md) has every option on both machines.

**Memory: XMS served out of EMS, the fastest setup on this machine** (step
29). An 8086-class PC has no memory above 1 MB, so it has no XMS of its own;
what the V30 has is the PicoMEM card's 4 MB of EMS. Two drivers StevenC and
Claude wrote for it turn that into XMS:

| | |
|---|---|
| [PMEMMSC](https://github.com/jdredd87/CH375USBTools/tree/main/PicoMEM/emm) | the PicoMEM's EMS driver, rebuilt: page mapping 45% faster, five EMS bugs fixed, loaded low (`CH375USBTools`, `PicoMEM/emm`) |
| [XMSSC](https://github.com/jdredd87/DOSBridge/tree/main/server/extras/xmssc) | an XMS 3.0 driver that hands out that EMS as XMS; on a PicoMEM it drives the card's page registers itself -- small moves 22% faster than the EMS driver's own move function (`DOSBridge`, an optional extra) |

Why XMS over EMS beats the EMS itself for this game: with EMS, id's page
manager maps textures into the 64 KB page frame and remaps its four slots
through INT 67h about nine times a frame, some 1.3 ms each on this card.
With XMS it copies a 4 KB page into its own cache in conventional memory once
-- XMSSC moving it straight off the PicoMEM -- and reads it there for as long
as it stays cached, so a texture used frame after frame costs nothing after
the first copy. The benchmark at step 29: 3.78 fps against 3.59 for id's
EMS-first setup. EMS is used only when there is no XMS, or when `EMS` asks
for id's original order; id's `NOEMS` and `NOXMS` still work. On the V30,
`CONFIG.SYS` loads `PMEMMSC.SYS /n` and then `XMSSC.SYS`. Everything else
is the game as id made it.

For measuring, `WOLF3DV TIMEDEMO QUICK PRELOAD` plays demo 0's first 200
frames flat out and prints the frame rate; `CRC` adds checksums of the picture,
`PROFILE` a sampled profile. It always measures the 240x120 view (size 15), whatever
size the game was left at; `VIEW n` measures that size, `MYVIEW` the one you left it at. [V30NOTES.md](V30NOTES.md) explains them all.

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

`release/` is the playable package: `mkrelease.py` zips `WOLF3DV.EXE`, the menu, the demo reel, `release/README.TXT` and id's `LICENSE.DOC` into `release/W3DV30.ZIP` (not committed) -- no game data.

`bsp/` is step 86's proof of concept, a program apart from the game: `mkbsp.py` and `mktables.py` make its data from your own `GAMEMAPS.WL6` and `MAPHEAD.WL6`, and `bsptest.pas` builds with FPC as `starter/` does in DOS Bridge (`fpc -Tmsdos -Pi8086 -WmLarge -FEbuild -FUbuild bsptest.pas`, with the bridge's `starter` on the unit path for `VidFix`); run it in a directory holding `TABLES.DAT` and the four `BSPnn.DAT`.

The source is id Software's, under the licence in
[WOLFSRC/README/LICENSE.DOC](WOLFSRC/README/LICENSE.DOC); the game data is not
included and never will be.
