"""Package the network game: release/W3DMP.ZIP.  StevenC & Claude, 2026-10-15.

    python w3dbuild.py build      first: WOLFSRC\\WOLF3DV.EXE from this branch's HEAD
    python mp/mkmprel.py

The zip holds what each player copies beside their own *.WL6 files --
WOLF3DM.EXE (this branch's build, renamed), the PLAY menu with its network
page (W3MENU.EXE, built here, and PLAY.BAT), release/MULTI.TXT and id's
LICENSE.DOC -- and SERVER\\, the Python server for the host PC (mpserver,
mpproto, mpconsole, mpctl, and gendemo for the bots' moves, in the layout
mpserver.py imports them from).  None of id's game data.  Text files for
DOS go in with CRLF.  It refuses an EXE older than the newest committed
source, and prints the EXE's size and CRC-32 so a release can be matched to
what the machines run.
"""
import os
import subprocess
import sys
import zipfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
import w3dbuild          # noqa: E402  (build_launcher)

EXE = os.path.join(ROOT, "WOLFSRC", "WOLF3DV.EXE")
OUT = os.path.join(ROOT, "release", "W3DMP.ZIP")
SERVER = ["mp/mpserver.py", "mp/mpproto.py", "mp/mpconsole.py", "mp/mpctl.py", "gendemo.py"]


def crlf(path):
    return open(path, "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def main():
    if subprocess.run(["git", "status", "--porcelain", "WOLFSRC", "mp", "gendemo.py"], cwd=ROOT,
                      capture_output=True, text=True).stdout.strip():
        sys.exit("WOLFSRC, mp/ or gendemo.py has uncommitted changes: commit, build, then package")
    src = [os.path.join(ROOT, "WOLFSRC", f) for f in os.listdir(os.path.join(ROOT, "WOLFSRC"))
           if os.path.splitext(f)[1].upper() in (".C", ".H", ".ASM")]
    if os.path.getmtime(EXE) < max(os.path.getmtime(p) for p in src):
        sys.exit("WOLFSRC\\WOLF3DV.EXE is older than the source: python w3dbuild.py build")
    menu = w3dbuild.build_launcher()
    exe = open(EXE, "rb").read()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("WOLF3DM.EXE", exe)
        z.write(menu, "W3MENU.EXE")
        z.writestr("PLAY.BAT", crlf(os.path.join(ROOT, "launcher", "PLAY.BAT")))
        z.writestr("MULTI.TXT", crlf(os.path.join(ROOT, "release", "MULTI.TXT")))
        z.writestr("LICENSE.DOC", open(os.path.join(ROOT, "WOLFSRC", "README", "LICENSE.DOC"), "rb").read())
        for f in SERVER:
            z.write(os.path.join(ROOT, f), "SERVER/" + f)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print("%s: %d bytes" % (OUT, os.path.getsize(OUT)))
    print("WOLF3DM.EXE %d bytes, CRC-32 %08X, source %s" % (len(exe), zlib.crc32(exe) & 0xFFFFFFFF, head))
    with zipfile.ZipFile(OUT) as z:
        for i in z.infolist():
            print("  %-24s %7d" % (i.filename, i.file_size))


main()
