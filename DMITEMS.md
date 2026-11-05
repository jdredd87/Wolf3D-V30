# Deathmatch items -- how they work, and how to change them

Written by **StevenC** and **Claude** (Anthropic), 2026-11-04.

id made Wolfenstein's floors for one player.  In a deathmatch that shows:
on the registered game a machine gun is placed on only 12 of the 60 floors,
the chaingun usually once -- often behind a pushwall -- and six floors have
neither (E1L10, E3L3, E3L4, E3L5, E3L10, E4L10).  DOOM's deathmatch had weapons because someone edited the maps.
**We edit no map.**  As a deathmatch floor is set up, every machine reads
id's own map and applies the same fixed rules, so every machine ends up with
the same items on the same tiles.  Change a rule here, rebuild, and every
floor changes with it.

Two rules, each a server switch, both on by default in `dm`, `tdm` and `ctf`
and never applied in co-op:

| | switch | what it does |
|---|---|---|
| **guns on every floor** | `--dmitems on\|off` | every floor has at least one machine gun and one chaingun the players can reach, and a few clips |
| **the dead drop** | `--drops on\|off` | a player who dies drops their best gun (or a clip), which is gone 30 s later |

`mp/mpserver.py`, `MPSRV` (DOS) and `MPSRVW` (Windows) all take both.  The
server console's `next mode` keeps them as they were given.

## Where it lives

All of it is in **`WOLFSRC/WL_MP.C`**, in the section headed
`DEATHMATCH ITEMS -- no map edited`, with the numbers together near the top
of the file just above `mpitemdue`:

```c
#define DMI_WANTMG(n)	((n) > 2 ? 2 : 1)	// machine guns a floor has at least,
											//   for n player slots
#define DMI_WANTCG		1			// chainguns a floor has at least
#define DMI_SPACE		8			// tiles kept between two guns where it can be
#define DMI_MINCLIPS	6			// clips a floor has at least (added if fewer)
#define DMI_ROOM		8			// statics never taken by an added item, for the
									//   drops (SpawnStatic quits at MAXSTATS)
#define DMI_DROPSTEPS	525			// a death's drop lies 30 s (17.5 steps a s)
#define DMI_DROPCAP		(MAXSTATS-4)	// a death's drop past this many statics only
									//   in a free slot: the rest for enemies' drops
```

`DMITRIES` (8, the regions tried when looking for the floor) is beside
`Floor ()`.

The protocol carries the two rules as bits of `rules2`, START's byte after
the starts (MULTIPLAYER.md, "Modes and rules"):

| bit | name | |
|---|---|---|
| 1 | `RULE2_TEAM` | team deathmatch |
| 2 | `RULE2_CTF` | capture the flag |
| 4 | `RULE2_ITEMS` | guns on every floor |
| 8 | `RULE2_DROPS` | the dead drop |

Both are bits that turn something ON, so a game recorded before them, or a
server older than them, plays exactly as before: id's items, nothing
dropped.  `win32/gate.sh` replays the old recordings and still passes 8 of 8.

## Rule 1: guns on every floor

Done once per floor, in `MPSpawn` after the flags are placed (`DMItems ()`).

**1. Find the floor.**  "The floor" is the biggest open region of the map:
the tiles a player can walk between with every door open (deathmatch gives
everyone every key) and **without moving a pushwall**.  Walls, pushwalls and
blocking statics (barrels, tables, pillars ...) stop it.  It starts from the
first player's start; if that region is under half the open floor, it tries
again from the next tile no region has yet, up to `DMITRIES` times, and
keeps the biggest.

Why not "what the first start can reach"?  E3L8 starts in a 14-tile room
shut by a pushwall, so on that floor everything would have been put in one
closet.  Deathmatch players respawn anywhere (`DMStart`), so the main region
is what they play in.

Why not count pushwall secrets?  Because on the floors that need guns most
(E1L1, the boss floors), id's weapons and clips are *all* in the secrets,
and a gun nobody can find is not a gun.

