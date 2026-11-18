"""smoke.py -- 1.x as a player gets it: the release zips unpacked into empty folders
(C:\\SMOKE on each DOS box and on .37), each machine's own game data beside them,
then two short games of hunting bots -- the zip's MPSRV on the 486, then the
zip's Python server on this PC -- P3, the V30 and Windows playing from those
folders.  StevenC & Claude (Anthropic), 2026-11-18.

    python tests/smoke.py [STEPS]          (6000: about 6 minutes a game)
"""
import os
import re
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BRIDGE = r"C:\dosbridgeDEV"
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
PC, DX486 = "192.168.50.46", "192.168.50.67"
STEPS = int(sys.argv[1]) if len(sys.argv) > 1 else 6000
OUT = os.path.join(ROOT, "stage", "smoke")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
EXTRA = {"p3": " VIEW 19", "v30": " LOWEST VIEW 10", "dx486": ""}


def say(s):
    line = "%s  %s" % (time.strftime("%H:%M:%S"), s)
    print(line, flush=True)
    open(os.path.join(OUT, "smoke.txt"), "a", encoding="utf-8").write(line + "\n")


def dos(box, *cmds, timeout=1800):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", box,
                        "--timeout", str(timeout)] + list(cmds),
                       capture_output=True, text=True, encoding="utf-8", errors="replace", env=ENV)
    return r.stdout + r.stderr


def agent(*a):
    return subprocess.run(AGENT + list(a), capture_output=True, text=True).stdout.strip()


def player(box, host, name):
    return subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", box,
                             "--timeout", str(STEPS // 15 + 1800), r"CD C:\SMOKE",
                             "WOLF3DM NET %s NAME %s NETBOT HUNT%s" % (host, name, EXTRA[box])],
                            stdout=open(os.path.join(OUT, "%s-%s.txt" % (name, box)), "w"),
                            stderr=subprocess.STDOUT, env=ENV)


open(os.path.join(OUT, "smoke.txt"), "w").close()
say("1.x from the zips, %d steps a game" % STEPS)

# 1. unpack into empty folders
for box in ("dx486", "p3", "v30"):
    dos(box, r"IF EXIST C:\SMOKE\NUL DELTREE /Y C:\SMOKE", r"MD C:\SMOKE")
    subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "deploy",
                    os.path.join(ROOT, "release", "W3DMP.ZIP"), "C:\\SMOKE", "--box", box],
                   capture_output=True, env=ENV)
    out = dos(box, r"CD C:\SMOKE", "PKUNZIP -d -o W3DMP.ZIP", r"COPY C:\WOLF3D\*.WL6 C:\SMOKE",
              r"DIR /B C:\SMOKE", r"DIR /B C:\SMOKE\SERVER", timeout=2400)
    have = sorted(set(re.findall(r"^([A-Z0-9_]+\.(?:EXE|BAT|TXT|DOC|WL6))\s*$", out, re.M)))
    say("%s: C:\\SMOKE has %s" % (box, " ".join(have)))
agent("ps", "if (Test-Path C:\\SMOKE) { Remove-Item C:\\SMOKE -Recurse -Force }; New-Item -ItemType Directory C:\\SMOKE | Out-Null")
agent("put", os.path.join(ROOT, "release", "W3DWIN.ZIP"), "C:\\SMOKE\\W3DWIN.ZIP")
agent("ps", "Expand-Archive C:\\SMOKE\\W3DWIN.ZIP -DestinationPath C:\\SMOKE -Force; Copy-Item C:\\W3DWIN\\*.WL6 C:\\SMOKE")
say(".37: C:\\SMOKE has " + agent("ps", "(Get-ChildItem C:\\SMOKE -Name) -join ' '").replace("\n", " "))


def game(label, host, server):
    say("game: %s" % label)
    jobs = [player("p3", host, "SMKP3")]
    time.sleep(10)
    say(".37: " + agent("start", "C:\\SMOKE\\WOLF3DW.EXE NET %s NAME SMKW NETBOT HUNT" % host, "C:\\SMOKE"))
    time.sleep(10)
    jobs.append(player("v30", host, "SMK30"))
    server.wait(timeout=STEPS // 15 + 2400)
    for j in jobs:
        try:
            j.wait(600)
        except subprocess.TimeoutExpired:
            j.kill()
    time.sleep(5)
    agent("get", "C:\\SMOKE\\WOLF3DW.LOG", os.path.join(OUT, "%s-win37.txt" % label))
    ok = True
    for f in ("SMKP3-p3", "SMK30-v30", "%s-win37" % label):
        try:
            o = open(os.path.join(OUT, f + ".txt"), errors="replace").read()
        except OSError:
            o = ""
        found = re.findall(r"net: \d+ steps played.*|net: ended.*|DESYNC.*", o)
        good = any("no desync" in x for x in found) and any("ended by the server" in x for x in found)
        ok &= good
        say("   %-10s %s  %s" % (f, "OK " if good else "BAD", " / ".join(found)[:200]))
    return ok


# 2. the zip's MPSRV on the 486
srv = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", "dx486",
                        "--timeout", str(STEPS // 15 + 2400), r"CD C:\SMOKE\SERVER",
                        "MPSRV.EXE --players 3 --mode dm --skill 2 --steps %d --once" % STEPS],
                       stdout=open(os.path.join(OUT, "mpsrv.txt"), "w"), stderr=subprocess.STDOUT, env=ENV)
time.sleep(20)
a = game("mpsrv", DX486, srv)
say("   the server: " + " | ".join(l.strip()[:150] for l in open(os.path.join(OUT, "mpsrv.txt"), errors="replace")
                                    if re.search(r"ended|desync", l))[:300])

# 3. the zip's Python server on this PC
tmp = tempfile.mkdtemp(prefix="smoke")
zipfile.ZipFile(os.path.join(ROOT, "release", "W3DMP.ZIP")).extractall(tmp)
pysrv = subprocess.Popen([sys.executable, "-u", os.path.join(tmp, "SERVER", "mp", "mpserver.py"),
                          "--players", "3", "--mode", "dm", "--skill", "2", "--steps", str(STEPS), "--once"],
                         cwd=os.path.join(tmp, "SERVER"), stdout=open(os.path.join(OUT, "pysrv.txt"), "w"),
                         stderr=subprocess.STDOUT, env=ENV)
time.sleep(5)
b = game("python", PC, pysrv)
say("   the server: " + " | ".join(l.strip()[:150] for l in open(os.path.join(OUT, "pysrv.txt"), errors="replace")
                                    if re.search(r"ended|desync", l))[:300])
say("SMOKE: %s" % ("PASS" if a and b else "FAIL"))
