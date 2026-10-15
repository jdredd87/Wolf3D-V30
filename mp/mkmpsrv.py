"""Build MPSRV.EXE, the DOS server -- StevenC & Claude, 2026-10-15.

    python mp/mkmpsrv.py            -> mp/build/MPSRV.EXE

FPC's i8086-msdos cross-compiler, large model, with the DOS Bridge's starter
units on the unit and include paths (About, VidFix, sumbuf.inc).  Run from
anywhere; DOSBRIDGE says where the bridge is (C:\\dosbridgeDEV by default).
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
STARTER = os.path.join(os.environ.get("DOSBRIDGE", r"C:\dosbridgeDEV"), "starter")


def main():
    os.makedirs(os.path.join(HERE, "build"), exist_ok=True)
    r = subprocess.run(["fpc", "-Tmsdos", "-Pi8086", "-WmLarge", "-O2",
                        "-Fu" + STARTER, "-Fi" + STARTER, "-FEbuild", "-FUbuild", "mpsrv.pas"],
                       cwd=HERE, capture_output=True, text=True)
    out = [l for l in (r.stdout + r.stderr).splitlines()
           if not l.startswith(("Free Pascal", "Copyright", "Target OS", "Compiling", "Assembling"))]
    print("\n".join(out))
    exe = os.path.join(HERE, "build", "mpsrv.exe")
    if r.returncode or not os.path.exists(exe):
        sys.exit("build FAILED")
    print("built:", exe, os.path.getsize(exe), "bytes")


main()
