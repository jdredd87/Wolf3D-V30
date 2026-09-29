# Wolf3D on the NEC V30 -- the lab notebook

Written by **StevenC** and **Claude** (Anthropic), September 2026. The front
page is [README.md](README.md); this is how the work was done and every number
it produced. Nothing here was changed on a guess: each optimisation was
profiled first, timed after, and checked to draw exactly id's picture.

## The machine

NEC V30 (8086 pin-compatible, runs the 80186 instruction set) at ~8 MHz, an
Intel 8087, MS-DOS 6.22, a 1 MB VBE VGA card, and a PicoMEM 2 providing 4 MB
of EMS (PMEMMSC) and, through XMSSC, XMS on top of that EMS. 557 KB free for a
program since the `CONFIG.SYS` change below. Registered WL6 1.4 data in
`C:\WOLF3D`.

## Why id's WOLF3D.EXE will not start on a V30

id's startup code (`WOLFSRC/C0.ASM`) tests the flags register and prints
*"Sorry, this program requires a 286 or better."* on anything 8086-class --
though nothing the game runs needs a 286: all of it is in the 80186 set. The
check now asks the CPU what it is (`AAD` base 11 answers 10 on a NEC part; a
shift of 32 is masked to nothing on an 80186) and lets those through. A real
Intel 8086/8088 is still refused: it would crash on the 186 opcodes.

## Building

Borland C++ 3.1 as id used. `BCC` and `TLINK` need a 286, so the build runs on
DOS Bridge's 486 (box `dx486`) and the V30 runs the result:

```
python w3dbuild.py bcpp        once: ship the Borland C++ subset to the 486
python w3dbuild.py all         build on the 486, deploy WOLF3DV.EXE to the V30
python w3dbuild.py listings WL_DR_A.ASM WL_DRAW.C ...   offset listings
```

