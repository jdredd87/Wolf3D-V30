"""soak.py -- hours of network play, to find what a short test does not: the
release candidates on every machine and server, one game after another (all
of them with a machine joining late, the next floor every 10 minutes):

    1  python      Python, co-op with enemies, the registered game    60 min
    2  soak        MPSRVW, deathmatch, WOLF3DW in widescreen          60 min
    3  mpsrv@p3    MPSRV on P3, deathmatch and a bot                  30 min
    4  wl1w        Python, the shareware, with WOLF3DW1               30 min
    5  sod         Python, Spear of Destiny, co-op (the V30: NOSB)     60 min

After each, a machine that stopped answering is written down and its plug
cycled.  stage/tests/soak/summary.txt has every machine's own report line,
the server's end and anyone who dropped.  StevenC & Claude (Anthropic),
2026-10-23."""
import os
import re
import shutil
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
T = os.path.join(WOLF, "stage", "tests")
OUT = os.path.join(T, "soak")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
RUNS = [("python", 63000, {"NETNEXT": "600"}),
        ("soak", 63000, {}),
        ("mpsrv@p3", 31500, {"NETNEXT": "600"}),
        ("wl1w", 31500, {"NETNEXT": "600"}),
        ("sod", 63000, {"NETNEXT": "600", "V30EXTRA": " NOSB"})]
if len(sys.argv) > 1:
    RUNS = [r for r in RUNS if r[0] in sys.argv[1:]]
SUMMARY = os.path.join(OUT, "summary.txt")


def say(s):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), s)
    print(line, flush=True)
    open(SUMMARY, "a", encoding="utf-8").write(line + "\n")


def status():
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "status"], capture_output=True,
                       text=True, env=ENV)
    return {m[0]: m[1] for m in re.findall(r"^(dx486|p3|v30)\s+\S+\s+(\w+)", r.stdout, re.M)}


say("soak: %s" % ", ".join("%s %d steps" % (k, n) for k, n, _ in RUNS))
for n, (kind, steps, extra) in enumerate(RUNS, 1):
    say("== %d. %s, %d steps %s" % (n, kind, steps, " ".join("%s=%r" % kv for kv in extra.items())))
    t0 = time.time()
    r = subprocess.run([sys.executable, "-u", os.path.join(WOLF, "tests", "netmatrix.py"), kind, str(steps)],
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=dict(ENV, **extra), cwd=WOLF)
    src = os.path.join(T, "net-" + kind.replace("@", "-"))
    dst = os.path.join(OUT, "%d-%s" % (n, kind.replace("@", "-")))
    shutil.rmtree(dst, ignore_errors=True)
    shutil.copytree(src, dst)
    for line in r.stdout.splitlines():
        if re.search(r" OK | BAD |RESULT|not heard|ended:|DESYNC|desync|dropped|joined", line):
            say("  " + line.strip()[:240])
    say("  %.0f min" % ((time.time() - t0) / 60))
    st = status()
    for box, s in st.items():
        if s != "alive":
            say("  !! %s %s after the game: its plug cycled" % (box, s))
            subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "power", "cycle", "--box", box],
                           capture_output=True, env=ENV)
    if any(s != "alive" for s in st.values()):
        time.sleep(120)
say("soak: done")
