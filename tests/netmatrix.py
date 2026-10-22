"""netmatrix.py KIND[@BOX] [STEPS] -- a network game, DOS and Windows
together, on one of the servers:

    python      mp/mpserver.py on this PC: co-op WITH enemies
    mpsrv@BOX   MPSRV.EXE on that DOS machine (p3, dx486, v30): deathmatch, a bot
    mpsrvw      MPSRVW.EXE on this PC: team deathmatch
    wl1         mp/mpserver.py: the shareware network game, WOLF3DM1 in C:\\WL1,
                the three DOS machines only (no Windows shareware build)
    soak        MPSRVW.EXE on this PC: deathmatch, the next floor every 10
                minutes, .37 in widescreen

Every DOS machine plays WOLF3DM 1.11 (NETBOT SHOW: a bot drives it, the game
draws); .37 plays the Windows game.  One machine joins late, at about step
1,500.  The server's console is asked over the network (mp/mpctl.py).
Every machine's own report must end "no desync", ended by the server."""
import os
import re
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
PC = "192.168.50.46"
ADDR = {"dx486": "192.168.50.67", "p3": "192.168.50.71", "v30": "192.168.50.66"}
ARG = sys.argv[1]
KIND, SRVBOX = (ARG.split("@") + ["p3"])[:2]
STEPS = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "net-" + ARG.replace("@", "-"))
os.makedirs(OUT, exist_ok=True)
EXTRA = {"dx486": "", "p3": " VIEW 19", "v30": " LOWEST VIEW 10"}
DM = "--mode dm --noenemies --itemrespawn 30"
PLAN = {   # the server's host, its rules, from the start, late, the Windows program (and its extra)
    "python": (PC, "--players 4 --mode coop --skill 2", ["dx486", "p3"], "v30", "WOLF3DW", ""),
    "mpsrv": (ADDR.get(SRVBOX), "--players 4 --bots 1 " + DM,
              [b for b in ("dx486", "p3", "v30") if b != SRVBOX][:1],
              "p3" if SRVBOX == "v30" else "v30", "WOLF3DMW", ""),
    "mpsrvw": (PC, "--players 4 --mode tdm --noenemies --itemrespawn 30", ["dx486", "p3"], "v30", "WOLF3DW", ""),
    "wl1": (PC, "--players 4 " + DM, ["dx486", "p3"], "v30", None, ""),
    "wl1w": (PC, "--players 4 " + DM, ["dx486", "p3"], "v30", "WOLF3DW1", ""),   # the shareware, with Windows
    "soak": (PC, "--players 4 --timelimit 10 " + DM, ["dx486", "p3"], "v30", "WOLF3DW", " WIDE"),
}
HOST, RULES, EARLY, LATE, WINEXE, WINEXTRA = PLAN[KIND]
WINDIR = {"WOLF3DW1": r"C:\W3DWIN1", "SPEARW": r"C:\W3DSOD"}.get(WINEXE, r"C:\W3DWIN")
RULES += " --steps %d --once" % STEPS
CTLHOST = HOST if KIND == "mpsrv" else "127.0.0.1"     # (the PC's servers: loopback only)


def note(s):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), s)
    print(line, flush=True)
    open(os.path.join(OUT, "events.txt"), "a").write(line + "\n")


def job(box, cmds, name, timeout):
    fh = open(os.path.join(OUT, name + ".txt"), "w", encoding="utf-8")
    return subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec"] + cmds
                            + ["--box", box, "--timeout", str(timeout)], stdout=fh,
                            stderr=subprocess.STDOUT, env=ENV)


def ctl(line):
    r = subprocess.run([sys.executable, os.path.join(WOLF, "mp", "mpctl.py"), "--host", CTLHOST, "--wait", "5"]
                       + line.split(), capture_output=True, text=True, env=ENV)
    out = r.stdout.strip()
    open(os.path.join(OUT, "console.txt"), "a").write(">>> %s\n%s\n" % (line, out))
    return out


def step_now():
    m = re.search(r"step (\d+)", ctl("status"))
    return int(m.group(1)) if m else -1


