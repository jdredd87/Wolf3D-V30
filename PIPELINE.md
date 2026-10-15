# How it is built, checked, deployed and played

Written by **StevenC** and **Claude** (Anthropic), 2026-10-15.

Nothing in this repository is compiled on the PC it is edited on. 64-bit
Windows cannot run DOS programs, and id's game is built the way id built
it -- Borland C++ 3.1 and TASM -- on a real DOS machine. Every DOS machine
here is reached over the network through
[DOS Bridge](https://github.com/jdredd87/DOSBridge), which treats a DOS PC
as a test runner: a command goes in, it runs there, its output and exit
code come back.

## The machines

```mermaid
flowchart LR
    subgraph PC["Windows 11 PC"]
        direction TB
        GIT[("git: this repository<br/>WOLFSRC, mp/, launcher/")]
        TOOLS["w3dbuild.py · ab.py · to8086.py<br/>refsrc.py · gendemo.py · mkrelease.py"]
        DOSD["dosd.py -- DOS Bridge daemon<br/>jobs + files: UDP 8069 (TFTP)<br/>HTTP 8080 · results 8081 · pulls 8082"]
        SRV["mp/mpserver.py -- game server<br/>UDP 31992 · console 127.0.0.1:31999"]
        GIT --> TOOLS --> DOSD
    end

    subgraph DOS["DOS machines -- each polls dosd every few seconds"]
        direction TB
        D486["<b>486</b> (66 MHz) -- box dx486<br/>Borland C++ 3.1 in C:\BCPP<br/><i>builds every EXE; runs the picture checks</i><br/>AWE64: Sound Blaster + OPL3"]
        V30["<b>NEC V30</b> (8 MHz, 8087) -- box v30<br/><i>the target: timing, play</i><br/>PicoMEM 2: disk, WiFi, EMS, AdLib, Sound Blaster"]
        P3["<b>Pentium II</b> (Intel 440BX) -- box p3<br/><i>the third player; picture checks</i><br/>Yamaha YMF740C: Sound Blaster Pro + OPL3"]
    end

    DOSD <-->|"WiFi / LAN<br/>jobs, files, results"| D486
    DOSD <--> V30
    DOSD <--> P3
    SRV <-.->|"UDP 31992<br/>the network game"| D486
    SRV <-.-> V30
    SRV <-.-> P3
    GIT <-->|push / pull| GH[("GitHub<br/>jdredd87/Wolf3D-V30")]
```

Each DOS machine boots into DOS Bridge's agent (`C:\AI\AI.BAT`), which asks
`dosd` for a job every few seconds. A job is a batch file: fetch any files
it needs, run the commands, send the output back.

```mermaid
sequenceDiagram
    participant T as a script on the PC<br/>(w3dbuild.py, ab.py ...)
    participant D as dosd.py
    participant B as a DOS machine's agent
    T->>D: dosctl exec / deploy / pull --box ID
    loop every few seconds
        B->>D: anything for me?
    end
    D-->>B: the job's batch (TFTP)
    B->>D: UGET the files it names (CRC-checked as they arrive)
    Note over B: runs the commands,<br/>output into C:\WORK\OUT.TXT
    B->>D: UPUT the output and the exit code
    D-->>T: printed, and the exit code returned
```

## Building, checking, deploying

```mermaid
sequenceDiagram
    autonumber
    participant PC as PC (git, scripts)
    participant A as 486 -- dx486
    participant V as V30 -- v30
    participant P as Pentium II -- p3
    participant G as GitHub

    Note over PC: edit WOLFSRC
    PC->>A: w3dbuild.py build: WOLFSRC zipped, sent to C:\W3D
    Note over A: BUILD86.BAT -- TASM (P186) for the assembler,<br/>BCC -1 for the C, TLINK
    A-->>PC: WOLF3DV.EXE + WOLF3DV.MAP pulled back
    PC->>A: ab.py --full -- the whole attract loop, 5,386 frames
    A-->>PC: view + screen checksums: must be id's own renderer's
    opt a second machine, a second CPU
        PC->>P: ab.py --full --box p3
        P-->>PC: the same checksums
    end
    PC->>V: ab.py: timing, interleaved rounds against the last build
    V-->>PC: play ticks -- kept only if faster, and PIXEL-IDENTICAL
    PC->>V: w3dbuild.py deploy: WOLF3DV.EXE, the PLAY menu, the demo reel
    PC->>G: commit, push
```

The same 486 builds three more trees, each in a folder of its own so none
of them disturbs another:

| tree | made by | built in | gives |
|---|---|---|---|
| `WOLFSRC` (branch `v30-8086`) | -- | `C:\W3D` | `WOLF3DV.EXE`, the V20/V30/186 game |
| a copy with every 186 instruction spelled the 8086 way | `to8086.py` | `C:\W3D8` | `WOLF3D8.EXE`, for a plain 8086/8088 (`w3dbuild.py build8086`) |
| this tree with id's own renderer put back | `refsrc.py` | `C:\W3R` | `WOLF3DO.EXE`, the yardstick the checksums come from |
| branch `bsp` | -- | `C:\W3D` | `WOLF3DB.EXE` |
| branch `multiplayer` | -- | `C:\W3D` | `WOLF3DM.EXE` (and `mp/huntbot.py`'s test build `WOLF3DT.EXE`) |

## The branches

```mermaid
flowchart LR
    M["master<br/>id's source, as released"] --> V["v30-8086<br/>WOLF3DV · WOLF3D8<br/><i>fixes go in here first</i>"]
    V -->|merged| B["bsp<br/>WOLF3DB"]
    V -->|merged| MP["multiplayer<br/>WOLF3DM + mp/"]
    V --> R1["release/W3DV30.ZIP<br/>(mkrelease.py)"]
```

Fixes flow from `v30-8086` into the other two, never the other way.

## Playing over the network

```mermaid
flowchart TB
    S["mp/mpserver.py on the PC<br/>keeps the clock: 17.5 steps a second<br/>passes every player's controls to everyone<br/>bots · console · control port (mp/mpctl.py)"]
    S <-->|"controls up, steps down"| A["486<br/>WOLF3DM NET pc"]
    S <-->|UDP 31992| V["V30<br/>WOLF3DM NET pc LOWEST VIEW 10"]
    S <--> P["Pentium II<br/>WOLF3DM NET pc VIEW 19"]
    A -. "a checksum every 50 steps" .-> S
    V -.-> S
    P -.-> S
```

Every machine plays every step of the same game from the same inputs --
the server sends no positions, only controls -- so the checksums every 50
steps must agree, and a machine that differs is caught at once.
[MULTIPLAYER.md](https://github.com/jdredd87/Wolf3D-V30/blob/multiplayer/MULTIPLAYER.md)
on that branch explains why that works, and how a machine joining late
catches up.

The long tests drive the same machines unattended -- every floor of every
episode, or eight hours at a stretch -- with small scripts kept out of the
repository (in the git-ignored `stage/`): they start the server, send each
machine in as a bot through `dosctl`, watch the server's log, and
power-cycle a machine that locks up (through its smart plug, which DOS
Bridge also drives) and send it back in.
