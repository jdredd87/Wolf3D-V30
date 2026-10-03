# The BSP version -- plan and notes

StevenC and Claude, 2026.  Branch `bsp`, started from tag `exact-final`.

`v30-8086` is id's game exactly: the same pixels and the same play, proven
against id's renderer on every map.  This branch gives up that promise to go
faster: it may change game play slightly.  It never merges back into
`v30-8086`; exact improvements made there can be merged in here, never the
other way.  Its program is `WOLF3DB.EXE`, so both can sit beside the same
game data.

## Why a BSP here, and what it can win

Step 86 (`bsp/`, on `v30-8086`) measured a BSP of each demo map's wall runs
against Wolf's grid walk, the same views in the same Pascal: on the V30 the
BSP found the visible walls in **40-77%** of the walk's time (least on dense
maps, most in open halls); on the 486, 50-100%.  The walk could not be
replaced on the exact branch because it also marks `spotvis` -- every tile a
ray crosses -- and `spotvis` is game logic: `FL_VISABLE` decides whether the
player's shots hit and how hard enemies shoot back.  Here it may come from
the BSP instead.

The ceiling: the ray loop and its hit routines are about 42% of a frame
(whole-loop profile, step 92), the compiled scalers that draw the walls 33%
and unchanged by a BSP.  So a BSP that halves the visibility work is worth
roughly 15-20% -- more on open maps, less on dense ones -- and the scalers
stay as they are.

## The plan, milestone by milestone

1. **The tree, built at level load.**  From `tilemap`: every wall face
   bordering an open (or door) tile, merged into runs along its grid line;
   an axis-aligned splitter by the median of the candidate lines (a k-d
   style tree: O(n log n), fast enough on a V30 at "Get Psyched"), node
   boxes for culling.  Memory from the page cache's pool, freed at level
   end.  Measured: build time on the V30, tree size per map.
2. **Walls from the tree.**  Front to back; a run facing the camera is
   projected (its two ends), its columns not yet claimed are claimed, and
   each claimed column gets what the hit routines give the post pipeline
   today -- the intercept on the wall, `wallheight` from `CalcHeight`, the
   texture column -- so `ScalePostA` and the compiled scalers draw it
   unchanged.  Stop when every column is claimed.  Compared column by
   column with the walk (step 86 found 99.7% the same wall; the rest are
   corner ties).
3. **Doors.**  A door is a run in the middle of its tile, open by
   `doorposition`: drawn when its column is not open there, else the ray
   goes on behind -- the tree holds door tiles as runs whose span depends on
   the door's state at draw time.
4. **Pushwalls.**  A moving block cannot be in a tree built at load: its
   four faces are projected separately each frame, in front of the tree's
   walls by depth, and its tile is left out of the tree while it moves.
5. **`spotvis` from the BSP.**  Every tile in front of the claimed walls
   within the view -- the tiles of each visible run's near side and the
   floor between the camera and it, marked per column group, not per ray.
   This is the game play change: an enemy in a tile no ray crossed but in
   view becomes visible.  Measured: how often `FL_VISABLE` differs from the
   walk's over the attract loop.
6. **Measure and tune** on the V30 against `exact-final`, and decide the
   ray loop's fate: kept for small rooms (where it is cheaper) and the tree
   used only past some distance, or the tree throughout.

## How it is tested

Not against id's checksums -- once `spotvis` changes, the demos play a
different game.  Instead: the picture of frame 1 of each generated demo
(before anything has diverged) against `exact-final`'s, the column-by-column
wall comparison of milestone 2, its own generated-demo checksums between its
own builds (a change that should not alter play must leave them alone), and
StevenC's eyes on the capture card.

## Milestone 1, done (2026-10-02): the tree at level load

`WL_BSP.C`, called at the end of `SetupGameLevel`; nothing draws from it
yet, and the attract loop is still id's picture exactly (view `0707C966`,
screen `F2A10CEB`), with no cost in play (V30 benchmark 722-726 against
720-721).  TIMEDEMO prints a line per tree built.  Over all 60 maps (one
generated demo each, on the 486):

| | min | mean | max |
|---|---|---|---|
| runs | 131 | 485 | 1,198 |
| runs cut | 10 | 50 | 145 |
| nodes | 118 | 409 | 987 |
| depth | 9 | 10.5 | 15 |
| bytes kept | 2,086 | 7,256 | 17,587 |
| build, 486 | 1-2 ticks after the fixes below | | ~5 |

