# Multiplayer -- a plan, not yet started

Written by **StevenC** and **Claude** (Anthropic), 2026-10-06.  Parked
until the 386SX's network card arrives; nothing here is built yet.

id never shipped multiplayer for the DOS game.  The idea: up to four
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
* **No player sprite in play** -- but BJ himself is in the data, at
  sprite size: the victory sequence's `SPR_BJ_W1`-`W4` (a four-frame run,
  **facing the viewer**) and `SPR_BJ_JUMP1`-`4` (a leap, arms up).  See
  "The players' look" below.  (An earlier draft said they show him from
  behind; extracting them showed they do not.)
* **DGROUP has ~12 bytes spare** on `v30-8086`: every new variable and
  buffer goes in a far segment.  Packet buffers and code cost a few KB of
  page cache.
* **Speed**: the V30 is a 5 fps game, and in multiplayer it will feel like
  one -- LOWDETAIL (7) or all switches (9) help.  The others are not held
  back by it.

## Modes and rules -- exactly as DOOM does it (StevenC, 2026-10-06)

**The rule: multiplayer behaves like DOOM's.**  Where DOOM has an answer,
that is the answer; only what Wolf3D has and DOOM does not (lives,
treasure, a boss who drops the key, a map with one player start) needs a
decision of our own, and those follow DOOM's spirit.  **Up to 4 players**,
DOOM's `MAXPLAYERS`.

Two modes, each **with enemies or without** (`NOENEMIES`, DOOM's
`-nomonsters`).  The server sends the rules in `WELCOME`, so every machine
plays the same ones -- they are part of the game state, and the checksum
would catch a mismatch.

| | co-op | deathmatch (DOOM's "deathmatch 1.0") | `ALTDEATH` (DOOM's "deathmatch 2.0") |
|---|---|---|---|
| goal | the level, together | frags, to `FRAGLIMIT` / `TIMELIMIT` | the same |
| the exit | **any** player at the elevator ends the level for everyone | does nothing; a limit ends the level | the same |
| a player dies | presses use (or fire) to respawn at **their own** player start, with a pistol and **50 bullets** (DOOM's figure; Wolf3D's own 8 is thin); the level stays as it was | respawns at a **random deathmatch start**, pistol and 50 bullets | the same |
| lives | none: respawns are unlimited (DOOM has no lives) | none | none |
| keys | **one player picks a key up, every player has it** (StevenC, 2026-10-06 -- here we part from DOOM, which leaves a netgame's keys in the map for each player to take) | **everyone starts with both keys** (DOOM gives all keys in deathmatch) | the same |
| weapons | **stay**: each player can take each weapon once | stay | **taken**, and respawn after 30 s |
| other items (ammo, food, first aid, treasure, extra life) | taken, as single player | taken, never back | **respawn after 30 s** (525 steps) |
| enemies | they look for each player in turn, and turn on whoever hurt them (DOOM's `P_LookForPlayers` and retaliation) | the same, when on | the same, when on |
| score | per player; treasure and kills counted per player | frags; a suicide is -1 | frags |

Options on top, DOOM's switches:

* `NOENEMIES` -- no actor is spawned from the map but players.  Wolf3D's
  own problem: **boss levels** -- Hans and Gretel drop the gold key, the
  last bosses end the episode.  With no enemies, the key is placed where
  the boss stood, and an episode's last level opens its exit (decided:
  DOOM would leave such a level unfinishable, and that is no fun).
* `RESPAWNENEMIES` -- DOOM's `-respawn`: a dead enemy stands up again at
  its start, about 12 seconds later, as DOOM's monsters do.
* `FASTENEMIES` -- DOOM's `-fast`, if it is cheap: enemies move and fire
  faster.  Optional.
* `FRAGLIMIT n`, `TIMELIMIT n` (minutes), skill (Wolf3D's four levels) and
  the starting map, as now.

**Player starts.**  A Wolf3D map has one; DOOM's have four (and
deathmatch starts besides).  Co-op: the other three are generated beside
the map's own start, on open tiles facing the same way.  Deathmatch: a set
of generated starts (`gendemo.py` already finds open tiles), far from each
other and outside locked areas; a spawn picks one at random from the
game's own random numbers, and DOOM's rule applies -- never one where
another player stands.

**The players' look: BJ, every angle, one gun** (StevenC, 2026-10-06:
not guards -- "playing as Nazis doesn't sit well"; all eight views from
the start; one gun in hand whatever he carries, as DOOM's players).
**Drafted -- `mp/mkbj.py`, branch `multiplayer`.**

The body comes from the **SS**: the one figure in the game with the full
set a DOOM-style player needs, *and his gun in every frame* -- 8 standing
views, 4 walking frames in 8 views, 3 firing, 2 pain, 3 dying and a body,
49 frames, at exactly the scale of everything else.  Repainted into BJ:

* **the cap becomes BJ's orange hair** -- down each column from the top
  of the head, the cap's blues and its black band mapped by brightness
  onto the palette's orange ramp (56-63; BJ's own hair is 59 and 61),
  stopping at the first pixel that is not cap, and at an eye (a blue
  pixel with skin either side -- the brim sits right on the eyes in the
  front views, and the first draft gave him an orange visor);
