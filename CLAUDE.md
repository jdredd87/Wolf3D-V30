# CLAUDE.md -- rules for work in this repository

Written by **StevenC** and **Claude** (Anthropic), 2026-10-21.

## Every change goes into every build

StevenC, 2026-10-21: "changes we make in one game carry over all our versions
for network and windows versions ... so we make sure every change is
duplicated in every build."

The builds:

| build | what | made by |
|---|---|---|
| `WOLF3DV.EXE` | DOS, the NEC V30 build (and with it the 8086, shareware and Spear builds made from `WOLFSRC`) | `python w3dbuild.py build` (on the 486) |
| `WOLF3DM.EXE` | DOS, the network game (this branch's `WOLFSRC`, `NETGAME` in `VERSION.H`) | the same |
| `win32/WOLF3DMW.EXE` | Windows, the network game | `python win32/build.py game` |
| `win32/WOLF3DW.EXE` | Windows, the whole game (id's single player, and `NET`) | `python win32/build.py sp` |
| `win32/W3DREP.EXE` | Windows, the gate: replays recordings, sums against DOS | `python win32/build.py rep`, `bash win32/gate.sh` |
| `mp/mpserver.py`, `mp/mpsrv.pas` (MPSRV, MPSRVW) | the servers: Python, DOS, Windows | |

For every change:

1. **Say which builds it reaches.**  Code in `WOLFSRC` reaches them all by
   itself -- but look for a twin in the platform layers that needs the same
   change: `win32/src` (the Windows picture, sound, input, and what the DOS
   renderer decides besides the picture: `w32vis.c`), the V30's assembly,
   `WL_MP.C`, the three servers.  A DOS behaviour the Windows build left out
   is the bug this rule was made after: in WOLF3DW no shot hit anyone,
   because the DOS renderer marks actors seen and the Windows one did not.
2. **Build and test each build it reaches**, on the machines that run it.
3. **The DOS game's bytes move only when a DOS build is meant to change.**
   Windows-only code is `#ifdef W32` (`W32SP`: the whole game only); after
   touching `WOLFSRC`, rebuild on the 486 and compare the CRC (2026-10-21:
   `WOLF3DV.EXE` `C39ED932`, 335,854 bytes).
4. **Say what was left out of a build, and why** -- some things cannot go
   everywhere (widescreen is a Windows window's; DOS's VGA picture is
   320x200 on a 4:3 screen).

## And always

- Credit **StevenC & Claude** on anything new: banners, source headers,
  READMEs, changelogs.
- Commit and push each step; `V30NOTES.md` has the steps, `MULTIPLAYER.md` the
  network game, `win32/README.md` the Windows builds.
- Never commit id's data (the `*.WL6`, `*.SOD` files) or anyone's binaries
  but ours.
