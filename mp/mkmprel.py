"""Package the network game: release/W3DMP.ZIP.  StevenC & Claude, 2026-10-15/16.

    python w3dbuild.py build          first: WOLFSRC\\WOLF3DV.EXE from this branch's HEAD
    python mp/mkmpsrv.py              ... mp/build/MPSRV.EXE, the DOS server
    python mp/mkmpsrv.py --windows    ... mp/build/win/MPSRVW.EXE, the Windows server
    python mp/mkmprel.py

The zip holds what each player copies beside their own *.WL6 files --
WOLF3DM.EXE (this branch's build, renamed), the PLAY menu with its network
page (W3MENU.EXE, built here, and PLAY.BAT), release/MULTI.TXT and id's
LICENSE.DOC -- and SERVER\\, the three servers, any one of which hosts a
game: MPSRV.EXE for a DOS machine, MPSRVW.EXE for Windows (since v1.4, both
built from mp/mpsrv.pas), and the Python one (mpserver, mpproto, mpconsole,
mpctl, and gendemo for the bots' moves, in the layout mpserver.py imports
them from).  None of id's game data.  Text files for DOS go in with CRLF.
It refuses an EXE older than its committed source, and prints every EXE's
size and CRC-32 so a release can be matched to what the machines run.
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
PYSERVER = ["mp/mpserver.py", "mp/mpproto.py", "mp/mpconsole.py", "mp/mpctl.py", "gendemo.py"]
# the Free Pascal servers: (built file, its name in the zip, the sources it is built from)
FPSERVERS = [("mp/build/mpsrv.exe", "SERVER/MPSRV.EXE", ["mp/mpsrv.pas", "mp/srvnet.pas"]),
             ("mp/build/win/mpsrvw.exe", "SERVER/MPSRVW.EXE", ["mp/mpsrv.pas", "mp/winnet.pas"])]


def crlf(path):
    return open(path, "rb").read().replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")


def setup_txt():
    """SETUP.md as plain text for DOS (2026-10-16): links as "text (url)",
    headings in capitals and underlined, code blocks indented, no ** or `."""
    import re
    md = open(os.path.join(ROOT, "SETUP.md"), encoding="utf-8").read().replace("\r\n", "\n")
    out, code = [], False
    for line in md.split("\n"):
        if line.strip().startswith("```"):
            code = not code
            continue
        if code:
            out.append("    " + line)
            continue
        if re.match(r"^\|[-| ]+\|$", line):          # a table's separator row
            continue
        line = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: m.group(1) if m.group(2).endswith(".md")
                      else "%s (%s)" % (m.group(1), m.group(2)), line)
        line = line.replace("**", "").replace("`", "").replace(r"\|", "|")
        m = re.match(r"^(#+) (.*)$", line)
        if m:
            text = m.group(2).upper() if len(m.group(1)) <= 2 else m.group(2)
            out += [text, ("=" if len(m.group(1)) == 1 else "-") * len(text)]
            continue
        out.append(line)
    text = "\n".join(out).replace("MULTIPLAYER.md", "MULTIPLAYER.md on the multiplayer branch")
    return text.replace("\n", "\r\n").encode("latin-1", "replace")


def crc(data):
    return "%08X" % (zlib.crc32(data) & 0xFFFFFFFF)


def main():
    if subprocess.run(["git", "status", "--porcelain", "WOLFSRC", "mp", "gendemo.py"], cwd=ROOT,
                      capture_output=True, text=True).stdout.strip():
        sys.exit("WOLFSRC, mp/ or gendemo.py has uncommitted changes: commit, build, then package")
    src = [os.path.join(ROOT, "WOLFSRC", f) for f in os.listdir(os.path.join(ROOT, "WOLFSRC"))
           if os.path.splitext(f)[1].upper() in (".C", ".H", ".ASM")]
    if os.path.getmtime(EXE) < max(os.path.getmtime(p) for p in src):
        sys.exit("WOLFSRC\\WOLF3DV.EXE is older than the source: python w3dbuild.py build")
    servers = []
    for built, name, sources in FPSERVERS:
        p = os.path.join(ROOT, built)
        if not os.path.exists(p):
            sys.exit("no %s: python mp/mkmpsrv.py%s" % (built, " --windows" if "win" in built else ""))
        if os.path.getmtime(p) < max(os.path.getmtime(os.path.join(ROOT, s)) for s in sources):
            sys.exit("%s is older than its source: python mp/mkmpsrv.py%s"
                     % (built, " --windows" if "win" in built else ""))
        servers.append((name, open(p, "rb").read()))
    menu = w3dbuild.build_launcher()
    exe = open(EXE, "rb").read()
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("WOLF3DM.EXE", exe)
        z.write(menu, "W3MENU.EXE")
        z.writestr("PLAY.BAT", crlf(os.path.join(ROOT, "launcher", "PLAY.BAT")))
        z.writestr("MULTI.TXT", crlf(os.path.join(ROOT, "release", "MULTI.TXT")))
        z.writestr("SETUP.TXT", setup_txt())             # SETUP.md, for DOS (2026-10-16)
        z.writestr("LICENSE.DOC", open(os.path.join(ROOT, "WOLFSRC", "README", "LICENSE.DOC"), "rb").read())
        for name, data in servers:
            z.writestr(name, data)
        for f in PYSERVER:
            z.write(os.path.join(ROOT, f), "SERVER/" + f)
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    print("%s: %d bytes, source %s" % (OUT, os.path.getsize(OUT), head))
    print("WOLF3DM.EXE  %7d bytes, CRC-32 %s" % (len(exe), crc(exe)))
    for name, data in servers:
        print("%-12s %7d bytes, CRC-32 %s" % (os.path.basename(name), len(data), crc(data)))
    with zipfile.ZipFile(OUT) as z:
        for i in z.infolist():
            print("  %-24s %7d" % (i.filename, i.file_size))


main()