* **the uniform stays in the SS blue ramp (140-159)** in the built
  sprite: no other part of him uses those colours, so the game translates
  that one ramp per player at draw time, DOOM's way -- BJ's own grey for
  player 1 (palette 18-30, a shade lighter than his 20-31), and any of
  the palette's other 16-step ramps for the others: green 97-111, red
  33-47, brown 208-223.  **Decided (StevenC, 2026-10-06): player 1 grey,
  2 green, 3 red, 4 brown**, DOOM's order where it overlaps.  One 256-byte table
  a player, a colour-translating path in the asm sprite scaler, no extra
  sprite memory;
* **kept**: the gun, the face, the near-black blues of boots and shadow
  (227/228/232 -- BJ's own sprite uses the same), the harness.

The previews (`stage/mp/bj_*.png`, from `python mp/mkbj.py WL6FOLDER`)
read as BJ at every angle.  Still to do: the built sprites written to a
file `WOLF3DM` loads (`mp/wl6art.py` reads VSWAP's sprite format; writing
it is next), the scaler's translation path, and a look in the game.  BJ's own
pictures stay for the HUD and tables: the status-bar faces (`FACE1A`...)
one per player on the frag table and the co-op tally, in their colours.

**id's art is never committed** -- the repo is public.  The tool builds
the sprites on the player's own machine from their own `VSWAP.WL6` (as
the BSP version writes `BSPCACHE.WL6`); only the code is in the
repository, and `stage/`, where the previews land, is git-ignored.

**Between levels**, DOOM's intermission: co-op shows every player's
kills, items and secrets; deathmatch the frag table (who killed whom).
Wolf3D's own level-end screen becomes that table.

**Also as DOOM**: the status bar is the local player's; a message line
says who fragged whom; and **chat**, below.

## Chat, as DOOM's (StevenC, 2026-10-06)

* **`T` starts a message to everyone**; the line being typed shows at the
  top of the view; Enter sends, Escape drops it.  While typing, the
  player's keys type instead of moving them -- their controls go out as
  "standing still", as DOOM's do.
* **Everyone sees it** at the top of the view -- `BJ2: door's over here`
  -- for a few seconds, with a short sound, the last few lines scrolling.
  The same line carries the game's own messages: who fragged whom, who
  joined and left.
* **Names**: each player's name travels in `HELLO`; W3MENU sets it, and
  the default is `Player 1`-`4`.  The name shows in the player's colour.
* Optional, as DOOM: **macros** -- Alt+0-9 send ten preset lines from the
  config file; and DOOM's colour keys to talk to one player only
  (`G`, `R`, `B` for green, red, brown -- here `T` then a number would be
  plainer).

**Not in the lockstep stream.**  DOOM sent chat one character a tic inside
the controls; a chat message changes nothing in the game, so here it is
its own packet, `CHAT`, sent to the server, which stamps it, sends it to
every player and keeps it in the match record.  Resent until the server
acknowledges it, so WiFi loss cannot drop a line; a whole message arrives
at once rather than a letter a step.

**The keyboard needs a queue.**  Wolf3D's keyboard handler keeps only the
*last* key typed (`LastASCII`, `ID_IN.C`).  At the V30's 5 frames a
second, anyone typing faster than 5 letters a second would lose letters --
so the INT 9 handler gets a small ring of typed characters (16 is
plenty), read each frame while a message is being typed.  The same ring
serves W3MENU-style name entry.

**Drawing** is the automap's trick: text over the finished 3-D view, on
the page about to be shown, with the game's own font -- a line or two of
characters, nothing measurable even on the V30.

## The network layer in the game

