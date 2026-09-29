# Wolfenstein 3-D for the NEC V30

Written by **StevenC** and **Claude** (Anthropic), September 2026: StevenC set
the goal -- id's Wolf3D, VGA and sound and everything, running as fast as it
can on a NEC V30 -- and Claude did the porting, the tools, the measurements
and the optimisation, on StevenC's V30 over
[DOS Bridge](https://github.com/jdredd87/DOSBridge).

The branch `v30-8086` is the work; `master` is id's source exactly as
released, and stays that way so every change can be diffed against it.

## The machine

NEC V30 (8086 pin-compatible, runs the 80186 instruction set), Intel 8087,
MS-DOS 6.22, 1 MB VBE VGA, a PicoMEM 2 providing 4 MB of EMS (PMEMMSC) and,
through XMSSC, XMS on top of that EMS. About 548 KB free conventional memory
when a game is launched over the bridge. Game data: registered WL6, 1.4,
in `C:\WOLF3D` on the V30.

## Why id's WOLF3D.EXE will not start on a V30

id's own startup code (`WOLFSRC/C0.ASM`) tests the flags register and prints
*"Sorry, this program requires a 286 or better."* on anything 8086-class.
But nothing the game executes needs a 286: everything is inside the 80186
set, which the V30 runs natively. The check now also asks the CPU what it
is -- `AAD` with base 11 answers 10 on a NEC part, and a shift of 32 is
masked to nothing on an 80186 -- and lets those through. A real Intel
8086/8088 is still refused, because it would crash on the 186 opcodes.

## Building

Borland C++ 3.1, as id used. Its `BCC` and `TLINK` are DPMI programs and
need a 286, so the compile runs on DOS Bridge's 486 (box `dx486`) and the
V30 only ever runs the result:

```
python w3dbuild.py bcpp        once: ship the Borland C++ subset to the 486
python w3dbuild.py all         build on the 486, deploy WOLF3DV.EXE to the V30
python w3dbuild.py listings WL_DR_A.ASM WL_DRAW.C ...   offset listings
```

`WOLFSRC/BUILD86.BAT` is the build itself (it also runs by hand on any 286+
with BC 3.1 at `C:\BCPP`). Flags are in `WOLFSRC/TURBOC.CFG`: medium model
as id had it, **`-1` (80186 instructions)** where id used `-2`, id's 8087
emulator (it drives the V30's 8087 when fitted), `-Fc` for id's communal
globals. The output is `C:\WOLF3D\WOLF3DV.EXE`; id's `WOLF3D.EXE` is not
touched.

## Measuring

Nothing in this project is changed on a guess; each optimisation is
profiled first and timed after.

| switch | what it does |
|---|---|
| `WOLF3DV TIMEDEMO` | id's four demos with no frame cap, timed off the BIOS tick, fps printed through DOS so the bridge captures it |
| `... QUICK` | demo 0, first 200 frames: the A/B benchmark, repeatable to a tick |
| `... PROFILE` | samples CS:IP on every timer interrupt (700 Hz) into `PROF.BIN`; `profmap.py` turns it into time per module, function and 16-byte bucket |
| `... CRC` | checksums the rendered view at frames 50/100/150/200 by reading all four VGA planes back: **every change must reproduce id's checksums exactly** |
| `NOEMS` / `NOXMS` | id's own switches: which memory the page manager may use |

`play` in the report is the time after each demo's first frame, which
carries the level-start fizzle.

Reference checksums (id's renderer, demo 0, QUICK):
`92AEBBA4 1B5D91C2 24B7E6FA 238BB608`.

Two things to know about the profiler: it takes 36 KB of the game's memory
for its histogram, which shrinks the page cache (42 -> 32 pages) and makes
the XMS configuration thrash; and it cannot see time spent inside interrupt
handlers (the music). Profile for *where*, time without it for *how much*.

## Results

QUICK timedemo (demo 0, 200 frames, view 240x120), BIOS ticks, lower is
better. Every row reproduces id's four checksums exactly.

| step | change | ticks | fps | vs start |
|---|---|---|---|---|
| 0 | id's code, 186 build (EMS+XMS) | 1519 | 2.39 | |
| 1 | `CalcHeight` in asm (was a C frame and two calls per ray); 16-bit texture shifts | 1435 | 2.53 | -5.5% |
| 2 | `ScaleShape` in asm (the sprite column walk) | 1359 | 2.67 | -10.5% |
| - | memory: `NOEMS` (XMS only) beats EMS: 1319 vs 1356 | 1319 | 2.76 | |
| 3 | page manager LRU scan in asm (was 6% of a frame when the cache was small) | 1313 | 2.77 | |
| 4 | V30 hardware `DIV` fast path in Borland's 32-bit divide (per visible object) | 1294 | 2.81 | -14.8% |
| 5 | FizzleFade's pixel loop in asm: level-start fizzle 6.2 s -> 3.8 s | 1250 | 2.91 | -17.7% |

Gameplay only (after the fizzle frame): 3.07 fps at step 5.

### Memory: use `NOEMS`

The page manager maps EMS pages into a 4-slot frame through INT 67h, and on
nearly every texture change it remaps. With XMS it copies a page once into
the 42-page cache in conventional memory and reads it directly -- and
XMSSC's copies go straight to the PicoMEM. So on this machine, XMS only is
about 3% faster. It depends on having enough conventional memory for the
cache: at 32 pages it thrashed and lost.

### What the V30 does and does not offer

The V30's own instructions (bit operations, `INS`/`EXT` bit fields, BCD
string ops, `ROL4`) are slower here than plain shifts and masks. What it
has over an 8086 that matters is **hardware effective-address calculation**
(complex addressing modes are nearly free) and a **fast multiplier and
divider** -- which is why step 4 replaces a 32-step shift-and-subtract loop
with `DIV`. The 8087 cannot help the frame rate: Wolf3D draws entirely in
fixed point by design.

## Verified tools

* `ldivmodel.py` -- instruction-exact model of step 4's divide, 1.2 million
  cases against exact division.
* `WOLFSRC/LDTEST.C` -- the real `H_LDIV.OBJ` against a reference with no
  divide: 80,473 pairs x 4 operations on the 486 and 16,473 on the V30,
  0 mismatches.

## Profile after step 4 (EMS+XMS, share of samples)

`AsmRefresh` 16% (the ray caster's tile-stepping loop), compiled wall
scalers 19%, `DrawScaleds` 8%, `FizzleFade` 7% (now fixed), `ScaleLine`
6%, `CalcHeight` 5%, `ThreeDRefresh` 4%, `ScalePost` 3%, `HitHorizWall`
3%, `VGAClearScreen` 2.5%, `SimpleScaleShape` 2%.

## Next

1. `AsmRefresh`'s inner loop: patch the per-ray steps in as immediates
   (id already patches its jump opcodes per ray), keep `xtile*64` in a
   register so the vertical loop loses its `SHL`.
2. `DrawScaleds` in asm -- careful: it also picks up bonus items
   (`GetBonus`) and marks actors active, so it is game logic, and the
   demos desync if its order changes. The checksums would show it.
3. The compiled scalers: swap the segments so the more frequent operation
   (the store, when scaling up) loses its segment prefix.
4. FizzleFade through the VGA latches: one register write per pixel
   instead of two.
5. `ThreeDRefresh`, `VGAClearScreen`, `HitHorizWall`/`HitVertWall`.
