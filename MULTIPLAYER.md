# Multiplayer

Written by **StevenC** and **Claude** (Anthropic), 2026-10-06.  Started the
same day on the V30 and the 486 (branch `multiplayer`); the 386SX joins
when its network card arrives.

## Where it stands

**Phase 1 -- up to four players in one game, no network -- works.**
`WOLF3DM TIMEDEMO MGEN n [LOCAL k] [MORTAL]` plays `Mn.DEM`, a demo
holding every player's controls (`mp/mpdemo.py` writes twenty: 2 and 4
players on each of E1's ten maps), and reports a checksum of the whole game
state every 50 steps.  `mp/mpsweep.py` plays every demo from several
players' eyes on a box and compares.

| | |
|---|---|
| the players | each extra player's globals (`player`, `gamestate`, controls, weapon timing) kept in a context and swapped in, so id's `T_Player` and `T_Attack` run unchanged for every player (`WOLFSRC/WL_MP.C`) |
| the renderer out of the game | id's renderer picked up items, woke enemies and decided gun hits -- for the one player it drew.  In multiplayer pickups happen where each player stands, nothing is woken by a screen, and aiming is geometry: the same cone id's screen test made, ~8 degrees, for any window size |
| enemies | DOOM's: look at each player in turn, go for whoever made a noise, keep a target once fighting, turn on whoever hurt them.  The target is in `flagspad`, the V30 build's pad byte |
| dying | DOOM's: no lives; a body on the floor; use after a second respawns at the player's own start with 100 health, a pistol and 50 bullets |
| keys | one player's keys are everyone's |
| proof | all 20 demos give the same checksums from P1's, P2's, P3's or P4's eyes, mortal or not; the V30 matched the 486 on E1M1 (a 20-demo V30 sweep against the 486's results is the next record); single player still IDENTICAL to id over the attract loop |

Still for later phases: players shootable (deathmatch) and blocking each
other, projectiles that hit any player (bosses, episodes 2-6), the BJ
sprites in place of the SS stand-ins, colours, a local camera that dies
properly, and everything network.

Since then: **players are solid and shootable**, as DOOM's -- a live
player is in `actorat`, so players and enemies block each other, and a
shot that finds a player hurts that player (friendly fire, as DOOM's
co-op); a kill counts as a frag, a suicide as -1; a body is neither.
id's `TryMove` skipped `objlist[0]` (always the player); in multiplayer
P1 blocks too.

**Phase 2 -- the wire -- measured, 2026-10-06.**  `mp/mpping.pas`
(`MPPING ECHO peer` on one box, `MPPING PING peer` on the other) times
48-byte round trips on port 31992 between the V30 and the 486, both on
their PicoMEMs' WiFi in the same room:

| | packets | lost | average round trip | slowest |
|---|---|---|---|---|
| V30 -> 486 -> V30 | 200 | 0 | ~11 ms | 3 ticks or less |
| 486 -> V30 -> 486 | 1000 | 0 | ~8.6 ms | 1 tick or less |

(BIOS-tick timing: the average is the total over all of them.)  A game
step is 57 ms, so the network is far from the limit -- the V30's frame
is.  Two things learned on the way:

* **A DOS box answers ARP only while a program has the network open** --
  between bridge polls nothing does -- so each side keeps trying to open
  the link until the other is up.  The game will have to do the same.
* **Free Pascal 3.2.2's i8086-msdos runtime returns '' for `ParamStr(n)`
  until `ParamCount` has been called once** (the command line is parsed
  lazily, and only `ParamCount` starts it).  Every tool checks
  `ParamCount` first.

**Phase 3 -- the Python server -- works, 2026-10-06.**  `mp/mpserver.py`
speaks "Protocol, version 1" below (`mp/mpproto.py` packs it);
`mp/mpfake.py` plays fake players against it.  Four fakes at 5, 30, 70
and 17 frames a second, dropping 5% of packets each way at both ends:
the server held 17.53 steps a second, waited for the slowest to load,
and all four ended with the same 600 steps -- the same as the match it
recorded (`--record`, an `Mn.DEM`).  With one fake altering its copy of
step 100, the next SYNC (step 150) raised a DESYNC naming that player.
Chat relayed.

**DOS machines on the server, 2026-10-06.**  `mp/mpcli.pas` is the wire
half of a client with no game (FPC, the bridge's `Net` unit).  The server
on the Windows PC (firewall rule for UDP 31992 in place), the 486 and the
V30 running MPCLI and a fake player as the third: 400 steps at 17.54 a
second, every player holding all 400, and the V30 and the 486 printing the
same CRC (`99C042E3`); the server compared their SYNCs with the fake's --
the same sums -- and found no desync.

**The players are BJ, 2026-10-06.**  `python mp/mkbj.py WL6FOLDER --vswap
VSWAPM.WL6` writes the player's own `VSWAP.WL6` with BJ added at the end of
the sprite range -- 49 frames in each player's colour (P1 grey, P2 green,
P3 red, P4 brown), each block in the SS's frame order, the sounds' pages
moved along behind them (their list is relative to `PMSoundStart`, so
nothing else changes).  Checked by decoding it again: all 196 frames as
encoded, every original page byte for byte.  WOLF3DM opens `VSWAPM.WL6`
when it is there (`MPPageFile`) and draws each player as BJ in their colour,
the SS when it is not.  Seen on the V30 through the capture card: a green BJ,
gun in hand, walking past a guard.  The file is built on the player's
machine from their own data and never committed.

**Phase 4 -- the game on the network -- works, 2026-10-06.**
`WOLF3DM NET server [PORT n] [NAME x] [NETBOT]` joins the server and plays
the map it names: each frame this player's controls go out as `INPUT`
(`NETBOT`: random ones of its own, for tests with nobody at a keyboard),
every step that has arrived is played exactly as a demo's step, and the
picture is drawn once.  `WOLFSRC/WL_NET.C` is the network -- the packet
driver, ARP (answered, always), IPv4 and UDP -- and `WL_NETA.ASM` the
driver's receive callback, into a 12 KB ring allocated only for a network
game.  The first match, the V30 (P2) and the 486 (P1) through the Python
server on the Windows PC: **600 steps, both machines ending on the same
game-state checksum (`203A7E11`), no desync** -- and the server's
recording of it, replayed with `TIMEDEMO MGEN`, ending on that same
checksum.  Getting there found:

* **the receive ring at 0000:0000**: Wolf3D's memory manager keeps a
  *near* pointer to a block's owner, and the owner was declared far -- the
  first frame in wrote over the interrupt vector table.  The owner is near;
* **the random numbers**: `SetupGameLevel` seeds them from the clock
  unless a demo is playing or recording -- each machine began its level
  with different ones.  Multiplayer seeds them as demos do;
* **the bosses and the sound card**: five bosses' deaths last longer with
  digitized sound, so machines with different cards would part on any boss
  level.  In multiplayer every machine takes the longer one (`MPDIGI`);
* **the checksum every step** cost the V30 most of its frame (32-bit
  shifts are software on an 8086): it is summed only on the 50th steps,
  when it is compared;
* **a recording must carry its skill** (P1's start's 4th byte, skill + 1),
  or the replay plays at id's demo skill and parts at once;
* the join waits 90 seconds and then quits, and shows what the network is
  doing -- frames sent and received, ARP, this machine's MAC -- so a stuck
  join says why.

**Modes, bots and the end of a level -- work, 2026-10-06** (StevenC's
asks after the first match: co-op or deathmatch, friendly fire, ESC that
asks, a score at the end, three or four players, bots to try it with).
Everything is chosen on the server and sent to every machine in `WELCOME`
and `START`:

```
python mp/mpserver.py --players 4 --bots 2 --mode dm --timelimit 5
python mp/mpserver.py --players 2 --mode coop --ff off
```

| option | |
|---|---|
| `--players N` | everyone, bots included (up to 4) |
| `--bots N` | the server's own players, in the last slots: gendemo's random runs, turns, strafes, fire and use. They cannot aim -- the server does not play the game -- but they move, shoot, open doors and get shot, and each machine plays them exactly as it plays a person |
| `--mode coop` / `dm` | co-op (the default) or deathmatch |
| `--ff off` | co-op without friendly fire: another player is no target, a shot goes through to what is behind |
| `--noenemies` | no enemies on the map |
| `--fraglimit N`, `--timelimit MIN` | a deathmatch level ends there |

* **Deathmatch**: every key from the start; everyone starts scattered and
  respawns scattered (open floor, no actor, no player within four tiles,
  picked from the step count so every machine picks the same); the
  elevator does nothing; the maps go round the episode.  The status bar's
  LIVES box shows frags -- deaths in co-op -- since nobody has lives here.
* **The end of a level, as DOOM's**: a tally on every machine -- each
  player's kills, items and secrets, frags and deaths, the local one
  marked `>` -- while the steps go on arriving.  It ends on a step all
  agree on (6 s, then the first step with anyone's fire or use; 20 s at
  most), and everyone loads the next floor together, by id's rules
  (secret floor and back).  Co-op keeps each player's health, weapons,
  ammo and score; keys go, as in id's game.
* **ESC asks** "Leave the game? Y or N" -- the game goes on underneath; it
  cannot stop for one player.
* **The status bar** is repainted from the local player's own numbers
  after every step: the 486 once showed no health, because the game draws
  it only when the local player's context happens to be in.
* **Sounds, as DOOM's** (StevenC: P2 killed a guard far away and P1 heard
  it).  Every machine plays every player's game, so each heard every gun
  and every pickup on the map at full volume.  Now a sound plays only
  within 16 tiles of the local player's eyes, and another player's gun or
  pickup comes from that player, panned there on a Sound Blaster
  (`MPHear`, asked by `SD_PlaySound`).  Only what is heard changes: nothing
  in the game depends on a sound's answer.
