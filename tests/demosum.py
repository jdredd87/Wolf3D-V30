"""demosum.py -- id's four demos, the DOS game against the Windows one, the
whole game state every 50 frames (WL_MP.C's DemoSum): the DOS side a test
build of this tree with DEMOSUM defined (stage/demosum, never the release),
run on the 486 with TIMEDEMO CRC DEMOSUM (sound off, view 15 -- and its
picture checksums must still be id's); the Windows side WOLF3DW TIMEDEMO
DEMOSUM on .37.  Every line must be the same.

    python tests/demosum.py              build the DOS test build, run both, compare
    python tests/demosum.py --nobuild    the DOS test build as it is

StevenC & Claude (Anthropic), 2026-10-22."""
import os
import re
import shutil
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
OUT = os.path.join(WOLF, "stage", "tests", "demosum")
os.makedirs(OUT, exist_ok=True)
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
SRC = os.path.join(WOLF, "stage", "demosum", "WOLFSRC")


def dosctl(*a, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def agent(*a, timeout=120):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


if "--nobuild" not in sys.argv:
    shutil.rmtree(os.path.dirname(SRC), ignore_errors=True)
    shutil.copytree(os.path.join(WOLF, "WOLFSRC"), SRC)
    p = os.path.join(SRC, "VERSION.H")
    b = open(p, "rb").read().replace(b"\x1a", b"").rstrip()
    open(p, "wb").write(b + b"\r\n#define DEMOSUM\t\t// the test build: TIMEDEMO DEMOSUM (WL_MP.C)\r\n\x1a")
    env = dict(ENV, W3D_SRC=SRC, W3D_REMOTE=r"C:\W3DS")
    subprocess.run([sys.executable, os.path.join(WOLF, "w3dbuild.py"), "build"], env=env, cwd=WOLF)
exe = os.path.join(OUT, "DSUM.EXE")
shutil.copyfile(os.path.join(SRC, "WOLF3DV.EXE"), exe)
dosctl("deploy", exe, r"C:\WOLF3D", "--box", "dx486")

# both at once: DOS on the 486, Windows on .37
dos = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", "dx486", "--quiet",
                        "--timeout", "1700", r"CD C:\WOLF3D", "DSUM TIMEDEMO CRC DEMOSUM"],
                       stdout=open(os.path.join(OUT, "dos.txt"), "w"), stderr=subprocess.STDOUT, env=ENV)
agent("start", r"C:\W3DWIN\WOLF3DW.EXE TIMEDEMO DEMOSUM", r"C:\W3DWIN")
time.sleep(20)
while agent("ps", "[bool](Get-Process WOLF3DW -ErrorAction SilentlyContinue)", "20").endswith("True"):
    time.sleep(15)
agent("get", r"C:\W3DWIN\WOLF3DW.LOG", os.path.join(OUT, "win.txt"))
dos.wait(1800)
dosctl("exec", "--box", "dx486", "--quiet", r"DEL C:\WOLF3D\DSUM.EXE")


def sums(name):
    t = open(os.path.join(OUT, name), errors="replace").read().replace("\r", "")
    return [l.rstrip() for l in t.splitlines() if l.startswith("demo sum:")], t


d, dt = sums("dos.txt")
w, _ = sums("win.txt")
view = re.search(r"view checksum, all \d+: (\w+)", dt)
scr = re.search(r"screen checksum, all \d+: (\w+)", dt)
print("DOS: %d sums, its picture %s / %s (id's: 0707C966 / F2A10CEB)" % (len(d), view and view.group(1),
                                                                          scr and scr.group(1)))
print("Windows: %d sums" % len(w))
bad = [(i, a, b) for i, (a, b) in enumerate(zip(d, w)) if a != b]
if not bad and len(d) == len(w) and d:
    print("RESULT demosum: PASS -- all %d the same" % len(d))
else:
    for i, a, b in bad[:3]:
        print("line %d\n  DOS %s\n  WIN %s" % (i+1, a, b))
    print("RESULT demosum: FAIL")
