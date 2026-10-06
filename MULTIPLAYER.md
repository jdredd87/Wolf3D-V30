# Multiplayer -- a plan, not yet started

Written by **StevenC** and **Claude** (Anthropic), 2026-10-06.  Parked
until the 386SX's network card arrives; nothing here is built yet.

id never shipped multiplayer for the DOS game.  The idea: two or more
real DOS machines -- the NEC V30, the 486, and the 386SX/25 once it is
back -- playing one game over UDP/IP, through the PicoMEMs' WiFi or any
card with a packet driver.  It gets its own branch and its own EXE
(working name `WOLF3DM.EXE`), like `bsp`; `v30-8086` stays id's game
exactly, and merges flow only from it.

## The model: lockstep, with a server keeping the clock

Every machine runs the whole game itself; only each player's controls
cross the network -- the way DOOM did it.  That needs the game to be
deterministic, and Wolf3D's demos prove it is: a demo is nothing but
recorded controls (3 bytes a step), and the same build plays the same
game on the V30 and the 486, checksum for checksum.

**The server** -- a third program, game-agnostic -- runs the clock.
Each step it takes the *latest* controls it has from each player, never
waiting for anyone, stamps them with the step number and sends the merged
list to every machine, which plays it exactly as it plays a demo.  So:

| problem | handled by |
|---|---|
| machines of different speeds | the server never waits: a slow machine only slows itself. The V30 catches up ~3 steps a frame (game logic is 2-3% of a frame) and draws the last |
| WiFi jitter and loss | every packet repeats the last few steps' controls; a client that missed a step asks again; a late player keeps their previous controls for that step |
| network delay (key to screen) | not hidden by the server. Measure it first (phase 2); add local prediction only if it is felt -- it needs saving and rewinding game state, costly on a V30 |
| who hit whom | free: everyone plays the same list, so everyone agrees |

Rejected: a server that runs the game and sends state (Quake-style).
Kilobytes of state an update, the game logic ported to the server, and
the DOS game cut down to a renderer.

## Facts from the source that shape it

* **The step is fixed at 4 tics** (`DEMOTICS`, `ID_HEADS.H`): demos
  advance in steps of 4/70 s, 17.5 a second, which is why every machine
  plays the same 5,386 frames of the attract loop.  Normal play instead
  advances by the frame's own `tics`, capped at `MAXTICS` 10 -- so on the
  V30 (5 fps, ~14 tics a frame) single-player runs slower than real time.
  Multiplayer uses the demo path: 17.5 steps a second, set by the server.
  The 486 then gets a new game state 17.5 times a second; it can redraw
  in between, or smooth the view.
* **`player` and `gamestate` are single globals** (health, ammo, keys,
  weapons, the face) used everywhere.  They become per player; the camera
  follows the local one.
* **The AI targets `player`** -- sight, chase, attack, and `areabyplayer`
  (which areas wake up).  It has to choose a target: nearest, or the one
  in sight.
* **`GunAttack` decides hits from what was just drawn** (`FL_VISABLE`,
  `viewx`).  The other machines never draw your view, so they would
  disagree.  Hits need an analytic test from the shooter's position, the
  same on every machine.  Bonus: then each machine can run its own
  renderer and detail switches (the V30 on LOWDETAIL, the 486 at full)
  and still stay in step.
* **Sound reaches the game's random numbers**: `UpdateFace` skips its
  `US_RndT` calls while the gatling pickup sound plays (why `TIMEDEMO CRC`
  turns effects off).  Anything local -- face, sound, the map -- gets its
  own random numbers.  Audit for others.
* **No player sprite.**  Recoloured guard sprites; BJ's running frames
  (the victory sequence) exist but only from behind.
* **DGROUP has ~12 bytes spare** on `v30-8086`: every new variable and
  buffer goes in a far segment.  Packet buffers and code cost a few KB of
  page cache.
* **Speed**: the V30 is a 5 fps game, and in multiplayer it will feel like
  one -- LOWDETAIL (7) or all switches (9) help.  The others are not held
  back by it.

## Rules

* **Co-op** works on id's maps as they are: shared doors and pickups,
  everybody at the elevator to finish.
* **Deathmatch** needs spawn points (`gendemo.py` already finds random
  open tiles), respawning, frags, and players made shootable.

## The network layer in the game

