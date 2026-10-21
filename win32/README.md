# WOLF3DM for Win32 -- the network game on Windows 95 and later

Written by **StevenC** and **Claude** (Anthropic), from 2026-10-21.

The goal: a native Windows build of the network game that plays in the same
game as the DOS machines.  Lockstep means every machine must compute exactly
the same game from the same inputs, so the port is proven, not assumed.

## Where it stands

1. **A checksum any platform can compute** -- done (DOS 1.11, `MPVER`
   0x0111, not released yet).  The sum read each actor's state by its 16-bit
   *address*; it reads what the state *is* now (`StateSum`, `WOLFSRC/WL_MP.C`).
2. **The gate -- PASSED, 2026-10-21.**  The game's logic built for Win32 with
   no picture, sound or input (`W3DREP.EXE`), replaying eight recordings:
   **all 515 sums identical to DOS 1.11's, to the last step of every one**
   (`gate.sh`):

   | recording | what | steps | sums |
   |---|---|---|---|
   | T1, T2, T3 | deathmatch | 2,550 | 51 each |
   | T4 | deathmatch | 3,000 | 60 |
   | T5 | team deathmatch, bots | 6,000 | 120 |
   | T6 | capture the flag | 4,000 | 80 |
   | C1 | co-op with enemies, every player dying | 4,500 | 90 |
   | PUSH0 | a pushwall, its tile, a door | 600 | 12 |

   And the DOS release build is **byte-identical** with every change below in
   (`C39ED932`): all of it is `#ifdef W32`, a typedef that is `unsigned` on
   DOS, or the `SUMDUMP` test build's.
3. Next: the Windows layer -- GDI for the picture, `waveOut` and an OPL
   emulator for sound, Winsock 1.1 for the network -- all of it there since
   Windows 95, so one EXE runs from 95 to 11.  Then a game with DOS and
   Windows machines on one server.

## How it is built

Open Watcom 2.0 (the 2026-10-01 build, unpacked into `C:\WATCOM`): the one
whose Win32 programs still run on Windows 9x.  `python win32/build.py`.
`WOLFSRC` is shared with the DOS build and compiled as it is, through:

| | |
|---|---|
| `src/w32comp.h` | forced into every file: `far`, `near`, `huge` and `_seg` mean nothing; Borland's `_argc`, `_fmemcpy`, `_dos_open` and the rest; `printf` through `w32fmt.c` |
| `src/w32logic.c` | id's own C (the master branch) for what the V30 keeps in assembly -- `TryWalk`, `MoveObj`, `CheckLine`, `SelectPathDir`, `T_Path` -- with step 98's change to `CheckLine` (a moving pushwall is solid), as `refsrc.py` takes them |
| `src/w32tab.c` | the sine and tangent tables **as the DOS game computes them**: `tools/TABLES.C`, id's `BuildTables` built by Borland C++ on the 486, run on the 486 and the V30 (identical), printed into `tools/TABLES.OUT` |
| `src/w32ca.c` | the maps (MAPHEAD, GAMEMAPS: Carmack and RLEW, read 16 bits at a time), memory from `malloc`, the DOS file calls |
| `src/w32stub.c` | the picture, sound, input and network as nothing; `FixedByFrac`, id's random table, the context swap (`MPSwapIn/Out`), `AutomapPickup` |
| `src/w32fmt.c` | `printf` and friends without Borland's `%Fs` far-pointer sizes |
| `src/w32main.c` | a 70 Hz `TimeCount` thread, the tables `InitGame` builds, then the game's own `MPNetArgs` and `MPNetGame` |

`W3DREP REPLAY FILE.MPR FAST` in a folder with the game's `*.WL6` prints the
same report as `WOLF3DM REPLAY`; `W3DSUMS=1` prints each 50th step's sum as
it is made, and `SUMDUMP n` the whole state of the 50 steps to n, one line a
thing -- the same as the DOS `SUMDUMP` test build (`#define SUMDUMP` in a copy
of `WOLFSRC`), so two builds that disagree can be diffed to the actor.

## What the gate found

Every one of these let the replay run and gave a sum that differed, or
crashed it -- and none could be seen without the DOS sums to hold it to:

* **The sum's 16-bit halves.**  `((unsigned far *)&mpsum)[1] = hi` is bytes
  2-3 on DOS; with a 32-bit `unsigned` it was bytes 4-7 -- `mpcur`, the
  variable after `mpsum`, so the next context swap went 2,050 players out.
* **16-bit random numbers.**  A deathmatch start is drawn with `n = n*25173 +
  13849` in an `unsigned`: wrapping at 65536 on DOS, not here.  `word16`
  (`unsigned` on DOS, `unsigned short` on Win32) for it, the face's and
  NETBOT's.
* **`StateSum` too**: its sum of a state's numbers wraps at 65536 on DOS.
* **`farmapylookup`**, the map's row offsets, filled by `InitGame` -- which
  the replay does not run.  Every plane-0 read was row 0.
* **`AutomapPickup` is game logic**: GetBonus for the items a player stands
  on, every step.  Its name made it look like drawing, and it was stubbed:
  the first item picked up, at step 2101, was the first sum that differed.
* **`%Fs`**: to Open Watcom's 32-bit `printf` an F size is a 48-bit pointer,
  so the first kill's notice ran zeros up the stack.
* **`_argc`**: Watcom puts an underscore before data names, so defining one
  replaced the runtime's own `__argc`, and `main` was given 0.

| `ref/` | |
|---|---|
| `*.MPR` | recordings (a server's `--record`: our protocol packets, none of id's data) |
| `*.SUM` | DOS 1.11's sum at every 50th step, the first 64 (what a release reports) |
| `*.ALL` | every sum to the end (the DOS `SUMDUMP` test build), what `gate.sh` checks |
