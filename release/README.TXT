WOLFENSTEIN 3-D FOR 8086-CLASS PCs  --  optimized by StevenC and Claude
=======================================================================
Version 1.6, 2026-10-16

id Software's Wolfenstein 3-D, rebuilt from id's released source to run
as fast as an 8086, 8088, V20 or V30 PC allows -- and faster on anything
better -- for the registered game and, since 1.6, the free shareware
episode.  Six programs:

    WOLF3DV.EXE   id's game and id's picture exactly, from faster code:
                  every build is checked against id's renderer over the
                  attract-mode demos and generated demos on all sixty
                  maps.  1.8 times id's speed on an NEC V30.  Needs a
                  V20/V30, an 80186/188, or a 286 or better.
    WOLF3D8.EXE   the same game for a plain Intel 8086 or 8088, which
                  WOLF3DV refuses: every 80186 instruction written the
                  8086 way, id's picture exactly, the same switches.  On
                  anything newer, use WOLF3DV.
    WOLF3DB.EXE   the faster version: far walls drawn in less detail,
                  near walls and every edge exact.  The BSP switch draws
                  the walls with a BSP tree, the way the SNES port did.
    WOLF3DO.EXE   id Software's own code -- id's renderer and game code,
                  rebuilt for the V20/V30 and 186 (id's WOLF3D.EXE needs
                  a 286) -- for comparing speeds.  The same picture as
                  WOLF3DV.
    WOLF3D1.EXE   WOLF3DV for the SHAREWARE episode (the free *.WL1
                  files of version 1.4): the same code with id's own
                  shareware settings, id's picture exactly.
    WOLF3D18.EXE  the same for a plain 8086 or 8088.

WOLF3DV, WOLF3D8, WOLF3DB and WOLF3DO need the registered *.WL6 files;
WOLF3D1 and WOLF3D18 need the shareware's *.WL1.  PLAY picks the right
one by itself.

On an NEC V30 (8086 class), demo 0 at full detail runs at 2.8 frames a
second in id's code, 5.0 in WOLF3DV, 5.3 in WOLF3DB; the detail switches
go up to 9.2, and the map (TAB) runs at 7.1.

Source, notes and every measurement (BENCHMARKS.md has every option on
an NEC V30 and a 486):
    https://github.com/jdredd87/Wolf3D-V30   (branch v30-8086; the BSP
                                              version on branch bsp)
id Software's original source:
    https://github.com/id-Software/wolf3d

New in 1.5: WOLF3D8.EXE, for a plain Intel 8086 or 8088 (WOLF3DV needs
the 80186 instructions a V20/V30 has) -- id's picture exactly, about 2%
slower than WOLF3DV on a V30.  Two fixes: a far call in the sprite
scaler that worked only by luck (it froze a 486 once), and, with
FLATWALLS, a wall's artwork kept in memory while its plain twin is
fetched.  WOLF3DV, WOLF3D8 and WOLF3DB were checked again over the
whole attract loop.

New in 1.6: the shareware episode.  WOLF3D1 and WOLF3D18 play the free
shareware Wolfenstein 3-D 1.4 (Episode 1, "Escape from Wolfenstein", ten
floors), checked against id's renderer built the same way: the attract
loop, and generated demos on all ten floors.  WOLF3D1 runs the shareware's
demo at 5.0 frames a second on an 8 MHz V30.  PLAY now runs in whatever
folder it is started from (before, it always went to C:\WOLF3D).

The network game -- up to four players, deathmatch or co-op, a server
for DOS, Windows or Python -- is its own download, W3DMP.ZIP, on the
same releases page; SETUP.md (in the repository) sets it up step by step.