* The packet driver interface (`INT 60h` here: `PM2000` on both PicoMEMs;
  any card's driver on the 386SX).  Nothing PicoMEM-specific.
* A small IPv4/UDP layer in TASM, ~1-2 KB.  mTCP is Open Watcom, the game
  Borland C++ 3.1: not linkable.  The design is the bridge's FPC stack
  (`C:\dosbridgeDEV\starter\net.pas`), whose lessons are in
  `docs/network.md` there -- above all, **answer ARP**, or unicast stalls.
* Broadcast UDP finds the server with no ARP at all (`KNET`'s keys had to
  be broadcast -- `knet.md` says why).  A UDP port of its own, not dosd's
  8069.

## Protocol (draft)

Little-endian, one UDP datagram each, every one carrying a version byte.

| packet | from | carries |
|---|---|---|
| `HELLO` | client | name, build CRC, wanted player slot |
| `WELCOME` | server | slot, players, map, skill, rules, start step |
| `INPUT` | client | slot, the steps it covers, controls for the last N steps (redundant) |
| `STEPS` | server | first step number, the merged controls of every player for the last N steps |
| `RESEND` | client | the first step it is missing |
| `SYNC` | client | step number, game-state checksum (actors, doors, player states) |
| `DESYNC` | server | the step at which two checksums differed, to every client |
| `BYE` | either | leaving |

The server keeps every `STEPS` it sent: the match is a multiplayer demo,
replayable and checkable afterwards.

## Two servers, one protocol

* **Python, on the Windows PC** -- written first, the reference: quick to
  change, logs everything, saves the match.  ~200-300 lines.
* **Free Pascal, on a DOS machine** -- the bridge's own network units
  (packet driver, ARP, UDP, the fast checksum), built for the plain 8086,
  so any box can be the server.  ~500-800 lines.  Two DOS details: its
  clock reads the PIT (the BIOS tick is 55 ms, a step 57 ms) or speeds
  the timer to 70 Hz as Wolf3D does; and it shows a **clock-driven status
  line** on screen, so "alive, nobody connected" never looks like a hang.
  The 386SX/25 is meant to be its box -- the whole thing on real MS-DOS
  machines.

Both are tested by a **fake-player program in Python** (as
`simulate_dos.py` does for the bridge): recorded controls, with injected
delay and loss, against either server, checking that every player got the
same list.  The FPC server can be tested on the 486 over the bridge before
the 386SX arrives.

## The 386SX coming back

* Its old SD card is the 486's boot disk now (`dx486`): it needs a boot
  disk of its own -- a plain network card is not a disk, as the PicoMEM was.
* A packet driver for the new card; the bridge's client kit; an entry in
  `boxes.json` (`C:\dosbridgeDEV\docs\multibox.md`, Part 1).
* Old lessons from it still hold: FPC programs need `VidFix` (no 387), and
  `SHELL=C:\COMMAND.COM C:\ /E:1024 /P` in `CONFIG.SYS` or bridge jobs
  lose their exit codes.  Its BIOS will not take a year past 2010.
* Wired while the others are on WiFi: broadcasts should still cross (one
  home network); the phase 2 test confirms it on day one.

## Phases -- each one proven before the next

1. **Two players, no network.**  The game with players[], AI targets,
   analytic hits, local random numbers split off.  A *two-player demo*
   (both players' controls, recorded or generated) played back on the V30
   and the 486 must give the same game-state checksums every step.  This
   settles whether the whole idea holds, and it is the biggest piece.
2. **The wire.**  A ping-pong of controls between the boxes: real delay
   and loss through the PicoMEMs' WiFi, broadcast across WiFi and wired.
3. **The Python server** and the fake players.
4. **Lockstep in the game**, against the Python server, with `SYNC`
   checks.  First real test under the bridge: both boxes run the same
   recorded match with nobody at a keyboard, and their checksums are
   compared.
5. **The FPC server**, tested on the 486, then moved to the 386SX.
6. **Rules and polish**: the other player's sprite, co-op and deathmatch,
   spawn points, a menu (W3MENU), and prediction only if phase 2 says so.

## Open questions

* Co-op first, or deathmatch?
* How many players -- 2, or 4?
* Does the 486 smooth the view between steps, or just redraw?
* Which UDP port?
* The exit when one player dies in co-op: respawn at the start, or wait?
