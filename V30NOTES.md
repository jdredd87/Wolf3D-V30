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
| 63 | the path-walking AI in assembly -- `TryWalk`, `SelectPathDir`, `MoveObj` and `T_Path`, statement for statement, calling one another directly with no frames, and `speed*tics` in two MULs instead of Borland's long-multiply helper. 0.41% over the whole attract loop (18,742 -> 18,665 play ticks, 5.24 fps); the quick benchmark's 200 frames have few patrolling guards (760.7 -> 758.3) | 758 | 4.78 |
| 64 | *(tried, dropped)* `SightPlayer` and `CheckSight` in assembly, and `MoveDoors` walking a pointer: identical, but no faster -- 759.0 against 758.3 on the quick benchmark, 18,685 against 18,665 play ticks over the whole attract loop | -- | -- |
| 65 | *(tried, dropped)* `PlaceActors` rejecting an actor outside the box the frame's rays reached (four compares a ray keep it): identical, and 1% slower (766.7 against 759.0) -- the box usually holds most of the level's actors, so the ray loop pays and little is saved | -- | -- |
| 66 | `SimpleScaleShape` -- the weapon and, in the demos, the DEMO sign, every frame -- draws a single-byte span itself, out of line: no call, and neither BP (the C frame pointer, not read again) nor, in the left half, DX kept. About 0.1% (759.7 -> 759.0), at the edge of the noise; 1777 -> 1775 on the 486 | 759 | 4.77 |
| 67 | the height calculation inline where a wall hit starts a new texture column -- the commonest way a post begins -- in both hit routines: no CALL or RET, the copy's immediates patched with the originals', and the branches around it laid out so none is a JUMPS expansion. 0.6% (759.3 -> 754.7); the 486 got 0.6% slower, a layout effect the V30 does not share | 755 | 4.80 |
| 68 | `ScalePostA` inline at the new-column paths too, its two rare branches (a new least wall; a post shorter than the band, which calls the routine) out of line; the horizontal copy's height tests its cache first so its miss block is a short jump back. 0.45% (754.7 -> 751.3) | 751 | 4.82 |
| 69 | `nextpix` sits directly before the next ray's setup, the frame's exit a short jump back: a ray ends with one taken jump where it had two. 0.2% (751.3 -> 749.7) | 750 | 4.83 |
| 70 | the horizontal hit block falls into `HitHorizWallA`, now placed right after it (its door test takes a short hop placed before the block); only one hit routine can go there, since the tile loops' branches to both hit blocks must stay short. 0.27% (749.7 -> 747.7) | 748 | 4.85 |
| 71 | the hit routines' per-quadrant test (`xtilestep`, `ytilestep` against -1, in memory, every ray) is one 2-byte instruction the quadrant code patches: EBh, a short jump, or 3Ch, CMP AL,imm8, which swallows the displacement and falls through. 0.2% (748.7 -> 747.0) | 747 | 4.85 |
| 72 | *(tried, dropped)* the height and the post draw inline on the new-wall paths too, as steps 67-68 did for new columns: identical, and slower (746.0 -> 747.7) -- new walls are too rare to pay for 400 more bytes of code in the hit routines | -- | -- |
| 73 | *(tried, dropped)* step 55's pixel loops with their per-sprite constants as patched immediates instead of memory operands: no gain (745.7 -> 746.7) -- step 48's finding again, a memory operand costs the V30 next to nothing | -- | -- |
| 74 | *(tried, dropped)* the ray loop's hot jump targets EVEN-aligned (three quadrant bodies, `initvars`, `notvertdoor` and the new-column paths were at odd addresses): 746.7 -> 746.0, inside the noise, and the 486 slower | -- | -- |
| 75 | a wall hit's intercepts and tiles stay in registers and are stored only where a post starts (the new-column and new-wall paths): a ray that only widens the current post -- the common case -- stores none of them. 0.54% (747.3 -> 743.3) | 743 | 4.87 |
| 76 | `tilehit` stored only where it is read: the door paths store it on entry, and the new-wall path takes it from the wall key it has just saved (`lastkey>>7` is `tilehit` exactly) -- one store fewer on every ray. 743.7 -> 743.0, at the edge of the noise | 743 | 4.88 |
| 77 | *(tried, dropped)* compiled blits for the weapon and the DEMO sign (drawn every frame): generated code writing each screen byte once per colour under a map mask of its planes -- half the screen writes of SimpleScaleShape, identical over the whole loop, and no faster (742.7 -> 744.7): the 18 KB of code cost the page cache 7 pages (87 -> 134 XMS page-ins over 200 frames), and the drawing it replaced was cheaper than it looked | -- | -- |
| 78 | *(tried, dropped)* `PlaceActors` reading its spotvis neighbours two at a time (three word loads and register compares for six of the nine byte compares): identical, and flat (743.0 -> 743.3) | -- | -- |
| 79 | LOWDETAIL, an optional switch: one ray per two screen columns, walls in two-pixel columns, sprites and weapon at full resolution -- 7.43 fps in play over the whole attract loop (5.38 without), 6.57 on the benchmark. Not id's picture, and a narrow distant tile can go unseen for a frame; without the switch the whole loop is id's exactly, for one NOP a ray (742.0 -> 743.7) | 744 | 4.87 |
| 80 | LOWSPRITES, an optional switch: enemies and items in two-pixel columns, each double column recording the x it covered so a neighbouring span can never leave a gap, and drawn double only when its partner is visible too. LOWWALLS is step 79's switch renamed; LOWDETAIL is both -- 522 ticks on the benchmark (551 at step 79), 7.68 fps in play over the whole loop; LOWSPRITES alone 723. The default mode is id's exactly and runs what it ran before plus an ADD AX,0 a sprite: the first call patches the routine for the switches (743.0 -> 743.7) | 744 | 4.87 |
| 81 | FLATWALLS, an optional switch: every wall one solid colour, the palette entry nearest its texture's average. A post records its columns' colour and half height; FlatRender fills a byte -- four columns -- at a time, the rows all four cover in one write through all four planes. Wall pages are never loaded. 743 -> 633.5 on the benchmark (5.72 fps), 6.47 fps in play over the whole loop; 482.5 with LOWDETAIL too (7.50 fps). The default mode is id's exactly and runs none of it (744.3 -> 745.0, noise) | 745 | 4.86 |
| 82 | LOWVERT, an optional switch: the CRTC shows every other row of the page, each four scan lines tall (offset 80 words, maximum scan line 3), and the 3D view is drawn on those rows only -- the compiled scalers skip their odd rows, so walls, enemies, items and the weapon all follow, and come out half the size (5 more cache pages). 743 -> 637 on the benchmark (5.68 fps), 6.39 fps in play over the whole loop; 444.5 with LOWDETAIL and FLATWALLS (8.15 fps). The default mode is id's exactly (743.3 -> 743.3) | 743 | 4.87 |
| 83 | FLATWALLS, as StevenC asked after seeing step 81 on the V30: no wall the colour of the floor or ceiling -- the colours are matched again at each new ceiling, the nearest colour to the average or to a darker or lighter one that keeps 9 steps from both, and from the light twin -- and the decorated walls (a fixed list, chosen by eye from stage/walls.png) drawn with their texture. FLATWALLS 633.5 -> 640 on the benchmark. It cost the default mode a cache page (43 -> 42, 742.5 against 743 ticks): step 84 wins it back | 743 | 4.87 |
| 84 | FLATWALLS paints the artwork on a flat wall: where a decorated texture agrees with its plain twin pixel for pixel, it is the wall behind, painted the twin's flat colour when the page is handed out (sentinels say when it is done; a reloaded page is painted again). FLATART, a new switch, makes the artwork flat too. FLATWALLS' buffers and fill body moved out of the program into a block allocated only in that mode. 640 ticks on the benchmark (5.65 fps), 6.14 fps in play over the whole loop; the default mode is id's exactly, 743 ticks | 743 | 4.87 |
| 85 | *(tried, dropped)* coherent rays: a column whose every intercept provably lands in the same tile as the column before's (the least and most fraction of each intercept sequence, kept by four compares patched into the walk, against the shift at crossing 0 and at the hit) skips its walk and takes the ray before's hit plus the shift -- exact by construction, the way to get BSP's saving without losing id's spotvis. Measured: **27% slower** on the V30 (943 play ticks against 744), the 486 69.2 -> 59.4 fps. The follow test was 11% of a frame (two IMULs and some forty memory operations a column), keeping each hit 3%, each fresh start 2%, the four compares on every step the rest: the V30's walk was already as cheap as the bookkeeping that would skip it. A rare column at frame 100 was also not exact; not chased | -- | -- |
| 86 | *(tried, not built in)* a BSP, the way the SNES port drew Wolf, measured outside the game: `bsp/BSPTEST.EXE` renders the same 64 views of each demo floor with Wolf's grid walk and with a BSP of the floor's wall runs, in the same Pascal. On the V30 the BSP's visibility costs **40-77% of the walk's**, on the 486 50-100%, and they find the same wall in 99.7% of columns. Not in the game because in the default mode it cannot replace the walk: the walk marks spotvis, which decides which enemies are `FL_VISABLE` -- whether the player's shot can hit one and how hard it shoots back -- and only a ray-by-ray walk marks the same tiles, so a BSP there is work added, not saved. Behind a switch the most it could take is about half the ray loop's 21% of a frame, before doors, pushwalls and 10-37 KB a level are paid for. See "BSP, measured" | -- | -- |

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