**2. Count what is already there**, on the floor only: machine guns,
chainguns, clips (Spear's 25-clips count as clips).

**3. Add what is missing**, one item at a time, best place first:

* machine guns until there are `DMI_WANTMG(slots)` -- 1 for a two-slot
  game, 2 for three or four,
* chainguns until there are `DMI_WANTCG` (1),
* clips until there are `DMI_MINCLIPS` (6).

Each gun is placed either **by turning one of id's clips into it**, or by
putting a new item on open floor.  Both are scored the same way:

| | score |
|---|---|
| at least `DMI_SPACE` tiles (8, counted as the bigger of the two distances) from every other gun on the floor | +4 |
| in a room (id's area number) that has no gun | +2 |

A clip is used if its score is as good as the best open tile's; otherwise
the gun goes on open floor.  So id's clips are used where they are well
placed, and a floor whose few reachable clips lie together (E1L3, E1L6) does
not get its guns side by side.  Clips added to a thin floor are spaced from
the other clips the same way.  Ties are broken by a fixed per-floor order (a
hash of the floor and the tile) -- the same on every machine, and the same
every time that floor is played.

"Open floor" means: on the floor, no wall or door, nothing standing there,
no static of any kind on the tile.

**4. It comes back as itself.**  A clip turned into a gun is recorded as a
gun (`mpitemshape`), so with `--itemrespawn` it reappears as the gun.

**Limits.**  The static list holds 400 (`MAXSTATS`), and `SpawnStatic`
quits the game past it, so a new item is only added while the floor has
fewer than `MAXSTATS - DMI_ROOM` (392); CTF's flags are placed before, and
an enemy's drop is skipped, not fatal, when the list is full.  Floors at
the limit (E6L8 with 398, Spear's floor 19 with 398) still get their guns,
by turning clips into them -- side by side, if that is where the clips are.

### What it did, floor by floor

`tests/dmitems.py` records every floor twice through the real server and
game (on and off), replays both with the Win32 replay, and prints what
changed -- the authority for "what will I find on E3L4".  It reads the
statics through a test hook in the Win32 builds only: `W3DDMI=1` prints
every static as the floor is set up, before a player can take one (a
deathmatch start can put a player on an item, which is gone by step 1).
`tests/dmicheck.py` then works out each main floor itself, from id's map --
not from the game's code -- and counts what is on it.

On 2026-11-04, with four slots (two machine guns wanted):

| | floors | only clips turned into guns | items added | most added to one floor |
|---|---|---|---|---|
| Wolfenstein 3-D (`*.WL6`) | 60 | 36 | 24 | 9 (E1L9, E2L10, E4L10, E6L9) |
| Spear of Destiny (`*.SOD`) | 21 | 14 | 7 | 7 (floor 1) |

**Every one of the 81 floors ends with at least 2 machine guns, a chaingun
and 6 clips on its main floor** (`dmicheck.py`: 0 short, both games).  The
floors that needed new items are the thin ones and the boss floors, whose
weapons and clips id put in secrets: E1L1 +8, E1L9 +9, E2L10 +9, E3L1 +8,
E4L10 +9, E6L9 +9, and so on (`stage/dmi/dmitems.txt`).

Run it again after changing a number:

```
python win32/build.py rep repsod       the Win32 replays, with the change
python tests/dmitems.py                all 60 floors -> stage/dmi/dmitems.txt
python tests/dmitems.py 0 8 27         just those (map numbers: (E-1)*10 + (L-1))
python tests/dmicheck.py               each main floor's guns and clips: 0 short?
python tests/dmitems.py --sod          Spear's 21 (W3DREPS.EXE, run in C:\wolf3d\SOD)
python tests/dmicheck.py --sod
```

`REP=W3DREP2.EXE` runs either with a second replay (`build.py rep2`) while
`W3DREP.EXE` is busy.

## Rule 2: the dead drop

In `MPDie`, `DeathDrop ()`: a player who dies drops, where they fell,

* the chaingun, if they had it; else
* the machine gun, if they had it; else
* a clip (the half clip enemies drop).

The anti-spam limits:

* **one drop a tile**: no drop where a death's drop already lies;
* **gone after `DMI_DROPSTEPS`** (525 steps, 30 s) if nobody takes it, and
  its slot is free again at once if somebody does;
* **never comes back** with `--itemrespawn` (only the map's own items do);
* **past `DMI_DROPCAP`** statics (396) only into a free slot, so the last
  four are left for the enemies' drops.

Seen in a recorded 5,000-step game with enemies (E1L2, 3 bots): every death
left a clip where the player fell, gone exactly 525 steps later unless
taken; a player who died with the chaingun dropped the chaingun.

A drop is a normal `PlaceItemType` (id's routine for an enemy's drop), marked
in `mpitemdrop` as 2 -- "a death's" -- with its time in `mpitemdue`;
`ItemsBack` clears it when the time comes.  Enemies still drop what id gave
them, unchanged.

## Changing it -- a cookbook

Every change below is in `WL_MP.C`.  After any of them: build the Win32
replay and run `tests/dmitems.py` to see the result on every floor, run
`bash win32/gate.sh` (must stay 8 of 8 -- the old recordings do not use these
rules), then build every network game -- `w3dbuild.py build`, `buildwl1`,
`buildsod`, and `win32/build.py game sp sp1 spsod` -- because **all the
machines in a game must have the same rules**, or the first difference is a
desync.

| to | change |
|---|---|
| more machine guns | `DMI_WANTMG`, e.g. `((n) > 2 ? 3 : 2)` |
| two chainguns | `DMI_WANTCG 2` |
| guns further apart | `DMI_SPACE` -- 8 tiles is an eighth of the map's width; the bigger it is, the sooner a small floor runs out of places that meet it, and then "a room without one" decides |
| more ammo on thin floors | `DMI_MINCLIPS` -- 0 adds no clips at all |
| drops lie longer | `DMI_DROPSTEPS` -- 17.5 steps a second, so 1050 is a minute |
| drop only guns, never clips | in `DeathDrop`, return when `bestweapon` is below `wp_machinegun` |
| also first aid or food | a loop in `DMItems` like the clips': `Count (bo_firstaid)`, then `Add (0,bo_firstaid,25,IsAid)` until there are enough, with an `IsAid` like `IsClip` for the spacing (food: `bo_food`, type 24) |
| count pushwall secrets as reachable | in `Walkable`, a pushwall tile is a wall with `MAPSPOT(x,y,1) == PUSHABLETILE` -- let it through |
| a rule in co-op too | `MPSpawn` calls `DMItems` only with `RULE_DM`; the server only sets the bits in a deathmatch mode (`dm_bits` in mpserver.py, `SetMode` in mpsrv.pas) |
| a new switch | a new `rules2` bit (16, 32, 64, 128 are free), set by the servers, read in `WL_MP.C`; a bit that turns something ON keeps old recordings and servers as they were |

The statinfo types `SpawnStatic` takes are the map codes less 23: clip 26,
machine gun 27, chaingun 28, food 24, first aid 25.  The sprite numbers in a
SUMDUMP are those plus 2 (clip 28, machine gun 29, chaingun 30).

## Why it cannot desync

Everything it reads -- id's map, the statics, the doors, the actors standing
on the floor, the first start, the number of slots -- is the same on every
machine when `MPSpawn` runs, and everything it changes is in the static
list, which is in every 50th step's sum and in the snapshot a late joiner
starts from.  The tie-break hash is 16-bit arithmetic, the same on DOS and
Windows.  Its scratch is `spotvis`, the renderer's per-frame visibility
array, cleared before and after -- nothing else reads it.  A death's drop
happens in the game logic, at the same step on every machine.

## Tested

2026-11-04, MPVER 0x0112 (build 01120006 on every machine), the DOS games
`WOLF3DM` 47130941, `WOLF3DM1` E1BF0676, `SPEARM` 3FD66CA3:

* `win32/gate.sh`: 8 of 8 -- the old recordings replay exactly as before;
* `tests/dmicheck.py`: 0 floors short of 81 (60 registered, 21 Spear);
* live, `tests/netmatrix.py mpsrvw 10500` with `NETNEXT=120`: team
  deathmatch on MPSRVW, the 486 and P3 from the start, WOLF3DW on Windows,
  the V30 in late from a snapshot, four floors (E1L1 to E1L4) -- 10,500
  steps on all four, **no desync**;
* live, `tests/netmatrix.py dmen 10500` with `NETNEXT=150`: deathmatch WITH
  enemies on mp/mpserver.py, the same four machines, three floors -- players
  killed on every floor, so their drops were in the game everywhere --
  10,500 steps on all four, **no desync**.

The recordings are `stage/dmi/LIVE1.MPR` and `LIVE2.MPR`.

## What it costs

Nothing per step.  At a floor's start, a few sweeps of the 64x64 map (array
walks, no calls per tile -- the V30 makes about 46,000 calls a second), done
while the floor loads.  No near data: DGROUP is full.
