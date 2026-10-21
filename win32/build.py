"""build.py -- the Win32 build of WOLF3DM, with Open Watcom 2.0 (C:\\WATCOM).

    python win32/build.py            the headless replay, win32/W3DREP.EXE
    python win32/build.py clean

WOLFSRC is shared with the DOS build and stays as it is: its files are copied
into obj/wsrc first, with the DOS end-of-file byte (Ctrl-Z, 1Ah) that id's
headers end with taken off -- Borland ignores it, Open Watcom does not.  A
change the Win32 build needs inside WOLFSRC is made there, under #ifdef W32,
so the DOS build's bytes do not change.  The files here (src/) are the Win32
side: the compatibility header forced into every file, and what replaces
id's managers for memory, files, sound, picture and input.

By StevenC and Claude (Anthropic), 2026-10-21.
"""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WOLFSRC = os.path.join(HERE, "..", "WOLFSRC")
OBJ = os.path.join(HERE, "obj")
WSRC = os.path.join(OBJ, "wsrc")
WATCOM = r"C:\WATCOM"

# id's files, built as they are (with W32's #ifdefs)
GAME = ["WL_ACT1", "WL_ACT2", "WL_AGENT", "WL_STATE", "WL_GAME", "WL_PLAY", "WL_MP"]
# ours, in src/
OWN = ["w32main", "w32stub", "w32ca", "w32logic", "w32tab", "w32fmt", "w32net"]
EXE = os.path.join(HERE, "W3DREP.EXE")


def tool(name):
    for d in ("binnt64", "binnt"):
        p = os.path.join(WATCOM, d, name + ".exe")
        if os.path.exists(p):
            return p
    sys.exit("no %s in %s" % (name, WATCOM))


def env():
    e = dict(os.environ)
    e["WATCOM"] = WATCOM
    e["PATH"] = os.path.join(WATCOM, "binnt64") + ";" + os.path.join(WATCOM, "binnt") + ";" + e["PATH"]
    e["INCLUDE"] = os.path.join(WATCOM, "h") + ";" + os.path.join(WATCOM, "h", "nt")
    e["LIB"] = os.path.join(WATCOM, "lib386") + ";" + os.path.join(WATCOM, "lib386", "nt")
    return e


def copy_sources():
    os.makedirs(WSRC, exist_ok=True)
    for f in glob.glob(os.path.join(WOLFSRC, "*.[CcHh]")) + glob.glob(os.path.join(WOLFSRC, "FOREIGN", "*.H")):
        rel = os.path.relpath(f, WOLFSRC)
        out = os.path.join(WSRC, rel)
        data = open(f, "rb").read().replace(b"\x1a", b"")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        if not os.path.exists(out) or open(out, "rb").read() != data:
            open(out, "wb").write(data)


def compile_one(name, src):
    obj = os.path.join(OBJ, name + ".obj")
    deps = [src, os.path.join(HERE, "src", "w32comp.h")] + glob.glob(os.path.join(WSRC, "*.H")) \
        + glob.glob(os.path.join(HERE, "src", "*.h"))
    if os.path.exists(obj) and os.path.getmtime(obj) >= max(os.path.getmtime(d) for d in deps):
        return True
    cmd = [tool("wcc386"), "-q", "-bt=nt", "-3r", "-zp1", "-w1", "-wcd=120", "-wcd=138", "-od", "-d2",
           "-fi=" + os.path.join(HERE, "src", "w32comp.h"),
           "-i=" + os.path.join(HERE, "inc"), "-i=" + WSRC, "-i=" + os.path.join(HERE, "src"),
           "-dW32", "-fo=" + obj, src]
    if name == "w32main":
        cmd.insert(1, "-s")      # its thread was not started by the runtime: no stack checks
    r = subprocess.run(cmd, capture_output=True, text=True, env=env())
    out = (r.stdout + r.stderr).strip()
    errors = [l for l in out.splitlines() if "Error!" in l]
    if out:
        print("\n".join(l for l in out.splitlines() if "Error!" in l or "Warning!" in l)[:6000])
    if r.returncode or errors:
        if os.path.exists(obj):
            os.remove(obj)
        print("%s: %d errors" % (name, len(errors)))
        return False
    return True


def main():
    if sys.argv[1:] == ["clean"]:
        shutil.rmtree(OBJ, ignore_errors=True)
        return
    copy_sources()
    ok = True
    for n in GAME:
        ok &= compile_one(n, os.path.join(WSRC, n + ".C"))
    for n in OWN:
        ok &= compile_one(n, os.path.join(HERE, "src", n + ".c"))
    if not ok:
        sys.exit("compile failed")
    lnk = os.path.join(OBJ, "w3drep.lnk")
    with open(lnk, "w") as f:
        f.write("system nt\nname %s\noption quiet, map=%s, stack=1m\ndebug all\n"
                "library wsock32\n"         # Winsock 1.1: Windows 95 and later
                % (EXE, os.path.join(OBJ, "w3drep.map")))
        for n in GAME + OWN:
            f.write("file %s\n" % os.path.join(OBJ, n + ".obj"))
    r = subprocess.run([tool("wlink"), "@" + lnk], capture_output=True, text=True, env=env())
    out = (r.stdout + r.stderr).strip()
    if r.returncode:
        undef = sorted(set(l.split("undefined symbol")[-1].strip() for l in out.splitlines()
                           if "undefined symbol" in l))
        print(out[:3000] if not undef else "undefined (%d): %s" % (len(undef), " ".join(undef)))
        sys.exit("link failed")
    print("built", EXE, os.path.getsize(EXE), "bytes")


if __name__ == "__main__":
    main()
