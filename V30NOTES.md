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
| `... MUSICLOG` | hash the music sequencer's first 1,000 writes with their ticks: two builds with one hash play the same music |
| `NOEMS` / `NOXMS` | id's switches: which memory the page manager may use |
| `EMS` | id's original EMS+XMS setup; since step 29 the default is XMS, with EMS only where there is no XMS |

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
| 14 | music ISR skips its full service when nothing is due | 1081 | 3.35 |
| 15 | compiled scalers store without a segment prefix (screen in DS, texture in ES) | 1062 | 3.41 |
| 16 | ray loop keeps `yintercept`'s low word in AX (no read-modify-write per step) | 1055 | 3.43 |
| 17 | FizzleFade through the VGA latches, `y` tested first -- fizzle 3.7 -> 3.2 s, play unchanged | 1055 | 3.43 |
| 18 | *(tried, reverted)* branchless fizzle step -- slower: see below | -- | -- |
| 19 | every communal word-aligned; `spotvis` carries a frame stamp, cleared every 255 frames | 1050 | 3.45 |
| 20 | *(tried, reverted)* skip clearing the rows last frame's walls all covered, then fill the gaps -- 2% slower: see below | -- | -- |
| 21 | `ScaleLine` keeps the screen segment in DX; id's per-ray multiply helpers inlined; hot loop tops `EVEN` | 1038 | 3.49 |
| 22 | `DrawScaleds`' actor loop in asm (`PlaceActors`) -- game logic: wakes actors, sets `FL_VISABLE`, same order | 1024 | 3.53 |
| 23 | `TransformTile` in asm: four `FixedByFrac`s and the long multiply inline, Borland's `LDIV@` kept for the divide | 1016 | 3.56 |
| 24 | `PlaceActors`/`PlaceStatics` laid out so an unseen object takes no jump; `vismark` an immediate | 1005 | 3.60 |
| 25 | music ISR counts down the ticks until the next event (`sqQuiet`), cleared by every C change to the sequencer | 1002 | 3.61 |
| 26 | `objtype` word-aligned (pad bytes after `flags` and `areanumber`) -- only 0.2%: game logic reads actors less than expected | 1000 | 3.62 |
| 27 | `CalcHeight`'s per-frame constants (`viewx`/`viewy`, `viewcos`/`viewsin`, `mindist`, `heightnumerator`) patched in as immediates by `AsmRefresh`; NEAR entry for the asm hit routines | 988 | 3.66 |
| 28 | `ScaleLine` and the glue that called it merged into one asm routine, `ScaleSpan`: the span stays in registers, one table lookup picks the one-byte case, the post loop tests at the bottom | 957 | 3.78 |
| 29 | XMS the default memory (what `NOEMS` bought, without the switch): no switch 957, `EMS` 1009, `NOXMS` 1012. `EMS` keeps id's EMS-first order, because XMSSC serves XMS out of EMS and an XMS-first start leaves EMS nothing | 957 | 3.78 |
| 30 | ray loop: `T = (xtile<<6)+ytile` in DX, so the vertical test is `xspot` against `T` and a vertical step moves `xspot` with one `ADC` (id rebuilt it with a shift of six); both loops test at the bottom; the quadrant's code patches rewritten only when a ray changes quadrant | 937 | 3.87 |
| 31 | *(tried, reverted)* `CalcHeight` remembering both products with their inputs -- 0.4% slower: see below | -- | -- |
| 32 | `ScalePost` as a NEAR asm routine for the asm hit routines (was a far call, a near call and a C frame per wall post) | -7.5 | |
| 33 | `TransformActor` in asm, NEAR from `PlaceActors` | -1 | |
| 34 | `CheckLine` (line of sight) in asm: the clamped long divide is one guarded `DIV` | -9 | |
| 35 | the actor loop in asm: an actor asleep outside the player's areas is skipped without a call | -14 | |
| - | steps 32-35 together, rebuilt without 31 | 905 | 4.00 |
| - | the `VGAClearScreen` fix (CH cleared; see the findings) -- the new baseline | 903 | 4.01 |
| 36 | `CalcHeight` for the ray loop's wall hits: a vertical wall's columns share `xintercept`, so `CalcHeightV` keeps `gxt` against its high word (`CalcHeightH` keeps `gyt`), each with its own patched immediates -- step 31's idea, narrowed to the product that repeats | 892 | 4.06 |
| 37 | per-ray setup specialised per quadrant: each block multiplies the positive tangent and adds or subtracts the product (id negated the tangent, tested the sign, negated back, multiplied, negated the product); the partial in a register; `xtile<<6` once for `xspot` and `T` | 879 | 4.12 |
| 38 | no `JUMPS`-expanded branches on the common paths: TASM made each out-of-range `jb`/`jle`/`ja`/`jge` a jump the other way over a `JMP`, so `ScaleShape`'s column walk took two jumps a column and `PlaceActors` one per unseen actor; short hops to a nearby `JMP` instead | 870 | 4.16 |
| 39 | no per-ray `xstep`/`ystep` stores: the door and pushwall paths read the values from the loop's own patch sites (`ystep`'s high word less `xtilestep<<6`, kept in `yadj`); id's two dead multiply helpers removed | 863 | 4.20 |
| 40 | a ray in the last ray's quadrant goes straight to its body: `cmp`/`cmp`/`jmp` with the range and target patched in on a change of quadrant (the target's rel16 computed at run time: TASM's label arithmetic across `JUMPS`' passes came out 6 bytes off); id's test chain for the rest | 856 | 4.23 |
| 41 | a byte less per tile step: `cmp [tilemap+si],bh` for id's `test ...,0FFh` (BH, xtile's high byte, is always 0); no screen ES loaded per ray (nothing reads it) | 853 | 4.25 |
| 42 | `LDIV`'s normalisation shifts a whole byte first: `nx`, the usual divisor, has a high word under 256, which cost the bit loop 9 to 15 turns (now at most 7); `LDTEST` 100,473 pairs on the 486 and 20,473 on the V30, 0 mismatches | 851 | 4.26 |
| 43 | the 700 Hz music interrupt's quiet tick, shorter: the effects counter counts down (`dec`/`jz`), `alTimeCount`'s high word carries only once in 65,536 ticks, and a quiet tick leaves inline with the common case (no BIOS chain) falling through; `MUSICLOG` hash unchanged (A92D) | 846 | 4.28 |
| 44 | *(tried, reverted)* the music timer interrupting only on ticks that need it -- PIT mode 2, each interval queued two ahead, quiet ticks counted in bulk, `MUSICLOG` still A92D: 49,365 interrupts became 10,961 and the speed did not move (847.5 vs 848.0 over four rounds). See below | -- | -- |
| 45 | the page manager's LRU search walks the 100 main-memory slots (an owner table kept by the four places that change residency) instead of all 663 pages, whenever nothing is in EMS; minimum over (lastHit, page), so the same page as id's; page-miss counts unchanged | 839 | 4.32 |
| 46 | `DrawVisList` sorts once -- a stable insertion sort by height -- where id selected the nearest object with a pass over the whole list per object drawn (the first minimum each time: the same order); a list holding a height id's loop could never pick (32000 up) is left to id's loop | 833 | 4.35 |
| 47 | the ray setup's per-frame values -- `viewx`/`viewy`, the partials, and xtile, xtile<<6, ytile and T for the quadrant -- patched in as immediates by the quadrant's patch block, which runs on each frame's first ray and on a change of quadrant | 815 | 4.44 |
| 48 | *(tried, dropped)* `ScaleSpan`'s per-shape values (the shape's segment, `leftpix`, `bufferofs`) as immediates patched by `ScaleShape` -- 832.0 against 832.3: those memory operands cost the V30 next to nothing there | -- | -- |
| 49 | `ScalePostA` keeps only SI (its callers, the hit routines, need nothing else back); `PlaceStatics` holds its bound in CX, reloaded after the C calls | 812 | 4.46 |
| 50 | `DoActor` in asm inside the actor loop, statement for statement, every field re-read after a think or action call -- 0.9% over the whole attract loop (19,964 -> 19,788 play ticks, 4.90 -> 4.95 fps); demo 0's first 200 frames, with few actors awake, do not show it | 812 | 4.46 |
| 51 | "same wall as the last column?" is one compare of a key -- tilehit, side and tile packed in one word by the ray loop, in registers it already holds; id's test was four compares against memory. The C door, pushwall and frame-start code invalidate it. 0.9% (812 -> 805) | 805 | 4.50 |
| 52 | the horizontal tile loop keeps xintercept's low word in BP instead of adding into memory every step: ytile is redundant there, since T - (xtile<<6) is ytile, so yspot is T + ((xinttile-xtile)<<6), a value a vertical step leaves unchanged. 0.3% (805.3 -> 803.0) | 803 | 4.51 |
| 53 | *(tried, dropped)* the walls cast first and drawn after the clear, so `VGAClearScreen` skips the band of rows every column's wall covers -- 3% slower (803.7 -> 828.7): recording each post and drawing it in a second loop costs more than the band saves | -- | -- |
| 54 | a one-pixel sprite span -- nearly every span of a sprite that is not close -- is drawn by `ScaleShape` itself, out of line, not through `ScaleSpan`: no call and return, no DX kept, no multi-byte test, the map mask straight from the pixel. 1.1% (804.7 -> 795.7) | 796 | 4.55 |
| 55 | a sprite under 64 pixels high is walked pixel by pixel, not source column by source column: under 64 every width in the scaler's table is 0 or 1, and pixel p is drawn by source column (64p+63)/h, which an exact integer DDA steps without dividing. Same pixels, same tests at the same points. 1.8% (797.0 -> 782.3) | 782 | 4.63 |
| 56 | per-ray trims in the ray loop: yintercept handed from the quadrant code to the ray setup on the stack, not through memory; no store of xtile, which every hit makes anyway; pixx carried from one ray to the next in a register, and midangle and viewwidth patched in as the frame's immediates. 0.9% (781.7 -> 774.7) | 775 | 4.68 |
| 57 | `PM_GetPage`'s common case -- the page resident in main memory -- in assembly: bounds, `mainPage`, `lastHit`, `MainMemPages[]`, and id's C for everything else, reached with the caller's frame untouched. 0.8% (774.7 -> 768.3) | 768 | 4.72 |
| 58 | `PlaceStatics`' scan unrolled by four: an unseen static -- nearly all of up to 400 -- costs three instructions and a quarter of the loop's. A seen one leaves for the same handler as before, which carries on from the next, so the order of `TransformTile` and `GetBonus` calls is unchanged. 0.1% (768.3 -> 767.3) | 767 | 4.72 |
| 59 | `DoActors` laid out so a skipped actor -- inactive, outside the player's areas: most of a level's -- costs one short jump back instead of two jumps, one of them TASM's JUMPS expansion. 0.1% over the whole attract loop (18,759 -> 18,742 play ticks); within the noise of the quick benchmark | 767 | 4.72 |
| 60 | `CalcHeightV` and `CalcHeightH` keep no registers: their only callers, the asm hit routines, need SI back and nothing else, so the multiply's sign moves from SI to the free BP and four pushes and pops go from every wall hit's height. 0.65% (767.0 -> 762.0) | 762 | 4.75 |
| 61 | the ray loop jumps into its hit routines, and they jump on to `nextpix` themselves: one JMP per ray where there were a CALL, a RET and a JMP. 0.2% (762.0 -> 760.7) | 761 | 4.76 |
| 62 | `VGAClearScreen` leaves out the band of rows the last frame's least wall covered -- 32 of 120 on average over the attract loop -- and a post whose wall is shorter this frame fills its own share of the band with the masks it drew the wall with, so the picture never depends on the prediction. Neutral on the quick benchmark (760.7 -> 760.3), 0.34% over the whole attract loop (18,805 -> 18,742 play ticks) | 760 | 4.77 |
| 63 | the path-walking AI in assembly -- `TryWalk`, `SelectPathDir`, `MoveObj` and `T_Path`, statement for statement, calling one another directly with no frames, and `speed*tics` in two MULs instead of Borland's long-multiply helper. 0.41% over the whole attract loop (18,742 -> 18,665 play ticks, 5.24 fps); the quick benchmark's 200 frames have few patrolling guards (760.7 -> 758.3) | **758** | **4.78** |
| 64 | *(tried, dropped)* `SightPlayer` and `CheckSight` in assembly, and `MoveDoors` walking a pointer: identical, but no faster -- 759.0 against 758.3 on the quick benchmark, 18,685 against 18,665 play ticks over the whole attract loop | -- | -- |
| 65 | *(tried, dropped)* `PlaceActors` rejecting an actor outside the box the frame's rays reached (four compares a ray keep it): identical, and 1% slower (766.7 against 759.0) -- the box usually holds most of the level's actors, so the ray loop pays and little is saved | -- | -- |

