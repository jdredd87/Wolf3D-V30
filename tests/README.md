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
| `netmatrix.py KIND[@BOX] [STEPS]` | a network game of DOS and Windows machines on one server, one machine joining late: `python`, `mpsrv@p3` / `@dx486` / `@v30`, `mpsrvw`, `wl1` (the shareware), `wl1w` (it with WOLF3DW1), `soak`; Spear: `sod`, `sod30`, `sodsrv@BOX`, `sodw`, `sodfloors`.  `NETEXE` plays a test build instead, `NETEARLY`/`NETLATE` other machines, `V30EXTRA` (and the like) a machine's own switches |
| `winattract.py [MINUTES]` | WOLF3DW's attract loop left to run on .37: still running at the end, nothing in the crash log |
| `keys37.py` | keys held in the game's window on .37 (used by `winlocal.py`; `W3DPROC` names another program) |
| `demosum.py [wl6\|wl1\|sod]` | id's demos, the DOS game against the Windows one, the whole game state every 50 frames (WL_MP.C's `DemoSum`): a DOS test build with `DEMOSUM` on the 486, `TIMEDEMO DEMOSUM` on .37 -- every line the same |
| `putvariants.py`, `varsmoke.py` | the Windows shareware (WOLF3DW1) and Spear (SPEARW) onto .37 with their data, and a first look at each |
| `winend.py [e1..e6\|wl1\|sod]` | each episode's end on Windows: a TEST build (`build.py spend`, `sp1end`, `spsodend`: `WL_PLAY.C`'s `ENDTEST` wins the floor after 70 frames) started on the last floor by `TEDLEVEL`, then id's victory, end text and high scores (Spear: its end screens) -- a picture of each, to the exit |
| `oplrec.py`, `opltempo.py`, `oplpitch.py` | the title music recorded off the V30 (its PicoMEM's AdLib, through the capture card) and out of WOLF3DW (`W3DRAW`), then its tempo in each, and the pitch, the notes over time and the sound octave by octave against each other (`oplpitch.py` needs NumPy) |
| `doskeys.py [BOX...]` | the DOS game played by keys: `K9INJ.COM` (`k9inj.asm`) puts them through the keyboard controller (D2h) on the 486 and P3; a new game, a save, a load, a second save, Quit -- proved by the files.  `k9.py` makes its scripts |

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
| SPEARM (its Spear of Destiny, 1.11) | 338,190 | 8932F1DC | 486, P3, V30 `C:\SPEAR` |
| WOLF3DV (DOS single player) | 284,878 | BC518078 | 486, P3, V30 |
| WOLF3D8 (8086/8088) | 290,590 | 36FE102F | 486, P3 |
| WOLF3D1, WOLF3D18 (shareware) | 283,918 / 289,582 | 849E2006 / A07EFE5C | 486, P3, V30 `C:\WL1` |
| SPEARV, SPEAR8 (Spear of Destiny) | 283,998 / 289,854 | 0B4C9805 / 0A03A36B | 486, V30 `C:\SPEAR` |
| WOLF3DB (the bsp branch) | 306,686 | 8BC33670 | 486, P3, V30 |
| MPSRV (DOS server) | 114,196 | A365D834 | 486, P3, V30 `C:\MPSRV` |
| WOLF3DW (Windows, the whole game) | 588,092 | C74A75A5 | .37 `C:\W3DWIN` |
| WOLF3DW1 (Windows, the shareware) | 586,738 | 4F311A00 | .37 `C:\W3DWIN1` |
| SPEARW (Windows, Spear of Destiny) | 580,834 | AAC8302D | .37 `C:\W3DSOD` |
| WOLF3DMW (Windows, the network game) | 413,583 | 580628F7 | .37 `C:\W3DWIN` |
| MPSRVW (Windows server) | 93,184 | 623DF7CC | this PC (`mp/build/win`) |

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

TIMEDEMO plays the game logic and the renderer through id's four demos;
the menus, saves and keyboard play are below (`doskeys.py`).

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
| Python | this PC | the shareware, with Windows | 486, P3, WOLF3DW1; V30 late | PASS, 0 desyncs |

Every machine in every game: all 4,000 steps, "no desync", ended by the
server.

**The soak** (`netmatrix.py soak 63000`, 01:08-02:08): MPSRVW on this PC,
deathmatch, the next floor every 10 minutes; the 486, P3 and WOLF3DW in
widescreen from the start, the V30 at step 1,968 -- **63,000 steps in
3,599.94 s, every machine to the last, no desync, 0 at the server**; floors
1 to 6 in .37's pictures, the kills, the respawns and the scores on its
widescreen.

### Windows, left running (`winattract.py 30`)

WOLF3DW's attract loop for 30 minutes on .37 -- the title, the credits, the
scores and id's demos, round and round (floors 38 and 44 among them): still
running at the end, nothing in the crash log.

### The Windows game against DOS, frame for frame (`demosum.py`)

id's four demos played by a DOS test build (`DEMOSUM`) on the 486 and by
the Windows build on .37 at the same time, the whole game state summed every
50 frames -- every actor (the player among them: place, angle, hit points,
state, flags), every pickup, every door, and health, ammo, keys, weapon,
score, lives, kills, treasure and secrets:

| | DOS | Windows | |
|---|---|---|---|
| `wl6` | the 486's `C:\WOLF3D` | WOLF3DW | **105 of 105 the same** |
| `wl1` (the shareware) | `C:\WL1` | WOLF3DW1 | **71 of 71 the same** |
| `sod` (Spear) | `C:\SPEAR` | SPEARW | **59 of 59 the same** |

It found three faults in the Windows game, all fixed (6a7322a):
`PlayDemo` read the demo's length as a 4-byte unsigned where DOS reads 2;
Watcom's `char` is unsigned where Borland's is signed (`-j` now); and
`TransformTile` took a tile too close to see where id's does not.  The
first sum to differ named the frame, and `DEMOFRAMES map from to` the field.

### Windows: the shareware and Spear (`putvariants.py`, `varsmoke.py`)

`python win32/build.py sp1` (WOLF3DW1, `UPLOAD`) and `spsod` (SPEARW,
`SODVER.H` with `GOODTIMES`), each into its own `obj/` -- the same sources
as WOLF3DW and the DOS builds.  On .37 with their data: the signon, the
title (Spear's own), the attract loop's demo; still running after it,
nothing in their logs.  The demos above are their play
test.  On the network, `netmatrix.py wl1w` -- the 486, P3 and
WOLF3DW1 on the Python server, the V30 joining at step 1,847: **4,000
steps, no desync, 0 at the server, PASS**.

### DOS, played by keys (`doskeys.py`)

Wolfenstein reads the keyboard itself (its INT 9 reads port 60h), past
KINJ and KNET.  `K9INJ.COM` (`k9inj.asm`, 6,914 bytes, most of them
room for a 6,000-byte script) goes under it: from the BIOS timer tick it hands each
scancode to the AT keyboard controller with command D2h, which raises IRQ 1
as if the key had been pressed -- the game's own INT 9 reads it.  Every
wait on the controller is bounded.  The V30 is an XT and has no such
controller.

In a scratch folder (`C:\W3TEST`, the game's data copied -- nobody's config
or saves touched), WOLF3DV, two runs:

1. the signon, the title, the menu, a new game, god mode (`GOOBERS`), to
   the cell door, two shots, F2: a save named K9TEST; F10, Y
2. a new game, god mode, F3: K9TEST loaded; F2: a save named LOADED; F10, Y

| | K9TEST | LOADED | CONFIG.WL6 | |
|---|---|---|---|---|
| 486 | 'k9test': E1L1, 3 lives, 100, ammo 6 | 'loaded': the same | written by Quit | **PASS** |
| P3 | 'k9test': the same | 'loaded': the same | written by Quit | **PASS** |

Run twice on each machine, all four PASS.  Both saves pulled back and read: names, floor, score, lives and ammo --
6, two shots off a new game's 8, so a fresh game cannot pass for the load.
God mode because the guards the shots wake are in the save, and they open
the cell door after the load.

### Spear of Destiny on the network (`netmatrix.py sod*`, 2026-10-22)

`SPEARM` on the 486, P3 and the V30 (`C:\SPEAR`), `SPEARW NET` on .37;
build `01110053`, Spear's own.

| game | server | steps | machines | |
|---|---|---|---|---|
| co-op, enemies | Python | 4,000 | 486, P3, SPEARW; V30 late | the V30 would not start: id's Spear memory check (fixed, below); the other three PASS, 0 desyncs |
| the same | Python | 4,000 | the same | the V30 froze at step 3,454; the other three to the end, 0 desyncs |
| the same, the V30 from the start | Python | 4,000 | V30, 486, SPEARW; P3 late | **PASS**, all four |
| deathmatch, a bot | MPSRV on P3 | 4,000 | 486, SPEARW; V30 late | **PASS**, all three |
| co-op, enemies | Python | 8,000 | 486, P3, SPEARW; V30 late | the 486 stopped at step 831; the other three to the end, 0 desyncs |
| the same, the watchdog build (`huntbot.py --spear`) | Python | 20,000 | the same | the V30 froze at step 4,594 -- its screen: in the packet driver's send, the tick stopped |
| **Wolfenstein** (`WOLF3DM`), the control | Python | 20,000 | the same, Wolfenstein | **PASS**, all four |
| co-op, enemies | Python | 20,000 | the same | the V30 froze at step 7,570; the other three to the end |
| the same, the V30 with `NOSB` | Python | 20,000 | the same | **PASS**, all four, 0 desyncs |
| the same, the V30 with `NOEMS` | Python | 20,000 | P3, SPEARW; V30 late | the V30 froze at step 3,359 |
| the same, the V30 with 14,848 bytes more memory (its `CONFIG.SYS`, 2026-10-23; put back after) | Python | 20,000 | 486, P3, SPEARW; V30 late | the V30 froze at step 5,921: not memory |
| floor order, the console (`sodfloors`) -- map 17, next; map 18, next; map 20, next | Python | 10,000 | 486, P3, SPEARW; V30 late (`NOSB`) | **PASS**, all four: the Angel's floor with the gold key, floor 19, floor 5, the Angel again, floor 1 -- in .37's pictures |
| team deathmatch (`sodw`) | MPSRVW | 4,000 | 486, P3, SPEARW; V30 late (`NOSB`) | **PASS**, all four |
| deathmatch, a bot (`sodsrv@v30`) | MPSRV on the V30 | 4,000 | 486, SPEARW; P3 late | **PASS**, all three |
| deathmatch, a bot (`sodsrv@dx486`) | MPSRV on the 486 | 4,000 | P3, SPEARW; V30 late (`NOSB`) | **PASS**, all three |

Every machine that stayed in played every step in agreement: no game in
this table had a desync.  **The V30 freezes in Spear while its PicoMEM
card's emulated Sound Blaster plays** -- 4 Spear games of 7 with it on, all three of
20,000 steps among them; none of the 4 with `NOSB`; none in the same
20,000 steps played as Wolfenstein; the card's WiFi
is on the same Pico, and the freeze was caught in a send with interrupts off
(the card's other freeze, its AdLib on the 09-27 firmware, is in
`PICOMEM-REPORT.md` in DOS Bridge).  Until the card is settled the V30 plays
networked Spear with `NOSB`.  The 486's one stop is its own: it hung twice
in eight hours of Wolfenstein on 2026-10-19.

### Windows: every episode's end (`winend.py`, 2026-10-23)

No test playing the game reaches an episode's end; the logic that leads
there is the demos' and the gate's, frame for frame the same as DOS.  So a
TEST build (never shipped: `ENDTEST` is defined by `build.py spend`,
`sp1end` and `spsodend` alone) wins the floor `TEDLEVEL` starts on after 70
frames, and id's own end runs from there -- each seen on .37, each program
leaving by itself with nothing in its crash log:

| | |
|---|---|
| E1-E6, WOLF3DW (floors 8, 18 ... 58) | "YOU WIN!" with the time and ratios over the status bar; the episode's own end text, every page (E3's Hitler, E6's "YOU DID IT!"); the high scores |
| the shareware, WOLF3DW1 (floor 8) | the same, and its "MORE WOLFENSTEIN" page -- call Apogee; the scores by level, as id's shareware has them |
| Spear, SPEARW (the Angel's floor, 20) | "YOU WIN!", the Allied forces' text, the president's picture, BJ through the wall, the Spear of Destiny, id and FormGen, the beta testers, the flames, THE END; the high scores |

### Windows' OPL2 against the V30's AdLib (`oplrec.py` ...; 2026-10-23)

NAZI_NOR, the title music, off the V30 (`WOLF3DV NOWAIT`; its PicoMEM 2's
emulated AdLib, through the capture card) and out of WOLF3DW (`W3DRAW`, the
mix as a file):

| | |
|---|---|
| tempo | its phrase 3.475 s on the V30, 3.478 s on Windows: the same, within 0.1% |
| pitch | 11 of the 12 strongest notes within 3.5 cents, -0.6 cents on average |
| the notes over time | each 100 ms's pitch classes 0.968 alike (0.609 with the two 1.7 s apart) |
| the sound, octave by octave | within about 2 dB up to 4 kHz; above it Windows 3-5 dB brighter -- the V30's is through the card's audio out and the capture card's in |

The V30's AdLib is the PicoMEM's emulation, not a Yamaha chip -- the 486's
and P3's real OPL3s have no capture card -- and this is one song.

## Not covered

- The V30 played by keys: an XT keyboard has no controller to take D2h.

