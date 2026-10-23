"""Package the Windows builds: release/W3DWIN.ZIP.  StevenC & Claude
(Anthropic), 2026-10-22.

    python win32/build.py              first: every Windows build from HEAD
    python mp/mkmpsrv.py --windows     ... mp/build/win/MPSRVW.EXE, the server
    python win32/mkwinrel.py

The zip holds what a player puts beside their own game data -- WOLF3DW.EXE
(the registered *.WL6), WOLF3DW1.EXE (the shareware's *.WL1), SPEARW.EXE
(Spear of Destiny's *.SOD), WOLF3DMW.EXE (the network game alone),
MPSRVW.EXE, the Windows server, and MKBJW.EXE, the players as BJ -- with release/WINDOWS.TXT and id's
LICENSE.DOC.  None of id's game data.  It refuses a program older than the
source it is built from, and prints every one's size and CRC-32 so a
release can be matched to what the machines run.
"""
import os
import subprocess
import sys
import zipfile
import zlib

WIN = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(WIN)
OUT = os.path.join(ROOT, "release", "W3DWIN.ZIP")
GAMES = ["WOLF3DW.EXE", "WOLF3DW1.EXE", "SPEARW.EXE", "WOLF3DMW.EXE"]
SERVER = os.path.join(ROOT, "mp", "build", "win", "mpsrvw.exe")
MKBJ = os.path.join(ROOT, "mp", "build", "mkbjw", "mkbjw.exe")       # python mp/mkmkbj.py (2026-10-23)


def crlf(path):
    return open(path, "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def crc(data):
    return "%08X" % (zlib.crc32(data) & 0xFFFFFFFF)


def newest(dirs, exts):
    return max(os.path.getmtime(os.path.join(d, f)) for d in dirs for f in os.listdir(d)
               if os.path.splitext(f)[1].upper() in exts)


def main():
    if subprocess.run(["git", "status", "--porcelain", "WOLFSRC", "win32/src", "mp"], cwd=ROOT,
                      capture_output=True, text=True).stdout.strip():
        sys.exit("WOLFSRC, win32/src or mp/ has uncommitted changes: commit, build, then package")
    src = newest([os.path.join(ROOT, "WOLFSRC"), os.path.join(WIN, "src")], (".C", ".H"))
    files = []
    for name in GAMES:
        p = os.path.join(WIN, name)
        if not os.path.exists(p) or os.path.getmtime(p) < src:
            sys.exit("win32/%s is missing or older than the source: python win32/build.py" % name)
        files.append((name, open(p, "rb").read()))
    if not os.path.exists(SERVER) or os.path.getmtime(SERVER) < os.path.getmtime(os.path.join(ROOT, "mp", "mpsrv.pas")):
        sys.exit("mp/build/win/mpsrvw.exe is missing or older than mp/mpsrv.pas: python mp/mkmpsrv.py --windows")
    files.append(("MPSRVW.EXE", open(SERVER, "rb").read()))
    if not os.path.exists(MKBJ) or os.path.getmtime(MKBJ) < os.path.getmtime(os.path.join(ROOT, "mp", "mkbj.pas")):
        sys.exit("mp/build/mkbjw/mkbjw.exe is missing or older than mp/mkbj.pas: python mp/mkmkbj.py")
    files.append(("MKBJW.EXE", open(MKBJ, "rb").read()))
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for name, data in files:
            z.writestr(name, data)
        z.writestr("WINDOWS.TXT", crlf(os.path.join(ROOT, "release", "WINDOWS.TXT")))
        z.writestr("LICENSE.DOC", open(os.path.join(ROOT, "WOLFSRC", "README", "LICENSE.DOC"), "rb").read())
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print("%s: %d bytes, source %s" % (OUT, os.path.getsize(OUT), head))
    for name, data in files:
        print("%-12s %7d bytes, CRC-32 %s" % (name, len(data), crc(data)))
    with zipfile.ZipFile(OUT) as z:
        for i in z.infolist():
            print("  %-14s %7d" % (i.filename, i.file_size))


if __name__ == "__main__":
    main()
