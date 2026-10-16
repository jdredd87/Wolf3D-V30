# Multiplayer

Written by **StevenC** and **Claude** (Anthropic), 2026-10-06.  Started the
same day on the V30 and the 486 (branch `multiplayer`); a third machine, a
Pentium II, joined on 2026-10-13.  (The 386SX this file once waited for was
retired.)  This file is the lab notebook, in the order things happened;
the summary comes first.

## At a glance (2026-10-13)

| | |
|---|---|
| the game | `WOLF3DM.EXE`: id's Wolfenstein 3-D for up to **four players** -- **deathmatch or co-op**, each with or without enemies; DOOM's rules (no lives, respawn with SPACE, frags, items back after a time, one player's keys everyone's in co-op); BJ in four colours; chat (T), scores (TAB), ESC asks first |
| the network | lockstep over UDP, port 31992: the server keeps the clock at 17.5 steps a second and passes controls along; every machine plays every step, so a V30 and a Pentium II play the same game.  Checksums every 50 steps catch any machine that differs |
| joining | any time: a joiner replays the game so far at full speed and walks in when caught up ("Catching up: N steps to go" -- README.md says why it has to, and how long: a 486 or the Pentium II under a minute for an hour's game, the V30 six to fifteen); a leaver's slot is free at once.  A WiFi dropout of up to a minute is ridden out |
| the server | `mp/mpserver.py` (Python), or **`MPSRV.EXE` on any DOS machine**, or **`MPSRVW.EXE` on Windows** (since 2026-10-15; one Free Pascal source), each with **bots** and a **console**: status, scores, say, kick with a reason, ban, pause, map and next floor, the limits mid-game, the next game's settings -- "The server's console" below |
| the machines | the NEC V30 (8 MHz; `LOWEST VIEW 10`, ~3-9 pictures a second), the 486 (66 MHz) and the Pentium II, all three with sound -- AdLib music and Sound Blaster effects |
| proof | 20 generated 2- and 4-player demos give the same checksums from every player's eyes (`mp/mpsweep.py`); every change is run against the last accepted sweep.  **Eight hours, three machines and a bot, no desync** (2026-10-13); every deathmatch floor of all six episodes, and **every one of the sixty floors in co-op, with enemies, on all three machines, no desync** (2026-10-14, `stage/logs/stress.py`); single player still id's picture exactly |
| not yet | a recording (`--record`) is one floor, so one the console ends early is cut where it ended |

Hosting and joining are in [README.md](README.md), "Multiplayer".

## How it works: one game, worked out on every machine

### Deterministic: the same start and the same inputs, the same result

A program is **deterministic** when, given the same starting point and the
same inputs, it always produces exactly the same result -- not roughly the
same, *exactly* the same, every time, on any machine.  Nothing is left to
chance, to the clock, or to how fast the computer happens to be.

Wolfenstein 3-D is like that.  Start a floor and press exactly the same
keys at exactly the same moments, and everything happens identically: every
guard walks the same path, every door opens on the same tick, every shot
hits or misses the same way, the score comes out the same, to the last
point.  The game proves it itself: **its attract-mode demos are not
films.**  A demo file holds nothing but key presses -- which buttons were
down, how far the player turned and moved, tic by tic -- and the game plays
those presses into the real game engine.  The guards, the doors, the deaths
are worked out afresh every time it plays, and they come out the same every
time.  (This repository leans on that too: `ab.py` checks every change to
the renderer by playing id's four demos and comparing the pictures, frame
by frame, with id's own code.)

Even the game's "random" numbers are not random.  id's `US_RndT` hands out
the next byte of a fixed table of 256; only *where in the table it starts*
can vary.  For a demo it always starts at the same place, so a guard's
"random" decision to shoot, or a "random" miss, comes out the same on every
playing.

### What that buys a network game

Because of that, the network never has to send *the game* -- where everyone
is, how much health they have, which doors are open, which guard is
chasing whom.  It only sends **what every player pressed**, and every
machine works the game out for itself, exactly as it would play a demo.
Four machines given the same presses in the same order arrive at the same
game, step for step, without ever comparing notes.

That is called **lockstep**, and it is how DOOM's network game worked too.
It is also why the traffic is tiny: a player's presses for one step are
three bytes, so four players come to 12 bytes a step -- about 210 bytes a
second of game, however much is happening on screen.

### A step

The game's clock runs at 70 ticks a second, and id's demos record one
entry every 4 ticks (`DEMOTICS`).  The network game does the same: **a step
is 4 ticks, 57 milliseconds, 17.5 steps a second.**  For every step, each
player's machine sends three bytes -- the buttons held (fire, use, run,
strafe ...), how far it turned, how far it moved -- and the server packs
every player's three bytes into one row: that row is the step.  An empty
slot's three bytes are `0, -128, -128`, which no real controls can be, so a
player arriving or leaving is part of the steps too, and every machine sees
it happen at the same step.

### The server keeps the clock and knows nothing of the game

`mp/mpserver.py` never runs Wolfenstein.  It does not know where anyone
is.  Seventeen and a half times a second it takes the newest presses it has
from each player (or the last ones, if a player's packet is late), makes
the next step, numbers it, keeps it, and sends it to everyone.  It never
waits for a slow machine: the steps go out on time, and each machine plays
them as fast as it can.  The server's bots are only more rows of presses --
it makes them up, and every machine plays them exactly as it plays a
person.

### Each machine plays every step

A machine plays the steps strictly in order -- step 1, step 2, step 3 ...
-- feeding each player's presses into id's own movement, shooting and
enemy code, then draws a picture of whatever its own player can see.  A
fast machine draws a picture for every step; a slow one plays several steps
and then draws once.  The V30 at its lowest detail draws three to nine
pictures a second while the 486 draws seventeen -- but **both play every
one of the 17.5 steps**, so both are in the same game.  What a machine
shows is its own business; what happens is everyone's.

That is why each machine can choose its own picture without anyone noticing:
the V30 plays at `LOWEST VIEW 10`, the 486 and the Pentium II at full
detail `VIEW 19`, one has a Sound Blaster and another only an AdLib -- and
they are still in the same game.  **The picture, the window size, the
detail switches and the sound are allowed to differ, because none of them
may change what happens.**  Making sure of that took work.

### What could break it -- and what did

Anything that is not the same on every machine pulls the games apart: the
machines start making different decisions, and from then on they are
playing different games while each thinks it is playing the right one.
That is a **desync**.  These are the real ones this project found and
fixed, every one of them something id never needed to care about, because
id's game only ever ran on one machine at a time:

* **Random numbers seeded from the clock.**  `SetupGameLevel` starts the
  random table at a place taken from the time of day -- unless a demo is
  playing.  Two machines starting the same floor a second apart began with
  different "random" numbers.  The network game seeds them as a demo does.
* **The renderer deciding the game.**  id's renderer, while drawing the
  one player's view, also picked up the items that player walked over,
  woke the enemies that player could see, and decided whether that
  player's shots hit -- from what had just been drawn.  The other machines
  never draw your view, so they would have disagreed about all three.  In
  the network game pickups happen where each player stands, nothing is
  woken by a screen, and a shot is a sum -- the same cone of about 8
  degrees id's screen test made, worked out from the shooter's position and
  angle, for any window size.  (Bonus: that is exactly what lets every
  machine pick its own window and detail.)
* **Sound reaching the game.**  id's status-bar face skips its random
  numbers while the gatling-gun pickup sound is playing -- and how long a
  sound plays depends on the machine's sound card and speed.  So a sound
  could shift the random table, and with it every later decision.  The face
  now has random numbers of its own.  Likewise **five bosses' deaths last
  longer with digitized sound** (they wait for the scream to finish); with
  different sound cards the machines would have parted on any boss floor,
  so in the network game every machine takes the longer one (`MPDIGI`).
* **The recording's skill.**  A recorded game has to carry its skill level,
  or a replay plays at id's demo skill and parts from the original at
  once.
* **A shortcut that looked harmless.**  Skipping the save of a value that
  "could not have changed" (an enemy's target, while it was aiming) made
  the sums differ by step 100 on one demo: some other code did change it.
  Taken out again; the checksums are what caught it.

### Checking: the checksum every 50 steps

Nobody has to take it on trust.  Every 50 steps each machine adds up the
state of its game into one 32-bit number, a **checksum**: for every actor
-- each player, each enemy, each moving thing -- its position, angle,
health, state, timer, flags and direction; every item lying on the floor;
every door's position; and every player's health, ammo, keys, weapon,
score, deaths and frags.  If anything at all differs between two machines,
the two numbers differ.

The machine sends its number to the server in a `SYNC` packet.  The first
machine to report a step sets that step's number; any machine reporting a
different one is told `DESYNC`, with the step -- and says so in its report
at the end ("DESYNC reported" instead of "no desync").  A machine that
joined late is checked against the numbers the others reported live, so
catching up wrong is caught too.  (The sum is only made on the 50th steps,
not every step: adding up 32-bit numbers is slow on an 8086, and every
step it would have cost the V30 most of its time.)

### Proving it before it goes on the network

`mp/mpsweep.py` plays twenty recorded games -- two and four players, on
each of episode 1's ten floors -- with no network at all
(`WOLF3DM TIMEDEMO MGEN n LOCAL k`), from every player's eyes in turn, and
compares the checksums.  They must all agree: P1's machine, P2's, P3's and
P4's view of the same game must be the same game.  Every change to the
network game is checked that way against the last accepted run ("20 of 20
demos agree") before it goes near a live game; the V30 and the 486 have
both run the sweep, and give the same numbers.  In live games the V30, the
486 and the Pentium II -- from an 8 MHz 8086-class chip to a 32-bit
Pentium -- agree to the bit.  And the long live runs end with every
machine's report saying
"no desync": eight hours, three machines and a bot, 518,791 steps, the
same game on all three to the last one.

### Catching up, which only works because of all this

Because only presses travel, a machine that joins a game already running
cannot be told where everyone is.  It has to *play* there: it takes every
step from the first, plays them as fast as it can without drawing or
sounding, and so arrives in exactly the game the others are in -- the box
says "Catching up: N steps to go" while it does.  A 486 or the Pentium II
replays 1,500 to 12,000 steps a second (an hour of play in under a minute);
the V30 70 to 180, so an hour-old game takes it six to fifteen minutes.  A
machine that misses steps -- a WiFi dropout, a floor loading slowly -- does
the same thing for the few it missed.  None of it would work if the game
were not deterministic: the replayed game would simply be a different one.

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
driver's receive callback, into an 8 KB ring allocated only for a network
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

**A faster picture on a slow machine -- 2026-10-07** (StevenC: "for the
v30, can we shrink the view port ... or dumb the graphics down?").  Each
machine draws only its own picture and aiming is geometry, so every
machine can choose its own window and detail without changing the game.
The V30 build's switches work on the command line as in single player,
and DOOM's keys work during play:

```
WOLF3DM NET 192.168.50.46 NAME V30 LOWDETAIL VIEW 10
```

| | |
|---|---|
| `-` / `=` | the window smaller / bigger, id's sizes 4-19.  Each new size rebuilds id's compiled scalers, 2.1 s on the V30 (measured, 145 ticks; freeing and retaking the page manager's memory is 1 tick), so presses are counted and the window changes once, half a second after the last.  The steps go on arriving meanwhile and the machine catches up |
| F5 | the walls' detail: a ray for every column, every 2nd (`LOWWALLS`), every 4th (`LOWWALLS4`).  Instant.  With `LOWSPRITES`/`LOWDETAIL` on the command line it keeps to 2 and 4: the sprite code is set up for walls in pairs |
| `LOWEST` | every cheap mode at once, the one to use on a V30 (StevenC: "make it so we can easily just scale all the graphics down to the lowest detail ... it makes it pretty playable"): `LOWWALLS4 LOWSPRITES FLATWALLS FLATART LOWVERT FARBLOBS 16`.  The window stays the player's -- `VIEW n`, or `-` and `=` |
| switches | `VIEW n`, `LOWDETAIL`, `LOWWALLS`, `LOWWALLS4`, `LOWSPRITES`, `FLATWALLS`, `FLATART`, `LOWVERT`, `FARBLOBS` -- set at start only |

Nothing is saved: a network game ends without `WriteConfig`.  The report
at the end now gives the frame rate too: `net: N pictures in S s, F a
second (view V, walls 1 ray in K)`.

Measured live, the V30 in a four-player deathmatch (486 + two bots),
1200 steps each:

| V30 | pictures a second |
|---|---|
| view 16, full detail (its CONFIG.WL6) | **2.4** |
| `LOWDETAIL VIEW 10` | **6.6** |
| `LOWEST VIEW 10` (each switch given separately, deathmatch, three bots) | **9.0** |
| `LOWEST VIEW 10`, co-op with the enemies | **8.4** |
| `LOWEST VIEW 6` | **13.8** |

`LOWVERT` shows every other row of the whole screen, so the status bar
loses its odd rows too -- the S of SCORE and LIVES looks garbled.  That is
step 82's design, the same in single player.  Once, in a run of four
back-to-back games, the V30 with `FLATWALLS` alone left its game at the
first picture (8 s: `FLATWALLS` reads every wall page then) having had no
step; run again it played all 500 steps.  Explained the next day (below,
"Easier to run"): the silence check's arithmetic was unsigned.

The 486 ran at view 19, full detail, 16.6 a second (it draws when a step
arrives, so 17.5 is its ceiling) -- and **0 desyncs** with the two machines
drawing so differently.  The first try at the keys ran out of memory on
both machines (`MM_GetPtr`): the scalers need 20 KB to be built in, and
the page manager holds the rest of memory, so they let it go first as id's
menu does (`ClearMemory`, then `PM_CheckMainMem`).  Tested with a
throwaway build whose netbot pressed `-`, `=` and F5 every few frames:
the window seen resizing on the V30's screen, no crash, no desync.

**Easier to run -- 2026-10-07** (StevenC: "be able to remember settings and
IP, name, port ... The long command lines get hard").

* **`WOLF3DM.CFG`**, a text file beside the game, keeps the server, the
  port and the name:

  ```
  SERVER 192.168.1.10
  PORT 31992
  NAME StevenC
  ```

  `WOLF3DM NET` alone joins that server as that name.  Whatever the
  command line gives (`NET a.b.c.d`, `PORT n`, `NAME x`) is used and saved
  for next time -- not under `NETBOT`, a test.  With no server known yet it
  says so and stops: `WOLF3DM NET a.b.c.d -- remembered after that`.  The
  game cannot add the file's words to its command line (medium model: the
  arguments are near strings, and DGROUP is full), so the file holds only
  these three; the picture switches are the menu's.
* **The PLAY menu has a network page: M** (shown when `WOLF3DM.EXE` is
  there).  S types the server's address (checked: four numbers 0-255), O
  the port, Y your name; A is the lowest picture (`LOWEST`'s switches), N
  full detail, +/- the window -- the same switches and size as the first
  page, FASTOPL left alone.  J (or Enter) writes `W3RUN.BAT` with the whole
  line, `WOLF3DM NET 192.168.1.10 PORT 31992 NAME StevenC LOWWALLS ...
  VIEW 10`, and PLAY.BAT runs it and comes back.  Driven over the bridge
  with KINJ: a new server, port and name typed, `WOLF3DM.CFG` and
  `W3RUN.BAT` exactly as above.
* **The report says how a game ended**: `net: ended by the server (BYE)`,
  `this player (ESC, Y)`, `15 s with nothing from the server`, or `the
  game`.

Found on the way, all three fixed:

* **The silence check was unsigned.**  `TimeCount` is a `longword`, and
  id's renderer sets it back to 0 after the first picture's fade-in; a
  packet heard a tick before that made `TimeCount - mpheard` about four
  billion -- "15 s of silence" -- and the machine left at its first
  picture with no step played.  It was the `FLATWALLS` early exit above:
  any first picture could do it, a slow one more often.  Now signed.
* **The first picture is drawn before the machine tells the server it is
  ready**, so the server's clock does not run while it reads the level's
  walls and sprites into the cache, or (`FLATWALLS`) averages every wall
  -- 8 s on the V30, which it used to spend behind.  V30, `LOWEST VIEW
  10`, four players: 9.9 pictures a second (9.0 before).
* **"BadScale called!" on the V30, a frozen 486 -- in single player too.**
  Not this branch's bug but the exact build's: `WL_SC_A.ASM` declared
  `EXTRN PM_GetPage:FAR` inside its code segment, so TASM framed both far
  calls on WL_SCALE_TEXT -- right only while ID_PM's code lay within 64 KB
  above it.  This branch's code lies between them and grew past that, and
  PM_GetPage wrapped round mid-function.  Fixed on `v30-8086` (d5426eb,
  same bytes, id's picture exactly; see V30NOTES.md) and merged here.
* **id's memory check** wanted 215000 bytes of main memory (lowered from
  235000 for this branch once already); the 486, 550 KB free, fell under
  it again and showed "You do not have enough memory".  200000 now: id's
  figure is for a page cache it likes, and less is a few pages fewer,
  from XMS.

Tested: single player IDENTICAL to id; all 20 `MGEN` demos agree; three
back-to-back V30 games joining from `WOLF3DM.CFG` alone (`WOLF3DM NET
NETBOT LOWEST VIEW 8`), 400 of 400 steps each; V30 (`LOWEST VIEW 10`) and
486 (view 19) in one four-player game, 1200 steps, 0 desyncs.

**Joining and leaving a running game -- 2026-10-07** (StevenC: "once a
server runs, people can join and leave as needed? ... if too many people
try to join ... they get rejected with a message? ... if a machine goes
down ... a slot is opened up for another person to join?").

```
python mp/mpserver.py --players 4 --mode dm --timelimit 10
```

runs until Ctrl-C.  `--players` is the number of slots (4 at most; `--bots`
of them the server's own, the last ones).  Nobody waits for anybody:

* **The game starts** the moment the first player has loaded the level.
* **Anyone who comes later** is sent every step from the first, plays them
  as fast as the machine can -- no picture, no sound, a box saying
  "Catching up: N steps to go" -- and is let into the game when it is all
  but caught up.  Every machine sees the player arrive at the same step,
  as from a respawn: a start, 100 health, a pistol, 50 bullets, score and
  frags 0.  (The game cannot be handed over -- every machine plays every
  step from the same beginning, and that is what keeps them the same.)
* **Leaving** -- ESC, Y -- frees the slot at once; a machine not heard from
  for 30 s (`--drop-after`) is let go, and told so.  Every machine sees the
  player vanish at the same step: no body, nothing to hit, nobody's target.
  A V30 loading a floor is quiet for 15 s or so; it now says it is alive
  three times during the load.
* **A full server** answers `HELLO` with `BYE` 1, and the game says "The
  server is full -- try again when someone leaves" and stops.
* **When the last player has gone** the game is over; the server waits,
  and the next player starts a new one (`--once`: it stops instead).
  `--record` writes each game as it ends (`M50.DEM`, `M50B.DEM` ...).

How: a slot's presence is in every step.  An empty slot's 3 bytes are 0,
-128, -128 -- a turn and a move that id's `PollControls` clamps to 100 a
tic, so no player's are ever that -- and `SetControls` (and `MPReadDemo`, for
a recording) turns a change into `Join` or `Leave` at that step on every
machine.  A slot nobody has taken is empty from the first step.  In a tally
only the slot's state changes, and the next floor sets the world to match
(a player who arrived during it starts new).  The server knows nothing of
the game: it marks the slots.  `mp/mpcome.py` is a scripted player for
testing -- `join@20 leave@60 quiet@100 knock@40` -- and SYNCs are now
checked against the first report of each step, so a machine that joined
late is compared with those that played it live.

Also fixed on the way: while catching up, the network is read every 8
steps.  The V30 played 64 between reads, 1.6 s in which its 8 packet slots
overflowed -- it lost the server's final `BYE` (and ended on 15 s of
silence instead), and the server kept sending it the same 64 steps,
because it had not said it had them.

Tested live, V30 and 486, every case:

| | |
|---|---|
| the 486 joins 45 s into the V30's game | caught up 360 steps in 0.6 s, in at step 370; 2200 steps, the same end state on both, 0 desyncs |
| the V30 joins 60 s into the 486's | caught up 1454 steps -- in at step 2501, 60 s later: it plays some 42 steps a second without drawing (E1M1, co-op), so it gains 24 a second on the game; 0 desyncs |
| `mpcome.py` joins, a fifth knocks, it leaves, another joins, goes quiet | slot P3 in at once; the knock told "full"; the slot freed by `BYE`; taken again; let go after `--drop-after` 10 s, and told so.  V30 and 486 ended identical, 0 desyncs |
| the last player leaves | game over, the server waits; the next player starts a new game |
| a one-slot server, the 486 in it, the V30 knocks | the V30 prints "The server is full -- try again when someone leaves" |
| `--drop-after 4`, a deathmatch floor ends | the V30, loading floor 2, was let go; it ended "by the server, which stopped hearing this machine"; the 486 played on to step 2400, 0 desyncs |
| the default 30 s, a 1-minute deathmatch floor, three floors | nobody dropped; 2600 steps, 0 desyncs |

**What it shows about the V30**: catching up on E1M2 and later floors
(a four-player deathmatch, with every enemy) ran at only 23 steps a second
-- the game runs at 17.5 -- so after each floor's load the V30 spent most
of the floor catching up, with no picture.  On those floors the V30's limit
is the game itself, four players' and every enemy's thinking, not the
drawing; that is the next thing to profile and put into assembly.  The
report says it: `net: caught up 2079 steps in 88 s, 23 a second`.

**Catching up, profiled and made faster -- 2026-10-07.**  `WOLF3DM NET ...
PROFILE` now runs WL_PROF.C's sampler over the catching up only, and
writes `PROF.BIN` (`python profmap.py PROF.BIN WOLFSRC\WOLF3DV.MAP`); its
36 KB come from the page manager's memory, as the window keys' do.  The
test: a four-player deathmatch on E1M2 (`--map 1`, two bots), the 486 in
it a minute before the V30 joins.

| | V30 catching up | what it was |
|---|---|---|
| before | 28 steps a second | -- |
| pickups only where a bonus may lie | (TIMEDEMO MGEN 11: play 937 -> 758 ticks) | `AutomapPickup`, a scan of the whole static list for every player every step: 16% |
| the context swap in assembly | 31 | `Save`/`Load` and their `_fmemcpy`: 24% |
| a tile's bonus bit cleared at its last pickup; `Take` copies only new steps; the state sum in locals; the server sends a stalled machine the same steps 4 times a second, not 17 | **35** | packets 6%, the sum 3%, old item tiles 4% |

* **Pickups**: a bit a tile (512 bytes, far) says a bonus may lie there --
  set by `SpawnStatic` and `PlaceItemType`, cleared with the list and when
  `GetBonus` takes a tile's last one -- and `Think` scans only there.
* **`MPSwapOut`/`MPSwapIn`** (WL_NETA.ASM) copy a context's fields with
  string moves, in `mpctx_t`'s order; `Init` checks that order and the
  struct's packing, and Borland reports the check as always false.
* **`% RING`** on a long was a 32-bit division per step; a mask now.
* Every change leaves the game as it was: the 20 `MGEN` demos give the same
  sums as before them, every 50 steps, from both players' eyes.

Tried and dropped: not saving a context back when an enemy's think left it
unchanged (an enemy runs with its target's context in, and an idle one
looks at each player in turn, so the context changes at nearly every
actor).  The idea is sound, but something besides `TakeDamage` and the death
cam changes the target's context -- M3's sums parted at step 100, and the
486 froze -- so it is not in.  The swaps are still some 17% of catching up:
the next place to look, with the context's real writers found first.

**Deathmatch, made to feel like one -- 2026-10-08** (StevenC: "can we do
death match with no enemies? and if so, items respawn? ... when killed, it
looks odd. your gun shows ... red tint? ... press space to respawn? ...
TAB to show the score board? ... not sure if T for message works?").

* **No enemies** was already there: `mpserver.py --mode dm --noenemies`.
* **Items come back** (`--itemrespawn SECS`, 30 in deathmatch unless given,
  never in co-op unless given): an item the map put there, taken, is back
  that many seconds later -- counted in steps, so at the same step on every
  machine, and a late joiner playing the steps again sees the same.  The
  time travels in the rules byte's bits 3-7 (5 s times n, to 155 s), so
  `WELCOME`, `START` and a recording carry it with no new field.  A dropped
  item does not come back, a slot whose item will is not handed to a drop
  (`PlaceItemType`), and the Spear never does.
* **Dying**: no gun in hand; the view goes red at once and fades in a
  second to a red that holds until the respawn (the palette is set only
  when it changes -- each set waits for the retrace, and a hit's flash sets
  it every step); "Killed by NAME" (or "You killed yourself", "You died")
  in the middle of the view, and after a second "Press SPACE to respawn".
* **TAB** held: the scores over the view -- every player in the game, the
  most frags first (score in co-op), frags and deaths, the frag limit and
  the time left when there are any.
* **T** (chat): the protocol had `CHAT`/`CHATMSG` and the server relayed
  them, but the game had never sent or shown one -- T did nothing.  Now T
  opens a line ("Say:", 40 letters, ENTER sends, ESC does not), sent until
  the server's copy comes back; typing, the player stands still.  The
  keyboard interrupt hands each letter to a 16-letter ring
  (`IN_SetKeyHook`), so the V30 drops none at 10 pictures a second.
* **Notices** at the top of the view for six seconds: chat, who killed
  whom, who joined and who left -- in the player's colour.
* **Names**: the server sends every slot's name (`NAMES`, type 11) when
  anyone comes or goes and every two seconds; the notices, the scores and
  the tally use them.
* **ESC quit with `MM_GetPtr: Out of memory`** (StevenC, the same night, on
  both machines): the "Leave the game?" box loads the big font, and in a
  network game the page manager holds the rest of memory.  id's own
  in-game messages let it go first (`ClearMemory`) and take it back after;
  so does this one now.  The small font the notices use is loaded the
  same way at each floor's start.
* Text is drawn over the finished view (`MPOverlay`, from `ThreeDRefresh`)
  with a shadow; with `LOWVERT` only the even rows are shown, so the font
  is drawn twice as tall there -- the only way it reads.
* **Tested** on the two machines (NETBOT, which now also holds up the
  scores 5 s in every 20, sends a chat line every 20 s, and *looks* dead
  5 s in every 20 -- the picture only, nothing summed -- so a camera can
  see what TAB, T and dying do): 3,000 steps of deathmatch with no enemies
  and items back after 5 s, the 486 joining late and catching up through
  the pickups and the items' return -- 0 desyncs, both machines ending on
  the same sum (`4A53F687`), 18 chat lines relayed, the V30 at 8.4
  pictures a second (`LOWEST VIEW 10`) with the text over the view.  The
  20 `MGEN` demos agree as before; single player is IDENTICAL to id.

**The 486's memory, and the ESC box again -- 2026-10-08, later** (StevenC
out for the day; a NETBOT build that also pressed ESC every minute, N four
seconds on and Y the fifth time, found both).

* **ESC could still end the 486**, with `PML_TransferPageSpace: Zero
  replacement`, at the second ESC.  The box's fix let the page manager's
  memory go and took it back only on N -- but the game goes on under the
  box, and a sound from a page that had been let go found no memory there.
  id's own order (`WL_PLAY.C`) is the cure: `Message`, `UNCACHEGRCHUNK`,
  `PM_CheckMainMem` at once.  Five ESCs then on both machines, no desync.
  After N the WHOLE border is drawn again: at a small view the box stands
  on the border above the view, and redrawing only the sides left half of
  it there for good (the V30's screen showed it).
* **The 486 was within 50 bytes of not starting.**  id's check wants
  200,000 bytes for its caches (`WL_MAIN.C`); under the bridge the 486 has
  550 KB free (DOS low, no EMS) and gave WOLF3DM about 199,950 -- a test
  build 1 KB bigger was refused.  Without EMS every page passes through
  main memory, so that figure is real, not id being fussy.  Two cuts, and
  neither changes the game:
  * Borland gives every `far` variable its own segment, rounded up to 16
    bytes: 1.9 KB of padding, mostly in `WL_MP.C`.  `#pragma option -zE`
    puts a file's far data in one segment, and `-Fc-` (from
    `BUILD86.BAT`; a pragma cannot say it) lets the uninitialized ones
    join -- 1,467 bytes back.  Only `WL_MP` gets `-Fc-`: id's `WL_MENU.H`
    defines a variable (`menuitems`), and a second such module defines it
    twice.
  * The receive ring's slots were 1,536 bytes, a whole Ethernet frame;
    the biggest packet the server sends is 820 (64 four-player steps).
    Slots of 1,024: the ring is 8 KB, not 12, and 4 KB more is the page
    manager's once a network game starts.
  The EXE is 333,678 bytes (was 335,166).  The 20 `MGEN` demos agree;
  single player is IDENTICAL to id.
* **More would come from the 486's `CONFIG.SYS`**, StevenC's to change:
  HIMEM is loaded and MEM says "The high memory area is available", but
  there is no `DOS=HIGH` -- DOS keeps 72 KB of conventional memory there.
* **A deathmatch started unfairly**: a player in the game from its first
  step kept id's 8 bullets, while one who joined after had a respawn's 50
  (and every floor after the first gave everyone 50).  Now everyone starts
  a deathmatch with 50.  Co-op still starts as id's game; the `MGEN`
  demos are co-op, and still agree.  (A server recording of a deathmatch
  made before this would not replay the same.)
* **Dead, at a small view**, the top notice ("X killed Y") was written over
  "Killed by X": only as many notices as fit above it are shown now.
* **A real kill, at last, on camera**: the test bots (`mp/huntbot.py`, a test build: NETBOT presses what
  only a keyboard can) hunted (turned toward
  the other player and ran, wandered when stuck, fired only when aimed),
  started beside P1 so they met, and waited 4 s before SPACE.  The 486
  killed the V30 twice in five minutes: the V30's screen went red with no
  gun, "Killed by QBOT486" and "Press SPACE to respawn", a bloodied face
  at 0%; after SPACE, 100% and 50 bullets, the notice at the top and the
  scores (TAB) sorted with the killer first, 2 frags to 2 deaths -- the
  same on both machines, no desync.

**The text on the whole screen, not in the view -- 2026-10-09** (StevenC,
from the V30: "the smaller it is, the more it's crammed").

* **The notices, the scores, the chat line and "Killed by" are laid out on
  the play area, 320 x 160, border and all** -- not inside the view.  At
  VIEW 10 the V30's view is 160 x 80, and LOWVERT draws text twice as tall,
  so it held three lines: the scores lost their title and shrank to "F" and
  "D", and every notice was cut at 154 pixels.  Now at any size: notices
  across the top, the chat line along the bottom, the scores in a 240-pixel
  box with "DEATHMATCH" and the time left, "Killed by" in the middle.
* **The border has to be cleaned up after, and only when it changed.**  The
  view is drawn again every frame; the border only when id draws it.  So
  each of the three pages keeps the rectangle and a sum of what was drawn on
  it, and a frame lays its overlay out twice -- first only adding it up,
  then for real.  If the sum differs from the page's, the border under the
  old rectangle is put back first (`Unborder`: the border's colour outside
  the view, then the view's edge); if it is the same, only the part that
  lands IN the view is drawn again.  That second half matters on the V30:
  the font is a port write a column and a test a pixel, and drawing it all
  every frame took a live game from 11 pictures a second to 6.6.  The
  clock is read once for both passes, and every `DrawAllPlayBorder`
  forgets what the pages had (`Redrawn`).
* **Measured, alone on a server** (`mp/huntbot.py --quit 3`, VIEW 10, the
  same wander each time -- it ended on the same tile): the old overlay
  9.1 pictures a second, the new 10.2.  Faster, because the top notice and
  the chat line now sit on the border and cost nothing once drawn.
* **Memory for the 486, again.**  The new overlay cost 1,456 bytes and its
  clipping 576 more, and the 486 had 1.3 KB over id's check.  Back:
  * `WL_MP` and `WL_NET` compiled for size (`-G-`, and `-k-`: no stack
    frame a function does not need) -- 991 bytes (816 + 56 in `WL_MP`,
    119 in `WL_NET`).  No speed lost: the
    benchmark gave 10.3 built for speed and 10.2 for size.
  * `WL_NET`'s uninitialized far variables each given a 0, so they join its
    one far segment -- 224 bytes of padding.
  * The step ring's step numbers are 16 bits, not 32 (a slot is written
    every 128 steps; 16 bits repeat only in 65,536) -- 256 bytes.
  Measured (`mp/huntbot.py --memonly`, which adds only the line that prints
  it): **200,770 bytes**, 770 over the check.  The EXE is 334,318 bytes
  (was 333,790).  `DOS=HIGH` is still the
  real cure.
* **Photographed on the V30 at VIEW 4, 10 and 19**, two bots hunting each
  other: notices, the scores, a typed chat line (the test build shows one
  5 s in 20), a kill, the death screen, ESC's box, and nothing left on the
  border after any of them.  No desync; the 20 `MGEN` demos agree; single
  player is IDENTICAL to id.
* The test bot now fires only when nothing is between (no wall, no shut
  door): without that it emptied its gun into a wall on 2026-10-08 and
  nobody died.

**Four hours, four players -- 2026-10-09** (StevenC: "Can we do a long
play demo test?  For 4 hours?").  The V30 (`VIEW 10 LOWEST`) and the 486
each ran `mp/huntbot.py --quit 240` (ESC and N every minute, Y at the
240th); the server held the other two slots with its own bots:

```
python mp/mpserver.py --players 4 --bots 2 --mode dm --noenemies --timelimit 60 --itemrespawn 30
```

* **263,552 steps in 4 h 11 min (17.50 a second), no desync** -- the
  server compares every machine's sum every 50 steps, and none differed
  in the whole run.  Both bots left by ESC, Y and printed it.
* **Past every 16-bit wrap**: the step ring holds the low 16 bits of a
  step, and they went round four times (65,536 steps is 62 minutes).
* **Four floors of 60 minutes, and into the fifth**: every machine left
  each one on the time limit and loaded the next together, the V30 too,
  with nobody dropped.  An hour of respawns and items coming back did not
  fill anything.
* **Joining late, three floors in**: the 486 came back 2 h 38 min in and
  played all 167,828 steps from the first -- three floors, two floor
  changes -- in 104 s (1,612 a second), 2 min 39 s with the loading, then
  played live to the end.  Its sums agreed with every one already
  reported for the steps it replayed.
* **The 486 hung once**, 2 h 30 min in, 28 minutes into floor 3 (step
  157,637): no packet, no answer to ARP for three minutes, the plug
  reading **69-70 W against 64.4 running** (`docs/hardware.md` in the
  bridge has it).  The server freed its slot after 30 s and the game went
  on; a power cycle brought it back.  **Not explained** -- the 486 has no
  capture stick, so nothing saw its screen, and nothing in the game writes
  a log.  It was not at a floor change.  Open below.
* **Pictures**: the V30 7.2 a second over the whole run (four players,
  every one on screen at times; 10.2 alone), the 486 15.8 at `VIEW 19`.
* The photos, one a minute: notices, chat, the scores, kills, ESC's box,
  the red damage flash, all right on every floor.  On floor 1 nobody
  scored for its last 43 minutes: the hunt bot runs in a straight line
  at the nearest player and gets stuck in a maze -- the bot, not the game.

**The hang watchdog, and four hours again -- 2026-10-09** (StevenC: "Are
we able to generate a stack trace on lockups?" -- then "run on both").
The 486 has no camera and the game keeps no log, so the hang above left
nothing to read.  Test builds (`mp/huntbot.py`) now carry a watchdog
(`WL_NET.C`, `WL_NETA.ASM`, `#ifdef HANGDUMP`; the real EXE comes out
byte-identical, md5 `c9cd91d1...`):

* **20 s without `NetPump`** -- which every loop the game has calls while
  the network is up -- and the BIOS tick (INT 1Ch) reports: the step, the
  floor, the network counters, where the packet driver, DOS and the disk
  BIOS live, and 384 bytes of the game's stack.  To the server as a
  `HANG` packet (mpproto 12; kept in `stage/hang-<address>.log`), three
  times 5 s apart, and once into `C:\WOLF3D\HANG.LOG` if DOS was not busy.
  The server going quiet while the game runs goes into `HANG.LOG` too.
* **The stack is the game's, not the tick's**: DOS (`STACKS=`) moves the
  BIOS tick onto a stack of its own, so by INT 1Ch the game's is out of
  sight -- the first trace read DOS's pool and named nonsense.  `Hang8`, an
  INT 8 entry in front of id's timer service, notes the game's SS:SP every
  tick and goes on; id's `SDL_SetTimerSpeed` sets its service behind it.
* **`python mp/hangtrace.py stage/hang-<address>.log`** names the frames:
  the test build compiles `-y` and links `/l`, so its map
  (`stage/WOLF3DT.MAP`) has line numbers -- read against the patched
  sources huntbot keeps in `stage/wolf3dt-src`.  It reports the frame the
  tick interrupted and every far return whose bytes before it are a far
  call; words left on the stack by older calls show up as well.
* **Proven**: a bot named `QS...` stalls 24 s at its second ESC.  Both
  machines sent the report and both traces named the stall's own line
  (`wl_mp.c:2838`, the `while`), called from `NetLoop ()`.  (Then the
  game's own rule ends it -- 15 s with nothing from the server -- because
  nothing was read during the stall.)
* **A useful fact on the way**: this stack answers ARP only from
  `NetPump`.  A game stuck in a loop stops answering ARP just as a dead
  machine does, so the 486's silence above said nothing about which.

**The second four hours, with it**: 262,437 steps (4 h 10 min), the same
four players and rules, both machines on the watchdog build -- **no hang,
no desync, no `HANG` report, nothing in either `HANG.LOG` but its start
line**.  The 486 16.3 pictures a second, the V30 7.2.  So the hang is one
in eight hours of the 486's play and did not come back; the watchdog stays
in every test build, to catch it if it does.  The 486's plug read 58.7 to
76.7 W while it ran, so watts alone cannot tell a hang from play.

**Eight hours, and a leak in id's memory manager -- 2026-10-10**
(StevenC: "If this worked fine for 4 hours, can we do 8 hours? both
machines and 2 bots?").  The same four players and rules, bots quitting
at their 480th ESC.  **Neither machine lasted**: the 486 quit 6 h 31 min
in (step 411,265) and the V30 7 h 23 min in (step ~464,500), both with
id's own **`MM_ClearBlock: No purgable blocks!`** -- not a hang, and not
memory: the memory manager had run out of block *handles*, of which
there are 700 (`MAXBLOCKS`).  No desync in the whole run.

* **The cause is id's.**  `MM_GetPtr` takes a handle (`GETNEWBLOCK`)
  before it searches, and an allocation allowed to fail
  (`MM_BombOnError (false)`) that finds no room set `mmerror` and returned
  still holding it.  The page manager's `PM_CheckMainMem`, which takes
  its pages back after every message box, view change and floor load,
  makes exactly those -- so each one could lose a handle for good.
* **Counted**: the test build's chat line now ends in the free handles
  (`"QBOT486 here, step 437059, 372 free"`, `MM_FreeBlocks`).  The 486
  had 392 after loading, lost one or two per floor load, and in play
  **one a minute -- one per bot ESC**: about 6 1/2 hours of handles,
  which is when it quit.  The V30 has more to start with (436 in the
  fixed build, against the 486's 396) and lasted longer.  The four-hour
  runs were 240 ESCs: under the line.
* **Fixed** (`ID_MM.C`): the handle goes back on the free list.  Real EXE
  334,350 bytes, `ab.py --full` IDENTICAL to id, mpsweep 20/20 on the
  486.  The fixed test build ran 17 minutes on both machines, 16 ESCs and
  three floor loads: 396 -> 400 free on the 486, 436 -> 440 on the V30.
  People playing lose handles the same way -- every ESC, every `<`/`>`
  -- only more slowly than a bot.  id's single-player game has the same
  bug (`v30-8086` is id-exact and keeps it).
* **The 486's hang came once more, without the network**: the first
  mpsweep of the fix (local demo playback, `TIMEDEMO MGEN`, no packet
  driver in use) stopped between demos M6 and M7 and needed a power
  cycle; M7 alone, and the whole sweep again, ran clean.  So whatever
  hangs the 486 now and then is not the network code.

**The eight hours again, with the fix -- 2026-10-10/11** (StevenC: "Ok
with the changes, can we do this test again?").  The same four players
and rules, started 22:56.
* **The V30 played the whole run**: 8 h 22 min, ending itself at its
  480th ESC with a Y.  527,798 steps (17.50 a second), **no desync**,
  197,230 pictures in 29,122 s (6.7 a second, view 10), 260,881 packets
  sent and 494,539 received.
* **The leak is gone**: the free handles went 436 -> 443 on the V30 and
  396 -> 413 on the 486, one or so up at some floor loads, and **never
  down once** in eight hours of a bot pressing ESC every minute.  The
  first run had lost one a minute.
* **The 486 hung again, 8 h 2 min in** (28,920 s, step 505,998, a minute
  into the ninth floor), with a message box up -- 413 free is what
  `ClearMemory` leaves, so most likely its 480th ESC, at about the time
  it was due.  No BYE packet reached the server, and the watchdog wrote
  nothing but its "armed" line to `HANG.LOG`.  `PHASE.LOG` ends inside
  `WOLF3DT`.  A power cycle brought it back.  So it is the same hang as
  2026-10-09 and the `TIMEDEMO` one, not the leak.  **A silent watchdog
  does not mean the tick stopped** (first written here as if it did): it
  sends its report through the packet driver *before* it writes
  `HANG.LOG`, so a game stuck inside the packet driver -- or inside the
  PicoMEM's disk BIOS, which the file write would need -- silences it as
  surely as interrupts left off.
* **The blocky text at the V30's start** (StevenC: "8086 had a very hard
  to read text at the very begining... maybe said listening?"), filmed
  on 2026-10-11: id's signon screen ("One moment...", then "Working..."
  in the small font), then **our "Joining the server..." box** -- three
  lines in the small font, `sent 1 in 4 drop 0` and `ARP yes MAC ...`,
  on screen for about 1.5 s before the fade.  Nothing says "listening"
  on a DOS machine; that word is only in the server's own window.

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
| 3 | `START` | server | players (u8), map, skill, rules (u8 each), then for each player a start: x, y, direction, 0 -- x 0 means "the map's own start" for P1 and "beside P1" for the others (scattered, in deathmatch), found by the game itself (the same search on every machine).  Rules bits: 1 deathmatch, 2 no friendly fire (co-op), 4 no enemies; bits 3-7 (since 2026-10-08) n: a taken item comes back after 5n seconds, 0 never.  A recording keeps them in P2's start's 4th byte, as it keeps the skill + 1 in P1's |
| 4 | `INPUT` | client | slot (u8), buttons (u8), turn (s8), move (s8), seq (u16), have (u32), played (u32: the highest step it has played; since 2026-10-07 -- the server lets a joiner in once it has caught up) |
| 5 | `STEPS` | server | first (u32), count (u8), players (u8), then count steps of players x 3 bytes -- buttons, turn, move, P1 first: a step exactly as `Mn.DEM` holds it.  An empty slot's 3 bytes are 0, -128, -128 (since 2026-10-07): no player's are, as id's PollControls clamps a turn and a move to 100 a tic |
| 6 | `SYNC` | client | slot (u8), pad, step (u32), sum (u32) |
| 7 | `DESYNC` | server | step (u32), the slots whose sum differed from the first slot's (u8 bit mask) |
| 8 | `BYE` | either | slot (u8), and from the server a reason (u8, since 2026-10-07): 0 the game is over, 1 the server is full, 2 a different build, 3 this machine was not heard from and its slot is free |
| 9 | `CHAT` | client | slot (u8), message number (u8), length (u8), text |
| 10 | `CHATMSG` | server | slot (u8), message number (u8), length (u8), text -- to every player; the sender's own copy is its acknowledgement |
| 11 | `NAMES` | server | count (u8), then each slot's name (16 bytes, NUL-padded; empty: nobody) -- when anyone comes or goes, and every 2 s (since 2026-10-08) |

**Joining** (since 2026-10-07; "Joining and leaving" below).  A client
sends `HELLO` every half second until it has a `WELCOME`; the server answers
with `WELCOME` and `START` at once, and `START` again every half second until
the client sends `INPUT` -- its level is loaded.  The first `INPUT` of a game
starts the clock.  Anyone after that is sent every step from the first, and
comes into the game -- its controls in the steps, not the empty slot's --
once its `INPUT` says it has played all but the last few.  A `HELLO` with
no free slot gets `BYE` 1.  (Before 2026-10-07 the server waited for the
number it was given, and started them together.)

**Playing.**  The server steps every 4/70 s (17.5 a second, `DEMOTICS`).
Each step it takes every player's newest controls -- the highest `seq` it
has (a lost `INPUT` costs nothing: the next one replaces it, and a player
whose controls are late keeps the last ones for that step) -- and sends each
client a `STEPS` with every step after that client's `have`, up to 64 (a
lost `STEPS` is covered by the next one, and a slow machine catches up).  It
never waits.  A client plays the steps in order, as many as it has, and
draws the last.  `have` is the highest step it holds with none missing.

**Checking.**  Every 50 steps each client sends `SYNC` with the game
state's checksum (`MPStep`'s).  The first report of a step sets its sum;
any machine whose sum differs is sent `DESYNC` with the step where its game
parted -- so a machine that joined late is checked against the ones that
played those steps live (since 2026-10-07; before, the server waited for
every slot's report and compared them together).

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

* **The 486 hung once in four hours of deathmatch** (2026-10-09, above):
  2 h 30 min in, mid-floor.  The game, the packet driver or the PicoMEM
  1?  Repeated with the hang watchdog the same day: four hours clean.  If
  it comes again in a test build, the watchdog's report says where -- or,
  if none comes, that the tick itself stopped (interrupts off, or the card
  holding the bus), which is not our loop.  **It came again on
  2026-10-10 in local demo playback with no network in use** (above), so
  it is not the network code; **and a third time 8 h 2 min into the
  retest of the leak fix, at a message box, with the watchdog silent**
  (which does not settle whether the tick stopped: the watchdog reports
  through the packet driver first).  So test builds now paint the answer
  on the screen (below), where no driver is needed to read it.  **Found
  and fixed on 2026-10-12** (below): id's memory manager running out on
  the ninth floor, and id's `Quit` recursing on it.
* Does the 486 smooth the view between steps, or just redraw?

## The crash, a third machine, the console -- 2026-10-11 to 13

**The screen report -- 2026-10-11** (StevenC: "ok so we need to figure
out the 486 issue").  Every BIOS tick, `Hang8` paints into the status
bar's left corner, white on black, the CS and IP the tick interrupted,
a where code and the tick's low byte; the where code is also painted
immediately on the way into and out of every call that waits on
hardware -- `11` the Sound Blaster's stop (`0D0h`), `12` its DMA start,
`13` its `0D4h` (id waits on the DSP with interrupts off and no limit),
`22` an XMS move, `31` the packet driver's send, `41` a DOS read (the
PicoMEM's disk), `00` none.  Every VGA register it touches is read and
put back, so it may interrupt the game anywhere.  A frozen 486 keeps its
picture until the power goes, so the photo can wait for whoever gets to
it first:
* the tick still counting: interrupts are on and the game is stuck at
  that CS:IP (`stage/WOLF3DT.MAP` names it);
* the tick stopped: interrupts went off, or the machine froze -- in the
  where code's call if it is not `00`, else shortly after that CS:IP.
Verified on the V30 (the camera's machine): drawn in the joining box
and in play, a game clean to the end.  `huntbot.py` also puts the real
`WOLF3DV.EXE` back after a test build now.  (The 8-hour run's two endings were not it:
  that was the handle leak, fixed.)

**Found: the floor's music was never let go -- 2026-10-11.**  The first
run with the screen report hung the 486 at 8 h 2 min again, **at the
same step as the run before** (506,006 against 505,998): not a random
fault but the game, replayed the same way.  Its screen was black with
green blocks, the PC speaker sounding one long tone (StevenC) -- and
this machine plays nothing on the PC speaker (`CONFIG.WL6`: AdLib
effects, AdLib music, Sound Blaster digitized), so the processor had
run off into code that was not code.  The screen report could not show
on it.  What found it was making it come sooner:
* starting on the ninth floor (`--map 8`): five minutes, nothing --
  it needs the floors before it;
* **5-minute floors: the hang at the ninth floor, 42 minutes in**;
  **2-minute floors from map 1: at the ninth floor (map 0), 17
  minutes in, at step 17,689 -- twice, to the step**;
* the bot's chat line given the memory figures (`huntbot.py`: block
  handles, `MM_UnusedMemory`, `MM_TotalFree`, `MainPagesAvail`).  The
  page manager's main-memory pages, floor by floor:

  | floor | 1 | 2 | 3 | 4-7 | 8 |
  |---|---|---|---|---|---|
  | pages | 16 | 15 | 12 | 7 | 4 |

  lost on exactly the floors whose song had not been heard yet, kept
  on 5 to 7, which repeat 1 to 4.
* **The cause** (`WL_MP.C`, `NextLevel`): id's `GameLoop` calls
  `StopMusic` at every floor's end, which unlocks the song and makes it
  purgeable; ours went straight to `StartMusic`.  Every song stayed
  locked for good.  The V30 keeps its page cache in EMS and never felt
  it; the 486 (XMS, no EMS -- 189,628 bytes for the game, 16 pages to
  start) paid in cache pages until there were too few.
* **Fixed**: `StopMusic ()` first thing in `NextLevel`.  The same
  2-minute game, 14 floors past the old crash: the pages go 16, 18,
  17, 15 and round again, never down; no desync on either machine.
  `ab.py --full` IDENTICAL to id; mpsweep 20/20 on the 486.
* **Still open** (then): a game that short of memory should stop with a
  message, not crash -- it had 7 pages when it died.  Found the next
  night, below.

**LOWEST's small font -- 2026-10-11** (StevenC: "the time limit screen
on the v30 i couldnt read. all blocky blobs of text").  `LOWVERT`
(part of `LOWEST`) sets the VGA to show the even rows only, all over the
screen, until the next fade; the chat line and the scores draw every row
twice and survive it, but the tally, the catching-up box and the joining
box use id's small font, 5 to 7 rows a letter, and lost half of every
one ("TIME LIMIT" read "IIMF IIMII").  `AllRows` (`WL_MP.C`) puts every
row back before those boxes draw and blanks the view's odd rows, never
drawn; the next 3-D frame sets `LOWVERT` again.  Photographed on the V30:
the tally reads cleanly; the catching-up box takes the same call and has
not been on camera since.

**Found: the crash itself was id's Quit -- 2026-10-12** (StevenC: "Lets
figure out the crash as that is the most important").  The music leak
only ran memory out; what turned "out of memory" into a black screen,
garbage and a stuck PC speaker tone was id's own error path.  Found with
the leak put back (`huntbot.py --leak`, the crash at floor 9 in 17
minutes, the same step every time for a given build) and breadcrumbs:
`huntbot.py --trace` sends one HANG packet per event from the ninth floor
on -- pages fetched and given away, sprites, digitized sounds, the loop's
stages, the floor load call by call -- each carrying SP and the stack's
lowest point so far, with the interrupt vectors checked at every one.
What did NOT do it, each tried and measured:
* the memory manager's block list and the page manager's bookkeeping --
  checked every pass of the loop (`MM_Check`, `PM_Check`), never wrong;
* digitized sound -- a pistol shot started 0.3 s before two deaths, but
  with none from floor 9 on (`--nodigi9`) it died at the same step;
* the packet driver writing to 0:0 for a refused frame -- the PicoMEM
  driver's receive (`8390.ASM`) honours the null;
* the stack running into the near heap in play -- its low point stayed
  at FBCE, 650 bytes above the near heap's top (F938), all game.

**The chain**, as the breadcrumbs gave it on the floor-9 load:
```
L3                       ClearMemory done; DrawPlayScreen next
HACK view 19 need 800    the status bar's 12.8 KB: no room, so id's
                         MM_GetPtr "sizes the view down" ...
SS 408 view 17           ... rebuilding the scalers -- no room for those
QUIT MM_GetPtr: Out of memory!     x 40 and more, SP falling 66h a time:
                         FD44 FCDE FC78 ... past the near heap's top
                         (F930) ... EF52 ... through the data segment
```
id's `Quit` with a message first caches `ERRORSCREEN` -- memory, which
there was none of -- so `MM_GetPtr` failed and called `Quit`, which
cached it again: recursion until the stack had overwritten the game's
data, and the machine ran wild.  It needed only a real out-of-memory,
which the 486 (no EMS, 190 KB for the game) reached once the songs
leaked.  The same chain may explain the 10-09 and `TIMEDEMO` hangs; not
proved.

**Fixed** (StevenC & Claude):
* `Quit` (`WL_MAIN.C`): its screen only if there is room
  (`MM_BombOnError (false)` around the cache) and only once (a re-entry
  goes straight to the message); the message printed either way.
* `CA_CacheGrChunk` (`ID_CA.C`): a big chunk's buffer that cannot be had
  is given up on, not read into segment 0 (with bombing off it was).
* `Picture` (`WL_MP.C`): a view the memory manager sized down is left so
  -- before, it was put back half a second later, into the same
  shortage.
* Proved with the leak put back: at floor 9 the 486 printed
  `MM_GetPtr: Out of memory!` once, went back to DOS by itself and was
  polling the bridge -- no freeze, no power cycle.  Real EXE 334,510
  bytes, `ab.py --full` IDENTICAL to id, mpsweep 20/20 on the 486, and
  a live game on it, both machines, 1-minute floors: 13,000 steps (about
  12 floors), no desync.
* **The overnight soak, 2026-10-12**: the fixed test build (heap checks
  every pass), both machines and two bots, 2-minute floors for 8 hours
  -- 505,155 steps, about 240 floor loads where the leak had died at the
  ninth -- no drop, no desync, no heap fault.  The 486's page cache held
  15 to 17 pages all night (the V30's 33 to 36) and its stack's lowest
  point was FBA2, some 620 bytes clear of the near heap.
* **The eight hours again, 2026-10-12** (StevenC: "can we do an 8 hour
  test now?"): the setup that had died at 8 h 02 min twice -- both
  machines, two bots, 60-minute floors, ESC every minute.  The first try
  stopped at 1 h 50 min with no fault in the game: both machines went
  silent to the server at the same moment for some 17 s and each ended
  itself after 15 s, as it is built to (the 486's `PHASE.LOG`: the game
  ended and its result was sent, never received; no plug cycled).  This
  PC is wired; the two PicoMEMs share one WiFi access point, the likely
  place.  **The second ran the whole way**: 8 h 13 min, 517,814 steps on
  both, no desync, no heap fault.  The ninth floor loaded at step
  ~504,860 and the 486 went on past 506,000, where it had died, for 11
  minutes more; its cache 15 to 17 pages throughout, its stack's low point
  FB6C.

**A third machine, p3box -- 2026-10-13.**  A Pentium II/III (Intel
440BX), MS-DOS 6.22 with HIMEM and DOS high (612 KB free, 64 MB XMS), a
D-Link DE-220PCT at 240h IRQ 3, at 192.168.50.71.  Its `C:\WOLF3D` has the
game's data from the 486 (never committed), `WOLF3DM.EXE`, `PLAY.BAT`,
`W3MENU.EXE`, and its own `WOLF3DM.CFG` (`NAME P3BOX`) and `W3RUN.BAT` at
`VIEW 19`, full screen.  Three machines, 3,000 steps: no desync, p3box at
17.4 pictures a second.  The play server now runs `--players 3`.
Renamed **P3** the same day (StevenC): `NAME P3` in its `WOLF3DM.CFG` and
`W3RUN.BAT` (the old files kept as `.P3B`), and `--box p3` on the bridge.

**Sound: full on the 486 and p3box -- 2026-10-13** (StevenC: "on the 486
and p3box we want full sound").  Both play Sound Blaster digitized effects
and AdLib music and effects:

| | card | how it is set up at boot | `BLASTER` |
|---|---|---|---|
| 486 | AWE64 (ISA PnP) | `PNPSB /I:9 /FM /Q`, then `AWEUTIL /S` | `A220 I2 D1 H5 P330 E620 T6` (IRQ 9 is "2" to the game) |
| p3box | onboard Yamaha YMF740C (PCI, DS-XG) | `CD \YAMAHA`, `SETUPDS /S` (Yamaha's v3.14, `DS.INI` with `IRQMODE=0`) | `A220 I5 D1 T4 P330` |
| V30 | the PicoMEM 2's emulated Sound Blaster 2.0 and OPL3 (since 2026-10-13) | `SET BLASTER`, then Freddy's `PMINIT /sb 1`; `SHELL ... /E:1024` in its `CONFIG.SYS` for the room | `A220 I5 D1 T3` |

p3box's chip is PCI: its Sound Blaster Pro (DSP 3.1) and OPL3 exist only
once Yamaha's `SETUPDS` turns its legacy side on, DMA through the 440BX's
DDMA.  In Yamaha's own interrupt mode (`IRQMODE=1`) the Sound Blaster's
interrupt came on the chip's PCI line, IRQ 10, which the game cannot use
(2, 3, 5, 7); `IRQMODE=0` sends it as IRQ 5 -- proven by SNDPROBE `/T`
(`extras/hwprobe` in the bridge): a silent DMA transfer ending in the
interrupt.  The network card moved to IRQ 3 so 5 is the sound's alone.

**The "static" was the AdLib gunshots** (StevenC: "some static noise on
all 3 systems ... it started with multi player").  Six builds and switches
run one after another on p3box (`TESTSND.BAT`, `TESTSN2.BAT`): with the
Sound Blaster on, shots were clean; with it off (`NOSB`), shots "sound
off" -- and id's own `WOLF3D NOSB` sounds the same.  Without a Sound
Blaster the game plays its AdLib versions of the shots, which id made from
FM noise; multiplayer, with three or four players firing, makes them
constant.  Nothing to fix.  The V30, with no Sound Blaster, always plays
them -- until 2026-10-13, when its PicoMEM 2's Sound Blaster went on (IRQ
5, DMA 1, proven by SNDPROBE's silent transfer).  The game uses it once
its Sound menu says Sound Blaster: `CONFIG.WL6` had been saved with no
card, and is StevenC's to change.  Without `BLASTER` the game would take
IRQ 7, which is the PicoMEM's own.

**Eight hours on three machines -- 2026-10-13** (StevenC: "3 player 1 bot,
8 hour test ... 486 and p3box with full sound").  The 486, p3box and the
V30 with one server bot, deathmatch, no enemies, items back after 30 s,
60-minute floors; the 486 and p3box on their Sound Blasters and AdLib, the
V30 at `LOWEST VIEW 10`.  **Passed: 8 h 13 min, 517,500 steps on all
three, nine floors (E1 M1 to M9), no desync, no drop, no heap fault.**
Nothing drifted all night -- each machine's least free near heap and its
page cache were what they were in the first hour:

| | least free | page cache | stack low point |
|---|---|---|---|
| 486 | 368 bytes | 15 to 17 pages | FB6C |
| p3box | 752 bytes | 30 to 33 pages | FBC2 |
| V30 | 784 bytes | 33 to 36 pages | FBB6 |

The 486's 368 bytes is the same figure the all-maps deathmatch stress
found, so it is the tightest floor's need, not a slow leak.

**A minute of silence is ridden out -- 2026-10-13** (StevenC: fix the
WiFi dropouts).  A game used to end itself after 15 s with nothing from
the server, and a 17-s dropout had ended the first eight-hour try.  Now:
from 3 s the picture holds with **"No word from the server: N s"** over
it, counting, and when the server is heard again the box goes and the
missed steps are caught up as a joiner's are; only after **60 s** does the
game end ("ended by 60 s with nothing from the server").  The server frees
a silent player's slot after 60 s too (`--drop-after`, was 30).
`mpserver --silence STEP:SECS[,...]` makes an outage on demand -- nothing
heard or sent for SECS from that step, the clock running on.  Proved on
the 486 and the V30, `--silence 1500:40,5000:70`: through the 40-s one
both showed the box (photographed on the V30) and played on -- the 486
caught up 704 steps -- and the 70-s one ended both at 60 s, the server
freeing both slots the same moment; 0 desyncs.  mpsweep 20/20 against
the accepted run.  The 486 has `DOS=HIGH` now: 626,336 bytes free, 63 KB
more, for what comes next.

**The server's console -- 2026-10-12/13** (StevenC: "do we have options
inside it? to kick users, send messages, change levels or episodes ...
make it a full fledged server to control everything?").  Commands typed
into the server's window while it runs (`mp/mpconsole.py`, read on a
thread of its own and carried out by the server's loop between packets):

| | |
|---|---|
| `help`, `status` | the commands; the game and every slot -- who, from where, how far behind, inputs, last heard |
| `scores` | every player's frags and deaths this floor -- each SYNC carries them now |
| `say TEXT` | "SERVER: TEXT" on every screen (CHATMSG from slot 255, sent three times, the copies dropped) |
| `kick N [reason]` | BYE 4 with the reason: "Kicked by the server" and the reason on that screen for 3 s, and in its report |
| `ban N`, `ban ADDR`, `unban ADDR`, `bans` | kick, and refuse the address's HELLO from now on -- "banned from this server" |
| `pause`, `resume` | no steps while paused; PAUSED (type 14) every half second, so the game shows "Paused by the server" instead of the dropout box; the clock goes on from the resume |
| `map E L` or `map N`, `nextfloor` | everyone to that floor: the floor ends with "ENDED BY THE SERVER" and the tally, then the server's map |
| `timelimit MIN`, `fraglimit N` | the game's limits, changed in play |
| `next map`/`mode`/`skill`/`bots`/`timelimit`/`fraglimit`/`itemrespawn`/`enemies`/`ff` | the next game's settings (at once if none is running) |
| `end [reason]`, `quiet on/off`, `quit` | end the game; the log off and on; stop the server |

**A change to the game must happen at the same step everywhere**, or the
machines play different games.  So map, nextfloor and the limits are
*events*: the server picks the next step it will make and puts the event in
STEPS' tail (a count, then step, event, argument -- 7 bytes each) of every
packet holding that step, and every machine applies it after playing it.
A joiner who replays the game from the first step meets each event at its
step too -- which is why WELCOME keeps the limits the game *started* with:
a joiner told the new limit at the door would have ended the game earlier
than everyone else did.  An event that lands while the players are in a
floor's tally is lost, by all of them alike.  Older games ignore the tail,
so every machine must have this `WOLF3DM`.

Phase 1 (everything that needs no new game: status, kick, ban, end, next)
was proved on loopback with `mpfake.py`.  Phase 2 live, the 486, the
Pentium II and the V30 as bots, the console typed on a timer and the V30
photographed at each step (`stage/logs/livecon.py`): say, scores, an 18-s
pause, both limits, `map 1 3` (floor 3), `nextfloor` (floor 4) and a kick
with its reason -- 3,936 steps, **0 desyncs**; the V30's report: "ended
by the server, which kicked this machine / the reason: testing the kick".
The first pause banner was drawn once and the bot's scoreboard drew over
it; it is redrawn every second now (proved again, `livepause.py`).
mpsweep 20/20 against the accepted run after each build.

**P3 on a PicoMEM 2 -- 2026-10-13, late.**  The V30's PicoMEM 2 went into
P3 (its WiFi in place of the D-Link, onboard Yamaha sound once the card's
IRQ 5 and DMA jumpers came off -- CLAUDE.md in DOS Bridge has it).  Twenty
minutes of deathmatch with the 486 and a bot, 10-minute floors: **21,000
steps on both, no desync, no drop**; both at 17.4 pictures a second at
`VIEW 19`, the step rate itself, so neither is the limit.

**The second night, three machines on PicoMEM 2s -- 2026-10-14.**  The 486,
P3 (the V30's old PicoMEM 2, onboard Yamaha) and the V30 (a PicoMEM 2 newly
flashed to BIOS 2026-09-27, its Sound Blaster on), a bot, 60-minute floors,
the hunting test build.  (The first start quit itself after five minutes:
the test build answers Y at the 5th ESC unless built `--quit 600`.)

* **The 486 and P3: 514,740 steps, nine floors, no desync**, 16.2 pictures
  a second each; least free 1,136 and 928 bytes, page cache 29 to 32 and 27
  to 30 -- `DOS=HIGH` gave the 486 twice the cache it had the night before.
* **The V30 locked up at 1 h 30 min** (step 94,530), and stopped dead --
  the watchdog's block frozen on screen, so the clock tick itself had
  stopped.  Its report (`stage/hang-192.168.50.66.log`, `mp/hangtrace.py`):
  inside DOS, in a disk read (the disk BIOS at 0070:07A1), the PicoMEM card
  being the disk -- the card never answered.  The night before, on the old
  firmware, it ran eight hours.  Then, with nothing else on the network:
  300 reads of `VSWAP.WL6` through the card (450 MB, 20 minutes, a steady
  40.6 s per ten) and the whole demo loop fifteen times (4 h 20 min of page
  loads, sound and the timer together) -- **both clean**.  So far it has
  only happened in a networked game; once is not yet a pattern.
* **Rejoining it found a bug of ours**: back in the game, the V30 took slot
  3 again -- the slot its hung session had held -- and while catching up it
  replayed that session's presence and then its drop, and took the drop for
  its own ("the server stopped hearing this machine"), at replayed step
  95,600 of 111,000.  **Fixed**: WELCOME carries the step a machine joined
  at, and the game ignores its slot's comings and goings before it.  Proved
  live (`stage/logs/rejoin.py`): the 486 kicked at step 1,168, back into the
  same slot at 1,830, caught up through its own earlier session and the
  kick, and stayed in to the end -- 3,901 steps, no desync.  mpsweep 20/20.

**Every co-op floor, three machines -- 2026-10-14, afternoon.**  All sixty
floors in co-op with enemies, 1,400 steps each (80 s), the V30 joining
first and playing every step live, the 486 and P3 catching up behind it, a
bot, the hunting test build (`stage/logs/stress.py coop`).  **No desync on
any floor, on any machine.**  The least free memory and page cache seen:

| | least free | fewest cache pages | stack's low point |
|---|---|---|---|
| 486 | 1,056 bytes (E1L2) | 28 (E3L9) | FB98 (E1L3) |
| P3 | 848 bytes (E1L2) | 26 (E3L9) | FBB8 (E3L1) |
| V30 | 608 bytes (E6L10) | 31 (E3L9) | FBA8 (E3L4) |

The V30's figures cover 59 floors: on E4L10, the heaviest, it was still
behind (1,088 steps of 1,400) when the server ended the game on time --
the slow machine catching up, not a fault; it came back and polled.

* **The V30 locked up twice more on the way** -- on E1L5 at 12:08 and on
  E3L4 at 13:33, both during play, the screen black, the machine drawing
  its usual 36 W and polling nothing.  The first was in DOS again
  (0032:758E), with no hang report.  StevenC found the V30's CH375 USB card
  partly out of its ISA slot after the first and reseated it; the second
  came after that, so the card was not the whole of it.
* **The firmware is not it either**: P3 runs a PicoMEM 2 on the same
  firmware (BIOS 2026-09-27) and played every floor clean.  What only the
  V30 does is use the **PicoMEM's emulated Sound Blaster** -- the 486 has
  a real AWE64, P3 the Yamaha with its PicoMEM's Sound Blaster off -- and
  every hang has come since that went on (2026-10-13).  Its `CONFIG.WL6`
  has digitized sound OFF, so no samples were playing; but the game finds
  the Sound Blaster and sets it up regardless (the DSP reset, IRQ 5
  hooked), and on the PicoMEM the Sound Blaster, the disk and the WiFi are
  all one Pico.
* **With `NOSB`** (id's own switch: the game leaves the Sound Blaster
  alone) the V30 played E3L4 -- where it had just hung -- and every floor
  after it, 37 floors in 78 minutes, clean.  The hangs had come 4, 20 and
  90 minutes into a run, so that points at the Sound Blaster without proving
  it: the next 8-hour run has the V30 on `NOSB`.  If it holds, the card's
  Sound Blaster emulation and its WiFi do not mix on this machine, and
  the V30 plays networked games with `NOSB` (or `PMINIT /sb 0`).

**The console during a floor's tally, live -- 2026-10-14, evening.**  An
event that landed while the players were in a floor's tally used to be
lost; now every machine applies it in the tally (`map` picks the coming
floor, the limits take effect).  The three machines as bots, the console
driven through the control port (`stage/logs/livetally.py`, `mp/mpctl.py`):
`nextfloor`, and 2 s later -- in the tally on every machine -- `map 1 5`,
`timelimit 7`, `fraglimit 50`.  The V30 photographed 40 s on: **floor 5,
"DEATHMATCH to 50, 6:21 left"** -- all three applied.  A second round
(`map 1 1`) on the 486 and P3; 6,919 steps through both, no desync.

**And the V30 hung again, with `NOSB`** -- a minute into that floor 5
(E1L5, as at 12:08), the picture frozen, no hang report.  So it is not the
game's use of the Sound Blaster; the 78 clean minutes were luck.  What only
the V30 does now: Wolf3D's page cache in **EMS**, which its PicoMEM serves
(PMEMMSC, and XMSSC's XMS out of that EMS), while the same Pico is the
disk and the WiFi -- P3 runs HIMEM and no PicoMEM EMS, and the V30's eight
clean hours were on its previous card.  Next: the V30 with `NOEMS NOXMS`.

**The V30 with `NOEMS NOXMS` -- 2026-10-14, 16:06 to 18:19.**  The V30 power-
cycled through its plug at StevenC's word (it came back by itself, no F1),
then all sixty co-op floors again, the V30 on `NOSB NOEMS NOXMS` -- id's own
switches, so its page cache is in main memory (32 to 35 pages, as before)
and its PicoMEM serves no EMS while it plays.  **2 h 13 min, every floor,
no hang and no desync** -- longer than any run of it since 10-13 (the hangs
had come 4, 20, 60 and 90 minutes in).  The 486 hung once (E3L2, step 443,
no report; power-cycled, and clean for the rest) -- it has no EMS at all,
so that is a matter of its own.  The 8-hour run tonight
(`stage/logs/long15.py`) has the V30 on the same switches: if it holds,
the V30's PicoMEM 2 on the 09-27 firmware does not stand EMS, the disk and
the WiFi together, and the V30 plays networked games with `NOEMS NOXMS`.

**The night of 2026-10-14/15: the V30's freeze is in the AdLib code.**  The
8-hour run (`stage/logs/long15.py`; deathmatch, 60-minute floors, a bot)
with the V30 on `NOSB NOEMS NOXMS`.  The 486 and P3 played it through with
no desync and no drop.  The V30 dropped out four times:

* **Three times its WiFi stopped receiving** (18:36, 21:36, 23:18) -- the
  game's own report, pulled off the box afterwards: "ended by 60 s with
  nothing from the server", no desync; the agent then failed 30 polls
  ("no ARP reply" on its screen), `NETCHK` cold-booted it and it came back
  by itself, 6 to 13 minutes on.  Sent back in by hand each time, it
  caught up (up to 291,000 steps in an hour, 81 a second) and played on.
  The same card's WiFi did this once in the morning too (07:08).  P3's
  PicoMEM 2, the same model and firmware, has not.
* **Once it froze** (00:36, catching up) -- the watchdog's corner block
  stopped at CS:IP 3DB6:17FE, "where" 00, tick 3A, the tick no longer
  moving: interrupts off, the machine stopped.  The game loads at 14CE on
  the V30 (the overnight report), so that is **`SD_PlaySound`**
  (id_sd.c:2155 in the test build) -- and what it does next, with
  digitized sound off, is `SDL_ALPlaySound`: 22 writes to the AdLib's
  registers **with interrupts off**.
* So: the freezes came with EMS and without it, with the game's Sound
  Blaster and without it, and the one caught red-handed was about to talk
  to the AdLib.  **On the V30 the AdLib is the PicoMEM's emulation** --
  the 486 has the AWE64's real OPL3, P3 the Yamaha's -- and since 10-13
  that is a new PicoMEM 2 on the 09-27 firmware, the one machine where that
  firmware's AdLib is used at all.  An I/O write the card does not finish
  holds the ISA bus, and with interrupts off nothing else ever runs.  The
  next test: the V30 with `NOAL` (effects on the PC speaker, no music) and
  everything else as normal, EMS and Sound Blaster included.

The run ended at 02:25 on time: **504,380 steps in 8 h 0 min (17.50 a
second), the 486 and P3 in it from first step to last, no desync, no drop,
no packet dropped by the server**; both at 16.2 pictures a second at
`VIEW 19`.  The V30 is left frozen for StevenC.

**The V30 with `NOAL` -- 2026-10-15, 05:06 to 13:06: eight hours clean.**
The same game as the night before (`stage/logs/long16.py`: deathmatch,
60-minute floors, a bot, the hunting test build), the V30 power-cycled
first and then exactly as it normally runs -- its page cache in EMS, its
Sound Blaster on -- but with `NOAL`, id's own switch: no AdLib, the effects
on the PC speaker, no music.  **503,905 steps, all three machines in from
the first step to the last, no desync, nobody dropped, no packet dropped
by the server**; the V30 played 503,903 of them (3.5 pictures a second at
`LOWEST VIEW 10`), the 486 and P3 16.3 and 16.2.  **No freeze and no WiFi
going deaf** -- the night before, with the AdLib on and everything else
off, it froze once and went deaf three times in the same eight hours.

So both of the V30's faults since 2026-10-13 go with **its PicoMEM 2's
emulated AdLib**, on the 09-27 firmware that card has run since that day.
The 486 and P3 have real OPL3 chips and never use a PicoMEM's AdLib, which
is why the same firmware on P3's card never showed it.  The V30's eight
clean hours of 2026-10-13 were on its old card and the 06-16 firmware.
Until that is settled the V30 plays networked games with `NOAL`; the next
step is the V30's card back on the 06-16 firmware, to see whether the
AdLib is sound there (StevenC's call -- it has never been rolled back).

## Phase 5: the server on DOS -- 2026-10-15

**`MPSRV.EXE`** (`mp/mpsrv.pas`, `mp/srvnet.pas`; `python mp/mkmpsrv.py`)
is `mp/mpserver.py` on a DOS machine, written in Free Pascal for the plain
8086, and it runs on P3 -- StevenC's choice, the fastest of the three.  The
same protocol, rules and behaviour as the Python server, which stays the
reference: joining at any time and catching up, every machine's checksums
compared step by step, bots, and the whole console -- typed at its keyboard,
or sent over UDP 31999 from any machine on its subnet
(`python mp/mpctl.py --host 192.168.1.30 status`, `mp/mpctl.py` grew
`--host` for it).

* **The network** is `mp/srvnet.pas`: the DOS Bridge's `net.pas` -- its
  interrupt-time receiver byte for byte, its packet-driver calls, its
  answering ARP for our own address -- made to serve many: it listens, takes
  any datagram for our address, learns each player's MAC from its frames and
  sends to any of them.  The bridge's own unit is not touched: `UGET` and
  `UPUT` are built from it.
* **The clock**: the PIT at 70 Hz while it serves, as the game's own is,
  the BIOS's INT 8 still fed at 18.2; a step every 4 ticks, exactly the
  game's.  Ctrl-C cannot leave it running (INT 23h is held), and every way
  out puts the timer back.
* **The history** -- every step of the game, for a machine joining late --
  goes into XMS: 32 MB, 2.8 million steps, 44 hours of four players; the
  newest 4,096 steps stay in memory too.  Without XMS, `MPSRV.HIS` on the
  disk.
* **A status line** on its screen moves with the clock (a spinner, the
  step, how many are in, packets in and out, and what is being typed), so a
  quiet server never looks hung.

**What the first trials found: P3's PicoMEM WiFi garbles a frame sent
hard on the heels of the last.**  Three fake players (`mp/mpfake.py`) on one
PC against MPSRV on P3: the one in slot 2 got about 50 STEPS packets of
800, and slot 3 got its copies -- slot 2's chat arrived at slot 3, twice.
The server built every frame right (it counted them, and read back the
port in each), the card refused none, and a ring of eight transmit buffers
changed nothing; a 1 ms pause after each frame made it go away entirely.
So the card's WiFi -- or the packet driver in front of it, `PM2000` 0.5-SC5,
the faster rebuild P3 has from the V30's SD card -- loses or mangles a
frame that follows another within about a millisecond.  On a PC the
mangled ones fail their UDP checksum and are dropped; **the game's own
stack does not check UDP checksums**, so the first real game on MPSRV took
mangled STEPS for real rows and desynced (the V30 against the 486, 14
times from 250 steps after a floor change).  MPSRV now pauses 1 ms after
each frame (`--txgap`, microseconds, calibrated against its clock at
start) and drops any datagram whose UDP checksum is wrong, as a PC would.
Whether the driver or the card's firmware is to blame is still open: the
original driver, `C:\DRIVERS\PM2000.ORG`, would answer it.

**Proven on P3** after that: three fake players with 3% loss -- every
row and every event the same for all three; and a real game, the 486 and
a bot from the start and the V30 (`NOAL`) joining at step 5,730, catching
up 7,040 steps in 52 s out of XMS, then the console from the PC -- status,
say, scores, a pause, `nextfloor` with `map 1 3` and both limits during
the tally, and a kick with its reason: **8,495 steps, 0 desyncs**, the
card's 11,012 frames all sent.  The same script against `mpserver.py`:
0 desyncs too.

**Eight hours on it -- 2026-10-15, 14:52 to 22:52.**  P3 serving (MPSRV,
`--timelimit 60`, a server bot), the 486 and the V30 (`NOAL`) playing the
hunting test build, watched through MPSRV's console over the network every
30 s (`stage/logs/long17.py`): **504,246 steps in 28,814 s (17.50 a
second), 0 desyncs, neither machine out once, no power cycle**; 1,043,389
frames sent and none refused, 0 datagrams with a wrong checksum, 7 frames
dropped coming in (the receive ring full for a moment; the protocol sends
them again).  The same eight hours the Python server gives.  Still to do:
every machine taking a turn as the server.

**And on Windows: `MPSRVW.EXE` -- 2026-10-15/16** (StevenC: "can we make a
windows wolf3d server now too? with freepascal?").  The same `mp/mpsrv.pas`
with `{$IFDEF WINDOWS}` around the five parts that touch DOS: the network
(`mp/winnet.pas`, WinSock behind the same procedures as `srvnet.pas`), the
70 Hz clock (the performance counter), the history (memory: room for 67
million steps), the console (a thread reading lines from the window or a
pipe; the status in the window's title; the console port on 127.0.0.1 only,
as `mpserver.py`'s), and Ctrl-C (a clean stop: everyone told goodbye).
`python mp/mkmpsrv.py --windows`, FPC's own i386-win32: 74 KB.

The first try on the network heard nothing at all: at its first run Windows
had made two inbound *block* rules for `mpsrvw.exe` (its "allow access?"
prompt went unanswered), and a block rule beats the port's allow rule.
StevenC removed them.  Then the live test (`stage/logs/livesrv.py --win`)
with the PC serving **all three DOS machines at once**: the 486 and P3 from
the start, a bot, the V30 (`NOAL`) joining at step 5,300-odd and catching up
7,612 steps in 76 s, then pause, `nextfloor` with `map 1 3` and both limits
in the tally, and a kick -- **9,185 steps, 0 desyncs**, the 486 and P3 at
17.0 pictures a second, 21,493 frames sent and none lost.

**Every machine a turn as the server -- 2026-10-16** (StevenC: "can we try
the 486 as the server? then the 8086 as the server? ... run the tests with
all the systems and a bot or bots as needed").  `stage/logs/livesrv2.py`:
MPSRV on one DOS machine, the other two playing -- one from the start, one
joining after step 5,300 so its catching up comes out of the server's XMS --
the four slots filled with bots, then the console from this PC: say,
scores, a pause, `nextfloor` with `map 1 3` and both limits in the tally,
and a kick of the late machine.

| server | players | steps | desyncs | frames dropped coming in |
|---|---|---|---|---|
| P3 (Pentium II) | 486, V30 late, 1 bot | 8,495 (and 8 hours: 504,246) | 0 | 0 (7 in 8 h) |
| 486 | P3, V30 late, 1 bot | 8,501 | 0 | 1 |
| 486 | P3, V30 late, 2 bots | 9,029 | 0 | 0 |
| V30 | 486, P3 late, 2 bots | 7,603 | 0 | 518 |
| V30, flushing its log once a second, 16-slot ring | 486, P3 late, 2 bots | 7,597 | 0 | 205 |
| this PC (`MPSRVW`) | 486, P3, V30 late, 1 bot | 9,185 | 0 | 0 |

The 8 MHz V30 serves a full game at the step rate -- 17.5 a second -- and
catches a fast machine up out of XMS that is itself served from its
PicoMEM's EMS (P3: 5,800 steps in under a second).  What it cannot quite do
is empty the packet driver's receive ring as fast as two players fill it:
the 486 sends its controls at its own frame rate, 17 times a second.  Its
first run dropped 518 frames; half of that was MPSRV writing `MPSRV.LOG` to
the disk after every line -- the V30's disk is its PicoMEM's, and slow -- so
the log now goes to the disk once a second, and the ring has 16 slots (8 of
the transmit ring's buffers gave the room: they were never the cure).  205
then, and it costs nothing: a lost INPUT is replaced by the next, which
comes a step later.
