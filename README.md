# Wolf3D-V30

**Wolfenstein 3-D, from id Software's source, rebuilt for real DOS PCs --
from an 8 MHz NEC V30 to a Pentium II -- made as fast as hand-written
assembly can make it, and turned into a four-player network game.**  VGA,
AdLib and Sound Blaster sound, the whole game: in its default mode every
frame is the picture id's own code draws, checksum for checksum.

It started as "make Wolfenstein run on a V30" (the name stays), and that was
done in the first week.  Since then:

* **It is fast.** 98 measured optimisation steps -- most of them id's C
  moved into hand-written 8086/80186 assembly -- take the V30 from 2.8 fps
  (id's 1992 code, rebuilt for it) to **5.5 fps with id's exact picture**,
  and past **10 fps** with the optional detail switches.  On a 486 at 66 MHz:
  **100 fps**.
* **It plays over a network.** Up to four players, **deathmatch or co-op**,
  with or without enemies, DOOM's rules, server bots, chat, scores, and
  people joining and leaving a game that keeps running -- lockstep over UDP,
  so a V30 and a Pentium II play the same game step for step.
* **It has a server you can drive.** A small Python server keeps the clock;
  its console kicks, bans, pauses, sends messages to every screen, changes
  the floor and the limits mid-game, and shows the scores.
* **It adds to the game without changing it.** An automap (TAB), window
  sizes, a launcher menu, a demo reel, and a second version built on a BSP
  tree -- all optional, all switches.  Leave them off and it is id's game.
* **It is proven, not assumed.** Every change is checked against id's
  renderer over the whole attract loop and 240 generated demos on all sixty
  maps; every multiplayer change against twenty four-player demos played from
  every player's eyes; long runs of eight hours on three machines.

Written by **StevenC** and **Claude** (Anthropic), 2026.  StevenC sets the
goals and runs the hardware; Claude did the porting, the assembly, the
network game, the tools and the measurements -- all over
[DOS Bridge](https://github.com/jdredd87/DOSBridge), which lets a Windows PC
build and run programs on a real DOS machine as if it were a test suite.

## The three versions

| program | branch | what it is |
|---|---|---|
| `WOLF3DV.EXE` | `v30-8086` (default) | **id's game exactly**, as fast as it goes.  The default picture is id's, pixel for pixel; every speed-for-picture trade is a switch you turn on |
| `WOLF3D8.EXE` | `v30-8086` | **the same, for a plain 8086/8088**: `WOLF3DV` with every 186 instruction spelled the 8086 way, built by `w3dbuild.py build8086` -- below |
| `WOLF3D1.EXE`, `WOLF3D18.EXE` | `v30-8086` | **the same for the free shareware episode** (version 1.4's `*.WL1`), for a V20/V30 and up and for a plain 8086/8088: `w3dbuild.py buildwl1` / `buildwl18` -- below |
| `WOLF3DB.EXE` | `bsp` | **the BSP version**: allowed to change the game a little for speed -- far walls drawn in less detail by default, or the whole world from a BSP tree instead of id's rays (`BSP`) -- [BSPNOTES.md](https://github.com/jdredd87/Wolf3D-V30/blob/bsp/BSPNOTES.md) on that branch |
| `WOLF3DM.EXE`, `WOLF3DM1.EXE` | `multiplayer` | **the network game**: everything `WOLF3DV` is, plus up to four players over UDP; `WOLF3DM1` is the same on the free shareware (since v1.6) -- [MULTIPLAYER.md](https://github.com/jdredd87/Wolf3D-V30/blob/multiplayer/MULTIPLAYER.md) on that branch |

`WOLF3DO.EXE` is **id Software's own 1992 code**, rebuilt for the 8086 by
`refsrc.py` with the same timing harness: the yardstick everything above is
measured against.  Fixes go into `v30-8086` first and flow from there into
the other two, never the other way.

## What it runs on

| machine | tested | sound |
|---|---|---|
| **NEC V30**, 8 MHz, 8087 | the target: everything, every day | PicoMEM 2's AdLib, and since 2026-10-13 its emulated **Sound Blaster 2.0** |
| **486**, 66 MHz | builds the game, runs every check | Creative **AWE64** (Sound Blaster + OPL3) |
| **Pentium II/III**, Intel 440BX | the third player | onboard **Yamaha YMF740C** (Sound Blaster Pro + OPL3) |

It needs a **NEC V20/V30, an 80186, or anything from a 286 up**, a VGA,
MS-DOS, and id's registered **1.4 WL6 data** (not included, and never will
be).  id's own `WOLF3D.EXE` refuses an 8086-class machine outright; this one
lets the V20/V30 and the 186 in, because the game only ever needed the 80186
instruction set.  **`WOLF3DV` refuses a plain Intel 8086 or 8088**: the
code uses 186 instructions throughout, and those crash an 8088 rather than
fail politely.

**`WOLF3D8.EXE` is the same game for a plain 8086 or 8088** (2026-10-14).
`to8086.py` writes a copy of the source with every 186 instruction spelled
the 8086 way -- 100 multi-bit shifts as single ones, `PUSHA`/`POPA`, one
three-operand `IMUL`, one `REP OUTSB` -- the C compiler told to emit 8086
code, and the CPU check opened; `python w3dbuild.py build8086` builds it.
It draws id's picture exactly (`ab.py --full`, on the 486 and the Pentium
II), and TASM assembles every file in 8086 mode, so a 186 instruction left
anywhere in the assembler would have been a build error.  It costs little:
on the V30, demo 0 plays in 738 ticks against `WOLF3DV`'s 722 from the same
source -- **2.3% slower**, 4.90 frames a second against 5.01 (three rounds
each, interleaved, `ab.py`; 2026-10-15).  On a V20/V30, a 186 or anything
newer, use `WOLF3DV` all the same.  It is in the download since v1.5
(2026-10-16), and the `PLAY` menu runs it by itself on an 8086 or 8088.
Nobody here has an 8088 to run it on: if you have one, we would like to
hear.

**`WOLF3D1.EXE` plays the free shareware episode** (2026-10-16, in the
download since v1.6), so nobody needs the registered game to try it.
`WOLF3D18.EXE` is the same for a plain 8086/8088.  id's source builds the
shareware with `UPLOAD` defined, but its `GFXV_WL1.H` describes an older
shareware's graphics (556 chunks); 1.4's `VGAGRAPH.WL1` has 156.
`mkgfxw14.py` writes `GFXV_W14.H` for it: the registered layout plus the
12 pictures of the shareware's help screens, every picture's size checked
against the data's own table.  The rest of 1.4's shareware data is laid
out as the registered game's -- 288 sound chunks, 663 VSWAP pages whose 26
missing digitized sounds are exactly the ones id's `UPLOAD` code leaves
out, and ten floors byte for byte the registered Episode 1's.  Checked
against id's renderer built the same way (`refsrc.py` with `UPLOAD`): the
attract loop (view `987C8F2A`, screen `B5A49A73`) and 40 generated demos
on the ten floors, both builds, on the 486; and on the V30, 5.0 frames a
second.  `PLAY` picks `WOLF3D1` or `WOLF3D18` by itself in a folder with
`*.WL1` and no `*.WL6`.  The shareware is free to copy (`1WOLF14.ZIP`,
from any DOS game archive), but none of it is in this repository.

## Status

| | |
|---|---|
| speed | **5.51 fps** over all four demos, **5.57 in play** on the V30 (id's code: 2.81); demo 0 in full **2.75 -> 5.17 fps, 1.88x**.  On the 486 at 66 MHz, 99.7 fps in play.  The BSP version's default 6.15 on the V30, 105.5 on the 486.  Every option on both machines: [BENCHMARKS.md](BENCHMARKS.md) |
| picture | identical to id's renderer over the whole attract loop -- 5,386 frames, every 50th checksummed, the 3-D view and the whole screen (`ab.py --full`) -- and over 240 generated demos on all sixty maps (`gendemo.py`, `allmaps.py`) |
| music | identical to id's: the same register writes on the same ticks (`MUSICLOG`) |
| multiplayer | **works**: deathmatch and co-op, up to four players, bots, chat, scores, drop-in and drop-out, a server console; eight hours on the 486, the Pentium II and the V30 together without a desync (2026-10-13), every floor in co-op (2026-10-14); **the server on DOS or Windows too** (`MPSRV.EXE`, `MPSRVW.EXE`; v1.4, 2026-10-15/16), each DOS machine serving in turn -- the V30 as well -- without a desync |
| optimisations | 98 steps, each one measured, each one proven to draw id's picture -- [V30NOTES.md](V30NOTES.md) is the lab notebook, including the ideas that measured as nothing |
| detail switches | optional, any combination, none on by default -- below |

## Multiplayer

**Setting it up:** [SETUP.md](https://github.com/jdredd87/Wolf3D-V30/blob/multiplayer/SETUP.md) walks through it step by step -- each DOS machine onto the network, the game, a server on DOS, Windows or Python, joining, and what to do when something doesn't work.  The download has it as `SETUP.TXT`.

On the `multiplayer` branch (`WOLF3DM.EXE`); the download is `W3DMP.ZIP` on
the [releases page](https://github.com/jdredd87/Wolf3D-V30/releases).  One
machine runs the server; every player runs the game and joins it.  Machines
of any speed play together: the server keeps the clock at 17.5 steps a
second, every machine plays every step, and a slow one draws fewer pictures,
not a different game.

**Host** -- any one of three servers, with the same switches and the same
console:

| server | runs on | built by |
|---|---|---|
| `MPSRV.EXE` | any DOS machine with a packet driver, the plain 8086 up | `python mp/mkmpsrv.py` (Free Pascal) |
| `MPSRVW.EXE` | Windows, no Python needed | `python mp/mkmpsrv.py --windows` -- the same source |
| `mp/mpserver.py` | any PC with Python 3 | -- (the reference) |

```
MPSRV  --players 4 --mode dm --noenemies --itemrespawn 30
MPSRVW --players 4 --bots 1 --mode coop --skill 2 --map 0
python mp/mpserver.py --players 4 --mode dm --noenemies --itemrespawn 30
```

`MPSRV /?` (or `MPSRVW /?`) explains every option with its default, and
gives examples.

**The DOS server** (since v1.4) needs a packet driver and the machine's
address in mTCP's config or `C:\AI\NET.CFG`, as the game does; XMS keeps a
long game's history (without it, `MPSRV.HIS` on the disk), so a machine can
join hours into a game.  Its console is its keyboard, or any PC on its
network: `python mp/mpctl.py --host ADDRESS status`.  A DOS machine that
serves cannot also play.  Every DOS machine here has served a game -- the
8 MHz V30, the 486 and the Pentium II, the other two playing and bots filling
the slots: not one desync (MULTIPLAYER.md has the runs).

**The Windows server**: the console is its window, or `python mp/mpctl.py`
on the same PC (its console port answers on 127.0.0.1 only).  Windows
Firewall must let it in: allow it when Windows asks the first time, or a
rule for UDP 31992 does it -- but a prompt left unanswered makes a rule that
*blocks* it, and that one wins.  The Python server needs the same rule.

`--mode coop|dm`, `--noenemies`, `--ff off`, `--fraglimit N`,
`--timelimit MIN`, `--itemrespawn SECS`, `--bots N`, `--map N` (0-59),
`--skill 0-3`.  The game starts when the first player has loaded the level;
anyone who joins later replays the game so far at full speed, catches up,
and walks in.

**What "Catching up: N steps to go" means.**  The network never sends the
game itself -- no positions, no health, no map -- only every player's
controls, 17.5 times a second: a *step*.  Each machine plays the steps for
itself, and because Wolfenstein does exactly the same thing with the same
controls, every machine arrives at the same game.  That property has a name
-- the game is **deterministic**: the same start and the same inputs always
give exactly the same result, on any machine; its own attract-mode demos
are nothing but recorded key presses, played into the real game.  What it
takes to keep a network game that way, what broke it and how every machine
is checked, is in
[MULTIPLAYER.md, "How it works"](https://github.com/jdredd87/Wolf3D-V30/blob/multiplayer/MULTIPLAYER.md#how-it-works-one-game-worked-out-on-every-machine).
So a machine that joins
late, or that missed steps, cannot be *told* where everyone is: it has to
*play* there.  It plays every step since the first one, as fast as it can,
without drawing a picture or making a sound, and the box counts the steps
left; when it is within a few steps of the others it walks into the game,
and the other players see it arrive.  Its checksums are compared with the
ones the others reported for the same steps, so a machine that caught up
wrong is caught.

How long it takes is the length of the game so far over the machine's
speed.  A 486 or a Pentium II replays 1,500 to 12,000 steps a second -- an
hour of play (63,000 steps) in under a minute.  The V30 manages about 70 to
180 a second, because every step means running every player, every door and
every enemy on an 8 MHz CPU: joining a game an hour old takes it six to
fifteen minutes.  The same happens, for a moment, after a WiFi dropout or a
floor load: whatever a machine missed, it plays through quickly, the same
way.

**Play** (on each DOS machine, in `C:\WOLF3D` with the game data):

```
WOLF3DM NET 192.168.1.10 NAME STEVE
```

or `PLAY` and the menu's network page (`M`), which keeps the server and
your name in `WOLF3DM.CFG`.  **T** chats, **TAB** shows the scores, **ESC**
asks before leaving; dead, **SPACE** respawns.  A WiFi dropout of up to a
minute is ridden out ("No word from the server: N s") and the game catches up
when the link is back.

**The server's console** -- typed into its window while it runs:

| | |
|---|---|
| `status`, `scores` | every slot (who, from where, how far behind), and every player's frags and deaths |
| `say TEXT` | a message on every player's screen, as SERVER |
| `kick N reason`, `ban N`, `unban ADDR` | out of the game, and told why on their screen |
| `pause`, `resume` | hold the game for everyone |
| `map E L`, `nextfloor` | everyone to that floor now |
| `timelimit MIN`, `fraglimit N` | change the limits mid-game |
| `next map/mode/skill/bots/...` | settings for the next game |
| `end`, `quit` | end the game; stop the server |

Every machine applies a mid-game change at the same step, so the game stays
in lockstep -- for anyone joining later too.
[MULTIPLAYER.md](https://github.com/jdredd87/Wolf3D-V30/blob/multiplayer/MULTIPLAYER.md) has the design, the protocol and every
test.

## Running it

In `C:\WOLF3D` beside the game data:

```
WOLF3DV
```

Optional switches trade picture for speed, in any combination: `LOWWALLS`, `LOWSPRITES`, `FLATWALLS`, `FLATART`, `LOWVERT`, or `LOWDETAIL` for the first two (`WOLF3DV LOWDETAIL` is about 40% faster) -- see Status. `FARBLOBS` draws distant enemies and items (under 16 pixels high; `FARBLOBS n` sets the height) as flat shapes, each opaque run in the colour of its middle pixel: 11% faster on a 486 (69 -> 76 fps in play over the attract loop), but not on the V30, where a distant sprite is already cheap to draw -- it is for faster machines. `FASTOPL` writes the AdLib's registers with no waits between them: an emulated chip such as the PicoMEM's needs none, and the music is the same (the same 1,000 register writes on the same ticks, `MUSICLOG`), 0.75% faster on the V30 -- but a real OPL2 chip needs its waits, so it is off by default. Without them the game draws exactly what id's does.

**TAB shows the map** (2026-10-05, StevenC's idea): a top-down map of what has been explored -- the rooms you have entered and everything the view has seen, walls, doors in their keys' colours, items, the enemies you have a line of sight to, and you, with the way you face.  The game goes on under it: move, turn and fire as ever.  It is faster than the 3D view (7.1 fps on the V30's benchmark, against 5.0), and it never touches a demo, so the game is still id's exactly.  `AUTOMAP` starts with it on, demos included, for showing it.  The Pause key freezes the game with the map left in full view (id's PAUSED sign is not drawn over it); any key goes on.  In both versions.

`VIEW n` sets the window, id's own Change View sizes 4 to 19 (16n x 8n pixels; the game's default is 15, 240x120) -- full detail and id's picture, only less of it, and it combines with the switches. On the V30's benchmark: size 19 (304x152) 3.95 fps, 17 4.42, **15 4.99**, 13 5.69, 11 6.53, 9 7.75. It is saved with the game's config, as id's menu saves it.

Or type `PLAY` for a menu of them: a key turns each switch on or off (`A` all, `N` none), `+` and `-` pick the window size (`0` leaves it to the game), `P` plays, `B` runs the 200-frame benchmark with them, `Q` quits, and quitting the game comes back to the menu. It remembers the last choice (`W3MENU.CFG`), and with no key for 30 seconds it quits by itself (`PLAY /T:60` changes that, `/T:0` waits for ever, `/PLAY` makes it start the game instead). The menu is `W3MENU.EXE` (`launcher/w3menu.pas`, built with FPC by `w3dbuild.py deploy`); it writes the game's command line into `W3RUN.BAT` and exits before the game starts, so it takes none of the memory the game's page cache could use.

`SHOWCASE` is a demo reel for recording (2026-10-05): pick `V` (WOLF3DV), `B` (WOLF3DB, far walls in less detail), `T` (WOLF3DB with the BSP tree) `A` for all three in a row, or `C` to choose any combination (Y or N for each of V, B and T -- just `B` and `T`, say); then two questions, each answered for you after 15 seconds -- whether to start with id's code (Y) and whether to show the map too (N; the map's runs come last in each reel).  With Y it starts with **id Software's own 1992 code** (`WOLF3DO.EXE`: id's renderer and game code, rebuilt for the 8086 by `refsrc.py` -- id's own EXE needs a 286 -- with the same timing harness, and the same picture as WOLF3DV checksum for checksum), then every mode of the version: each a title screen saying what it shows and with which switches (8 seconds), three minutes of the game's demos with them (`TIMEDEMO PRELOAD SECS 180`, so a faster mode gets further; one minute, until 2026-10-05, left demo 0 near its start on a V30), and its speed report; at the end every run's speed together.  On the V30: id's code 2.81 fps, WOLF3DV 4.87, everything on 10.07, the map 7.46 -- `A` runs 29 segments, about an hour and 35 minutes (32 and an hour and 45 with the map); `V` alone about 40 minutes.  `S` skips a wait, `Q` quits.  `launcher/mkshow.py` writes the batch files; [BENCHMARKS.md](BENCHMARKS.md) has every option on both machines.

**Memory: XMS served out of EMS, the fastest setup on this machine** (step
29). An 8086-class PC has no memory above 1 MB, so it has no XMS of its own;
what the V30 has is the PicoMEM card's 4 MB of EMS. Two drivers StevenC and
Claude wrote for it turn that into XMS:

| | |
|---|---|
| [PMEMMSC](https://github.com/jdredd87/CH375USBTools/tree/main/PicoMEM/emm) | the PicoMEM's EMS driver, rebuilt: page mapping 45% faster, five EMS bugs fixed, loaded low (`CH375USBTools`, `PicoMEM/emm`) |
| [XMSSC](https://github.com/jdredd87/DOSBridge/tree/main/server/extras/xmssc) | an XMS 3.0 driver that hands out that EMS as XMS; on a PicoMEM it drives the card's page registers itself -- small moves 22% faster than the EMS driver's own move function (`DOSBridge`, an optional extra) |

Why XMS over EMS beats the EMS itself for this game: with EMS, id's page
manager maps textures into the 64 KB page frame and remaps its four slots
through INT 67h about nine times a frame, some 1.3 ms each on this card.
With XMS it copies a 4 KB page into its own cache in conventional memory once
-- XMSSC moving it straight off the PicoMEM -- and reads it there for as long
as it stays cached, so a texture used frame after frame costs nothing after
the first copy. The benchmark at step 29: 3.78 fps against 3.59 for id's
EMS-first setup. EMS is used only when there is no XMS, or when `EMS` asks
for id's original order; id's `NOEMS` and `NOXMS` still work. On the V30,
`CONFIG.SYS` loads `PMEMMSC.SYS /n` and then `XMSSC.SYS`. Everything else
is the game as id made it.

For measuring, `WOLF3DV TIMEDEMO QUICK PRELOAD` plays demo 0's first 200
frames flat out and prints the frame rate; `CRC` adds checksums of the picture,
`PROFILE` a sampled profile. It always measures the 240x120 view (size 15), whatever
size the game was left at; `VIEW n` measures that size, `MYVIEW` the one you left it at. [V30NOTES.md](V30NOTES.md) explains them all.

## Building

Borland C++ 3.1 and TASM 3.1, as id used. The compiler needs a 286, so it runs
on a 486 on the same DOS Bridge and the V30 only runs the result:

```
python w3dbuild.py bcpp      once: ship the Borland C++ subset to the 486
python w3dbuild.py all       build there, deploy WOLF3DV.EXE to the V30
```

[PIPELINE.md](PIPELINE.md) draws the whole of it: the PC, the three DOS
machines and what each one does, how a build is made, checked against id's
picture, timed and deployed, how the branches feed each other, and the
network game.

## This repository

| | |
|---|---|
| `v30-8086` | `WOLF3DV`, id's game exactly (default branch) |
| `bsp` | `WOLF3DB`, the BSP version |
| `multiplayer` | `WOLF3DM`, the network game, and its server (`mp/`) |
| `master` | id's source exactly as released, for diffing |
| `upstream` remote | https://github.com/id-Software/wolf3d |

`release/` is the playable package: `mkrelease.py` zips `WOLF3DV.EXE`, `WOLF3D8.EXE`, `WOLF3DB.EXE`, `WOLF3DO.EXE`, the menu, the demo reel, `release/README.TXT` and id's `LICENSE.DOC` into `release/W3DV30.ZIP` (not committed) -- no game data.

`bsp/` is step 86's proof of concept, a program apart from the game: `mkbsp.py` and `mktables.py` make its data from your own `GAMEMAPS.WL6` and `MAPHEAD.WL6`, and `bsptest.pas` builds with FPC as `starter/` does in DOS Bridge (`fpc -Tmsdos -Pi8086 -WmLarge -FEbuild -FUbuild bsptest.pas`, with the bridge's `starter` on the unit path for `VidFix`); run it in a directory holding `TABLES.DAT` and the four `BSPnn.DAT`.

The source is id Software's, under the licence in
[WOLFSRC/README/LICENSE.DOC](WOLFSRC/README/LICENSE.DOC); the game data is not
included and never will be.
