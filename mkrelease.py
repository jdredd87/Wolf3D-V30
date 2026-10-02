"""Package a playable release: release/W3DV30.ZIP.  StevenC & Claude, 2026.

    python w3dbuild.py build      first: WOLFSRC\\WOLF3DV.EXE from HEAD
    python mkrelease.py

The zip holds what a player copies beside their own *.WL6 files --
WOLF3DV.EXE, the menu (W3MENU.EXE, PLAY.BAT), the demo reel (SHOWCASE.BAT),
release/README.TXT and id's LICENSE.DOC -- and none of id's game data.
Text files go in with CRLF, for DOS.  It refuses an EXE older than the
newest committed source, and prints the EXE's size and CRC-32 so a
release can be matched to its build.
"""
import os
import subprocess
import sys
import zipfile
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import w3dbuild          # noqa: E402  (build_launcher)
sys.path.insert(0, os.path.join(HERE, "launcher"))
import mkshow            # noqa: E402

EXE = os.path.join(HERE, "WOLFSRC", "WOLF3DV.EXE")
OUT = os.path.join(HERE, "release", "W3DV30.ZIP")


def crlf(path):
    return open(path, "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def main():
    if subprocess.run(["git", "status", "--porcelain", "WOLFSRC"], cwd=HERE,
                      capture_output=True, text=True).stdout.strip():
        sys.exit("WOLFSRC has uncommitted changes: commit, build, then package")
    src_time = max(os.path.getmtime(os.path.join(HERE, "WOLFSRC", f))
                   for f in os.listdir(os.path.join(HERE, "WOLFSRC"))
                   if os.path.splitext(f)[1].upper() in (".C", ".H", ".ASM"))
    if os.path.getmtime(EXE) < src_time:
        sys.exit("WOLF3DV.EXE is older than the source: python w3dbuild.py build")
    menu = w3dbuild.build_launcher()
    show = mkshow.write()
    exe = open(EXE, "rb").read()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("WOLF3DV.EXE", exe)
        z.write(menu, "W3MENU.EXE")
        z.writestr("PLAY.BAT", crlf(os.path.join(HERE, "launcher", "PLAY.BAT")))
        z.writestr("SHOWCASE.BAT", crlf(show))
        z.writestr("README.TXT", crlf(os.path.join(HERE, "release", "README.TXT")))
        z.writestr("LICENSE.DOC", open(os.path.join(HERE, "WOLFSRC", "README", "LICENSE.DOC"), "rb").read())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=HERE,
                          capture_output=True, text=True).stdout.strip()
    print("%s: %d bytes" % (OUT, os.path.getsize(OUT)))
    print("WOLF3DV.EXE %d bytes, CRC-32 %08X, source %s" % (len(exe), zlib.crc32(exe) & 0xFFFFFFFF, head))
    with zipfile.ZipFile(OUT) as z:
        for i in z.infolist():
            print("  %-12s %7d" % (i.filename, i.file_size))


main()