**Build time on the V30 is the problem left**: floor 38 (980 runs) 67
ticks (3.7 s), floor 28 (537) 37, floor 1 (322) 24 -- added to the level's
load.  Three versions got it from 269 ticks: choosing each node's line from
per-coordinate counts over only the node's extent (269 -> 94), scanning
`tilemap` directly instead of a bounds-checking `Solid()` four times a cell
(runs 20 -> 6 ticks), and the counts as bytes in near memory with the
bounding box in locals (94 -> 67).  What is left is Borland's code for far
memory, which the V30 runs some 20 times slower than the 486 against the
usual 5.  Next, if it matters: the two inner loops by hand in assembly, or
a disk cache -- each map's tree written the first time and read (8-18 KB)
after.

Two lessons, both from hangs (each machine was power-cycled): **`Build` is
recursive, 9-15 deep, under whatever the game already has on its 4 KB
stack** -- counts kept in its frame overran it, and so did a 780-byte frame
of ints in a helper once `Build`'s own frame grew by 20 bytes; and a report
string longer than the stack buffer it is copied into overran that.  The
format strings are far data copied to the stack for `printf`, because
DGROUP has 4 bytes left (the two block handles took the other 4).

## Before milestone 2: what a BSP can actually win here (2026-10-02)

The plan's 15-20% assumed the BSP would replace most of the ray loop's 42%.
It cannot: it replaces only the walk's tile stepping, and the profile after
step 90 (demo 0, EMS, labels of `AsmRefresh`) puts that at about **8% of a
frame** -- the loop head and its tile test (`ivt`, 2.7%: its bucket holds
`vertcheck`), the vertical step (`vspotop`, 2.5%), the horizontal side's
entry (`vyadc`, 1.6%), the rays' initial values (`ivxt`, 0.8%) and the
horizontal step's adds (`hxadd`, `hxadc`, 0.8%).  Everything else in the
loop -- each ray's setup, the hit routines, the heights, the posts -- a BSP
needs as much as the walk does.

And the BSP's own work replaces it: each column's intercept computed
directly (three or four multiplies, operands wider than 16 bits), where the
walk gets it from additions; some 40 runs projected (four multiplies and a
divide each); some 80 nodes visited -- about 45,000 clocks a frame on the
V30, some 3% of one.  **So the net is about 4-5% on the V30**, for doors,
pushwalls and visibility rebuilt and game play changed.  Step 86 measured
40-77% because a Pascal walk's steps are dear; this one's are compares and
adds in assembly, which is why the exact build got there.

On the 486 the balance is different (its multiplies are cheap next to its
memory), and FARBLOBS showed a gain can be the 486's alone.  Milestone 2 is
held here until StevenC decides whether 4-5% on the V30 is worth it, or
whether this branch should go after larger non-exact wins (the compiled
scalers are a third of a frame).

## Milestone 2, working (2026-10-03): the tree draws the game's walls

StevenC asked for the BSP to run the actual game, so milestone 2 went ahead.
`TIMEDEMO BSP`, or `BSP` on the command line, puts `BSPRefresh` in
`WallRefresh` in place of `AsmRefresh` (the walk stays for `FLATWALLS` and
`LOWWALLS`, and if a map's tree could not be built).  Front to back through
the tree, frustum-culled by node box and by run; each run facing the camera
is projected at its two ends and stepped across its columns; doors after the
walls, wherever they are nearer; then object visibility (`spotvis`) from the
same projection.  TIMEDEMO prints a line of per-frame counts.

**The picture**: frame 50 of demo 0 against the walk differs in 2,726
pixels, single texels at scattered columns -- the BSP samples each column
where its own ray falls, from ends known to 1/64 column, and the walk
truncates differently.  No holes: every column of every frame is claimed.

**Speed, demo 0, `QUICK PRELOAD`, play frames:**

| | 486 | V30 |
|---|---|---|
| the walk | 58-60 fps | 4.98 fps |
| BSP, first working version | 20.8 | |
| + the culling fixed (below) | 28.5 | 2.01 |
| + exact stepping, view box for statics | 32.3 | |
| + one routine per end, doors culled | **39.0** | **2.58** |

So far it is half the walk's speed on the V30.  How each step was found:

* **id's `sintable` is sign and magnitude** (a negative entry is the
  magnitude with bit 31 set, as `FixedByFrac` takes).  Read with a plain
  shift every negative sine came out positive, three quadrants' culling
  planes pointed outward, and whole walls were culled -- an average of 93
  columns a frame were left to the floor fill, and the tree walk never
  stopped early.  Counters, not the picture, showed it: frame 50 looked fine.