Like for like with step 0 (`TIMEDEMO QUICK`, EMS+XMS, no preload): 1519 ->
1183 ticks at step 19, **2.39 -> 3.07 fps, 28% faster**. The whole attract
loop (`TIMEDEMO PRELOAD NOEMS`, all four demos, 5,386 frames) ran at 3.88 fps
after step 19 and **4.05 fps after step 24**; demo 0 alone went from 4,575
ticks (2.75 fps) at the start to **3,328 (3.78 fps), 1.37x**.

Steps 32-35 were measured as a chain that still carried step 31, each against
the one before, so the table gives their differences; the rebuilt tree was then
measured against both.

**Every build is now checked against id's own renderer over all four demos.**
`TIMEDEMO CRC` folds every 50th frame of the whole attract loop -- 5,386
frames, 105 checkpoints -- into two numbers, one for the 3-D view and one for
the whole screen (border and status bar too), and they must equal those of a
build of id's renderer and game logic with only TIMEDEMO's instruments added
(`refsrc.py` makes that tree): **view `0707C966`, screen `F2A10CEB`**. CRC
switches sound effects off, which makes a full run deterministic, so it runs on
the 486 in two minutes (`ab.py --full`) and gives the V30's numbers. Steps
1-36 all pass. Before this (see the findings below) only demo 0's first 200
frames had been compared with id's picture; the frame counts staying
691/1899/1140/1656 proves nothing -- a demo's length is its recorded input,
whatever the game does with it.