WHAT YOU NEED
-------------
* Wolfenstein 3-D's game data, version 1.4 -- none of it is in this
  package; it is id's:
    - the REGISTERED game's *.WL6 files (VSWAP.WL6, VGAGRAPH.WL6,
      AUDIOT.WL6, GAMEMAPS.WL6 and the rest) for all six episodes, or
    - the free SHAREWARE episode's *.WL1 files.  The shareware is free to
      copy: it is 1WOLF14.ZIP, on most DOS game archives (for one,
      https://www.dosgamesarchive.com/download/wolfenstein-3d).  Unzip it
      and run its INSTALL: it puts the game's files in the folder you
      choose.  On an 8086 or V30 it says the game needs a 286 and asks
      whether to install anyway (id's game did; these builds do not).
* An 8086 or better, VGA, DOS.  A coprocessor is not used.  On a plain
  Intel 8086 or 8088, run WOLF3D8 (WOLF3D18 for the shareware);
  WOLF3DV, WOLF3D1, WOLF3DB and WOLF3DO need the 80186 instructions a
  V20/V30, a 186 or a 286 has.
* The free conventional memory id's own game wants; any more than that
  becomes page cache, and fewer pauses.
* XMS or EMS helps and is used if present (XMS first).


INSTALLING
----------
Copy the files from this package into the directory that holds your
*.WL6 (or *.WL1) files.  Nothing of id's is replaced.


PLAYING
-------
    PLAY                the menu: pick a version, switches and a window
                        size, then play
    WOLF3DV             the game, as id made it
    WOLF3DB             the faster version
    WOLF3D1             the shareware episode
    WOLF3DV LOWDETAIL   ... with switches (any combination, either
                        version):

    LOWWALLS     walls in two-pixel columns
    LOWWALLS4    walls in four-pixel columns
    LOWSPRITES   enemies and items in two-pixel columns
    LOWDETAIL    LOWWALLS and LOWSPRITES
    FLATWALLS    every wall one solid colour (its texture's average),
                 artwork kept
    FLATART      artwork walls solid too (the elevator switch -- the way
                 out of a level -- turns magenta, so it can be found)
    LOWVERT      half the vertical resolution
    FARBLOBS [n] distant enemies and items (under n pixels high, 16)
                 as flat shapes -- for faster machines
    FASTOPL      no waits between AdLib writes -- for an emulated
                 AdLib such as the PicoMEM's; a real OPL2 chip needs
                 the waits, so leave it off there
    VIEW n       the window size, 4 to 19 (id's Change View; 15 is
                 240 x 120).  Full detail, just smaller

  WOLF3DB only:
    NOLOD        far walls at full detail: id's picture
    BSP          the walls found by a BSP tree instead of id's rays
                 (slower on an 8086: the rays are cheaper on Wolf's
                 grid maps; the wall switches above use the rays)

  In the game:
    TAB          the map: what you have explored -- the rooms you
                 have entered, walls, doors (in their keys' colours),
                 items, the enemies you can see, and you.  The game
                 goes on under it: move and fire as ever.  It is
                 faster than the 3D view
    PAUSE        with the map up, the game freezes and the map stays
                 in full view; any key goes on

  On an NEC V30, frames a second in play (demo 0's first 200 frames):

    WOLF3DO (id's own code)   2.8     LOWWALLS4            8.4
    WOLF3DV (id's picture)    5.0     LOWDETAIL            7.1
    WOLF3DB                   5.3     all eight switches   9.2
    WOLF3DB BSP               4.5     the map (TAB) up     7.1
    LOWWALLS                  6.7     LOWVERT              5.8
    FLATWALLS                 5.6     LOWSPRITES           5.2
    WOLF3D8 (plain 8086)      4.9

PLAY's menu: a letter turns a switch on or off (D is FARBLOBS, O is
FASTOPL, 4 is LOWWALLS4), T picks WOLF3DV or WOLF3DB, and for WOLF3DB
K is BSP and L is NOLOD.  On a plain 8086 or 8088 the menu runs
WOLF3D8 by itself.  + and - pick the window size (0 leaves it to
the game), P plays, B runs the benchmark, Q quits.  Quitting the game
comes back to the menu.  It remembers your choices in W3MENU.CFG, and
quits by itself after 30 seconds with no key (PLAY /T:60 changes that,
/T:0 waits for ever).


THE SHOWCASE
------------
    SHOWCASE    a demo reel for recording a video.  Pick V (WOLF3DV),
                B (WOLF3DB), T (WOLF3DB with the BSP tree), A (all
                three, about an hour and a half on a V30) or C, to
                choose any of the three one by one.  Then two
                questions, answered for you after 15 seconds: start
                with id's own code, for its speed (Y), and show the
                map too (N).  Every mode of the version follows: a
                title screen saying what it shows, three minutes of
                the game's demos, and its speed; at the end, every
                run's speed together.  S skips a wait, Q quits.


MEASURING
---------
    WOLF3DV TIMEDEMO QUICK PRELOAD    demo 0's first 200 frames, flat out
    WOLF3DV TIMEDEMO PRELOAD          all four demos
    WOLF3DV TIMEDEMO PRELOAD SECS 60  the demos for 60 seconds

Add switches to measure them; CRC adds checksums of the picture;
AUTOMAP shows the map over the demos (for showing it -- a demo with
the map up may wander from its recording).


MEMORY ON A PICOMEM
-------------------
On an 8086-class PC with a PicoMEM card, the fastest setup found is XMS
served out of the card's EMS -- two drivers StevenC and Claude wrote:
    PMEMMSC   https://github.com/jdredd87/CH375USBTools  (PicoMEM/emm)
    XMSSC     https://github.com/jdredd87/DOSBridge     (extras/xmssc)
loaded low in CONFIG.SYS:
    device=c:\drivers\pmemmsc.sys /n
    device=c:\drivers\xmssc.sys


HOW IT WAS MADE
---------------
Built with Borland C++ 3.1 and Turbo Assembler -- the tools id used --
on a 486, and measured on an NEC V30 with an 8087, MS-DOS 6.22 and a
PicoMEM 2 card, every build and test sent to both machines over WiFi
with DOS Bridge (https://github.com/jdredd87/DOSBridge).  About a
hundred measured steps: the renderer, the sprite scaler, the game's
logic and the sound in 8086 assembly, each step kept only if it was
faster, and checked against id's renderer by checksums of the picture.


CREDITS AND LICENCE
-------------------
Wolfenstein 3-D is id Software's.  Its source is used under id's licence,
LICENSE.DOC in this package: free, and never for money.  This package has
none of id's game data.

The V30 work -- the optimisations, the detail switches, the faster
version, the BSP renderer, the map, the menu and the showcase -- by
StevenC and Claude (Anthropic), 2026.  Written by StevenC and Claude.
