"""Build Wolfenstein 3-D for the NEC V30 over DOS Bridge -- StevenC & Claude, 2026.

Borland C++ 3.1's BCC and TLINK are DPMI programs and need a 286 or better, so
the compile runs on the 486 (box `dx486`) and the EXE it makes is run on the
V30 (box `v30`).  Nothing is compiled on this PC: 64-bit Windows cannot run
DOS programs.

    python w3dbuild.py bcpp          ship Borland C++ 3.1 (the subset we need) to the 486
    python w3dbuild.py build         ship WOLFSRC, build on the 486, pull WOLF3DV.EXE + .MAP back
    python w3dbuild.py deploy        put WOLFSRC\\WOLF3DV.EXE into the V30's C:\\WOLF3D, with the
                                     switches menu (PLAY.BAT and W3MENU.EXE, built here)
                                     and the demo reel (SHOWCASE.BAT)
    python w3dbuild.py all           build, then deploy
    python w3dbuild.py listings WL_DR_A.ASM WL_DRAW.C ...
                                     assembler listings into stage/lst, to read profiles against

The source goes to C:\\W3D on the 486 and Borland C++ to C:\\BCPP (the same
path it has on the V30).  The V30 only ever receives WOLF3DV.EXE, beside the
game data in C:\\WOLF3D; nothing of id's there is touched.
"""
import os
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
# W3D_SRC / W3D_REMOTE build another tree (the reference renderer, for one)
# in its own folder on the 486, leaving WOLFSRC and C:\\W3D alone
SRC = os.environ.get("W3D_SRC", os.path.join(HERE, "WOLFSRC"))
REMOTE = os.environ.get("W3D_REMOTE", r"C:\W3D")
BRIDGE = os.environ.get("DOSBRIDGE", r"C:\dosbridgeDEV")
DOSCTL = [sys.executable, os.path.join(BRIDGE, "dosctl.py")]
BCPP_SRC = os.environ.get("BCPP_SRC", r"C:\Software\86Box\Software\BCPP")
LAUNCHER = os.path.join(HERE, "launcher")    # W3MENU.EXE and PLAY.BAT, the switches menu
STAGE = os.path.join(HERE, "stage")          # zips land here; git-ignored
BUILD_BOX = "dx486"
RUN_BOX = "v30"

BCPP_BIN = ["BCC.EXE", "TLINK.EXE", "TASM.EXE", "DPMI16BI.OVL", "DPMILOAD.EXE",
            "DPMIMEM.DLL", "DPMIINST.EXE", "DPMIRES.EXE"]
BCPP_LIB = ["CM.LIB", "MATHM.LIB", "EMU.LIB", "FP87.LIB", "C0M.OBJ"]
SRC_EXT = {".C", ".H", ".ASM", ".EQU", ".ASI", ".BAT", ".CFG", ".RSP"}


def dosctl(*args, timeout=600, check=True):
    cmd = DOSCTL + list(args) + ["--timeout", str(timeout)]
    print(">", " ".join(args), flush=True)
    # PKUNZIP's progress bar is CP437 graphics; a piped cp1252 stdout cannot print it
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    r = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                       errors="replace", env=env)
    out = r.stdout + r.stderr
    print(out.rstrip())
    if check and r.returncode != 0:
        sys.exit("dosctl %s failed, rc %d" % (args[0], r.returncode))
    return out


def make_zip(path, entries):
    os.makedirs(STAGE, exist_ok=True)
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for src, arc in entries:
            z.write(src, arc)
    print("%s: %d files, %d bytes" % (os.path.basename(path), len(entries), os.path.getsize(path)))


def ship_zip(zpath, dest):
    """Deploy one zip to BUILD_BOX and unpack it into dest (a directory)."""
    name = os.path.basename(zpath)
    # dosd CRC-checks every deploy and refuses a corrupt one, so a retry is safe
    for attempt in range(3):
        out = dosctl("deploy", zpath, r"C:\WORK", "--box", BUILD_BOX, check=False)
        if "dosctl: deployed" in out:
            break
    else:
        sys.exit("deploy of %s failed three times" % name)
    dosctl("exec", "IF NOT EXIST %s\\NUL MD %s" % (dest, dest),
           r"C:\SOFTWARE\PKZIP\PKUNZIP.EXE -o -d C:\WORK\%s %s\ " % (name, dest),
           r"DEL C:\WORK\%s" % name,
           "--box", BUILD_BOX, "--quiet")


def cmd_bcpp():
    entries = [(os.path.join(BCPP_SRC, "BIN", f), "BIN/" + f) for f in BCPP_BIN]
    inc = os.path.join(BCPP_SRC, "INCLUDE")
    for root, _, files in os.walk(inc):
        for f in files:
            p = os.path.join(root, f)
            entries.append((p, os.path.relpath(p, BCPP_SRC).replace(os.sep, "/")))
    entries += [(os.path.join(BCPP_SRC, "LIB", f), "LIB/" + f) for f in BCPP_LIB]
    z = os.path.join(STAGE, "BCPP.ZIP")
    make_zip(z, entries)
    ship_zip(z, r"C:\BCPP")
    dosctl("exec", r"DIR C:\BCPP\BIN", "--box", BUILD_BOX)