## Findings worth keeping

**The weapon covers less of the view than it looks.** Decoded from `VSWAP.WL6` and placed as `SimpleScaleShape` places it (scale 60, the 120-high scaler, at the 240x120 view): the ready poses cover 1-6% of the view, the chain gun's firing frames about 11%, all of it in the lower half. Skipping the floor and wall pixels under it would save perhaps 0.3-0.5% for a row cut-off table per wall scaler; not yet worth it. (`stage/weapcover.py`.)

**The ceiling and floor fill can be trimmed after all -- by predicting, not deferring.** Step 53's deferred walls were exact and slower. Step 62 skips the band the *last* frame's least wall covered, and a post whose wall is shorter than that band fills its own share of it (`BandFix`, with the map masks it drew the wall with), so the picture never depends on the prediction being right -- only the speed does. Measured on the V30: the whole fill is 31.6 ticks of the 200-frame benchmark (a build with no clear at all), the band averages 11.5 rows there and 32 of 120 over the whole attract loop, and the posts needing a fill write about 7 byte-rows a frame. What it took to make it pay: the first version tracked the frame's least wall with a taken jump on every post and cost as much as the band saved; with the rare update out of line it is neutral on the benchmark and 0.34% over the whole loop, less than the 1.1% the fill's share promised.

