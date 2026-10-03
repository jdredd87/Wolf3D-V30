WOLFENSTEIN 3-D FOR 8086-CLASS PCs  --  optimized by StevenC and Claude
=======================================================================

id Software's Wolfenstein 3-D, rebuilt from id's released source to run
as fast as an 8086, 8088, V20 or V30 PC allows -- and faster on anything
better.  With no switches it draws exactly what id's own game draws,
pixel for pixel: every build is checked against id's renderer over the
attract-mode demos and over generated demos on all sixty maps.

On an NEC V30 (8086 class) the game runs about 1.9 times as fast as id's
WOLF3D.EXE: demo 0 at 5.2 frames a second instead of 2.75.  Optional
switches trade picture for speed, up to about 8 frames a second.

Source, notes and every measurement:
    https://github.com/jdredd87/Wolf3D-V30   (branch v30-8086)


WHAT YOU NEED
-------------
* The game data from the REGISTERED Wolfenstein 3-D, version 1.4 -- the
  *.WL6 files (VSWAP.WL6, VGAGRAPH.WL6, AUDIOT.WL6, GAMEMAPS.WL6 and the
  rest).  None of it is in this package; it is id's and you need your own.
  The shareware *.WL1 files will not work.
* An 8086 or better, VGA, DOS.  A coprocessor is not used.
* The free conventional memory id's own game wants; any more than that
  becomes page cache, and fewer pauses.
* XMS or EMS helps and is used if present (XMS first).


INSTALLING
----------
Copy the files from this package into the directory that holds your
*.WL6 files.  Nothing of id's is replaced: the game is WOLF3DV.EXE.


PLAYING
-------
    PLAY                the menu: pick switches and a window size, then play
    WOLF3DV             the game, as id made it
    WOLF3DV LOWDETAIL   ... with switches (any combination):

    LOWWALLS     walls in two-pixel columns
    LOWSPRITES   enemies and items in two-pixel columns
    LOWDETAIL    both of the above
    FLATWALLS    every wall one solid colour (its texture's average),
                 artwork kept
    FLATART      artwork walls solid too
    LOWVERT      half the vertical resolution
    FARBLOBS [n] distant enemies and items (under n pixels high, 16)
                 as flat shapes -- 11% faster on a 486, but not on
                 a V30, where far sprites are already cheap
    FASTOPL      no waits between AdLib writes -- for an emulated
                 AdLib such as the PicoMEM's (0.75% faster); a real
                 OPL2 chip needs the waits, so leave it off there
    VIEW n       the window size, 4 to 19 (id's Change View; 15 is
                 240 x 120).  Full detail, just smaller

  On a V30, frames a second (demo 0's first 200 frames):

    none (id's picture)   5.0     LOWDETAIL           7.1
    LOWSPRITES            5.2     LOWWALLS            6.7
    FLATWALLS             5.7     LOWDETAIL FLATWALLS 7.4
    LOWVERT               5.8     LOWDETAIL FLATWALLS
                                    LOWVERT           8.1
    VIEW 13 (208 x 104)   5.7     VIEW 11 (176 x 88)  6.5

PLAY's menu: a letter turns a switch on or off (D is FARBLOBS, O is
FASTOPL), + and - pick the window size (0 leaves it to the game), P plays,
B runs the benchmark, Q quits. Quitting the game comes back to the menu.
It remembers your choice in W3MENU.CFG, and quits by itself after 30
seconds with no key (PLAY /T:60 changes that, /T:0 waits for ever).

SHOWCASE runs a demo reel of every mode, a minute each, with the speed
of each -- made for recording a video.  S skips a wait, Q quits.


MEASURING
---------
    WOLF3DV TIMEDEMO QUICK PRELOAD    demo 0's first 200 frames, flat out
    WOLF3DV TIMEDEMO PRELOAD          all four demos

Add switches to measure them; CRC adds checksums of the picture.


MEMORY ON A PICOMEM
-------------------
On an 8086-class PC with a PicoMEM card, the fastest setup found is XMS
served out of the card's EMS -- two drivers StevenC and Claude wrote:
    PMEMMSC   https://github.com/jdredd87/CH375USBTools  (PicoMEM/emm)
    XMSSC     https://github.com/jdredd87/DOSBridge     (extras/xmssc)
loaded low in CONFIG.SYS:
    device=c:\drivers\pmemmsc.sys /n
    device=c:\drivers\xmssc.sys


CREDITS AND LICENCE
-------------------
Wolfenstein 3-D is id Software's.  Its source is used under id's licence,
LICENSE.DOC in this package: free, and never for money.  This package has
none of id's game data.

The V30 work -- 92 measured steps, the detail switches, the menu -- by
StevenC and Claude (Anthropic), 2026.  Written by StevenC and Claude.
