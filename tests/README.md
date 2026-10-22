# tests -- every build, every machine, every server

Written by **StevenC** and **Claude** (Anthropic), 2026-10-22.

StevenC: "do an effort to make sure all versions now match everywhere. Then
run tests on all the systems. DOS local play, Windows local Play, and DOS and
Windows Network play. And make sure all our servers work. DOS server, Windows
Server, Python Server" -- and "swap server so each of the 3 dos machines runs
as a server".  These scripts are that run, kept so it can be run again.  They
drive the machines through DOS Bridge (`C:\dosbridgeDEV`) and the Windows PC
(.37) through its agent; output goes to `stage/tests/` (git-ignored).

| script | what |
|---|---|
| `deployall.py BOX...` | every DOS build onto every machine that has it: each program present in `C:\WOLF3D`, `C:\WL1`, `C:\SPEAR`, `C:\MPSRV` replaced by its new build (the old kept as `.PRV`), read back by CRC-32 on the machine |
| `doslocal.py [BOX...]` | DOS local play: each new build plays id's attract loop with `TIMEDEMO CRC` -- against id's own renderer's checksums, or the build the machine had (QUICK on the V30) |
| `winlocal.py` | Windows local play on .37, start to quit: signon, title loop, a demo, the menu, a new game, a door, a save (F2), a floor's end and its tally, the next floor, a load (F3), widescreen and back (F11), Quit (F10, Y) -- a screenshot each |
| `netmatrix.py KIND[@BOX] [STEPS]` | a network game of DOS and Windows machines on one server, one machine joining late: `python`, `mpsrv@p3` / `@dx486` / `@v30`, `mpsrvw`, `wl1` (the shareware), `soak` |
| `keys37.py` | keys held in the game's window on .37 (used by `winlocal.py`) |

The builds come from three trees: this one (the network game and the
Windows builds), the `v30-8086` branch (the DOS single-player family) and the
`bsp` branch (WOLF3DB) -- as worktrees at `C:\wolf3d-v30` and
`C:\wolf3d-bsp` for `deployall.py` and `doslocal.py`.

## 2026-10-22: the run

### The builds, and where they are

| build | bytes | CRC-32 | on |
|---|---|---|---|
| WOLF3DM (DOS network game, 1.11) | 335,854 | C39ED932 | 486, P3, V30 `C:\WOLF3D` |
| WOLF3DM1 (its shareware, 1.11) | 334,574 | 5949C066 | 486, P3, V30 `C:\WL1` |
| WOLF3DV (DOS single player) | 284,878 | BC518078 | 486, P3, V30 |
| WOLF3D8 (8086/8088) | 290,590 | 36FE102F | 486, P3 |
| WOLF3D1, WOLF3D18 (shareware) | 283,918 / 289,582 | 849E2006 / A07EFE5C | 486, P3, V30 `C:\WL1` |
| SPEARV, SPEAR8 (Spear of Destiny) | 283,998 / 289,854 | 0B4C9805 / 0A03A36B | 486, V30 `C:\SPEAR` |
| WOLF3DB (the bsp branch) | 306,686 | 8BC33670 | 486, P3, V30 |
| MPSRV (DOS server) | 113,224 | 8C8EC9F1 | 486, P3, V30 `C:\MPSRV` |
| WOLF3DW (Windows, the whole game) | 582,459 | B0F76F19 | .37 `C:\W3DWIN` |
| WOLF3DMW (Windows, the network game) | 407,537 | 6C8ACA67 | .37 `C:\W3DWIN` |
| MPSRVW (Windows server) | 92,672 | DA741190 | this PC (`mp/build/win`) |

All 27 DOS files read back on their machines with the right CRC.  Two fixes
found on the network branch went into the single-player and bsp builds
first (`v30-8086` 8df95b4): id's `Quit` recursing when out of memory, and
`MM_GetPtr` keeping a block handle when it fails.

### DOS local play (`doslocal.py`)

| machine | build | against | |
|---|---|---|---|
| 486 | WOLF3D8 | id's renderer (view 0707C966, screen F2A10CEB) | identical |
| 486 | WOLF3DM 1.11 | id's renderer | identical |
| 486 | WOLF3DV (`ab.py --full`) | id's renderer | identical |
| P3 | WOLF3DV | id's renderer | identical |
| P3 | WOLF3D1, WOLF3D18, WOLF3DM1 | the builds it had (shareware) | identical |
| V30 | WOLF3DV, SPEARV, SPEAR8 (QUICK) | the builds it had | identical |
| 486 | WOLF3DB | the build it had | identical |

What cannot be driven from here: the DOS games' menus, saves and keyboard
play -- Wolfenstein reads the keyboard itself (INT 9), past KINJ and KNET.
TIMEDEMO plays the game logic and the renderer through id's four demos.

### Windows local play (`winlocal.py`)

Every stage as it should be: the signon with its memory bars, PG-13, the
title, a demo, the menu, a new game on E1L1, the door, a save, "Floor 1
Completed", Floor 2, the save loaded, widescreen on and off, the quit
question and Quit; CONFIGW.WL6, SAVEGAW0.WL6 and W32VIEW.CFG written; no
crash in the log.

### Network play (`netmatrix.py`, 4,000 steps each, one machine joining late)

| server | where | rules | players | |
|---|---|---|---|---|
| Python | this PC | co-op, enemies | 486, P3, WOLF3DW; V30 late | PASS, 0 desyncs |
| MPSRV | P3 | deathmatch, a bot | 486, WOLF3DMW; V30 late | PASS |
| MPSRVW | this PC | team deathmatch | 486, P3, WOLF3DW; V30 late | PASS |
| MPSRV | 486 | deathmatch, a bot | P3, WOLF3DMW; V30 late | PASS |
| MPSRV | V30 | deathmatch, a bot | 486, WOLF3DMW; P3 late | PASS |
| Python | this PC | the shareware (WOLF3DM1) | 486, P3; V30 late | PASS |

Every machine in every game: all 4,000 steps, "no desync", ended by the
server.

## Not covered

- A Windows build of the shareware or of Spear: the Windows builds are the
  registered game's (`*.WL6`) only.
- The DOS games' interactive play (above).
