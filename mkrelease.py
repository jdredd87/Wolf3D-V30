"""Package a playable release: release/W3DV30.ZIP.  StevenC & Claude, 2026.

    python w3dbuild.py build      first: WOLFSRC\\WOLF3DV.EXE from HEAD
    python mkrelease.py

The zip holds what a player copies beside their own *.WL6 files --
WOLF3DV.EXE, WOLF3DB.EXE (the bsp branch's build) and WOLF3DO.EXE (id's
code, refsrc.py's build), both taken from stage/deploy, the menu
(W3MENU.EXE, PLAY.BAT), the demo reel (SHOWCASE.BAT and SHOW?.BAT),
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
    shows = mkshow.write()              # SHOWCASE.BAT and its reels
    exe = open(EXE, "rb").read()
    # v1.2: the BSP branch's WOLF3DB.EXE and refsrc.py's WOLF3DO.EXE (id's
    # code), built separately and placed in stage/deploy -- their CRCs are
    # printed below, to be matched with what the boxes run
    others = []
    for name in ("WOLF3DB.EXE", "WOLF3DO.EXE"):
        p = os.path.join(HERE, "stage", "deploy", name)
        if not os.path.exists(p):
            sys.exit("no stage/deploy/%s: build it (the bsp branch; refsrc.py)" % name)
        others.append((name, open(p, "rb").read()))
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("WOLF3DV.EXE", exe)
        for name, data in others:
            z.writestr(name, data)
        z.write(menu, "W3MENU.EXE")
        z.writestr("PLAY.BAT", crlf(os.path.join(HERE, "launcher", "PLAY.BAT")))
        for p in shows:
            z.writestr(os.path.basename(p), crlf(p))
        z.writestr("README.TXT", crlf(os.path.join(HERE, "release", "README.TXT")))
        z.writestr("LICENSE.DOC", open(os.path.join(HERE, "WOLFSRC", "README", "LICENSE.DOC"), "rb").read())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=HERE,
                          capture_output=True, text=True).stdout.strip()
    print("%s: %d bytes" % (OUT, os.path.getsize(OUT)))
    print("WOLF3DV.EXE %d bytes, CRC-32 %08X, source %s" % (len(exe), zlib.crc32(exe) & 0xFFFFFFFF, head))
    for name, data in others:
        print("%s %d bytes, CRC-32 %08X" % (name, len(data), zlib.crc32(data) & 0xFFFFFFFF))
    with zipfile.ZipFile(OUT) as z:
        for i in z.infolist():
            print("  %-12s %7d" % (i.filename, i.file_size))


main()
