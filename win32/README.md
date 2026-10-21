# WOLF3DM for Win32 -- the network game on Windows 95 and later

Written by **StevenC** and **Claude** (Anthropic), from 2026-10-21.

The goal: a native Windows build of the network game that plays in the same
game as the DOS machines.  Lockstep means every machine must compute exactly
the same game from the same inputs, so the port is proven, not assumed:

1. **A checksum any platform can compute** (DOS 1.11, `MPVER` 0x0111): the
   sum read each actor's state by its 16-bit *address*; it reads what the
   state *is* now (`StateSum`, `WOLFSRC/WL_MP.C`).
2. **The gate**: the game's logic built for Win32 with no picture, replaying
   the recordings in `ref/`; every sum must equal the DOS build's in
   `ref/*.SUM` (written by DOS 1.11 on P3; T1 also on the 486, identical).
3. Then the Windows layer -- GDI for the picture, `waveOut` and an OPL
   emulator for sound, Winsock 1.1 for the network -- all of it there since
   Windows 95, so one EXE runs from 95 to 11.

The compiler is Open Watcom 2.0 (the 2026-10-01 build, unpacked into
`C:\WATCOM`): the one whose Win32 programs still run on Windows 9x.  `test/`
is the toolchain check; `owbuild.sh` sets up its environment.

| `ref/` | |
|---|---|
| `*.MPR` | recordings (a server's `--record`: our protocol packets, none of id's data) |
| `*.SUM` | DOS 1.11's sum at every 50th step of a plain `REPLAY ... FAST` |
