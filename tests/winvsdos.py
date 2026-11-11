"""winvsdos.py -- a recorded network game replayed by the Win32 replay, its
sum at every 50th step checked against the ones the DOS machines sent while
they played it: a server writing GAME.MPR writes GAME.SUM beside it (every
SYNC, "step name sum").  Twenty-five minutes for a 3-hour game, where a DOS
replay to compare against takes four hours.  StevenC & Claude (Anthropic),
2026-11-11.

    python tests/winvsdos.py GAME.MPR [wl6|wl1|sod] [--win XWIN ...] [--repdir DIR]

--repdir: the replays from another tree -- the release the machines played,
when this tree has moved on (git worktree add C:/wolf3d-rel vX.Y; build
rep/repsod/rep1 there).

The game's data: wl6 (W3DREP.EXE in win32/run), wl1 (W3DREP1.EXE, the
shareware in C:\\Software\\86Box\\Software\\wolf3d-sw), sod (W3DREPS.EXE in
C:\\wolf3d\\SOD).  --win names the Windows players, whose sums are left out
(XWIN by default).  Prints the first step where the replay differs from DOS,
and whether the DOS machines ever disagreed among themselves.
"""
import os
import re
import shutil
import subprocess
import sys

ROOT = r"C:\wolf3d"
GAMES = {"wl6": ("W3DREP.EXE", os.path.join(ROOT, "win32", "run")),
         "wl1": ("W3DREP1.EXE", r"C:\Software\86Box\Software\wolf3d-sw"),
         "sod": ("W3DREPS.EXE", os.path.join(ROOT, "SOD"))}
args = sys.argv[1:]
mpr = args[0]
game = next((a for a in args[1:] if a in GAMES), "wl6")
repdir = args[args.index("--repdir") + 1] if "--repdir" in args else os.path.join(ROOT, "win32")
if "--repdir" in args:
    i = args.index("--repdir")
    del args[i:i + 2]
win = set(args[args.index("--win") + 1:]) if "--win" in args else {"XWIN"}
exe, run = GAMES[game]

dos, split = {}, []
for line in open(os.path.splitext(mpr)[0] + ".SUM"):
    p = line.split()
    if len(p) != 3 or p[1] in win:
        continue
    step, name, s = int(p[0]), p[1], p[2].upper()
    if step in dos and dos[step][0] != s:
        split.append((step, name, s, dos[step]))
    dos.setdefault(step, (s, name))

local = os.path.join(run, "WVD%d.MPR" % (os.getpid() % 100000))
shutil.copy(mpr, local)
out = subprocess.run([os.path.join(repdir, exe), "REPLAY", os.path.basename(local), "FAST", "NOAL"], cwd=run,
                     capture_output=True, text=True, errors="replace", env=dict(os.environ, W3DSUMS="1")).stdout
os.remove(local)
w = {int(m.group(1)): m.group(2).upper() for m in re.finditer(r"^w32 step (\d+): (\w+)", out, re.M)}

both = sorted(set(dos) & set(w))
bad = [st for st in both if dos[st][0] != w[st]]
print("%s: %d DOS sums, %d replayed, %d compared -- %s" % (
    os.path.basename(mpr), len(dos), len(w), len(both),
    "the same at every one" if not bad else "FIRST DIFFERENCE at step %d (DOS %s by %s, Windows %s), %d differ"
    % (bad[0], dos[bad[0]][0], dos[bad[0]][1], w[bad[0]], len(bad))))
if split:
    print("the DOS machines disagreed among themselves %d times, first at step %d" % (len(split), split[0][0]))
sys.exit(1 if bad or split else 0)