* **A run cut at the near plane can project thousands of columns off the
  screen**, and stepping from there -- the start found by multiplying a
  truncated step -- slid the texture along every near wall.  Runs are now
  clipped to the view's sides (only when an end is more than 100 columns
  out), ends kept in 64ths of a column, and the per-column steps exact: a
  quotient and a remainder carried, as a line is drawn.
* **Object visibility projected every static in the level, every frame**,
  with six `FixedByFrac`s each -- 14% of the 486's frame.  Now the view's
  triangle, cut off at the farthest wall drawn (`postmin`), gives a box that
  rejects most statics with four compares, and the rest use 16-bit IMULs.
* **Borland calls a helper for every 32-bit multiply, divide and shift**,
  and the first run setup made sixty calls a run; `DrawDoors` also
  projected every door on the level.  On the V30 those calls were a third
  of the frame (the profile: `UDiv16` 7%, `Col64` 6%, `UMul16` 5%).
  `ColHeight` now does a point's column, height and u*h inline on the
  8086's MUL and DIV, `MulDivFloor` the stepping set-up as 48-bit products
  over three DIVs, and doors are culled by the view and skipped when open.

**Not handled yet** (then): pushwalls -- done below, milestone 4.  `spotvis`
is marked only for objects (the tile under each static and actor whose
projection is nearer than the wall in its column).

**Where the V30's time goes now** is the next job: the per-column loop in C
(`DrawRun`, 15% before the last step), the visibility pass, and the tree
walk with its culling tests.  The walk is assembly throughout; to be worth
anything here the column loop has to be as well.

## Speed, round two (2026-10-03): from half the walk to four fifths

The V30 profile after milestone 2 put the BSP's own code at 65% of the
frame.  Six changes, each measured on both machines, each leaving frame 50
of demo 0 exactly as it was:

| | 486 | V30 |
|---|---|---|
| milestone 2 | 39.0 | 2.58 |
| claimed columns as ranges, the column loop in assembly | 42.1 | 2.97 |
| culling and object visibility in assembly | 47.1 | 3.59 |
| objects in areas shut off by closed doors skipped | 49.0 | 3.75 |
| runs wholly behind what is drawn found before projecting | 50.3 | 3.97 |
| subtrees wholly behind what is drawn skipped | 51.8 | 4.10 |
| (the walk) | 58-60 | 4.98 |

* **The claimed columns are sorted ranges**, Doom's solidsegs.  A run is
  stepped only through the gaps between them; the first loop stepped every
  column a run covered and skipped the claimed ones, and a far wall behind
  a near one cost all its columns -- 37% of `DrawRun` (`stage/proflines.py`
  charges a profile to the C lines of a function from BCC's own assembly).
  The loop itself is `BSPCols` in `WL_DR_A.ASM`, back to C only when the
  texture's tile changes.
* **`BSPOutside` and `BSPMarkVis` in assembly**, the frame's camera and
  planes kept in `WL_DR_A`'s code segment, because DGROUP is full.  In C a
  dot product was a helper call over values in memory.
* **`areabyplayer`**: the view box reaches as far as the farthest wall
  drawn, so with a corridor in view it let most of a level's statics
  through to the full test.  A static in an area the player's does not
  reach through open doors cannot be seen.
* **Occlusion before projection.**  Of 28 runs a frame, 19 turned out to
  lie wholly behind walls already drawn, found only after the full
  projection.  `BSPColRange` estimates a segment's columns from 8.8
  operands with a few IMULs -- within some two and a half columns, four
  allowed, and only for ends at least a tile in front -- and a run inside
  one claimed range is skipped.  The same test on a node's box (its two
  silhouette corners, which two depending on where the camera is: Doom's
  `checkcoord`) skips whole subtrees: 59 nodes and 28 runs a frame became
  34 and 13.

Two bugs found on the way, both latent before: the stepping remainder was
compared signed (`e + r` can pass 32767), and a post still pending when a
new tile's page was fetched pointed into a page `PM_GetPage` may evict.