**Every map, checked (2026-10-02).** The attract loop's four demos visit four of the sixty maps, so every step so far had been proven on those alone. `gendemo.py` now writes demos for all sixty from the game's own map data -- two a map from the map's own start and from random open tiles, structured random input (runs, turns, strafes, "use" every ninth frame, bursts of fire) -- and `TIMEDEMO GEN n` plays one with god mode on, so a demo is not cut short by dying; `allmaps.py` runs each on our build and on `refsrc.py`'s reference (id's renderer, which takes GEN from HEAD too) and compares the CRC checksums. `refsrc.py` had rotted since steps 63 and 79-84 and was repaired (id's `WL_ACT2.C`; the switches' variables defined, all off); the repaired reference still gives the attract loop's view `0707C966` and screen `F2A10CEB`. The first 120 demos found **one difference**, G54 (map 27 from its own start): two columns of one frame. Frame dumps from both builds, a post log of id's `ScalePost` and a hit log of both showed id's own bug -- its pushwall routines never set `lastside`, so when a frame begins with a moving pushwall in view, the first wall after it skips the pushwall's last post -- and ours showing an old frame where id shows the floor and ceiling, because step 62 no longer clears the band. Step 92 fixed it; all 120 now match, and a second set of 120 (600 frames, other random starts) runs against the same reference. The 486 runs a set in about 80 minutes.

**The window size, measured (step 88, 2026-10-02).** id's game already sells picture for speed without changing any of it: Change View, sizes 4 to 19, 16n x 8n pixels. `VIEW n` sets it at start-up -- W3MENU's `+` and `-` -- and TIMEDEMO keeps it instead of forcing 15, so each size can be measured; the word is compared in code, not as a string, because DGROUP has 14 bytes left (a literal took it 2 bytes past what a 4 KB stack allows). On the V30, demo 0's 200 frames, two rounds each within a tick:

| size | view | play ticks | fps |
|---|---|---|---|
| 19 | 304 x 152 | 917 | 3.95 |
| 17 | 272 x 136 | 819 | 4.42 |
| **15** | **240 x 120** | **726.5** | **4.99** |
| 13 | 208 x 104 | 636 | 5.69 |
| 11 | 176 x 88 | 554 | 6.53 |
| 9 | 144 x 72 | 467.5 | 7.75 |

Each step of 2 is 11-16%: the rays and posts scale with the width, the scalers' stores with the area, and a smaller window's scalers are smaller too. One step down, size 13, is about as fast as `FLATWALLS` or `LOWVERT` -- and is id's picture, pixel for pixel, with a wider border.

**The walls' 34% is the CPU's, not the VGA's (measured 2026-10-02) -- and that is what step 87 used.** The profile charged a third of a frame to the compiled scalers writing wall pixels, and the question it could not answer was whether that time is the V30 or the video card's wait states; if the card, full detail was finished. `stage/exp_ramw.py` settles it: two builds that both read the walls' segment from a variable and both allocate the same 16 KB (so the page cache is the same), one of them pointing every wall post -- `BandFix` too -- into that RAM block instead of the screen. The map-mask OUTs, the texture reads and every other write are unchanged. 746.7 against 716.0 play ticks, three rounds each, every round within 2 ticks: **the VGA's share of the wall writes is 4.1% of a frame.** So about 30 of the 34 points are the scalers' own instructions -- 4 bytes for each texel's load, 4 for each pixel's store, and on the V30's 16-bit bus every fetched word is a bus cycle like the store's own. Every byte taken out of a scaler is the lever. Step 87 took a load out of every pair of texels a tall wall draws (2.1%). The stores are what is left, one per screen pixel, and no shorter encoding reaches rows 80 bytes apart (an 8-bit displacement covers rows 0 and 1). With the experiment build the game plays with no walls on the screen -- StevenC saw it on the capture -- which is what it is for, and it is never a game build.

**BSP, measured (step 86, 2026-10-01).** StevenC asked for a BSP in the full game, the way the SNES port drew Wolf, and for coherent rays first so that the two could be compared; coherent rays are step 85, 27% slower. `bsp/` is the proof of concept, measured outside the game so that the question is the algorithm's and not the integration's. `mkbsp.py` reads the four demo floors out of `GAMEMAPS.WL6` (id's Carmack and RLEW compression), leaves the doors open -- a static tree has no place for them -- and merges every wall face that borders an open cell into runs along its grid line, then builds the BSP offline, as the SNES port did, splitting on the grid line that scores best on balance and splits (|low - high| + 3 x splits). `mktables.py` makes the projection, 240 columns. `BSPTEST.EXE` renders 64 random views of each floor both ways, in the same Pascal with the same three assembler helpers (IMUL, IDIV and Wolf's FixedByFrac), and counts the columns where the two disagree. The walk is Wolf's: x and y crossings alternately, a tile test and a 32-bit add each. The BSP goes front to back, skips a subtree whose box is wholly behind the near plane, projects each run that faces the camera (four IMULs and an IDIV for each end), claims its columns in a coverage mask, stops when all 240 are claimed, and then pays one multiply a column for the intercept on the wall, which the walk gets for nothing.

| floor | runs | nodes | V30 walk | V30 BSP | | 486 walk | 486 BSP | | runs projected | nodes visited | columns that differ |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 38 | 1,114 | 890 | 105.1 ms | 76.3 ms | 72% | 4.7 ms | 4.2 ms | 90% | 39 | 67 | 44 of 15,360 |
| 44 | 227 | 188 | 108.5 | 43.7 | 40% | 5.1 | 2.5 | 50% | 13 | 25 | 22 |
| 57 | 1,354 | 1,103 | 94.8 | 73.8 | 77% | 4.2 | 4.2 | 100% | 37 | 67 | 46 |
| 32 | 591 | 502 | 126.1 | 61.7 | 48% | 5.5 | 3.8 | 69% | 27 | 50 | 48 |
| 87 | the compiled scalers load two texels with one word load: where texels 2k and 2k+1 both draw, `mov ax,es:[si+2k]` feeds AL's stores and then AH's (`mov [di+ofs],ah`, as long as the AL store), so a wall taller than 32 pixels loads half as often. Sprites enter a scaler at any texel, so the nine sprite call sites load the post's start texel into AH and keep the byte under the RETF in the code segment. Found by measuring first that the walls' 34% is the CPU's -- walls sent to RAM instead of the VGA saved only 4.1% (see "The walls' 34%"). 2.1% (743.0 -> 727.3); id's picture over the whole loop, and LOWSPRITES+LOWVERT and FLATWALLS+LOWWALLS give the same checksums as before; the 486 unchanged | 727 | 4.98 |
| 88 | VIEW n, an option: id's own window size (Change View, 4-19, 16n x 8n) from the command line, and W3MENU's + and -; TIMEDEMO keeps it instead of forcing size 15. Full detail and id's picture, only less of it: on the benchmark 19 3.95 fps, 17 4.42, 15 4.99, 13 5.69, 11 6.53, 9 7.75 (see "The window size"). The word is compared in code -- a string literal took DGROUP 2 bytes past a 4 KB stack. The default mode is unchanged (726.5 ticks) | 727 | 4.98 |
| 89 | the byte under a sprite post's RETF goes on the stack -- PUSH AX and POP AX, a byte each -- not into the code segment by two 4-byte memory instructions: default 727 -> 725, FLATWALLS 651 -> 648, every switch 455 -> 455.5. What step 87 still costs: FLATWALLS, whose walls use no scaler, is 0.5% slower than before it (645 -> 648) and all the switches together 1.4% (449 -> 455.5) -- the sprites pay some 40 clocks a post to preload the start texel, and pairing gives them less back, under LOWVERT (every other row) little at all; a profile of that mode puts +347 samples in the sprite code against -165 in the scalers. Pairing only the scalers under 64 pixels, which sprites do not use, would have left the sprite code as it was: it hung the 486, so something still draws through a short scaler by the old protocol. Dropped | 725 | 5.00 |
| 90 | pairing only in the scalers from 64 pixels up, and step 55's pixel walk -- sprites under 64, a scaler call per pixel column, whose post loop the profile after step 89 put at 3.7% of a frame -- back to its lean loop: it calls only scalers built under 64 (shared scalers are shared upwards), so with those unpaired AH keeps the RETF's byte and no texel is preloaded. Walls 33-63 pixels high lose the pairing. Default 726.5 -> 720.5, FLATWALLS 648 -> 640.5 (645 before step 87), every switch 454.5 -> 450 (449). It also explains step 89's dropped experiment: pairing only under 64 put pairs exactly where the pixel walk calls with the old protocol. Pixel-identical over the whole loop; the switch modes' checksums and VIEW 6's (the weapon in a short scaler) as before | 721 | 5.03 |
| 91 | pairing at every height again (step 90's from-64-up lost 0.35% over the whole loop: walls 33-63 pixels high gave up their pairs), with the small sprites' pixel walk choosing its post loop per sprite: a scaler built 32 or under never pairs, so under 34 pixels the lean loop (step 90's), from 34 to 62 a copy that preloads the start texel (step 89's), through a 3-byte patch point (LEA BX,[BX+0] or JMP) set only when the mode changes, out of line; with FLATWALLS, whose walls use no scaler, scalers pair only from 64 up and the walk stays lean. **The whole loop 17,770 ticks, 5.51 fps (5.58 in play)** -- step 87 17,814, step 90 17,886, better on all four demos; the benchmark 719-721 as step 90; FLATWALLS 643.5 and every switch 452 (step 90 642 and 450: the patch point and the test cost a little). The first build hung the 486: TASM makes a RET inside a FAR procedure a RETF, so the near-called helper returns with RETN, written so. Pixel-identical over the whole loop; switch checksums and VIEW 6's as before | 720 | 5.03 |
| 92 | a post id drops shows the floor and ceiling, as id's does, not an old frame. Found by the generated demos (gendemo.py, allmaps.py: every map against id's renderer): id's pushwall routines never set lastside, so when a frame begins with a moving pushwall in view, the first ordinary wall or door after it still finds the frame's -1 and skips the ScalePost for the pushwall's last post -- in id's picture VGAClearScreen's ceiling and floor show through. Ours dropped the same post, but step 62 no longer clears the band it predicts the walls will cover, so the columns showed the page from three frames before (G54, map 27: two columns of one frame). DropFill gives such a post's columns the skipped band in the ceiling and floor colours, by BandFix with a wall of height 0; the new-wall paths reach it out of line. Speed unchanged (719-723 against 719-720) | 720 | 5.03 |
| 93 | FARBLOBS, an option (StevenC's idea): a sprite under 16 pixels high (FARBLOBS n sets it) drawn as flat shapes -- each opaque run of each column one span, in the colour of its middle texel, from the generated fill MOV [DI+k*80],AL (k = 159..0, then RETF; 641 bytes made at start-up, only with the switch), no texel loads, no RETF patch. The pixel walk's two draw jumps are retargeted per sprite when the mode changes, out of line (RETN). Four versions: one span a column in the sprite's average colour made a ceiling lamp a grey band (StevenC saw it on the V30); a looped fill was 8% SLOWER on the V30 (777 against 720); the compiled fill and a trimmed column still cost the V30 a little (16: 732 against 721) -- a distant sprite's runs are a few pixels, and step 90 left its draw lean -- while the 486 runs the whole loop 11% faster (68.9 -> 76.1 fps in play). So it is for faster machines. Off, it is id's picture and the same speed; menu key D. TASM: a FAR EXTRN declared inside a segment is assumed to share it (PUSH CS, CALL NEAR), inside DATASEG it is fixed up against DGROUP -- outside every segment, it links; and a memptr is a segment, one word | 721 | 5.03 |
| 94 | FASTOPL, an option: no waits between AdLib register writes (alOut skips its status-read loops on a count of 0 -- LOOP with CX 0 would run 65,536 times). SDL_TimeOPL calibrates the waits for a real OPL2 (3.3 and 23 us, x1.5); the PicoMEM answers a status read in about 4 us from its firmware, so the 2+9 reads cost ~44 us a write, and its emulated chip needs none. 0.75% on the V30 (720-721 against 715-716, three rounds). The music is the same: with sound effects off (CRC) MUSICLOG gives one hash, DFAF, for the first 1,000 writes and their ticks with and without it -- with them on the hashes differ either way, the effects running on real time. Off by default: a real chip needs its waits. Menu key O | 721 | 5.03 |
| 95 | the OPL register shadow: alOut keeps each register's last value (from 20h up; below, test, timers and IRQ reset, every write is made) and skips a write of the value already there -- on an OPL2 that changes nothing, a note starting only on key-on going 0 to 1. 45% of the writes go (4,047 of 9,024 in demo 0), mostly the sound effects' block register, written by id every 140 Hz tick. Sound effects, measured for the first time (NOMUSIC against NOSOUND), cost 15 ticks of demo 0 (2.1%) and 2 cache pages; the shadow takes 2.5 ticks of that, 1 tick of the whole (721.3 against 722.3, three rounds) -- the rest is the interrupt doing an effect's work, not its writes. Attract loop identical to id's. TIMEDEMO now reports the writes and skips, and the sound mode before ShutdownId turned it off (it said 0 every time) | 721 | 5.03 |
| 96 | the first load in runs: when no main-memory block is in use yet, the longest stretch of them lying one after another in memory (up to 32 KB) is a buffer, and pages that follow one another in VSWAP -- across the up-to-511 bytes of padding that puts each on a 512-byte boundary -- are read into it at once and copied to XMS from there; then the main blocks are filled as before, and which page goes where is id's. A test program found the time: reading VSWAP as id does, a seek and a read a page, 110 ticks on the V30; in 32 KB blocks 48 -- the PicoMEM's cost is per read. 663 reads became 45: the first load 118 -> 68 ticks on the V30 (6.5 -> 3.7 s), 198 -> 75 on the 486 (10.9 -> 4.1 s). Attract loop identical to id's; play unchanged. TIMEDEMO reports the buffer and its reads | **721** | **5.03** |

Per view (one 240-column frame); "runs projected" and "nodes visited" are per view too. The two machines agree column for column, so both programs are deterministic. What it says:

1. **The BSP wins where the views are long.** On floor 44, open halls, a ray crosses many cells and few runs face the camera: 40%. On floor 57, dense and short, the walk is cheap already: 77%.
2. **The better the CPU at simple instructions, the less the BSP wins.** A 486 does a compare or an add in a cycle or two and an IDIV in 27, so the walk's many cheap steps get cheaper than the BSP's few dear ones, and on floor 57 they tie. Of these two machines the V30 is the BSP's best case.
3. **This is Pascal against Pascal, and assembly would favour the walk.** The game's walk in assembly is about 39 ms a frame (21% of 186), a third of the Pascal walk, because its steps are compares and adds and assembly makes those cheap. The BSP's time is mostly its multiplies and divides, which assembly cannot make cheaper. So in the game the ratio would be worse than in this table.
4. **The 0.3% of columns that differ** are columns whose centre falls on the end of a run, where the two round differently. For id's picture each would need id's own arithmetic.
5. **The reason it is not in the game.** The walk marks spotvis, every tile a ray crosses; the sprite pass (id's `DrawScaleds`, `PlaceActors` in this build) sets `FL_VISABLE` from it, and `FL_VISABLE` is game logic: `GunAttack` and `KnifeAttack` will only hit an enemy that has it, and `T_Shoot` lowers an enemy's hit chance when it has it ("player can see to dodge"). Only a walk ray by ray marks the same tiles -- a tile can lie between two rays and be missed -- so in the default mode, which must be id's game exactly, a BSP would be added to the walk, not instead of it. Coherent rays (step 85) were the attempt to skip the walk and keep spotvis exact, and their bookkeeping cost more than the walk. The SNES port was free to change the game; this one is not.

Behind a switch (a `BSPWALLS`, say), with spotvis taken from the BSP's view instead of the rays, the ceiling is about half the ray loop, some 10% of a frame on the V30 -- and against it: each door a run that moves, each pushwall a block that the offline tree cannot hold and whose four faces would be added every frame, 10-37 KB of tree a level (two to nine page-cache pages, where losing one has been measurable), and enemies that see and are hit a little differently, which is the game, not the picture. `LOWWALLS` already halves the ray loop and keeps id's tiles, so it was not built.

**Loading the game data, measured (2026-10-01).** TIMEDEMO's header now gives the preload's time: the first level loads every one of VSWAP's 663 pages, the rest find them in XMS. The V30 (XMSSC): 118 ticks, 6.5 s, of which reading the file page by page as the page manager does is 108 -- the disk, at its limit; merging contiguous pages into one read (493 reads, not 663) saves about a tenth. The 486 (HIMEM): 199 ticks, though the same reads take it 90 and HIMEM moves 2 MB in 2-3 ticks whatever the size. The rest is the music: id starts a level's music before "Get Psyched" loads, and on the 486's PicoMEM 1 its 700 Hz AdLib service and the card's disk emulation get in each other's way -- the preload is 200 ticks with music, 132 with NOMUSIC, 116 with NOSOUND, and the profile puts the time inside the card's disk ROM. The V30's PicoMEM 2 shows none of it. **So a slow first load on a PicoMEM 1 is the card, not the game**: the PicoMEM 1 cannot emulate the AdLib and the disk at once at full speed, and its firmware is already the newest PicoMEM 1 release (PM_W_11_16_25, whose BIOS is the 2025-11-02 the card reports), so no update will change it; it is not the 486, whose faster CPU makes the music's own interrupt cheaper. DOS Bridge's docs/hardware.md has it for every program, not just this one. Not changed: silence during the first load would be the only fix, and the music during "Get Psyched" is id's.

**DGROUP is full.** 61,426 bytes after TIMEDEMO's SECS and preload lines; with the 4 KB stack, some 14 bytes to spare. Every new string in the game now has to replace one.

**FLATWALLS' artwork and colours (steps 83, 84).** StevenC, watching step 81: walls the colour of the floor or ceiling, and the artwork gone. A wall's colour is now the nearest to its texture's average -- or to a darker or lighter average, so grey stays grey -- that keeps 9 steps of 6-bit RGB from the floor, the level's ceiling and the light twin, matched again at each new ceiling. The decorated textures are a fixed list chosen by eye from stage/walls.png; an automatic centre-against-edge test took plain brick for art and missed the banners. A Wolf texture is one picture -- the decoration was painted over a plain wall -- so where a decorated texture agrees with its plain twin pixel for pixel (stage/arttab.py, at least 20% of both sides), it is the wall behind: FlatPage paints those pixels the twin's flat colour when it hands the page out, unless two sentinel pixels (whose plain colours differ) say it is painted already; a page the cache reloads comes back as on disk and is painted again, some 20 ms. Twinless artwork (the eagle in its arch, the stained glass) and the elevator stay as they are; FLATART makes it all flat. 640 ticks on the benchmark (5.65 fps), 6.14 in play over the whole loop.

**Every byte resident costs a page sooner or later.** Step 83's 1.9 KB took the default mode from 43 cache pages to 42. Step 84 moved FLATWALLS' 640-byte column buffer, its 384 bytes of averages and its 641-byte fill body out of the program into one block allocated at startup, before the page cache takes the rest, and only with FLATWALLS -- the body built at run time, already in its LOWVERT form, and far-called. That left the default mode 368 bytes above step 82, still 42 pages: the slack had been under 368 bytes. The page measured as nothing (743 against 743 and 745 ticks; four more misses in 200 frames, some 2 ms each), and the rest of the residents -- the colour and artwork tables, the flat routines -- would have had to go with the features. One trap in the move: a sweep of [cs:si+...] to [es:si+...] missed the one [cs:si] with no displacement, the first column's colour, so no group of four ever looked one colour and every column was filled alone -- a correct picture at 754 ticks instead of 640, found by the profiler (the fill body 3.7 times its step-81 share).

**LOWVERT (step 82): let the CRTC skip the rows, and the scalers follow.** Two CRTC registers -- the offset to 80 words, so a displayed row steps two rows of memory, and the maximum scan line to 3, so each is shown four times -- display rows 0, 2 ... 198 of the same 320x200 page at the same size. Nothing 2D has to change: the status bar, border and text are drawn as ever and lose their odd rows on the screen. The 3D view is drawn on the even rows only, and nearly all of that is one test in BuildCompScale: a compiled scaler skips its odd rows (and a texel that lands on none), and walls, enemies, items and the weapon all draw through those scalers. VGAClearScreen fills even rows; with FLATWALLS the fill body's odd row in each pair becomes LEA BX,[BX+0]. The view's top row is always even (80-4*size). The display switches at the first 3D frame and back at the end of any fade-out, while the screen is black. The scalers come out half the size, which gave the page cache 5 more pages (48). Benchmark 743 -> 637 (5.68 fps), 6.39 fps in play over the whole loop; 452 with LOWDETAIL (8.01 fps); 444.5 with LOWDETAIL and FLATWALLS (8.15 fps). Not exercised by TIMEDEMO: the menus and intermissions in real play, which depend on a fade-out coming first.

**FLATWALLS (step 81): a byte at a time, and measure the overhead, not just the writes.** Every wall one colour -- the palette entry nearest the average of 255 of the texture's pixels. (The commonest pixel was tried first and lost the walls' light and dark sides: in grey stone the commonest is the mortar, in both twins.) A post only records its columns' colour and half height; after the cast FlatRender fills four columns -- one byte -- at a time: where the four share a colour, the rows all four walls cover are one write each through all four planes, and only the rows by which the taller ones exceed the shortest go column by column. Wall pages are never loaded. The probe said walls' pixels were 185 ticks of the benchmark's 743; the first version saved 89 of them, and its profile said why: the writes were only 41% of FlatRender, the rest per-column clamping (21%), the ragged ends through a patched-RET call (19%) and band tests (12.5%). Clamping once a post instead, a four-of-one-height group in a single fill, a plain loop for the ragged rows and a one-compare skip of the band took it to 633.5 (5.72 fps, 15% faster), 6.47 fps in play over the whole loop (5.38 without); 482.5 with LOWDETAIL as well (7.50 fps).

**LOWSPRITES (step 80): patch once, never test per sprite -- and never assume the neighbour.** Enemies and items in two-pixel columns: a column drawn double covers its pair partner (the walls' pairs, 2k and 2k+1) and records the x it covered; a column is skipped only when it is that x. LOWDETAIL's benchmark 551 -> 522 ticks, 7.68 fps in play over the whole loop (7.43 at step 79); LOWSPRITES alone 742 -> 723. Three things on the way. (1) The first version copied the pixel walk's loops and tested pixstep once a sprite: 742.0 -> 745.3 in the default mode, every round, with the same page cache (43 pages, the same misses) -- far more than a compare a sprite can cost. What shipped costs the default mode nothing measurable (742.0 -> 743.7, 743.0 -> 743.7 in two runs): the first call to ScaleShape turns its own entry jump into ADD AX,0 and, only with LOWSPRITES, retargets the four jumps into the one-pixel blocks. TASM got two of the patches wrong on the way: a difference of forward labels as an immediate came out 6 bytes off (its one pass sized the code between them before it was final), so displacements are computed at run time from relocated offsets; and one jump had been assembled short (EB xx 90), so the patch writes the E9 opcode too. (2) StevenC saw vertical gap lines in the nearer sprites: the second version skipped every odd column, trusting its even neighbour to draw it, which the pixel walk (every pixel visited) can do but the column loops cannot -- there the neighbour may be a two-pixel span, which covers only its own pixels. A Python model of the loops over 200,000 random sprites found a gap in 11% of them with that rule and in none with the one that shipped. (3) Without LOWWALLS a pair's two columns can have different walls in front, so a column is drawn double only when its partner is visible too; with LOWWALLS that test cannot fail, and the full stubs cost 12 ticks of the benchmark (531.5 against 519.5), so the first call picks lean ones then.

**What the walls' pixels cost: 25% of a frame.** A probe build with the wall scalers' calls replaced by NOPs -- every ray cast, every height computed, no wall drawn -- ran the benchmark in 558 ticks against 743 (445.5 against 551 with LOWWALLS). That is the ceiling for any change to how walls are filled, FLATWALLS included.

**LOWDETAIL (step 79): the one switch that is not id's picture.** Half the rays -- the ray loop, the hit routines and the posts are about a third of a frame -- for walls drawn in two-pixel columns: 6.57 fps on the benchmark against 4.88, 7.43 over the whole loop in play. Two things besides the picture change, and both are why it is a switch and not the default: a tile is marked seen only when a ray crosses it, so a narrow tile far off can be missed and an enemy there wake a little later; and the recorded demos, which replay the player's input and not the outcome, can then drift from what id's renderer showed. In the default mode it costs one NOP a ray (742.0 -> 743.7 on the benchmark, at the edge of the noise), and the whole loop is identical to id's.

**The weapon and the DEMO sign: what skipping them measures is not all drawing.** A build that skips `DrawPlayerWeapon` plays the benchmark 7.1% faster (743 -> 690), but step 77 drew the same shapes with half the screen writes and no call per post, and gained nothing: much of that 7.1% is the two shapes' pages in a page cache of 43, and any memory taken from the cache is paid back in XMS page-ins. Decoded from `VSWAP.WL6` at the 240x120 view: the DEMO sign is 2,418 pixels (8.4% of the view), the ready weapons 190-1,370, the chain gun firing about 3,100.

**Borland C: `far` binds to each declarator, not to the declaration.** `byte far *vals,*planes;` makes `planes` a near pointer; assigning it a far address keeps only the offset, and the writes land in DGROUP. It cost step 77 a wrong picture and a hung 486 before the "suspicious pointer conversion" warning was read. Declare each far pointer on its own.

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

## Where the time goes now (profile after step 90, the benchmark, EMS+PRELOAD)

34,421 samples over demo 0's 200 frames (`TIMEDEMO QUICK PRELOAD PROFILE EMS`; EMS keeps the profiler's 36 KB out of the page cache, and adds the page manager's EMS mapping, about 3%). The compiled scalers 28%; the ray loop and its hit routines (WL_DR_A) 39%, spread so thin that the largest label is 2.7% (`ivt`, the vertical intercept's tile step) and every one of the first ten has been worked over in steps 27-63; the sprite code 13%, of which **step 55's pixel walk -- sprites under 64 pixels -- is about 8%**: 2.8% its post calls (lean again since step 90; since step 91, below 34 pixels), 2.7% each visible column's setup (four registers saved for the post loop, which needs all of them; the map mask; the shape's post list), 2.1% the pixel loop itself; the weapon 2.7%; `VGAClearScreen` 3.4%; `PlaceActors` 2.8%, `TransformTile` 1.3%, `PlaceStatics` and `DoActors` 1% each. The level-start fizzle (5.8%), `BuildCompScale` (1.1%) and the fade's `VL_WaitVBL` (1%) are the first frame's, which the play figure leaves out.

The pixel walk's column setup was looked at after step 90 and not built: the post loop needs SI, DI, CX and BP, the walk keeps its own state in all four, and moving that state to memory costs what the pushes and pops save; patching each sprite's post-list base into the code and keeping the shape in ES would save some 16 clocks of the 250 a column costs (under 0.2%).

### The profile after step 55, for comparison (whole attract loop, EMS+PRELOAD)

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

## Done -- the exhaustion checklist, closed 2026-10-02

Set with StevenC: this exact build is done when every item has been
measured and kept or dropped, and no profile item over about 2% is left
unworked.  All of it, as it came out:

1. **Verification on every map** -- 240 generated demos, two sets of 120
   over all 60 maps (TIMEDEMO GEN; "Every map, checked"), identical to id's
   renderer after step 92 fixed the one difference they found; and the
   playable release, v1.0.
2. **The AdLib on a PicoMEM** -- step 94, `FASTOPL`: 0.75% (721 -> 715),
   the same music by `MUSICLOG`; an option, since a real OPL2 needs its
   waits.
3. **Small sprites plane by plane** -- dropped by measuring its ceiling: a
   build with the pixel walk's map-mask OUT removed altogether (a wrong
   picture, for timing only) ran 720, 722, 725 against 720, 721, 722.  An
   OUT a column costs nothing that shows, so drawing by plane could only
   add the four passes' overhead.
4. **Reciprocal division** for `CalcHeight` -- dropped by arithmetic: the
   V30's 16-bit divide runs at 52,561 a second against 58,640 for its
   multiply (BENCH), so exact division by reciprocal, two multiplies and a
   correction at least, costs nearly twice the IDIV it would replace; a
   486's divide and multiply are as close.
5. **The game logic's remaining C** -- dropped: the whole-loop profile puts
   all of it at about 1.4% (`T_Chase`, the largest, 0.27%), where step 64's
   assembly of `SightPlayer` and `CheckSight` measured as nothing.
6. **A whole-loop profile** (781,727 samples, all four demos, EMS): the
   compiled scalers 33.2%, the ray loop and its hit routines 42.6%
   (`AsmRefresh` 19.1%), the sprite code 12% (`ScaleShape` 6.6%, the
   weapon 3.0%, `ScaleSpan` 2.4% -- charged by profmap to `BuildCompScale`,
   the public below it, which first looked like scalers rebuilt in play),
   `VGAClearScreen` 3.4%, `PlaceActors` 2.2%, `DoActors` 1.9%.  Nothing
   that demo 0's profile had not shown, and every item over 2% has been
   worked by several steps.

And StevenC's FARBLOBS, an option rather than part of the exact build:
step 93, distant sprites as flat shapes -- 11% on a 486, nothing on the V30.

So the exact build is complete at step 94: id's game and id's picture,
1.88x id's speed on the V30's demo 0, checked on every map.  It is tagged
`exact-final`; the BSP version, which may change game play slightly,
starts from that tag on its own branch and never merges back.

Older candidates, each 0.1-1%: `ScaleSpan`'s per-call overhead for the
weapon and close sprites (every register is in use); `PlaceActors`' nine
spotvis tests per actor (a bounding box of the rays' hit tiles costs the
ray loop about what it saves); the long divides (`ny*scale/nx`, 0.4%,
normalised by steps 4 and 42).

Measured and set aside: coherent rays (step 85, 27% slower) and a BSP (step 86 -- in the default mode it cannot replace the walk, because the walk's spotvis is game logic).

The scalers after step 87: what is left in them is the stores, one per screen pixel, and they are at the encoding's floor. `mov [di+disp16],al` is 4 bytes; the rows are 80 bytes apart, so an 8-bit displacement reaches only the three rows around DI -- pointing DI at the view's middle row, which every wall crosses, would save 3 bytes a post, well under 0.1% of a frame. A store cannot cover two rows, and `STOSB` needs an `ADD DI,79` beside it (4 bytes again, in two instructions). Not built.
