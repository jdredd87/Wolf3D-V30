"""dmitems.py -- what deathmatch's items (DMITEMS.md) do to every floor, read
out of the real game: for each floor a short bot game is recorded twice by
mp/mpserver.py, --dmitems on and off, each replayed by the Win32 replay with
W3DDMI=1 -- every static as the floor is set up, before anyone has taken
one -- and the two compared.  Prints, per floor, the guns
and clips id put there and what was changed or added (tile, and the room it
is in).  StevenC & Claude (Anthropic), 2026-11-04.

    python tests/dmitems.py [--sod] [MAP...]     results to stage/dmi/dmitems.txt

--sod: Spear of Destiny, with W3DREPS.EXE (win32/build.py repsod) in C:\\wolf3d\\SOD.
REP=W3DREP2.EXE: another replay (win32/build.py rep2), while W3DREP.EXE is busy.
"""
import concurrent.futures
import os
import queue
import re
import shutil
import subprocess
import sys
import time

ROOT = r"C:\wolf3d"
SOD = "--sod" in sys.argv
RUN = os.path.join(ROOT, "SOD") if SOD else os.path.join(ROOT, "win32", "run")
REP = os.path.join(ROOT, "win32", os.environ.get("REP") or ("W3DREPS.EXE" if SOD else "W3DREP.EXE"))
OUT = os.path.join(ROOT, "stage", "dmi")
maps = [int(a) for a in sys.argv[1:] if a.isdigit()] or list(range(21 if SOD else 60))
# SPR_STAT_n is n + 2 in the sprite list (SPR_DEMO, SPR_DEATHCAM first)
NAMES = {28: "clip", 29: "MG", 30: "CG"}
if SOD:
    NAMES[51] = "clip25"
os.makedirs(OUT, exist_ok=True)


def record(m, items, port):
    name = "D%02d%s.MPR" % (m, "I" if items else "N")
    path = os.path.join(OUT, name)
    if os.path.exists(path):
        os.remove(path)
    srv = subprocess.Popen([sys.executable, os.path.join(ROOT, "mp", "mpserver.py"), "--port", str(port),
                            "--control", str(port + 1000), "--players", "4", "--bots", "3", "--mode", "dm",
                            "--map", str(m), "--steps", "20", "--once", "--record", path, "--quiet",
                            "--dmitems", "on" if items else "off"],
                           cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(1)
    subprocess.run([sys.executable, os.path.join(ROOT, "mp", "mpfake.py"), "--port", str(port), "--fps", "35",
                    "--load", "1"], cwd=OUT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=60)
    srv.wait(30)
    return path


def statics(mpr):
    local = os.path.join(RUN, os.path.basename(mpr))
    shutil.copy(mpr, local)
    r = subprocess.run([REP, "REPLAY", os.path.basename(mpr), "FAST", "NOAL"], cwd=RUN,
                       capture_output=True, text=True, errors="replace", env=dict(os.environ, W3DDMI="1"))
    os.remove(local)
    out = {}
    for line in r.stdout.splitlines():
        g = re.match(r"dmi st(\d+) (-?\d+) at (\d+),(\d+)", line)
        if g:
            out[int(g.group(1))] = (int(g.group(2)), int(g.group(3)), int(g.group(4)))
    return out


PORTS = queue.Queue()
for k in range(4):
    PORTS.put(32100 + 4 * k)


def one(m):
    port = PORTS.get()
    try:
        return one_(m, port)
    finally:
        PORTS.put(port)


def one_(m, port):
    a = statics(record(m, False, port))
    b = statics(record(m, True, port))
    def count(d, k):
        return sum(1 for s, x, y in d.values() if NAMES.get(s) == k)
    have = " ".join("%s %d" % (k, count(a, k)) for k in ("MG", "CG", "clip"))
    ch = []
    for i in sorted(b):
        if i not in a:
            ch.append("+%s at %d,%d" % (NAMES.get(b[i][0], b[i][0]), b[i][1], b[i][2]))
        elif a[i] != b[i]:
            ch.append("%s->%s at %d,%d" % (NAMES.get(a[i][0], a[i][0]), NAMES.get(b[i][0], b[i][0]),
                                           b[i][1], b[i][2]))
    if not a:
        return "map %2d: NO DUMP" % m
    return "map %2d: id's %-18s statics %3d -> %3d | %s" % (m, have, len(a), len(b), "; ".join(ch) or "nothing")


res = os.path.join(OUT, "dmitems%s.txt" % ("-sod" if SOD else ""))
open(res, "w").close()
with concurrent.futures.ThreadPoolExecutor(4) as ex:
    for line in ex.map(one, maps):
        print(line, flush=True)
        open(res, "a").write(line + "\n")
