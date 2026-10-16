"""Build the Wolf3D server -- StevenC & Claude, 2026-10-15.

    python mp/mkmpsrv.py              -> mp/build/MPSRV.EXE      (DOS, the plain 8086)
    python mp/mkmpsrv.py --windows    -> mp/build/win/MPSRVW.EXE (Windows, 32-bit)

One source, mp/mpsrv.pas.  For DOS: FPC's i8086-msdos cross-compiler, large
model, with the DOS Bridge's starter units on the unit and include paths
(About, VidFix, sumbuf.inc) and mp/srvnet.pas, the packet driver.  For
Windows: FPC's own i386-win32 compiler and mp/winnet.pas, WinSock.  Run from
anywhere; DOSBRIDGE says where the bridge is (C:\\dosbridgeDEV by default).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STARTER = os.path.join(os.environ.get("DOSBRIDGE", r"C:\dosbridgeDEV"), "starter")


def main():
    if "--windows" in sys.argv:
        out_dir = os.path.join("build", "win")
        cmd = ["fpc", "-Twin32", "-O2", "-FE" + out_dir, "-FU" + out_dir, "-ompsrvw.exe", "mpsrv.pas"]
        exe = os.path.join(HERE, out_dir, "mpsrvw.exe")
    else:
        out_dir = "build"
        cmd = ["fpc", "-Tmsdos", "-Pi8086", "-WmLarge", "-O2", "-Fu" + STARTER, "-Fi" + STARTER,
               "-FE" + out_dir, "-FU" + out_dir, "mpsrv.pas"]
        exe = os.path.join(HERE, out_dir, "mpsrv.exe")
    os.makedirs(os.path.join(HERE, out_dir), exist_ok=True)
    r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
    out = [l for l in (r.stdout + r.stderr).splitlines()
           if not l.startswith(("Free Pascal", "Copyright", "Target OS", "Compiling", "Assembling"))]
    print("\n".join(out))
    if r.returncode or not os.path.exists(exe):
        sys.exit("build FAILED")
    print("built:", exe, os.path.getsize(exe), "bytes")


main()