**The ceiling and floor fill cannot be trimmed by deferring the walls.** A wall post always draws its whole texture column, and the scaler for scale *i* covers exactly rows `viewheight/2-i` to `viewheight/2+i-1` (scaler 0 is scaler 1; from `stepbytwo` up every scaler covers the view). So the rows within the least scale of a frame are wall in every column, and `VGAClearScreen`'s fill there (4.2% of the whole loop) is always overwritten. Step 53 recorded each post during the cast, cleared around the band, and then drew the posts -- identical to id's over the whole loop, and 3% slower on the V30. Every post was handled twice, and the band is set by the frame's smallest wall, which is usually a distant one. A padded build ruled out the buffer's memory: it cost a page of cache (44 -> 43) and about ten more XMS page-ins per 200 frames, which measured as nothing. The sources are in `stage/step53/`.

**The benchmark's view size is fixed at 240x120 now.** TIMEDEMO used whatever `CONFIG.WL6` held, and a window enlarged in play (size 16, 256x128) turned the next A/B into a comparison of a bigger view against a reference made at the smaller one -- the checksums no longer matched and the ticks were 5% higher, which read as a fault in the step being measured. TIMEDEMO now sets size 15 for the run unless `MYVIEW` is given, and exits without writing the config, so the player's own setting is untouched.

