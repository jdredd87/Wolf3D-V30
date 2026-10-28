"""series.py -- long network games one after another, a machine that drops
power-cycled and put back into the same game, so no hours are lost.
StevenC & Claude (Anthropic), 2026-10-27.

    python tests/series.py RUNS [STEPS] [KIND]        e.g. 3 504000 python
    DX486EXTRA=" NOSB" python tests/series.py 3       the 486 on AdLib only
    NETRECORD=1 ...                                   each run recorded: runN.MPR

Each run is netmatrix's KIND with NETNEXT=600 (a new floor every 10
minutes).  While it plays, the server's log is watched: a DOS machine "not
heard from for 60 s" is photographed (the V30, which has the capture card),
its plug cycled, and once it polls it joins the same game again with the
switches it had (netmatrix's, and <BOX>EXTRA / <BOX>EXE).  Everything goes
to stage/tests/series/summary.txt: each drop with its step and time, each
run's machines' report lines.
"""
import os
import re
import shutil
import subprocess
import sys
import threading
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
T = os.path.join(WOLF, "stage", "tests")
OUT = os.path.join(T, "series")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8", NETNEXT=os.environ.get("NETNEXT", "600"))
D = [sys.executable, os.path.join(BRIDGE, "dosctl.py")]
RUNS = int(sys.argv[1])
STEPS = sys.argv[2] if len(sys.argv) > 2 else "504000"
KIND = sys.argv[3] if len(sys.argv) > 3 else "python"
SRV = os.path.join(T, "net-" + KIND.replace("@", "-"), "server.txt")
NAME = {"dx486": "X86", "p3": "XP3", "v30": "X30"}
EXTRA = {"dx486": "", "p3": " VIEW 19", "v30": " LOWEST VIEW 10"}     # netmatrix's own
GAME = (r"C:\WL1", "WOLF3DM1") if KIND in ("wl1", "wl1w") else \
    (r"C:\SPEAR", "SPEARM") if KIND.startswith("sod") else (r"C:\WOLF3D", "WOLF3DM")
SUMMARY = os.path.join(OUT, "summary.txt")


def say(s):
    line = "%s  %s" % (time.strftime("%Y-%m-%d %H:%M:%S"), s)
    print(line, flush=True)
    open(SUMMARY, "a", encoding="utf-8").write(line + "\n")


def alive(box):
    r = subprocess.run(D + ["status"], capture_output=True, text=True, env=ENV).stdout
    m = re.search(r"^%s\s+\S+\s+(\w+)" % box, r, re.M)
    return bool(m) and m.group(1) == "alive"


def rejoin(box, n):
    if box == "v30":
        subprocess.run(D + ["capture", "shot", os.path.join(OUT, "run%d-v30-%s.png" % (n, time.strftime("%H%M%S")))],
                       capture_output=True)
    subprocess.run(D + ["power", "cycle", "--box", box], capture_output=True, env=ENV)
    t = time.time()
    while not alive(box):
        if time.time() - t > 300:
            say("   %s did not come back after its plug was cycled" % box)
            return
        time.sleep(10)
    exe = os.environ.get(box.upper() + "EXE", os.environ.get("NETEXE", GAME[1]))
    cmd = "%s NET %s NAME %s NETBOT SHOW%s%s" % (exe, "192.168.50.46" if KIND not in ("mpsrv", "sodsrv") else "",
                                               NAME[box], EXTRA[box], os.environ.get(box.upper() + "EXTRA", ""))
    say("   %s back after %.0f s; joining again: %s" % (box, time.time() - t, cmd))
    subprocess.Popen(D + ["exec", "CD " + GAME[0], cmd, "--box", box, "--timeout", "40000"],
                     stdout=open(os.path.join(OUT, "run%d-%s-rejoin.txt" % (n, box)), "a"),
                     stderr=subprocess.STDOUT, env=ENV)


def watch(n, stop):
    seen = 0
    time.sleep(40)                          # netmatrix has the new server.txt by now
    while not stop.is_set():
        try:
            lines = open(SRV, errors="replace").read().splitlines()
        except OSError:
            lines = []
        for l in lines[seen:]:
            m = re.search(r"\]\s+P\d (X86|XP3|X30) was not heard from for 60 s.*had step (\d+)", l)
            if m:
                box = {v: k for k, v in NAME.items()}[m.group(1)]
                say("run %d: %s dropped -- %s" % (n, box, l.split("] ", 1)[-1][:120]))
                threading.Thread(target=rejoin, args=(box, n), daemon=True).start()
        seen = len(lines)
        stop.wait(20)


say("series: %d runs of %s, %s steps; %s" % (RUNS, KIND, STEPS,
                                             ", ".join("%s=%r" % (k, v) for k, v in os.environ.items()
                                                       if k.endswith("EXTRA") or k.endswith("EXE"))))
for n in range(1, RUNS + 1):
    t0 = time.time()
    stop = threading.Event()
    w = threading.Thread(target=watch, args=(n, stop), daemon=True)
    w.start()
    env = dict(ENV)
    if os.environ.get("NETRECORD"):     # NETRECORD=1: each run recorded, runN.MPR beside the
        env["NETRECORD"] = os.path.join(OUT, "run%d.MPR" % n)    # summary (2026-10-28)
    subprocess.run([sys.executable, "-u", os.path.join(WOLF, "tests", "netmatrix.py"), KIND, STEPS],
                   capture_output=True, env=env, cwd=WOLF)
    stop.set()
    src = os.path.join(T, "net-" + KIND.replace("@", "-"))
    dst = os.path.join(OUT, "run%d" % n)
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)
    for l in open(os.path.join(dst, "events.txt"), errors="replace"):
        if re.search(r"\s(OK|BAD)\s|RESULT|ended:", l):
            say("run %d: %s" % (n, l[10:].strip()[:200]))
    for f in sorted(os.listdir(OUT)):
        if f.startswith("run%d-" % n) and f.endswith("-rejoin.txt"):
            r = re.findall(r"net: \d+ steps played.*|net: ended.*", open(os.path.join(OUT, f), errors="replace").read())
            say("run %d: %s rejoin: %s" % (n, f.split("-")[1], " / ".join(r)[:200]))
    say("run %d took %.1f h" % (n, (time.time() - t0) / 3600))
    time.sleep(60)
    for box in NAME:
        if not alive(box):
            say("   after run %d %s is not polling: its plug cycled" % (n, box))
            subprocess.run(D + ["power", "cycle", "--box", box], capture_output=True, env=ENV)
            time.sleep(90)
say("series done")
