"""latejoin.py -- the V30 joining a game late, again and again: the case that
froze it in the 486's three-hour watchdog hunt (2026-10-24: in at step 1985,
the status bar drawn, the view black, never loaded the level).

    python tests/latejoin.py RUNS [STEPS] [KIND]      V30EXTRA=" NOSB" for the other half
                                                      (LJTAG=name: the runs' label)

Each run is netmatrix's KIND (python: co-op, the 486 and P3 from the start,
WOLF3DW on .37, the V30 in at step 1500).  After a run whose V30 is BAD its
screen is photographed and its plug cycled; a machine left STALE is cycled
too.  stage/tests/latejoin/summary.txt has every run.  StevenC & Claude
(Anthropic), 2026-10-24."""
import os
import re
import shutil
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
T = os.path.join(WOLF, "stage", "tests")
OUT = os.path.join(T, "latejoin")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
RUNS = int(sys.argv[1])
STEPS = sys.argv[2] if len(sys.argv) > 2 else "3000"
KIND = sys.argv[3] if len(sys.argv) > 3 else "python"
TAG = os.environ.get("LJTAG") or os.environ.get("V30EXTRA", "").strip().replace(" ", "-") or "sb"
SUMMARY = os.path.join(OUT, "summary.txt")
D = [sys.executable, os.path.join(BRIDGE, "dosctl.py")]


def say(s):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), s)
    print(line, flush=True)
    open(SUMMARY, "a", encoding="utf-8").write(line + "\n")


def status():
    r = subprocess.run(D + ["status"], capture_output=True, text=True, env=ENV)
    return {m[0]: m[1] for m in re.findall(r"^(dx486|p3|v30)\s+\S+\s+(\w+)", r.stdout, re.M)}


def cycle(box):
    subprocess.run(D + ["power", "cycle", "--box", box], capture_output=True, env=ENV)
    t = time.time()
    while time.time() - t < 300:
        time.sleep(10)
        if status().get(box) == "alive":
            return True
    return False


say("latejoin: %d runs of %s, %s steps, V30EXTRA=%r" % (RUNS, KIND, STEPS, os.environ.get("V30EXTRA", "")))
bad = 0
for n in range(1, RUNS + 1):
    t0 = time.time()
    subprocess.run([sys.executable, "-u", os.path.join(WOLF, "tests", "netmatrix.py"), KIND, STEPS],
                   capture_output=True, env=ENV, cwd=WOLF)
    src = os.path.join(T, "net-" + KIND.replace("@", "-"))
    dst = os.path.join(OUT, "%s-%02d" % (TAG, n))
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)
    ev = open(os.path.join(dst, "events.txt"), errors="replace").read()
    res = dict(re.findall(r"^\S+\s+(dx486|p3|v30|win37)\s+(OK|BAD)", ev, re.M))
    srv = open(os.path.join(dst, "server.txt"), errors="replace").read()
    why = "; ".join(l.split("] ", 1)[-1][:90] for l in srv.splitlines()
                    if re.search(r"X30 .*(never|left|dropped|timed)", l))
    say("%s %2d  %4.0f s  %s  %s" % (TAG, n, time.time() - t0,
                                     " ".join("%s %s" % kv for kv in sorted(res.items())), why))
    if res.get("v30") != "OK":
        bad += 1
        subprocess.run(D + ["capture", "shot", os.path.join(dst, "v30.png")], capture_output=True, env=ENV)
    st = status()
    for box in ("dx486", "p3", "v30"):
        if res.get(box) != "OK" or st.get(box) != "alive":
            say("   %s: %s, its plug cycled -- %s" % (box, st.get(box), "back" if cycle(box) else "NOT back"))
say("latejoin %s: the V30 BAD in %d of %d" % (TAG, bad, RUNS))