def cmd_build():
    entries = []
    for f in sorted(os.listdir(SRC)):
        if os.path.splitext(f)[1].upper() in SRC_EXT:
            entries.append((os.path.join(SRC, f), f))
    for f in ("GAMEPAL.OBJ", "SIGNON.OBJ"):
        entries.append((os.path.join(SRC, "OBJ", f), "OBJ/" + f))
    z = os.path.join(STAGE, os.path.basename(REMOTE) + "SRC.ZIP")
    make_zip(z, entries)
    ship_zip(z, REMOTE)
    # CALL, or the job's own batch never gets control back to send the result
    # CALL, or the job's own batch never gets control back to send the result;
    # and the log is TYPEd because a CALLed batch's output cannot be redirected
    out = dosctl("exec", "CD " + REMOTE, "CALL BUILD86.BAT", "TYPE " + REMOTE + r"\BUILD.LOG",
                 "--box", BUILD_BOX, timeout=1500, check=False)
    if "##BUILD OK" not in out:
        sys.exit("build FAILED on %s -- see the output above" % BUILD_BOX)
    for f in ("WOLF3DV.EXE", "WOLF3DV.MAP"):
        dosctl("pull", REMOTE + "\\" + f, "--out", os.path.join(SRC, f), "--box", BUILD_BOX)
    print("built:", os.path.join(SRC, "WOLF3DV.EXE"), os.path.getsize(os.path.join(SRC, "WOLF3DV.EXE")), "bytes")


def cmd_listings(names):
    """Assembler listings of the given modules, for reading profiles against:
    TASM /l for an .ASM, BCC -S (the compiler's own assembly) for a .C.
    Uses the sources already on the 486 (in W3D_REMOTE) -- run `build` first."""
    cmds = ["CD " + REMOTE, "IF NOT EXIST %s\\LST\\NUL MD %s\\LST" % (REMOTE, REMOTE)]
    pulls = []
    for n in names:
        base, ext = os.path.splitext(n.upper())
        if ext == ".ASM":
            cmds.append(r"C:\BCPP\BIN\TASM.EXE /l /mx /m2 /d__MEDIUM__ %s.ASM,NUL,LST\%s.LST" % (base, base))
            pulls.append(base + ".LST")
        else:
            # BCC -S has no byte offsets; assembling its output with /l gives
            # them, for the identical code, to read profile offsets against
            cmds.append(r"C:\BCPP\BIN\BCC.EXE -S -nLST %s.C" % base)
            cmds.append(r"C:\BCPP\BIN\TASM.EXE /l /mx LST\%s.ASM,NUL,LST\%s.LST" % (base, base))
            pulls += [base + ".ASM", base + ".LST"]
    dosctl("exec", *cmds, "--box", BUILD_BOX, timeout=900)
    out = os.path.join(STAGE, "lst")
    os.makedirs(out, exist_ok=True)
    for f in pulls:
        dosctl("pull", REMOTE + "\\LST\\" + f, "--out", os.path.join(out, f), "--box", BUILD_BOX)
    print("listings in", out)


def cmd_deploy():
    exe = os.path.join(SRC, "WOLF3DV.EXE")
    if not os.path.exists(exe):
        sys.exit("no WOLF3DV.EXE yet -- run `build` first")
    dosctl("deploy", exe, r"C:\WOLF3D", "--box", RUN_BOX)
    # and the switches menu: PLAY.BAT runs W3MENU.EXE, built here with FPC
    dosctl("deploy", build_launcher(), r"C:\WOLF3D", "--box", RUN_BOX)
    dosctl("deploy", os.path.join(LAUNCHER, "PLAY.BAT"), r"C:\WOLF3D", "--box", RUN_BOX)
    sys.path.insert(0, LAUNCHER)        # and the demo reel, SHOWCASE.BAT, fresh
    import mkshow
    dosctl("deploy", mkshow.write(), r"C:\WOLF3D", "--box", RUN_BOX)


def build_launcher():
    """launcher\\w3menu.pas -> launcher\\build\\W3MENU.EXE, with the FPC
    i8086 cross-compiler and the bridge's starter units (VidFix)."""
    out = os.path.join(LAUNCHER, "build")
    os.makedirs(out, exist_ok=True)
    r = subprocess.run(["fpc", "-Tmsdos", "-Pi8086", "-WmSmall",
                        "-Fu" + os.path.join(BRIDGE, "starter"), "-FEbuild", "-FUbuild",
                        "w3menu.pas"], cwd=LAUNCHER, capture_output=True, text=True)
    if r.returncode:
        sys.exit("W3MENU build failed:\n" + r.stdout + r.stderr)
    return os.path.join(out, "w3menu.exe")


def main():
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "bcpp":
        cmd_bcpp()
    elif cmd == "build":
        cmd_build()
    elif cmd == "deploy":
        cmd_deploy()
    elif cmd == "listings":
        cmd_listings(sys.argv[2:])
    elif cmd == "all":
        cmd_build()
        cmd_deploy()
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
