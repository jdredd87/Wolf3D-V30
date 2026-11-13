"""release.py VERSION -- a multiplayer release in one command.  StevenC & Claude
(Anthropic), 2026-11-13.

    python tests/release.py 1.14 [--no-deploy] [--no-push] [--dry-run]

In order, stopping at the first thing that fails:

  1. the tree is clean, and release/MULTI.TXT and WINDOWS.TXT both say
     "Version VERSION" (the notes are written by hand, first);
  2. every DOS build on the 486 (w3dbuild.py build, buildwl1, buildsod),
     every Windows build (win32/build.py), both servers (mp/mkmpsrv.py);
  3. win32/gate.sh -- 8 of 8, or no release;
  4. unless --no-deploy: the DOS programs onto every box (deployall.py,
     read back by CRC) and the Windows ones onto .37 (MD5);
  5. W3DMP.ZIP and W3DWIN.ZIP (mp/mkmprel.py, win32/mkwinrel.py);
  6. the Windows programs committed as packed, tag vVERSION;
  7. unless --no-push: win32, multiplayer (fast-forward) and the tag pushed;
  8. stage/relVER-notes.md's table of every program's size and CRC-32,
     and the gh command for StevenC to publish with.

--dry-run says what it would do.  The boxes must be free of games (the
486 builds), and dosd running.
"""
import hashlib
import os
import re
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIN = os.path.join(ROOT, "win32")
SRC = os.path.join(ROOT, "WOLFSRC")
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
BOXES = ["dx486", "p3", "v30"]
DOS = ["WOLF3DM.EXE", "WOLF3DM1.EXE", "SPEARM.EXE"]
WINGAMES = [("WOLF3DMW.EXE", r"C:\W3DWIN"), ("WOLF3DW.EXE", r"C:\W3DWIN"),
            ("WOLF3DW1.EXE", r"C:\W3DWIN1"), ("SPEARW.EXE", r"C:\W3DSOD")]
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
DRY = "--dry-run" in sys.argv


def step(what):
    print("\n== " + what, flush=True)


def run(cmd, cwd=ROOT, check=True, quiet=False):
    print("> " + (cmd if isinstance(cmd, str) else " ".join(cmd)), flush=True)
    if DRY:
        return ""
    r = subprocess.run(cmd, cwd=cwd, shell=isinstance(cmd, str), capture_output=True, text=True,
                       encoding="utf-8", errors="replace", env=ENV)
    out = r.stdout + r.stderr
    if not quiet:
        print("\n".join(out.strip().splitlines()[-6:]), flush=True)
    if check and r.returncode:
        sys.exit("FAILED (rc %d): %s" % (r.returncode, cmd))
    return out


def crc(p):
    return "%08X" % (zlib.crc32(open(p, "rb").read()) & 0xffffffff)


