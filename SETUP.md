# Setting up a network game

Written by **StevenC** and **Claude** (Anthropic), 2026-10-16.

A step-by-step guide to playing Wolfenstein 3-D over a network with
`WOLF3DM.EXE`: getting each DOS machine onto the network, setting up the
game on each one, running a server, and what to do when something doesn't
work.  For *how* it works, see [MULTIPLAYER.md](MULTIPLAYER.md); this file
is only the how-to.

## The picture

```
    DOS machine 1 ----\
    DOS machine 2 -----+---- your network ---- the SERVER
    DOS machine 3 ----/                        (a DOS machine, a Windows
    (up to four players)                        PC, or any PC with Python)
```

Every player runs `WOLF3DM.EXE`.  One machine runs the server, which keeps
time for everyone and passes each player's controls to the others.  The
server can be a DOS machine (then that machine doesn't play), a Windows PC,
or any PC with Python.  Up to four players; the server can fill empty
slots with bots.

Everything happens on UDP port **31992** (the server's console uses 31999).

## What you need

- **The game data**: the *registered* Wolfenstein 3-D 1.4 files
  (`VSWAP.WL6`, `GAMEMAPS.WL6` and the rest) on every player's machine.
  They are not included.  The shareware `*.WL1` files won't work.
- **On each player's DOS machine**: a NEC V20/V30, an 80186, or a 286 and
  up (the network game uses 186 instructions; a plain 8086 or 8088 can run
  the DOS server, but not play yet), VGA, DOS, at least about **550 KB of
  free conventional memory**, and a **network card with a packet driver**.
  XMS or EMS helps (it becomes page cache) but isn't required.
- **The download**: `W3DMP.ZIP` from the
  [releases page](https://github.com/jdredd87/Wolf3D-V30/releases).

## Step 1: get each DOS machine onto the network

The game has its own small network code.  It needs two things on each
machine: a **packet driver** loaded, and a text file saying the machine's
**address**.

### The packet driver

A packet driver is a small TSR from your network card's maker (or the
free Crynwr collection) that the game talks to.  Load it before running the
game, usually from `AUTOEXEC.BAT`, at software interrupt **0x60**:

| card | example |
|---|---|
| PicoMEM (its WiFi) | `PM2000.COM 0x60` |
| NE2000 or a clone | `NE2000.COM 0x60 3 0x300` (interrupt, IRQ, I/O port) |
| D-Link DE-220PCT | `DE22XPD.COM 0x60 0x240 3` |

The game finds the driver by itself anywhere from 0x60 to 0x80.

### The address file

The game reads its address from the first of these it finds:

1. the file named by `%MTCPCFG%` -- if you use mTCP, you already have one;
2. `C:\AI\NET.CFG` -- create it if you have neither.

It needs these lines (use your own network's numbers):

```
IPADDR 192.168.1.21
NETMASK 255.255.255.0
GATEWAY 192.168.1.1
```

Add `PACKETINT 0x60` if the driver is somewhere the game shouldn't search.
Give each machine **its own fixed address** that nothing else on your
network uses.  If you use mTCP's `DHCP`, run it at boot so the address in
the file is current.

## Step 2: the game on each player's machine

1. Copy `WOLF3DM.EXE`, `W3MENU.EXE` and `PLAY.BAT` from the zip into the
   directory with your `*.WL6` files.  (They replace the base package's
   menu with one that has a network page.)
2. Check the memory: `MEM`'s "largest executable program size" should be
   about 550 KB or more.  Free more by loading drivers high, or leaving out
   what the game doesn't need (a CD-ROM driver is a common one).
3. Everyone must run **the same `WOLF3DM.EXE`**: the server refuses a
   machine with a different build.

## Step 3: the server -- pick one

All three are the same server, with the same switches and the same
console.  `MPSRV /?` or `MPSRVW /?` lists every option with examples.

### A. On a DOS machine: `MPSRV.EXE`

1. It needs a packet driver and an address file, exactly as in step 1.
2. Copy `SERVER\MPSRV.EXE` to any directory it can write to (it keeps
   `MPSRV.LOG` there).
3. Run it, for example:
   ```
   MPSRV --mode dm --noenemies
   ```
4. A status line at the bottom of the screen moves the whole time.  Type
   console commands and press Enter.

A machine that serves can't also play.  It keeps the game's history in XMS
so players can join hours into a game; without XMS it uses `MPSRV.HIS` on
the disk.  Even an 8 MHz V30 can host a full game.

### B. On Windows: `MPSRVW.EXE`

1. Copy `SERVER\MPSRVW.EXE` anywhere and run it from a command prompt:
   ```
   MPSRVW --mode dm --noenemies
   ```
2. **Windows Firewall**: the first time it runs, Windows asks whether to let
   it on the network.  **Allow it, for private networks.**  If that question
   is dismissed or ignored, Windows makes a rule that *blocks* it, and the
   players will never connect.  See "Troubleshooting" for how to remove that
   rule.
3. The console is its window; the status shows in the window's title.

### C. With Python: `mpserver.py`

1. Install Python 3 and copy the whole `SERVER` folder.
2. Run:
   ```
   python SERVER\mp\mpserver.py --mode dm --noenemies
   ```
3. On Windows, Python needs the same firewall permission as `MPSRVW`.

### The server's address

Players need the server machine's address: on Windows run `ipconfig`; on
DOS, it's the `IPADDR` in its address file.

## Step 4: join and play

On each player's machine, in the game's directory:

```
WOLF3DM NET 192.168.1.10 NAME STEVE
```

or type `PLAY`, press **M** for the network page, and fill it in: **S**
the server's address, **Y** your name, **O** the port (only if the server
uses another), then **J** to join.  The server and your name are remembered
in `WOLF3DM.CFG`, so next time `WOLF3DM NET` on its own is enough.

| key | does |
|---|---|
| T | chat |
| TAB | the scores |
| SPACE | respawn, when dead |
| ESC | asks, then leaves the game |

The game starts as soon as the first player has loaded the level.  Anyone
who joins later sees **"Catching up: N steps to go"** while their machine
replays the game so far, then walks in.  A 486 or better catches up an
hour's game in under a minute; an 8 MHz V30 takes six to fifteen minutes.
A network dropout of up to a minute is ridden out the same way.

**On a slow machine** (an 8 MHz 8086/V30), use the least detail:

```
WOLF3DM NET LOWEST VIEW 10
```

(or **A** on the menu's network page).  It still plays the same game; it
just draws fewer frames.

## Running the game

### Good settings to start with

| game | command |
|---|---|
| Deathmatch, empty map, items return after 30 s | `MPSRV --mode dm --noenemies` |
| A timed match: 10 minutes or 25 frags a floor | `MPSRV --mode dm --noenemies --timelimit 10 --fraglimit 25` |
| Two players plus two bots | `MPSRV --players 4 --bots 2 --mode dm --noenemies` |
| Co-op from episode 3, hardest skill | `MPSRV --mode coop --skill 3 --map 20` |
| Co-op without friendly fire | `MPSRV --mode coop --ff off` |

(For `MPSRVW` or `mpserver.py` the switches are the same.)

`--map N` picks the first floor: N is (episode - 1) * 10 + (floor - 1), so
E1L1 is 0, E2L1 is 10 and E6L10 is 59.

### The console

While a server runs it takes commands: type one and press Enter.  All
three servers have the same ones, and `help` lists them.

**Seeing what is going on**

| command | does |
|---|---|
| `help` (or `?`) | lists the commands |
| `status` | the game, and every slot: who, from what address, how far behind, how long since they were last heard |
| `scores` | everyone's frags and deaths |

**The players**

| command | does |
|---|---|
| `say TEXT` | a message on every player's screen, from SERVER |
| `kick N [reason]` | puts slot N (1-4) out of the game; their screen shows the reason |
| `ban N` or `ban ADDRESS` | kicks them, and refuses that address from then on |
| `unban ADDRESS` | lets that address back in |
| `bans` | lists the banned addresses |

**The game in progress**

| command | does |
|---|---|
| `pause` / `resume` | holds the game for everyone, then lets it go on |
| `map E L` (or `map N`) | everyone to episode E, floor L now -- after the floor's tally |
| `nextfloor` | everyone to the next floor now |
| `timelimit MIN` | changes the time limit now (`0`: none) |
| `fraglimit N` | changes the frag limit now (`0`: none) |
| `end [reason]` | ends the game for everyone; the server waits for the next one |

**The next game**

These settings take effect when the next game starts -- straight away
if none is running -- because every machine in a game must play by the
same rules.

| command | does |
|---|---|
| `next` | shows the settings now, and any waiting for the next game |
| `next map E L` (or `next map N`) | the floor it starts on |
| `next mode dm` / `next mode coop` | deathmatch or co-op |
| `next skill 0-3` | the difficulty, as the game's own menu |
| `next bots N` | how many slots the server plays itself |
| `next timelimit MIN` / `next fraglimit N` | the limits |
| `next itemrespawn SECS` | how long before a taken item comes back |
| `next enemies on\|off` | enemies, or an empty map |
| `next ff on\|off` | friendly fire in co-op |

**The server itself**

| command | does |
|---|---|
| `quiet on\|off` | stops (or restarts) the log lines scrolling past |
| `quit` | ends the game and stops the server |

**An example**, during a deathmatch:

```
scores
say On to E2L1 -- 15 minutes a floor from here
map 2 1
timelimit 15
```

Everyone sees the message at once; after the tally everyone goes to
E2L1, and from then on a floor ends after 15 minutes (a time limit
counts from the start of the floor).

**From another window or another PC.**  `python SERVER\mp\mpctl.py
COMMAND` sends one command to a running server and prints its answer --
`mpctl.py status`, `mpctl.py say Back in 5`, any of the above.  For the
Windows and Python servers it works on the PC the server runs on.  The DOS
server listens on its own address, so any PC on its network can reach it
with `--host`:

```
python SERVER\mp\mpctl.py --host 192.168.1.30 status
```

## Troubleshooting

| what you see | what it means, and what to do |
|---|---|
| `no packet driver` | Load the card's packet driver first (step 1). |
| `no IPADDR in %MTCPCFG% or C:\AI\NET.CFG` | Write the address file (step 1). |
| `Joining the server...` and then `No answer from the server in 90 seconds` | The server can't be reached.  Check that it's running, that the address is right, and on Windows the firewall (below). |
| `The server is full -- try again when someone leaves` | All four slots are taken (bots count).  Start the server with fewer `--bots`. |
| `The server is playing a different WOLF3DM` | Use the same `WOLF3DM.EXE` on every machine. |
| `No word from the server: N s` | The network dropped.  It recovers by itself within a minute; after 60 s the server frees the slot. |
| `DESYNC reported` at the end | The machines disagreed.  This shouldn't happen.  If it does, note what happened and let us know. |
| A machine with a **PicoMEM** card freezes in network games | Its emulated AdLib can lock the machine up.  Add `NOAL` (sound effects then play on the PC speaker): `WOLF3DM NET NOAL`. |
| Players catch up very slowly | That's the machine's speed: an 8 MHz machine needs minutes to replay an hour's game.  Join early. |

**Windows Firewall is blocking the server.**  Open "Windows Defender
Firewall with Advanced Security", go to *Inbound Rules*, and delete any
**Block** rule for `mpsrvw` or `python`.  Or, in an Administrator
PowerShell:

```
Remove-NetFirewallRule -DisplayName "mpsrvw"
New-NetFirewallRule -DisplayName "Wolf3D multiplayer (UDP 31992)" -Direction Inbound -Protocol UDP -LocalPort 31992 -Action Allow -Profile Private,Domain
```

The second line lets any program receive on UDP 31992 from your local
network, so whichever server you run will get through.

**Across a router or the Internet.**  The game sends to its `GATEWAY` for a
server on another subnet, and a server behind a home router needs UDP 31992
forwarded to it.  We've only played on one home network, so this is the
untested part.

## Quick reference

| | |
|---|---|
| game port | UDP 31992 (`--port N` on the server, `PORT N` on the game) |
| console port | UDP 31999 (`--control N`; 0 turns it off) |
| player files | `WOLF3DM.EXE`, `W3MENU.EXE`, `PLAY.BAT`, beside the `*.WL6` files |
| remembered settings | `WOLF3DM.CFG` (server, port, name) |
| server files | `MPSRV.EXE` (DOS), `MPSRVW.EXE` (Windows), `SERVER\mp\*.py` (Python) |
| server log | `MPSRV.LOG`, beside the server |
| help | `MPSRV /?`, `MPSRVW /?`, and `help` in the console |