## Milestone 4, working (2026-10-03): pushwalls

A pushable block moves, and the tiles it leaves open up for good, so a tree
built at load cannot follow it.  The tree is built with every pushable tile
open -- the walls around it are in the tree -- and every tile a block can
be in (the pushable tile and the open ones within two tiles of it, the
farthest a push goes; 5 to 24 of them on the maps tried) gets its faces in
the tree too, as one-tile runs marked as a block's (bit 2 of `of`):
`DrawRun` draws one only while a block stands in its tile.  So a standing
block is drawn front to back like any wall, and hides what is behind it.
The block on the move -- `tilemap` 0C0h, `pwallpos` along `pwalldir` -- is
the only one drawn apart, after the walls, each face wherever it is nearer
(as the doors are).

The first version drew every standing block that way, after the walls; the
tree then drew the secret behind each pushable wall first, every wall
there twice, and its occlusion tests found nothing hidden.  Beside
pushwalls the V30 ran at two thirds of the walk's speed.

`stage/pwdemo.py` writes a demo for each map with a pushable wall that can
move (G240-G288, 49 of the 60 maps): the player faces it, presses use,
watches it slide two tiles, walks in and looks both ways.  Played on the
V30 and watched on the capture card, the block slides back down its
corridor with the side walls appearing as it goes.

Two side effects.  The renderer's code put the 486 (549 KB free, the
V30 557) just under id's 235,000-byte check at start-up ("You do not have
enough memory"), so this branch asks for 225,000; and `BuildBSP`'s
borrowed buffers are sized for 2,000 runs and 1,400 nodes (the most any of
the 60 maps had was 1,198 runs, 145 more cut, and 987 nodes) -- a map that
needed more would simply be drawn by the walk.

**BSP is now the default on this branch**; `WALK` gives id's rays.

Checked against the walk frame by frame on G240 (E1M1's portrait wall):
every tenth frame through the push, the walk in and the turn, differing
only in single texels, mostly on the right half of the view (id's rays put
that half one column over from its own sprite projection, which the tree
follows).  Pushwall maps on the V30, play frames, before and after the
standing blocks went into the tree:

| demo | walk | blocks drawn apart | blocks in the tree |
|---|---|---|---|
| G245 (floor 6) | 6.67 | 4.53 | 5.23 |
| G255 (floor 16) | 6.66 | 4.10 | 4.91 |
| G266 (floor 31) | 7.31 | 4.86 | 5.88 |
| G281 (floor 51) | 6.05 | 3.99 | 4.70 |

## Last steps of the day, and a hang (2026-10-03)

* **`BSPCols` in fewer bytes.**  On the V30 the column loop is
  fetch-bound -- some 750 clocks a column for about 150 bytes of
  instructions -- so: the height in CX:BP (its step's remainder left out,
  1/65536 a column), the flip as an XOR mask (0FC0h - t is t xor 0FC0h),
  and no page compare, since a post never spans a tile change.  Demo 0
  3.91 -> 4.01, G245 5.23 -> 5.42.
* **`BSPClassify`**: a node wholly inside the view needs no frustum test
  below it.  Demo 0 4.01 -> 4.05; little, but nothing lost.
* **Map 52 hung at load** (generated demo G102), with `WALK` as much as
  with the tree, because the tree is built either way.  Its tree is the
  deepest of the 60, and with the pushwalls' faces `Build`'s recursion plus
  `ChooseSplit`'s 390 bytes of counts overran the game's 4 KB stack -- the
  milestone 1 lesson again.  The counts are far statics now (`ChooseSplit`
  is never re-entered), and a tree deeper than 24 is given up for the walk.
  Found only by playing every generated demo with the BSP; the scan of all
  288 on the 486 is the test this branch is held to.

**Where it stands**: on the V30 the BSP runs demo 0 at 4.05 fps against
the walk's 4.98 (81%), and pushwall maps at 78-81%.  Its own code is now
mostly assembly; what is left is spread thin -- the column loop 8%, object
visibility 5%, the tree walk and its tests (`Walk`, `BSPOutside`,
`BSPColRange`, `BoxHidden`) about 14%, the runs' set-up about 7%.  The
estimate made before milestone 2 -- 4-5% better than the walk at best on
this machine -- still looks right: the walk's tile stepping is cheap
assembly, and the tree has to pay for the walk, culling and set-up it
replaces it with.
