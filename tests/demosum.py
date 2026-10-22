"""demosum.py [wl6|wl1|sod] [--nobuild] -- id's demos, the DOS game against
the Windows one, the whole game state every 50 frames (WL_MP.C's DemoSum):
the DOS side a test build of this tree with DEMOSUM defined (stage/demosum-*,
never a release), run on the 486 with TIMEDEMO CRC DEMOSUM (sound off, view
15); the Windows side its build's TIMEDEMO DEMOSUM on .37.  Every line must
be the same.

    wl6   the registered game: WOLF3DW (C:\\W3DWIN) and the 486's C:\\WOLF3D
    wl1   the shareware: WOLF3DW1 (C:\\W3DWIN1) and C:\\WL1 -- UPLOAD
    sod   Spear of Destiny: SPEARW (C:\\W3DSOD) and C:\\SPEAR -- SODVER.H and GOODTIMES

StevenC & Claude (Anthropic), 2026-10-22."""
import os
import re
import shutil
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
VAR = next((a for a in sys.argv[1:] if not a.startswith("--")), "wl6")
DOSDIR, WINEXE, WINDIR = {"wl6": (r"C:\WOLF3D", "WOLF3DW", r"C:\W3DWIN"),
                          "wl1": (r"C:\WL1", "WOLF3DW1", r"C:\W3DWIN1"),
                          "sod": (r"C:\SPEAR", "SPEARW", r"C:\W3DSOD")}[VAR]
OUT = os.path.join(WOLF, "stage", "tests", "demosum-" + VAR)
SRC = os.path.join(WOLF, "stage", "demosum-" + VAR, "WOLFSRC")
os.makedirs(OUT, exist_ok=True)


def dosctl(*a, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def agent(*a, timeout=120):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


if "--nobuild" not in sys.argv:
    shutil.rmtree(os.path.dirname(SRC), ignore_errors=True)
    shutil.copytree(os.path.join(WOLF, "WOLFSRC"), SRC,
                    ignore=shutil.ignore_patterns("*.EXE", "*.MAP", "*.exe", "*.map"))
    p = os.path.join(SRC, "VERSION.H")
    if VAR == "sod":                         # as w3dbuild.py's buildsod
        b = open(os.path.join(SRC, "SODVER.H"), "rb").read().replace(b"\x1a", b"").rstrip()
        b += b"\r\n#define GOODTIMES"
    else:
        b = open(p, "rb").read().replace(b"\x1a", b"").rstrip()
        if VAR == "wl1":                     # as buildwl1
            assert b.count(b"//#define UPLOAD") == 1
            b = b.replace(b"//#define UPLOAD", b"#define UPLOAD")
    open(p, "wb").write(b + b"\r\n#define DEMOSUM\t\t// the test build: TIMEDEMO DEMOSUM (WL_MP.C)\r\n\x1a")
    env = dict(ENV, W3D_SRC=SRC, W3D_REMOTE=r"C:\W3DS" + {"wl6": "", "wl1": "1", "sod": "S"}[VAR])
    subprocess.run([sys.executable, os.path.join(WOLF, "w3dbuild.py"), "build"], env=env, cwd=WOLF)
exe = os.path.join(OUT, "DSUM.EXE")
shutil.copyfile(os.path.join(SRC, "WOLF3DV.EXE"), exe)
dosctl("deploy", exe, DOSDIR, "--box", "dx486")

# both at once: DOS on the 486, Windows on .37
dos = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", "dx486", "--quiet",
                        "--timeout", "1700", "CD " + DOSDIR, "DSUM TIMEDEMO CRC DEMOSUM"],
                       stdout=open(os.path.join(OUT, "dos.txt"), "w"), stderr=subprocess.STDOUT, env=ENV)
agent("start", "%s\\%s.EXE TIMEDEMO DEMOSUM" % (WINDIR, WINEXE), WINDIR)
time.sleep(20)
while agent("ps", "[bool](Get-Process %s -ErrorAction SilentlyContinue)" % WINEXE, "20").endswith("True"):
    time.sleep(15)
agent("get", WINDIR + "\\WOLF3DW.LOG", os.path.join(OUT, "win.txt"))
dos.wait(1800)
dosctl("exec", "--box", "dx486", "--quiet", "DEL %s\\DSUM.EXE" % DOSDIR)


def sums(name):
    try:
        t = open(os.path.join(OUT, name), errors="replace").read().replace("\r", "")
    except OSError:
        t = ""
    return [l.rstrip() for l in t.splitlines() if l.startswith("demo sum:")], t


d, dt = sums("dos.txt")
w, _ = sums("win.txt")
view = re.search(r"view checksum, all \d+: (\w+)", dt)
scr = re.search(r"screen checksum, all \d+: (\w+)", dt)
floors = re.findall(r"demo \d+  floor\s+(\d+)\s+(\d+) frames", dt)
print("%s DOS: %d sums, floors %s, its picture %s / %s" % (VAR, len(d), floors, view and view.group(1),
                                                          scr and scr.group(1)))
print("%s Windows: %d sums" % (VAR, len(w)))
bad = [(i, a, b) for i, (a, b) in enumerate(zip(d, w)) if a != b]
if not bad and len(d) == len(w) and d:
    print("RESULT demosum %s: PASS -- all %d the same" % (VAR, len(d)))
else:
    for i, a, b in bad[:3]:
        print("line %d\n  DOS %s\n  WIN %s" % (i+1, a, b))
    print("RESULT demosum %s: FAIL" % VAR)
