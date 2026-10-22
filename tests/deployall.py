"""deployall.py -- every DOS build onto every machine that has it: in each
folder, a program present is replaced by its new build (the old kept as
NAME.PRV), then read back by CRC-32 on the machine (HD)."""
import os
import re
import shutil
import subprocess
import sys
import zlib

BRIDGE = r"C:\dosbridgeDEV"
T = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "deploy")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
V30W, MPW, BSPW = r"C:\wolf3d-v30\WOLFSRC", r"C:\wolf3d\WOLFSRC", r"C:\wolf3d-bsp\WOLFSRC"
NEW = {  # folder: {name on the machine: the build}
    r"C:\WOLF3D": {"WOLF3DM.EXE": os.path.join(MPW, "WOLF3DV.EXE"),
                   "WOLF3DV.EXE": os.path.join(V30W, "WOLF3DV.EXE"),
                   "WOLF3D8.EXE": os.path.join(V30W, "WOLF3D8.EXE"),
                   "WOLF3DB.EXE": os.path.join(BSPW, "WOLF3DV.EXE")},
    r"C:\WL1": {"WOLF3D1.EXE": os.path.join(V30W, "WOLF3D1.EXE"),
                "WOLF3D18.EXE": os.path.join(V30W, "WOLF3D18.EXE"),
                "WOLF3DM1.EXE": os.path.join(MPW, "WOLF3DM1.EXE")},
    r"C:\SPEAR": {"SPEARV.EXE": os.path.join(V30W, "SPEARV.EXE"),
                  "SPEAR8.EXE": os.path.join(V30W, "SPEAR8.EXE")},
    r"C:\MPSRV": {"MPSRV.EXE": r"C:\wolf3d\mp\build\mpsrv.exe"},
}


def dosctl(*a, timeout=1800):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a),
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def crc(p):
    return "%08X" % (zlib.crc32(open(p, "rb").read()) & 0xffffffff)


for box in sys.argv[1:]:
    for d, files in NEW.items():
        listing = dosctl("exec", "--box", box, "--quiet", "DIR %s\\*.EXE" % d).upper()
        for name, src in files.items():
            base, ext = name.split(".")
            if not re.search(r"\b%s\s+%s\b" % (base, ext), listing):
                continue                        # not on this machine: nothing to replace
            if not os.path.exists(src):
                print("%-6s %s\\%s: NO BUILD %s" % (box, d, name, src), flush=True)
                continue
            stage = os.path.join(T, box)
            os.makedirs(stage, exist_ok=True)
            shutil.copyfile(src, os.path.join(stage, name))
            dosctl("exec", "--box", box, "--quiet", "COPY %s\\%s %s\\%s.PRV" % (d, name, d, base))
            dosctl("deploy", os.path.join(stage, name), d, "--box", box)
            out = dosctl("exec", "--box", box, "--quiet", "C:\\TOOLS\\HD.EXE %s\\%s 0 0" % (d, name))
            m = re.search(r"crc32\s*:\s*([0-9A-F]{8})", out)
            got, want = (m.group(1) if m else "?"), crc(src)
            print("%-6s %s\\%-13s %s %s" % (box, d, name, got, "OK" if got == want else "WANTED " + want),
                  flush=True)
