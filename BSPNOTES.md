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
