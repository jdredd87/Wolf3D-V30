"""mpprof.py [--nobuild] -- where the V30's time goes in the network game.

WOLF3DM has no profiler (WL_PROF.C is stubbed under NETGAME, for the V30's
memory), so this makes a TEST build that keeps it: a copy of WOLFSRC with
MPPROF defined (stage/srcmpprof, built in C:\\W3DP on the 486), whose
PROFILE samples all of play, not only a late joiner's catching up, and whose
start-up check asks 150,000 bytes for the profiler's 36 KB.  Back as
stage/WOLF3DP.EXE and .MAP.

Then the V30 replays a recorded game (REPLAY: the same steps every time, no
network) with it, LOWEST VIEW 10 as it plays, and profmap.py says where the
time went.  StevenC & Claude (Anthropic), 2026-10-23."""
import os
import shutil
import subprocess
import sys

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
STAGE = os.path.join(WOLF, "stage")
SRC = os.path.join(STAGE, "srcmpprof", "WOLFSRC")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
REC = os.path.join(STAGE, "tests", "mprec", "REC.MPR")
OUT = os.path.join(STAGE, "tests", "mpprof")
os.makedirs(OUT, exist_ok=True)


def dosctl(*a, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=ENV, timeout=timeout)
    return r.stdout + r.stderr


if "--nobuild" not in sys.argv:
    shutil.rmtree(os.path.dirname(SRC), ignore_errors=True)
    shutil.copytree(os.path.join(WOLF, "WOLFSRC"), SRC,
                    ignore=shutil.ignore_patterns("*.EXE", "*.MAP", "*.exe", "*.map"))
    p = os.path.join(SRC, "VERSION.H")
    b = open(p, "rb").read()
    z = b.find(b"\x1a")                 # Borland stops at a Ctrl-Z: the define goes before it
    body = b[:z] if z >= 0 else b
    body = body.rstrip() + b"\r\n#define MPPROF\t\t// the profiling TEST build (tests/mpprof.py)\r\n"
    open(p, "wb").write(body + (b"\x1a" if z >= 0 else b""))
    # line numbers in the objects and the map (huntbot.py's), so a sample is a
    # source line: -y to the compiler, /l to the linker
    for f, old, new in (("TURBOC.CFG", b"-w-aus\r\n", b"-w-aus\r\n-y\r\n"),
                        ("LINK86.RSP", b"/c /m /s C0.OBJ+", b"/c /m /s /l C0.OBJ+")):
        q = os.path.join(SRC, f)
        t = open(q, "rb").read()
        if old not in t:
            old, new = old.replace(b"\r\n", b"\n"), new.replace(b"\r\n", b"\n")
        assert t.count(old) == 1, f
        open(q, "wb").write(t.replace(old, new))
    env = dict(ENV, W3D_SRC=SRC, W3D_REMOTE=r"C:\W3DP")
    if subprocess.run([sys.executable, os.path.join(WOLF, "w3dbuild.py"), "build"], env=env, cwd=WOLF).returncode:
        sys.exit("build failed")
    for ext in ("EXE", "MAP"):
        shutil.copyfile(os.path.join(SRC, "WOLF3DV." + ext), os.path.join(STAGE, "WOLF3DP." + ext))
    print("built stage/WOLF3DP.EXE")

if not os.path.exists(REC):
    sys.exit("no recording: %s (netmatrix.py with NETRECORD)" % REC)
for f in (os.path.join(STAGE, "WOLF3DP.EXE"), REC):
    print(dosctl("deploy", f, r"C:\WOLF3D", "--box", "v30").strip().splitlines()[-1])
out = dosctl("exec", "--box", "v30", r"CD C:\WOLF3D", "IF EXIST PROF.BIN DEL PROF.BIN",
             "WOLF3DP REPLAY REC.MPR LOWEST VIEW 10 PROFILE" + os.environ.get("MPPROFEXTRA", ""),
             "--timeout", "1500", timeout=1800)
open(os.path.join(OUT, "v30.txt"), "w", encoding="utf-8").write(out)
print("\n".join(l for l in out.splitlines() if "net:" in l or "PROFILE" in l or "samples" in l))
print(dosctl("pull", r"C:\WOLF3D\PROF.BIN", "--out", os.path.join(OUT, "PROF.BIN"), "--box", "v30").strip())
dosctl("exec", "--box", "v30", "--quiet", r"DEL C:\WOLF3D\WOLF3DP.EXE", r"DEL C:\WOLF3D\REC.MPR", r"DEL C:\WOLF3D\PROF.BIN")
r = subprocess.run([sys.executable, os.path.join(WOLF, "profmap.py"), os.path.join(OUT, "PROF.BIN"),
                    os.path.join(STAGE, "WOLF3DP.MAP"), "--top", "40", "--lines", "40"], capture_output=True, text=True)
open(os.path.join(OUT, "profile.txt"), "w").write(r.stdout + r.stderr)
print(r.stdout[-6000:])