def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("-"):
        sys.exit(__doc__)
    ver = sys.argv[1]
    tag = "v" + ver

    step("1. the tree and the notes")
    dirty = run(["git", "status", "--porcelain", "--untracked-files=no"], quiet=True)
    if dirty.strip() and not DRY:
        sys.exit("the tree has changes -- commit them first:\n" + dirty)
    for f in ("MULTI.TXT", "WINDOWS.TXT"):
        if "Version %s," % ver not in open(os.path.join(ROOT, "release", f), errors="replace").read():
            sys.exit("release/%s does not say \"Version %s,\" -- write the notes first" % (f, ver))
    if run(["git", "tag", "-l", tag], quiet=True).strip():
        sys.exit("%s is already a tag" % tag)

    step("2. every build")
    run([sys.executable, "w3dbuild.py", "build"])
    run([sys.executable, "w3dbuild.py", "buildwl1"])
    run([sys.executable, "w3dbuild.py", "buildsod"])
    for t in ("game", "sp", "sp1", "spsod", "rep", "rep1", "repsod"):
        run([sys.executable, "build.py", t], cwd=WIN)
    run([sys.executable, os.path.join("mp", "mkmpsrv.py")])
    run([sys.executable, os.path.join("mp", "mkmpsrv.py"), "--windows"])

    step("3. the gate")
    out = run(["bash", "gate.sh"], cwd=WIN, check=False)
    if not DRY and not re.search(r"gate: \d+ passed, 0 failed", out):
        sys.exit("the gate failed -- no release")

    if "--no-deploy" not in sys.argv:
        step("4. onto every machine")
        ENV["ONLY"] = " ".join(DOS + ["MPSRV.EXE"])     # deployall: just these
        for b in BOXES:
            out = run([sys.executable, os.path.join("tests", "deployall.py"), b], check=False)
            if "WANTED" in out or "NO BUILD" in out:
                sys.exit("a program on %s did not read back right:\n%s" % (b, out))
        for name, d in WINGAMES:
            src = os.path.join(WIN, name)
            want = hashlib.md5(open(src, "rb").read()).hexdigest().upper()
            run(AGENT + ["put", src, d + "\\" + name], quiet=True)
            got = run(AGENT + ["ps", "(Get-FileHash '%s\\%s' -Algorithm MD5).Hash" % (d, name)], quiet=True)
            if not DRY and want not in got.upper():
                sys.exit(".37: %s\\%s did not read back right" % (d, name))
            print("   .37 %s\\%s OK" % (d, name))

    step("5. the zips")
    run([sys.executable, os.path.join("mp", "mkmprel.py")])
    run([sys.executable, os.path.join("win32", "mkwinrel.py")])

    step("6. commit and tag")
    run(["git", "add"] + [os.path.join("win32", n) for n, _ in WINGAMES])
    if not DRY and subprocess.run(["git", "diff", "--cached", "--quiet"], cwd=ROOT).returncode:
        run(["git", "commit", "-q", "-m", "%s: the Windows programs as packed in W3DWIN.ZIP\n\n"
             "StevenC & Claude (Anthropic).\n\nCo-Authored-By: Claude <noreply@anthropic.com>" % ver])
    run(["git", "tag", "-a", tag, "-m", "Wolfenstein 3-D multiplayer %s -- StevenC & Claude" % ver])

    if "--no-push" not in sys.argv:
        step("7. push")
        run(["git", "push", "-q", "origin", "win32"])
        run(["git", "push", "-q", "origin", "win32:multiplayer"])
        run(["git", "branch", "-f", "multiplayer", "win32"])
        run(["git", "push", "-q", "origin", tag])

    step("8. the table, and the command to publish")
    rows = [(n, os.path.join(SRC, "WOLF3DV.EXE" if n == "WOLF3DM.EXE" else n)) for n in DOS]
    rows += [("MPSRV.EXE", os.path.join(ROOT, "mp", "build", "mpsrv.exe"))]
    rows += [(n, os.path.join(WIN, n)) for n in ("WOLF3DW.EXE", "WOLF3DW1.EXE", "SPEARW.EXE", "WOLF3DMW.EXE")]
    rows += [("MPSRVW.EXE", os.path.join(ROOT, "mp", "build", "win", "mpsrvw.exe"))]
    table = "| file | bytes | CRC-32 |\n|---|---|---|\n" + "".join(
        "| %s | %s | %s |\n" % (n, format(os.path.getsize(p), ","), crc(p)) for n, p in rows if os.path.exists(p))
    notes = os.path.join(ROOT, "stage", "rel%s-notes.md" % ver.replace(".", ""))
    if not os.path.exists(notes) and not DRY:
        open(notes, "w", encoding="utf-8").write("(what is new -- by hand)\n\n" + table +
                                                 "\nBy StevenC and Claude (Anthropic).\n")
    print(table)
    print("notes: %s (write what is new above the table)" % notes)
    print('\ngh release create %s -R jdredd87/Wolf3D-V30 --title "Wolfenstein 3-D for 8086-class PCs %s: ... -- '
          'StevenC & Claude" --notes-file %s release/W3DMP.ZIP release/W3DWIN.ZIP release/W3DV30.ZIP'
          % (tag, tag, os.path.relpath(notes, ROOT).replace("\\", "/")))


if __name__ == "__main__":
    main()