* The packet driver interface (`INT 60h` here: `PM2000` on both PicoMEMs;
  any card's driver on the 386SX).  Nothing PicoMEM-specific.
* A small IPv4/UDP layer in TASM, ~1-2 KB.  mTCP is Open Watcom, the game
  Borland C++ 3.1: not linkable.  The design is the bridge's FPC stack
  (`C:\dosbridgeDEV\starter\net.pas`), whose lessons are in
  `docs/network.md` there -- above all, **answer ARP**, or unicast stalls.
* Broadcast UDP finds the server with no ARP at all (`KNET`'s keys had to
  be broadcast -- `knet.md` says why).
* **UDP port 31992 by default, and changeable** (StevenC, 2026-10-06).
  Checked against IANA's registry (2026-10-06): inside the unassigned
  block 31950-32033, and clear of the ports games and common programs are
  known to use -- Steam's 27000s, Quake's 26000, Minecraft's 25565,
  ZDoom's 5029, Chocolate Doom's 2342, Zandronum's 10666, Xbox's 3074,
  and the bridge's own 8069.  Below 32768, so Windows (49152 and up) and
  Linux (32768 and up) never hand it out as an ephemeral port.  The 1992
  is Wolf3D's year.  To change it, the same number goes to every piece:
  `PORT n` on the game (and a W3MENU field), `--port n` on the Python
  server, `PORT n` on the DOS server; a client and a server on different
  ports simply never meet, so the server prints its port on screen and
  the game says which port it is looking on while it waits.

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
| `CHAT` | client | sender slot, message number (for the acknowledgement), up to 60 characters |
| `CHATMSG` | server | the sender's name and colour, the text -- to every player; acknowledges the sender |
| `BYE` | either | leaving |

The server keeps every `STEPS` it sent: the match is a multiplayer demo,
replayable and checkable afterwards.

## Two servers, one protocol

* **Python, on the Windows PC** -- written first, the reference: quick to
  change, logs everything, saves the match.  ~200-300 lines.  **It needs an inbound
  Windows Firewall rule for its UDP port** (31992, or whatever `--port`
  says), scoped to the LAN -- the bridge's own `dosfirewall.cmd` exists
  because a missing rule once silenced both boxes and looked nothing like
  a firewall (`C:\dosbridgeDEV\CLAUDE.md`).  Add the rule the same way,
  or have the server check for it and say so.
* **Free Pascal, on a DOS machine** -- the bridge's own network units
  (packet driver, ARP, UDP, the fast checksum), built for the plain 8086,
  so any box can be the server.  ~500-800 lines.  Two DOS details: its
  clock reads the PIT (the BIOS tick is 55 ms, a step 57 ms) or speeds
  the timer to 70 Hz as Wolf3D does; and it shows a **clock-driven status
  line** on screen, so "alive, nobody connected" never looks like a hang.
  The 386SX/25 is meant to be its box -- the whole thing on real MS-DOS
  machines.

**Every machine gets a turn as the server** (StevenC, 2026-10-06), to
prove the FPC server is not tied to one CPU -- and a DOS box serving can
not also play (one program at a time), so trials 2-4 are two machines
playing -- and the Python fake player (below) can join any trial as a
third or fourth player, since it plays recorded controls:

| trial | server | players |
|---|---|---|
| 1 | Windows (Python) | V30 + 486 (+ 386SX when it is back) |
| 2 | V30 (FPC) | 486 + 386SX |
| 3 | 486 (FPC) | V30 + 386SX |
| 4 | 386SX (FPC) | V30 + 486 |
| 5 | Windows (Python) | **all three DOS machines at once**, plus a fake player as the fourth |

The V30 as a server is the interesting one: its job is a few small
packets every 57 ms, which an 8086 can do, but it is the proof that the
server costs nothing.  Each trial uses the same recorded match where it
can, so the servers' merged lists can be compared byte for byte.

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
* **It has a 387 now** (StevenC, 2026-10-06).  The game does not use one
  (Wolf3D is all integer), but it retires the 386SX's worst old fault:
  FPC's INT 10h hook only wedged it because there was *no* coprocessor,
  and `VidFix` steps aside when it sees one.  Run `FPU.EXE` to confirm
  when it is back.  It is 4-5x the V30 on every `BENCH` row -- between
  the V30 and the 486.
* Other old lessons still hold: `SHELL=C:\COMMAND.COM C:\ /E:1024 /P` in
  `CONFIG.SYS`, or bridge jobs lose their exit codes; and its BIOS will
  not take a year past 2010.
* Wired while the others are on WiFi: broadcasts should still cross (one
  home network); the phase 2 test confirms it on day one.

## Phases -- each one proven before the next

1. **Two to four players, no network.**  The game with players[], AI targets,
   analytic hits, local random numbers split off.  A *two-player demo*
   (every player's controls, recorded or generated) played back on the V30
   and the 486 must give the same game-state checksums every step.  This
   settles whether the whole idea holds, and it is the biggest piece.
2. **The wire.**  A ping-pong of controls between the boxes: real delay
   and loss through the PicoMEMs' WiFi, broadcast across WiFi and wired.
3. **The Python server** and the fake players.
4. **Lockstep in the game**, against the Python server, with `SYNC`
   checks.  First real test under the bridge: both boxes run the same
   recorded match with nobody at a keyboard, and their checksums are
   compared.
5. **The FPC server**: each DOS machine in turn as the server (trials 2-4
   above), then all three playing with Windows serving (trial 5).
6. **Modes, rules and chat**: co-op and deathmatch, each with and without
   enemies; `RESPAWNITEMS`, `WEAPONSSTAY`, `RESPAWNENEMIES`, frag and time
   limits; spawn points; the other player's sprite; chat and the
   message line, with the keyboard queue; W3MENU keys; and
   prediction only if phase 2 says so.  Each rule is proven like the rest:
   a recorded match, the same checksums on every machine.

## Open questions

* Co-op first, or deathmatch?  (Co-op with enemies is closest to the game
  as it is.)
* Does the 486 smooth the view between steps, or just redraw?
