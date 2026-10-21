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
3. **Live, with DOS machines -- 0 desyncs, 2026-10-21.**  The network on
   Winsock 1.1 (`src/w32net.c`), and the same headless build joined real
   games as a NETBOT, with the 486 and P3 on DOS 1.11, a Python server:

   | | steps | desyncs |
   |---|---|---|
   | the DOS machines first, Win32 joining 40 s in (replaying from step 0) | 4,000 | 0 |
   | Win32 first, the 486 joining 50 s in (asked of Win32, a snapshot is declined: the 486 replays from step 0) | 3,500 | 0 |

   A Win32 machine never gives a snapshot (it is its memory, which a DOS
   joiner cannot read) nor takes one (a PC replays an hour in seconds).  The
   server still asks it, four times, before the joiner replays: teaching the
   server to ask a DOS player instead is to do.
4. **The game, in a window -- 2026-10-21: `WOLF3DMW.EXE`.**  The picture
   (a new renderer in C, `src/w32draw.c`, drawn as id's draws: id's
   projection, texture columns and flips, doors, jambs, the moving pushwall,
   sprites with their eight rotations, the weapon), id's status bar, the
   network game's overlay (notices, chat, scores) -- all through id's own code
   where it is C -- into a 320x200 screen shown 4:3 in a window with GDI;
   the keys from the window's messages.  On a Windows 10 PC, live, with the
   486 and P3 on DOS 1.11: **3,000 steps, 0 desyncs, 17.4 pictures a second**
   (it is paced by the game's 17.5 steps).  Replaying T1 in the window at
   normal speed: every sum the same as DOS.  No menus: it starts straight
   into the network game.

   **Sound** (`src/w32snd.c`, `src/w32wave.c`): the digitized sounds out of
   the page file, the AdLib's effects and music on an OPL2 written here in C
   from what the chip is documented to do (two operators a channel, four
   waveforms, the chip's envelope rates, feedback), mixed at 22,050 Hz into
   `waveOut` by a thread -- id's priorities and a sound's place left and
   right; `NOAL`, `NOSB`, `NOMUSIC` as on DOS.  `W3DRAW=file` writes the mix
   to a file instead (raw 22,050 Hz 16-bit stereo), which is how it was
   checked: music all through a replay, the effects over it.

   `WOLF3DMW` alone joins the last server (WOLF3DM.CFG) or finds one on the
   network; `WOLF3DMW NET 192.168.1.10 NAME STEVE` as on DOS; `VIEW n` (4-20,
   20 the default: the whole width).  Beside the game's own `*.WL6` (and
   `VSWAPM.WL6`, for the players as BJ).  `WOLF3DMW.LOG` beside it has the
   game's report.  Windows Firewall asks the first time it opens the
   network; answer for your network's type.
5. **An hour, DOS and Windows in one game -- 2026-10-21, 02:27-03:27.**
   The Python server with a bot; the 486 and P3 on DOS 1.11; the windowed
   game on the Windows 10 PC (all NETBOT SHOW): **63,000 steps, 0 desyncs,
   no packet dropped**, every machine every step, 17.4 pictures a second on
   each (`stage/logs/mix1`).
6. **The boxes** are id's, drawn as on DOS: ESC's question in the big font,
   black on grey in an outlined panel (`Message`, WL_MENU.C), and every
   other box white in the blue frame of TILE8's eight tiles
   (`US_DrawWindow`).  The first build wrote ESC's question straight on to
   the picture in the small font, black -- hard to read (StevenC).
7. **The mouse**: a click in the window gives it to the game (the cursor
   hidden and kept there; a move turns, or steps up and down, as on DOS);
   F12 or leaving the window gives it back.  Left fires, **right opens
   doors**, middle strafes -- `RIGHTSTRAFE` for id's own (right strafes,
   middle opens); `NOMOUSEY`: the mouse only turns.  Under Remote Desktop
   each move is read from the last place, not the window's middle (Remote
   Desktop sends where the far mouse is: put back in the middle, the view
   spun), so the window's edge ends a turn there.  **A Win32 machine gives no
   snapshot**: its HELLO says so (FDh, where FFh is to play), and the Python
   server and MPSRV/MPSRVW never ask it -- a joiner takes a DOS machine's, or
   replays from step 0.
8. Next: a DOS 1.11 release with the Win32 game beside it; listening to the
   OPL2 against a real AdLib; menus (it goes straight into the network game).

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
| `src/w32net.c` | the network: WL_NET.C's calls on Winsock 1.1 UDP (`wsock32`, Windows 95 and later) |
| `src/w32gfx.c` | the game: the page file (VSWAP, all of it in memory), the graphics file (Huffman: VGADICT, VGAHEAD, VGAGRAPH), fonts, pictures, and id's VL_/VWB_/US_ drawing calls into one 320x200 screen |
| `src/w32draw.c` | the game: ThreeDRefresh -- walls, doors, the pushwall, sprites, the weapon -- then the network game's overlay |
| `src/w32win.c`, `src/w32in.c` | the game: the window (GDI's StretchDIBits), its keys and mouse as id's Keyboard[] and IN_ calls |
| `src/w32snd.c`, `src/w32wave.c` | the game: id's SD_ calls; an OPL2 in C, the digitized sounds, the mix into `waveOut` |
| `src/w32pal.c` | id's palette, from WOLFSRC/OBJ/GAMEPAL.OBJ (`tools/mkpal.py`) |
| `src/w32null.c` | the replay: no picture, no input |
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
* **`TimeCount` written, not added to.**  The game sets it back to 0 and
  counts on it climbing from there; written from the clock it never heard,
  and a replay at normal speed stalled for 60 s and gave up.

| `ref/` | |
|---|---|
| `*.MPR` | recordings (a server's `--record`: our protocol packets, none of id's data) |
| `*.SUM` | DOS 1.11's sum at every 50th step, the first 64 (what a release reports) |
| `*.ALL` | every sum to the end (the DOS `SUMDUMP` test build), what `gate.sh` checks |