def player(box):
    d, exe = (r"C:\WL1", "WOLF3DM1") if KIND in ("wl1", "wl1w") else (r"C:\WOLF3D", "WOLF3DM")
    return job(box, ["CD " + d, "%s NET %s NAME X%s NETBOT SHOW%s" % (exe, HOST, box[-2:].upper(), EXTRA[box])],
               box, STEPS // 15 + 1800)


open(os.path.join(OUT, "events.txt"), "w").close()
open(os.path.join(OUT, "console.txt"), "w").close()
note("%s server on %s: %s" % (ARG, HOST, RULES))
srvout = open(os.path.join(OUT, "server.txt"), "w")
if KIND in ("python", "wl1", "wl1w"):
    srv = subprocess.Popen([sys.executable, "-u", "mp/mpserver.py"] + RULES.split(), cwd=WOLF,
                           stdin=subprocess.DEVNULL, stdout=srvout, stderr=subprocess.STDOUT, env=ENV)
elif KIND in ("mpsrvw", "soak"):
    srv = subprocess.Popen([os.path.join(WOLF, "mp", "build", "win", "mpsrvw.exe")] + RULES.split(), cwd=OUT,
                           stdin=subprocess.DEVNULL, stdout=srvout, stderr=subprocess.STDOUT, env=ENV)
else:
    srvout.close()
    srv = job(SRVBOX, [r"CD C:\MPSRV", "MPSRV.EXE " + RULES], "server", STEPS // 15 + 2400)
t = time.time()
while not re.search(r"waiting|playing", ctl("status")):
    if time.time() - t > 120:
        note("the server never answered its console")
        break
    time.sleep(5)
note("console: " + ctl("status").replace("\n", " | ")[:200])
jobs = {}
for box in EARLY:
    jobs[box] = player(box)
    note("%s in" % box)
    time.sleep(10)
if WINEXE:
    r = subprocess.run(AGENT + ["start", r"%s\%s.EXE NET %s NAME XWIN NETBOT SHOW%s" % (WINDIR, WINEXE, HOST, WINEXTRA),
                                WINDIR], capture_output=True, text=True).stdout.strip()
    note("%s%s on .37: %s" % (WINEXE, WINEXTRA, r))
t = time.time()
while step_now() < 1500 and time.time() - t < 400:
    time.sleep(10)
ctl("say Hello from %s" % ARG)
jobs[LATE] = player(LATE)
note("%s in, late (step %d)" % (LATE, step_now()))
time.sleep(60)
note("console: " + ctl("status").replace("\n", " | ")[:300])
note("scores: " + ctl("scores").replace("\n", " | ")[:300])
k = 0
t = time.time()
while srv.poll() is None and time.time() - t < STEPS // 15 + 900:
    time.sleep(30)
    if WINEXE and KIND == "soak" and int(time.time() - t) // 300 > k:
        k = int(time.time() - t) // 300            # a picture of .37 every 5 minutes
        subprocess.run(AGENT + ["shot", os.path.join(OUT, "w37-%02d.png" % k)], capture_output=True)
        note("status: " + ctl("status").split("\n")[0][:150])
if srv.poll() is None:
    note("the server did not end")
    srv.kill()
note("server ended")
for j in jobs.values():
    try:
        j.wait(600)
    except subprocess.TimeoutExpired:
        j.kill()
time.sleep(5)
if WINEXE:
    log = "WOLF3DMW.LOG" if WINEXE == "WOLF3DMW" else "WOLF3DW.LOG"
    subprocess.run(AGENT + ["get", WINDIR + "\\" + log, os.path.join(OUT, "win37.txt")], capture_output=True)
PAT = r"net: \d+ steps played.*|net: ended.*|DESYNC.*|desync.*"
ok = True
for name in list(jobs) + (["win37"] if WINEXE else []):
    try:
        o = open(os.path.join(OUT, name + ".txt"), errors="replace").read()
    except OSError:
        o = ""
    found = re.findall(PAT, o)
    good = any("no desync" in f for f in found) and any("ended by the server" in f for f in found)
    ok &= good
    note("%-6s %s  %s" % (name, "OK " if good else "BAD", " / ".join(found)[:220]))
try:
    s = open(os.path.join(OUT, "server.txt"), errors="replace").read()
except OSError:
    s = ""
for l in s.splitlines():
    if re.search(r"joined|ended|DESYNC|desync|left|dropped", l):
        note("server: " + l.strip()[:200])
note("RESULT %s: %s" % (ARG, "PASS" if ok else "FAIL"))