**Borland's global optimiser (`-O2`): only where there is no inline assembly.** `TURBOC.CFG` has id's `-O`, which in Borland C++ 3.1 is jump optimisation only. `-O2` for the whole program built a binary 4 KB smaller that did not run -- it printed nothing and left the 486 unstable enough that the next job hung it (a power cycle). Its register allocation does not respect what id's inline `asm` blocks assume. Confined with `#pragma option -O2` to the four game-logic files that have no inline assembly (`WL_STATE.C`, `WL_ACT1.C`, `WL_ACT2.C`, `WL_AGENT.C`), it is identical to id's over the whole attract loop -- every demo still plays out move for move -- and 1.6 KB smaller. But over the whole attract loop on the V30 it measured 19,801 -> 19,782 play ticks, 0.1%: noise. Borland's C was already close for this code, so the pragmas were not kept -- a known-buggy optimiser for nothing measurable.

**Self-modifying code and the 486's prefetch queue.** The V30 prefetches 6 bytes, a 486 32, and a 486 does not notice a store into bytes it has already fetched: only a taken jump (or an interrupt) flushes them. Step 40 patched its fast quadrant entry at the start of every frame about 25 bytes before executing it, with no jump between. Harmless while the skipped patch block held only per-quadrant state; when step 47 put per-frame values there, the whole-loop CRC on the 486 differed -- deterministically for a given binary, and not at all once a diagnostic moved the code or its timing (a heisenbug: whether the stale CMP ran depended on where a timer interrupt fell). The V30 run of the same binary matched id's. The fix is a taken jump after the patch. **Rule for this code: a patched instruction must never be reached by falling through from the store within 32 bytes** -- every site was audited against it, and the whole-loop CRC runs on the 486 precisely because it would catch another.