`WOLFSRC/BUILD86.BAT` is the build itself. Flags (`WOLFSRC/TURBOC.CFG`):
medium model as id had it, **`-1` (80186)** where id used `-2`, id's 8087
emulator (it drives the V30's 8087), `-Fc` for id's communal globals.

## Measuring

| switch | what it does |
|---|---|
| `TIMEDEMO` | id's four demos with no frame cap, timed off the BIOS tick, printed through DOS |
| `... QUICK` | demo 0, first 200 frames: the A/B benchmark, repeatable to a tick or two |
| `... PRELOAD` | fill the page cache before each demo, as "Get Psyched" does before real play (id's demo playback skips it) |
| `... CRC` | checksum the rendered view at frames 50/100/150/200 by reading all four VGA planes back |
| `... PROFILE` | sample CS:IP on every timer interrupt into `PROF.BIN`; `profmap.py` maps it to modules, functions and 16-byte buckets |
| `... NOMUSIC` / `NOSOUND` / `OPLID` | measure what the AdLib costs; `OPLID` restores id's fixed OPL waits for A/B listening |
| `NOEMS` / `NOXMS` | id's switches: which memory the page manager may use |

The report also counts page-cache misses during play (EMS remaps, copies from
and to XMS, LRU evictions, disk reads), and gives a *play* figure that leaves
out each demo's first frame, which carries the level-start fizzle.

**The benchmark is `TIMEDEMO QUICK PRELOAD NOEMS`**, and the figure that
matters is *play* ticks. Every optimisation must reproduce id's checksums:
`92AEBBA4 1B5D91C2 24B7E6FA 238BB608`.

Profiler caveats, all learned the hard way: it takes 36 KB of the game's memory
(the page cache shrinks, so profile with EMS to keep that out of the picture);
it cannot see time inside interrupt handlers; and a symbol is only the
function if it is a public of the same segment -- the 8087 emulator's fix-up
constants (`FIARQQ`, `0000:xxxx`) and id's non-public helpers at the top of a
segment were each charged to the wrong function until `profmap.py` learned
that.

## Results

QUICK demo 0, 200 frames, view 240x120. Lower ticks are better. Every row is
pixel-identical to id's renderer.

### The first benchmark (EMS+XMS or NOEMS, no preload) -- steps 0-6

| step | change | ticks | fps |
|---|---|---|---|
| 0 | id's code, 186 build (EMS+XMS) | 1519 | 2.39 |
| 1 | `CalcHeight` in asm (it was a C frame and two calls per ray); 16-bit texture shifts | 1435 | 2.53 |
| 2 | `ScaleShape` in asm: the sprite column walk | 1359 | 2.67 |
| - | memory: `NOEMS` beats EMS, 1319 vs 1356 | 1319 | 2.76 |
| 3 | page manager's LRU scan in asm | 1313 | 2.77 |
| 4 | V30 hardware `DIV` fast path in Borland's 32-bit divide | 1294 | 2.81 |
| 5 | FizzleFade's pixel loop in asm: level start 6.2 s -> 3.8 s | 1250 | 2.91 |
| 6 | ray loop steps patched in per ray as immediates (only 0.3%) | 1246 | 2.92 |

### System settings -- `CONFIG.SYS`, at StevenC's instruction

ANSISC and CH375EXT out (variant `w3dA` in DOS Bridge's `projects/dostune`):
548 -> 557 KB free, page cache 41 -> 44 pages, evictions 57 -> 31, play ~0.6%
faster. `BUFFERS` 30 -> 20 gave one more page and nothing measurable, so it
stayed at 30 for the bridge's sake. The previous files are
`C:\CONFIG.W3B`/`C:\AUTOEXEC.W3B`, and `tune.py apply xms2c` rebuilds them
byte for byte.

### The benchmark from here: QUICK PRELOAD NOEMS, play ticks

| step | change | play ticks | play fps |
|---|---|---|---|
| - | starting point, after steps 1-6 and `w3dA` | 1161 | 3.12 |
| 7 | `DrawScaleds`' back-to-front sprite loop in asm (`DrawVisList`) | 1140 | 3.17 |
| 8 | `DrawScaleds`' static-object scan in asm (`PlaceStatics`) -- game logic, `GetBonus` order kept | 1125 | 3.22 |
| 9 | LRU scan tests residency first | 1121 | 3.23 |
| 10 | no `CalcHeight` for a wide-scale column (id computed it and threw it away) | 1109 | 3.26 |
| 11 | `HitVertWall`/`HitHorizWall` in asm, NEAR from the ray loop | 1105 | 3.27 |
| 12 | `SimpleScaleShape` (the weapon) in asm -- within noise | 1104 | 3.28 |
| 13 | `alOut` in asm, OPL2 waits calibrated in real time | 1099 | 3.29 |
| 14 | music ISR skips its full service when nothing is due | **1081** | **3.35** |

## Findings worth keeping

**Memory: use `NOEMS`.** With EMS the page manager remaps its 4-slot frame
through INT 67h nine times a frame, ~1.3 ms each on this card. With XMS it
copies a page into its conventional-memory cache once and reads it there; the
copies go straight to the PicoMEM. A smaller cache thrashes: at 32 pages
`PML_GiveLRUPage` was 6% of a frame.

**Sound costs what its interrupt costs, not what its writes cost.** An `IN`
takes ~4 us on this V30 whatever the port (`OPLTIME.C`), so id's OPL waits
came to 25 and 144 us where the chip needs 3.3 and 23 -- but music writes are
rare (~22 a second), so calibrating them bought 0.3%. `TIMEDEMO NOMUSIC`
showed where music's 5.8% really went: the 700 Hz timer interrupt, which took
its full path every tick at ~100 us. Step 14 recovered a third of it. Your
`CONFIG.WL6` has **sound effects off** (music on); with effects on, step 13
matters more.

**Checked by ear, as far as a capture stick can.** The HDMI capture carries
the AdLib: the same notes appear with the calibrated waits and with id's
(`OPLID`), none with `NOMUSIC`, and the broadband clicks in all three are the
capture path's own.

**What the V30 does and does not offer.** Its own instructions (bit
operations, `INS`/`EXT`, BCD strings, `ROL4`) are slower here than shifts and
masks. What it has over an 8086 is hardware effective-address calculation --
which is why step 6 barely moved: memory operands were already cheap -- and a
fast multiplier and divider, which step 4 uses. The 8087 cannot help: Wolf3D
draws entirely in fixed point.

**Borland's C was better than expected more than once** (steps 11 and 12):
converting to assembly pays where the C keeps loop state in memory (steps 2,
7, 8), not where it is merely C.

## Verified tools

* `ldivmodel.py` -- instruction-exact model of step 4's divide, 1.2 million
  cases against exact division; `WOLFSRC/LDTEST.C` -- the real `H_LDIV.OBJ`
  against a reference with no divide: 80,473 pairs on the 486, 16,473 on the
  V30, 0 mismatches.
* `WOLFSRC/OPLTIME.C` -- the cost of a port read on this machine.
* `profmap.py`, `lstat.py`, `gfxchunks.py` -- profile, listing and data tools.

## Where the time goes now (profile after step 11, EMS+PRELOAD)

Ray casting ~27% (`AsmRefresh` 18% -- mostly its tile-stepping loop --
id's per-ray multiply helpers 3.4%, `CalcHeight` 4.8%), pixels ~38% (compiled
wall and sprite scalers 24%, `ScaleLine` 7.9%, `ScalePost` 2.9%,
`VGAClearScreen` 2.8%), sprite bookkeeping ~6%, game logic ~4%, the fizzle
(once per level) and the music interrupt.

## Next

1. The compiled scalers (24%): swap the segments so the store, the more
   frequent operation on near walls, loses its prefix byte -- needs
   `ScalePost`, `ScaleLine` and the weapon changed together.
2. The ray loop: keep `xtile*64` in AX so the vertical loop loses its shift.
3. The music ISR's remaining cost: its fast path still enters and leaves
   through id's full prologue.
4. FizzleFade: skip off-screen steps faster, and copy through the VGA latches.
5. `VGAClearScreen` overdraw, `ScaleLine`'s per-post overhead.