* **A machine that falls behind catches up.**  The server used to send only
  the newest 64 steps, so a machine more than 64 behind (a V30 loading a
  floor) had a gap nobody filled; it sends from the first one missing now.
  `BYE` goes five times, and a machine that hears nothing from the server
  for 15 s ends the game itself -- one lost `BYE` had left the V30 waiting
  on floor 3.

Tested live, V30 + 486 + two server bots, deathmatch with a one-minute
limit: 2900 steps over three floors, both machines through every tally
and every load, **0 packets dropped, no desync**; the tally photographed
on the V30.  Single player stays IDENTICAL to id and all 20 `MGEN` demos
agree after each change.

Not yet: a recording replays only its first floor (`TIMEDEMO MGEN` has no
level changes); a boss floor ends in id's death cam, which is not made
for more than one player; a slow machine runs behind the others after a
floor loads (10 s on the V30) and catches up as fast as it can play;
chat; the FPC server.

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

## Protocol, version 1 (2026-10-06)

One UDP datagram a packet, port 31992 by default (changeable everywhere).
Every packet starts `'W' 'M' version type` -- 4 bytes -- and every number
after it is little-endian.  `mp/mpserver.py` is the reference; a client or
server that disagrees with it is wrong.

| type | packet | from | after the header |
|---|---|---|---|
| 1 | `HELLO` | client | name (16 bytes, NUL-padded), build (u32: the EXE's CRC-32, so two builds never play together), wanted slot (u8, FFh = any) |
| 2 | `WELCOME` | server | slot (u8), players expected (u8), map (u8), skill (u8), rules (u8), pad, frag limit (u16), time limit (u16, minutes) |
| 3 | `START` | server | players (u8), map, skill, rules (u8 each), then for each player a start: x, y, direction, 0 -- x 0 means "the map's own start" for P1 and "beside P1" for the others (scattered, in deathmatch), found by the game itself (the same search on every machine).  Rules bits: 1 deathmatch, 2 no friendly fire (co-op), 4 no enemies.  A recording keeps them in P2's start's 4th byte, as it keeps the skill + 1 in P1's |
| 4 | `INPUT` | client | slot (u8), buttons (u8), turn (s8), move (s8), seq (u16), have (u32) |
| 5 | `STEPS` | server | first (u32), count (u8), players (u8), then count steps of players x 3 bytes -- buttons, turn, move, P1 first: a step exactly as `Mn.DEM` holds it |
| 6 | `SYNC` | client | slot (u8), pad, step (u32), sum (u32) |
| 7 | `DESYNC` | server | step (u32), the slots whose sum differed from the first slot's (u8 bit mask) |
| 8 | `BYE` | either | slot (u8) |
| 9 | `CHAT` | client | slot (u8), message number (u8), length (u8), text |
| 10 | `CHATMSG` | server | slot (u8), message number (u8), length (u8), text -- to every player; the sender's own copy is its acknowledgement |

**Joining.**  A client sends `HELLO` every half second until it has a
`WELCOME`.  When the expected number have joined, the server sends `START`
every half second; a client sets up the level, then starts sending `INPUT`.
The server's clock starts when every player has sent an `INPUT` after
`START` -- a V30 takes seconds to load a level, and nobody plays until all
can.

**Playing.**  The server steps every 4/70 s (17.5 a second, `DEMOTICS`).
Each step it takes every player's newest controls -- the highest `seq` it
has (a lost `INPUT` costs nothing: the next one replaces it, and a player
whose controls are late keeps the last ones for that step) -- and sends each
client a `STEPS` with every step after that client's `have`, up to 64 (a
lost `STEPS` is covered by the next one, and a slow machine catches up).  It
never waits.  A client plays the steps in order, as many as it has, and
draws the last.  `have` is the highest step it holds with none missing.

**Checking.**  Every 50 steps each client sends `SYNC` with the game
state's checksum (`MPStep`'s); when every slot has reported a step the
server compares, and a `DESYNC` tells everyone the step where the games
parted.

**Ending.**  `BYE` from a client takes it out (its controls stay at
nothing); the server ends on Ctrl-C, a step limit, or every player gone,
sends `BYE` five times (a client also gives up after 15 s of silence),
and writes the match as `Mn.DEM`, so `TIMEDEMO MGEN n` replays it on any
machine (a demo holds 65535 bytes: 5,400 steps -- five minutes -- of four
players, more of fewer).

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
