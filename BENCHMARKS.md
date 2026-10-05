# Benchmarks

Measured 2026-10-05 on the two machines on the bridge, StevenC & Claude.

| | the V30 | the 486 |
|---|---|---|
| CPU | NEC V30, 8086-class, with an 8087 | 486, 66 MHz (a DX2-class part) |
| board | PicoMEM 2: disk, network, EMS, AdLib | PicoMEM 1 |
| memory | 570 KB free, XMS served from EMS | 549 KB free, HIMEM |

`TIMEDEMO` plays id's own demos with the game's fixed tics, so the picture is
the same on any machine and only the time differs.  **fps in play** leaves
out the first frame (it carries the fizzle-in).  View 240 x 120 (size 15).

## Every option: demo 0, 200 frames (`TIMEDEMO QUICK PRELOAD`)

| program | switches | what it does | V30 fps | 486 fps |
|---|---|---|---|---|
| WOLF3DO | (none) | **id Software's own 1992 code**, rebuilt for the 8086 -- the base | 2.80 | 59.39 |
| WOLF3DV | (none) | id's game and picture, exactly | 5.02 | 82.34 |
| WOLF3DV | `LOWWALLS` | walls in 2-pixel columns | 6.67 | 95.34 |
| WOLF3DV | `LOWWALLS4` | walls in 4-pixel columns | 8.36 | 113.22 |
| WOLF3DV | `LOWSPRITES` | sprites in 2-pixel columns | 5.17 | 84.25 |
| WOLF3DV | `FLATWALLS` | walls one solid colour, artwork kept | 5.62 | 106.56 |
| WOLF3DV | `FLATART` | artwork solid too | 5.62 | 106.56 |
| WOLF3DV | `LOWVERT` | half the vertical resolution | 5.84 | 97.92 |
| WOLF3DV | `FARBLOBS` | far sprites as flat shapes | 4.96 | 82.34 |
| WOLF3DV | `FASTOPL` | AdLib with no waits | 5.04 | 84.25 |
| WOLF3DV | `LOWWALLS LOWSPRITES FLATWALLS LOWVERT FLATART FARBLOBS FASTOPL LOWWALLS4` | all eight of the above | 9.19 | 139.34 |
| WOLF3DV | `AUTOMAP` | the map (TAB) up | 7.13 | 113.22 |
| WOLF3DB | (none) | id's rays, far walls in less detail (the default) | 5.26 | 82.34 |
| WOLF3DB | `NOLOD` | id's rays, full detail -- id's picture exactly | 4.89 | 80.51 |
| WOLF3DB | `BSP` | the BSP tree, far walls in less detail | 4.45 | 77.08 |
| WOLF3DB | `BSP NOLOD` | the BSP tree, full detail | 4.27 | 73.94 |
| WOLF3DB | `AUTOMAP` | the map up | 7.24 | 113.22 |
| WOLF3DB | `BSP AUTOMAP` | the map up, the tree | 6.83 | 109.79 |
| WOLF3DB | `LOWWALLS LOWSPRITES FLATWALLS LOWVERT FLATART FARBLOBS FASTOPL LOWWALLS4` | all eight detail switches | 9.05 | 139.34 |

On the 486 a run is only 30-50 BIOS ticks, so its figures move by a few
percent from run to run; the V30's, at 500-800 ticks, are good to about one
tick.

## The whole attract loop: all four demos (`TIMEDEMO PRELOAD`)

**WOLF3DO**, id Software's own code:

| | frames | V30 fps in play | 486 fps in play |
|---|---|---|---|
| demo 0 | 691 | -- | 67.90 |
| demo 1 | 1899 | -- | 79.62 |
| demo 2 | 1140 | -- | 68.89 |
| demo 3 | 1656 | -- | 78.67 |
| **all four** | 5386 | -- | 75.20 |

**WOLF3DV**, the exact version:

| | frames | V30 fps in play | 486 fps in play |
|---|---|---|---|
| demo 0 | 691 | 5.29 | 92.37 |
| demo 1 | 1899 | 5.73 | 104.08 |
| demo 2 | 1140 | 5.39 | 93.83 |
| demo 3 | 1656 | 5.66 | 102.48 |
| **all four** | 5386 | 5.57 | 99.68 |

**WOLF3DB**, the default: id's rays, far walls coarser:

| | frames | V30 fps in play | 486 fps in play |
|---|---|---|---|
| demo 0 | 691 | 5.57 | 94.45 |
| demo 1 | 1899 | 6.22 | 109.35 |
| demo 2 | 1140 | 6.00 | 99.69 |
| demo 3 | 1656 | 6.46 | 110.77 |
| **all four** | 5386 | 6.15 | 105.47 |

WOLF3DO is id's own renderer and game code (id's WOLF3D.EXE needs a 286), built
by `refsrc.py` with the same timing harness: the speed everything here is
measured against.  It draws the same picture as WOLF3DV, checksum for checksum.

