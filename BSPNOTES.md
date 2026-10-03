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

