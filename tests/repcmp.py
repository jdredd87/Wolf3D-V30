"""repcmp.py -- two Win32 replays of every recorded game, checksum for
checksum: W3DREP0.EXE and W3DREP1.EXE in win32/run (two builds of the
replay), each recording replayed by both with W3DSUMS=1 and every 50th
step's sum compared.  For a game the live Windows machine played with no
desync, the old build's sums ARE the DOS machines' -- so a new build that
gives the same sums agrees with DOS there too.  StevenC & Claude
(Anthropic), 2026-11-03.

    python tests/repcmp.py [JOBS] MPR...       results to stage/tests/repcmp.txt
"""
import concurrent.futures
import os
import subprocess
import sys

RUN = r"C:\wolf3d\win32\run"
OUT = r"C:\wolf3d\stage\tests\repcmp.txt"
jobs = int(sys.argv[1]) if sys.argv[1:] and sys.argv[1].isdigit() else 3
files = [a for a in sys.argv[1:] if not a.isdigit()]


def sums(exe, mpr):
    env = dict(os.environ, W3DSUMS="1")
    r = subprocess.run([os.path.join(RUN, exe), "REPLAY", mpr, "FAST", "NOAL"], cwd=RUN,
                       capture_output=True, text=True, errors="replace", env=env)
    return [l.strip() for l in r.stdout.splitlines() if l.startswith("w32 step")]


def one(mpr):
    a, b = sums("W3DREP0.EXE", mpr), sums("W3DREP1.EXE", mpr)
    first = next((i for i, (x, y) in enumerate(zip(a, b)) if x != y), None)
    if first is None and len(a) == len(b):
        return "%s: the same, all %d sums (to %s)" % (mpr, len(a), a[-1] if a else "-")
    if first is None:
        return "%s: %d sums against %d" % (mpr, len(a), len(b))
    return "%s: DIFFER first at %s / %s" % (mpr, a[first], b[first])


with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
    for line in ex.map(one, files):
        print(line, flush=True)
        open(OUT, "a").write(line + "\n")
print("done", flush=True)
