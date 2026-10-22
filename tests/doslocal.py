"""doslocal.py -- DOS local play: each new build plays id's attract loop
(TIMEDEMO CRC: the view and the whole screen checksummed every 50 frames,
sound effects off so a run is deterministic) beside the build the machine
had, or against id's own renderer's numbers; QUICK on the V30 (demo 0, 200
frames).  A new build goes in under a test name and is deleted after."""
import os
import re
import shutil
import subprocess
import sys

BRIDGE = r"C:\dosbridgeDEV"
T = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "doslocal")
os.makedirs(T, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
V30W = r"C:\wolf3d-v30\WOLFSRC"
MPW = r"C:\wolf3d\WOLFSRC"
REF = ("0707C966", "F2A10CEB")          # id's renderer, all four demos (ab.py)


def dosctl(*a, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a),
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def run(box, d, exe, quick):
    out = dosctl("exec", "--box", box, "--quiet", "--timeout", "3000", "CD " + d,
                 "%s TIMEDEMO CRC%s" % (exe, " QUICK" if quick else ""), timeout=3300)
    v = re.search(r"view checksum, all \d+: ([0-9A-F]{8})", out)
    s = re.search(r"screen checksum, all \d+: ([0-9A-F]{8})", out)
    if not v or not s:
        open(os.path.join(T, "%s-%s.txt" % (box, exe)), "w").write(out)
        return None
    return v.group(1), s.group(1)


def deploy(box, d, local, name):
    p = os.path.join(T, name)
    shutil.copyfile(local, p)
    out = dosctl("deploy", p, d, "--box", box, timeout=900)
    return re.search(r"%s\s+%s\s+[\d,]+" % tuple(name.split(".")), out.upper()) is not None


TESTS = [  # box, folder, old program (or REF), new build, test name, quick
    ("dx486", r"C:\WOLF3D", "REF", os.path.join(V30W, "WOLF3D8.EXE"), "NEW8.EXE", False),
    ("dx486", r"C:\WOLF3D", "REF", os.path.join(MPW, "WOLF3DV.EXE"), "NEWM.EXE", False),
    ("p3", r"C:\WOLF3D", "REF", os.path.join(V30W, "WOLF3DV.EXE"), "NEWV.EXE", False),
    ("p3", r"C:\WL1", "WOLF3D1.EXE", os.path.join(V30W, "WOLF3D1.EXE"), "NEW1.EXE", False),
    ("p3", r"C:\WL1", "WOLF3D18.EXE", os.path.join(V30W, "WOLF3D18.EXE"), "NEW18.EXE", False),
    ("p3", r"C:\WL1", "WOLF3DM1.EXE", os.path.join(MPW, "WOLF3DM1.EXE"), "NEWM1.EXE", False),
    ("v30", r"C:\WOLF3D", "WOLF3DV.EXE", os.path.join(V30W, "WOLF3DV.EXE"), "NEWV.EXE", True),
    ("v30", r"C:\SPEAR", "SPEARV.EXE", os.path.join(V30W, "SPEARV.EXE"), "NEWSV.EXE", True),
    ("v30", r"C:\SPEAR", "SPEAR8.EXE", os.path.join(V30W, "SPEAR8.EXE"), "NEWS8.EXE", True),
]
only = sys.argv[1:]
for box, d, old, local, name, quick in TESTS:
    if only and box not in only:
        continue
    if not deploy(box, d, local, name):
        print("%-6s %-9s %-13s DEPLOY FAILED" % (box, d, name), flush=True)
        continue
    new = run(box, d, name, quick)
    ref = REF if old == "REF" else run(box, d, old, quick)
    dosctl("exec", "--box", box, "--quiet", "DEL %s\\%s" % (d, name), timeout=300)
    verdict = "SAME" if new and ref and new == ref else "DIFFERENT"
    print("%-6s %-9s %-11s %s  vs %-12s %s  %s%s" % (box, d, os.path.basename(local), new,
          old, ref, verdict, " (QUICK)" if quick else ""), flush=True)