**What music costs, measured -- and what it does not.** `NOMUSIC` plays demo 0 about 3.4% faster (819 against 848 play ticks). Step 44 cut the timer interrupts 4.5-fold with no gain at all, so a quiet 700 Hz tick is next to free on this machine; the earlier estimate of ~100 us a tick was wrong. `OPLID` (id's 6+35 status reads a write, against the calibrated 2+9) costs 14.5 ticks: 30 extra reads at 4.02 us each put the music at ~140 OPL writes a second, far more than the 22 assumed at step 13, each costing 13 port accesses (~52 us). That accounts for roughly a fifth of music's cost; the rest is the full service on event and effects ticks and, it seems, the PicoMEM itself, whose AdLib is emulated in software on the card.

**Two faults the view checksums could not see, found 2026-09-29.**

1. *A regression of mine, from step 19, spotted by StevenC on the V30's
   screen:* ceiling colour everywhere outside the view, no status bar.
   `VGAClearScreen` loads only CL for each row's `REP STOSW`; id's
   `ThreeDRefresh` cleared `spotvis` with a `REP STOSW` every frame just
   before, which left CX = 0, and step 19's frame stamp removed that clear.
   With a stray CH the ceiling fill ran across the whole page. The floor fill
   and the walls then repainted the view every frame, so every view checksum
   matched -- the checksum measured exactly the part that was right. Fixed by
   `xor ch,ch`, and the whole screen is now checksummed too. Timings between
   step 19 and the fix carried the overrun's cost whenever CH was not 0, so
   they are noisier than they look.
2. *With AdLib sound effects on (as `CONFIG.WL6` has them) a demo is not
   deterministic under an unpaced TIMEDEMO.* `UpdateFace` skips its `US_RndT`
   calls while the gatling pickup sound plays; a sound lasts real time, and a
   faster build fits more frames into it, so from that moment every build
   plays a slightly different game. Shown on the 486: one EXE run twice gave
   one number, four EXEs gave four. Every full run agreed on its first 400
   frames, which is why demo-0 checks never noticed. CRC now turns sound
   effects off; music never touches the game.

**`ScaleLine`'s `OUT`s cost nothing measurable.** Replacing all six with `NOP`s
(same size, wrong picture) timed identically, 988 against 989 play ticks.
The VGA card's ports are fast; the ~4 us `IN` measured for the OPL2 is the
PicoMEM's emulated port, not this bus. What the profile charged to
`ScaleLine` (10.3%, with the non-public `CallScaleLine` folded in) was its
per-span setup and per-post bookkeeping, which step 28 cut.

**Memory: XMS, the default since step 29 (`NOEMS` before).** With EMS the page manager remaps its 4-slot frame
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

**The music is proven identical, not just heard.** `TIMEDEMO MUSICLOG`
hashes the first 1,000 register writes the sequencer makes, each with its
value and the timer tick it happened on (from the song's start). id's
original interrupt code (built from before step 13, with the log added by
`musiclog.py`), step 14's fast path and step 25's countdown all give
**A92D**: the same music, note for note and tick for tick.

**Also checked by ear, as far as a capture stick can.** The HDMI capture carries
the AdLib: the same notes appear with the calibrated waits and with id's
(`OPLID`), none with `NOMUSIC`, and the broadband clicks in all three are the
capture path's own.

**Step 31: a cache that costs more than it saves.** A vertical wall's columns
share `xintercept`, so one of `CalcHeight`'s two products repeats from column
to column. Remembering *both* products with their inputs -- two compares and
four stores on every call, for one reuse -- measured 0.4% slower. Memory
writes are dear on this bus and a V30 `MUL` is not. Step 36 tries the narrow
version: the hit routine knows which product repeats.

**What the V30 does and does not offer.** Its own instructions (bit
operations, `INS`/`EXT`, BCD strings, `ROL4`) are slower here than shifts and
masks. What it has over an 8086 is hardware effective-address calculation --
which is why step 6 barely moved: memory operands were already cheap -- and a
fast multiplier and divider, which step 4 uses. The 8087 cannot help: Wolf3D
draws entirely in fixed point, and the one place it could stand in exactly --
a 32/32 divide, `FIDIV` then `FISTP` with the rounding set to chop, exact for
32-bit operands under a 64-bit mantissa -- costs more than the V30's own
divide path (8087 `FDIV` ~200 clocks, `FILD`/`FISTP` ~50 each, against a V30
`MUL` of ~22). Floating point anywhere else would stop the picture matching
id's to the pixel.

**Borland's C was better than expected more than once** (steps 11 and 12):
converting to assembly pays where the C keeps loop state in memory (steps 2,
7, 8), not where it is merely C.

**Data alignment matters on the V30, and Borland does not give it.** A word
at an odd address costs two bus cycles on its 16-bit bus. Each module's
`_DATA` and `_BSS` start even, but with `-Fc` every uninitialized global is a
communal, and TLINK packs all 40 KB of them with *no* alignment -- one
odd-sized communal shifts every one after it. Found the hard way: a one-byte
global added in step 19 put `actorat` (and all that followed) on odd
addresses and cost **3%**, with the pictures identical. id's own byte globals
had already left 113 communals odd, including `ScaleLine`'s. `aligncheck.py`
reads the map and lists them; after step 19 there are none. **Declare any new
global as a word, or initialize it.**

**Savegames belong to the EXE that wrote them.** They store actors raw,
including a near pointer to each actor's state, so a save only ever loaded
in the build that made it -- id's own releases were the same. `WOLF3D.EXE`
and `WOLF3DV.EXE` do not exchange saves, and a rebuild of `WOLF3DV.EXE`
that moves data may not load an older one.

**Lay loops out so the common case falls through.** Step 24 changed no
arithmetic at all -- only which way the branches go, so that an object
nobody can see (nearly all of them, every frame) runs straight through
its tests instead of jumping eight times -- and gained 1%.

**A taken jump is expensive, but so is fetching code.** The V30 flushes its
6-byte prefetch queue on every taken jump, which is why the fizzle's reject
path was slow. But replacing the sequence step's 50/50 `JNC` with a
branchless six-instruction `SBB`/`AND`/`XOR` (step 18) made it *slower*: on
a 16-bit bus the extra instruction bytes cost more than half a flushed queue.
Measure both ways.

**Not clearing what the walls will cover did not pay** (step 20). The
idea is sound -- walls are centred, so the rows every column's wall
covered last frame form one band the clear could skip, with any column
whose wall came out shorter filled in afterwards -- and it stayed
pixel-identical, the fill made sure of that. But the player is always
moving or turning, so the fills were frequent, and `VL_Bar` fills with
three register writes a row: 1072 play ticks against 1050. A margin on the
band and a faster column fill might break even; the evidence says the room
is thin.

**What is left of the music interrupt's cost: ~4%** (`NOMUSIC` 1007 vs 1050
play ticks). The fast path is ~450 clocks, 700 times a second: interrupt
entry and `IRET`, id's common prologue (DS through a CS override), four
memory counters, the end-of-interrupt `OUT` (~4 us here). A countdown of
"ticks until anything is due" could halve it, but id's C music routines write
the sequencer state with interrupts off and would have to invalidate it --
a glitch at a song's start if one were missed. Parked, not forgotten.

## Verified tools

* `ldivmodel.py` -- instruction-exact model of step 4's divide, 1.2 million
  cases against exact division; `WOLFSRC/LDTEST.C` -- the real `H_LDIV.OBJ`
  against a reference with no divide: 80,473 pairs on the 486, 16,473 on the
  V30, 0 mismatches.
* `WOLFSRC/OPLTIME.C` -- the cost of a port read on this machine.
* `profmap.py`, `lstat.py`, `gfxchunks.py` -- profile, listing and data tools.

## Where the time goes now (profile after step 55, whole attract loop, EMS+PRELOAD)

849,000 samples over the four demos.  The compiled scalers writing pixels
34%; the ray loop (`AsmRefresh`) 21%, most of it the vertical and
horizontal tile steps, which are at the floor of what the V30 can fetch;
`CalcHeight` 5.7% (two MULs and an IDIV a ray, what id's truncation
needs to stay exact); `ScaleShape` and `ScaleSpan` together 9.7% (the
weapon, drawn every frame, and close sprites); `VGAClearScreen` 4.3%;
`ScalePostA` 4.2% and the two hit routines 3.9%; `PlaceActors` 2.1%,
`DoActors` 1.8%, `PlaceStatics` 1.2%; game logic in C about 3%; the page
manager 2.8% (in EMS mode -- XMS, the default, spends less); the level-start
fizzle and fades about 1.5%.

Measured rather than read off the profile: the whole ceiling and floor fill
is 31.6 ticks of the 200-frame benchmark (4.1%), and an XMS page-in costs
about 2 ms.

## Next

What is left is spread thin; every candidate measured or estimated is worth
0.1-1%:

1. The game logic's C (`T_Path`, `SelectPathDir`, `TryWalk`, `T_Chase`,
   `SightPlayer`, `MoveObj`: 1.7% together) in assembly.
2. `ScaleSpan`'s per-call overhead for the weapon and close sprites (about
   3%): every register is in use, so only the call itself can go.
3. `PlaceActors`' nine spotvis tests per actor: a bounding box of the rays'
   hit tiles would reject most actors, but keeping it costs the ray loop
   about as much as it saves.
4. Long divides (`ny*scale/nx`, 0.4%): already normalised by steps 4 and 42.
