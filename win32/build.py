"""build.py -- the Win32 build of WOLF3DM, with Open Watcom 2.0 (C:\\WATCOM).

    python win32/build.py            both: W3DREP.EXE and WOLF3DMW.EXE
    python win32/build.py rep        the headless replay, win32/W3DREP.EXE (the gate)
    python win32/build.py game       the network game, win32/WOLF3DMW.EXE (a window)
    python win32/build.py sp         the whole game, win32/WOLF3DW.EXE: id's own
                                     single-player game -- title, menus, floors,
                                     tallies, saves -- and NET as well
    python win32/build.py sp1        the same for the shareware: WOLF3DW1.EXE (*.WL1)
    python win32/build.py spsod      Spear of Destiny: SPEARW.EXE (*.SOD)
    python win32/build.py clean

WOLFSRC is shared with the DOS build and stays as it is: its files are copied
into obj/wsrc first, with the DOS end-of-file byte (Ctrl-Z, 1Ah) that id's
headers end with taken off -- Borland ignores it, Open Watcom does not.  A
change the Win32 build needs inside WOLFSRC is made there, under #ifdef W32,
so the DOS build's bytes do not change.  The files here (src/) are the Win32
side: the compatibility header forced into every file, and what replaces
id's managers for memory, files, sound, picture and input.  The two programs
share all of it but their picture and input: w32null.c in the replay;
w32gfx.c, w32draw.c, w32win.c and w32in.c in the game.

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
# id's single-player files, for the whole game (sp): built with W32SP, which
# also leaves VERSION.H's NETGAME off -- the saves, tallies and help come back
SPGAME = ["WL_MAIN", "WL_MENU", "WL_INTER", "WL_TEXT", "ID_US_1", "WL_DEBUG"]
# ours, in src/: in both, then each program's own
COMMON = ["w32main", "w32stub", "w32ca", "w32logic", "w32tab", "w32fmt", "w32net", "w32pal", "w32dos"]
GUI = ["w32gfx", "w32draw", "w32win", "w32in", "w32snd", "w32wave"]
# target: (exe, system, our own files, id's extra files, defines)
TARGETS = {
    "rep": ("W3DREP.EXE", "nt", ["w32null"], [], []),
    "game": ("WOLF3DMW.EXE", "nt_win", GUI, [], []),
    "sp": ("WOLF3DW.EXE", "nt_win", GUI + ["w32sp", "w32vis", "w32sign"], SPGAME, ["W32SP"]),
    # the shareware (*.WL1) and Spear of Destiny (*.SOD), as w3dbuild.py's
    # buildwl1 and buildsod make the DOS ones: UPLOAD; SPEAR (VERSION.H has
    # GOODTIMES already -- id's release without the manual's quiz)
    "sp1": ("WOLF3DW1.EXE", "nt_win", GUI + ["w32sp", "w32vis", "w32sign"], SPGAME, ["W32SP", "UPLOAD"]),
    "spsod": ("SPEARW.EXE", "nt_win", GUI + ["w32sp", "w32vis", "w32sign"], SPGAME, ["W32SP", "SPEAR"]),
}


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


def objdir(target):
    """rep and game share obj/ (the same flags); each other is built apart"""
    return os.path.join(OBJ, target) if TARGETS[target][4] else OBJ


def gen_signon():
    """obj/w32sign.c: the signon picture, 320x200, a byte a pixel, from id's
    SIGNON.OBJ (WOLFSRC/OBJ) -- linked into the DOS games as introscn.  Made at
    build time: id's picture, not ours to keep in git"""
    out = os.path.join(OBJ, "w32sign.c")
    src = os.path.join(WOLFSRC, "OBJ", "SIGNON.OBJ")
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(src):
        return out
    d = open(src, "rb").read()
    i, data = 0, bytearray()
    while i < len(d):
        t, n = d[i], d[i + 1] | (d[i + 2] << 8)
        body = d[i + 3:i + 3 + n - 1]
        if t in (0xA0, 0xA1):               # LEDATA: segment, offset, bytes
            off = body[1] | (body[2] << 8)
            chunk = body[3:]
            if len(data) < off + len(chunk):
                data.extend(bytes(off + len(chunk) - len(data)))
            data[off:off + len(chunk)] = chunk
        i += 3 + n
    assert len(data) == 64000, len(data)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    rows = [",".join(str(v) for v in data[k:k + 40]) + "," for k in range(0, 64000, 40)]
    open(out, "w").write("/* w32sign.c -- id's signon picture (SIGNON.OBJ), made by build.py */\n"
                         "unsigned char w32signon[64000] = {\n%s\n};\n" % "\n".join(rows))
    return out


def compile_one(name, src, target):
    od = objdir(target)
    os.makedirs(od, exist_ok=True)
    obj = os.path.join(od, name + ".obj")
    deps = [src, os.path.join(HERE, "src", "w32comp.h")] + glob.glob(os.path.join(WSRC, "*.H")) \
        + glob.glob(os.path.join(HERE, "src", "*.h"))
    if os.path.exists(obj) and os.path.getmtime(obj) >= max(os.path.getmtime(d) for d in deps):
        return True
    # -j: char is signed, as Borland's -- Open Watcom's is unsigned, and id's
    # demos turn by signed chars (a -100 read as 156: the demos went astray)
    cmd = [tool("wcc386"), "-q", "-bt=nt", "-3r", "-zp1", "-w1", "-wcd=120", "-wcd=138", "-od", "-d2", "-j",
           "-fi=" + os.path.join(HERE, "src", "w32comp.h"),
           "-i=" + os.path.join(HERE, "inc"), "-i=" + WSRC, "-i=" + os.path.join(HERE, "src"),
           "-dW32"] + ["-d" + d for d in TARGETS[target][4]] + ["-fo=" + obj, src]
    if name == "w32main":
        cmd.insert(1, "-s")      # its thread was not started by the runtime: no stack checks
    r = subprocess.run(cmd, capture_output=True, text=True, env=env(), cwd=od)
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


def link(target):
    exe, system, own, idown, _ = TARGETS[target]
    od = objdir(target)
    exe = os.path.join(HERE, exe)
    base = os.path.splitext(os.path.basename(exe))[0].lower()
    lnk = os.path.join(od, base + ".lnk")
    with open(lnk, "w") as f:
        f.write("system %s\nname %s\noption quiet, map=%s, stack=1m\ndebug all\n"
                "library wsock32, winmm\n"  # Winsock 1.1, waveOut: Windows 95 and later
                % (system, exe, os.path.join(od, base + ".map")))
        for n in GAME + idown + COMMON + own:
            f.write("file %s\n" % os.path.join(od, n + ".obj"))
    r = subprocess.run([tool("wlink"), "@" + lnk], capture_output=True, text=True, env=env(), cwd=od)
    out = (r.stdout + r.stderr).strip()
    if r.returncode:
        undef = sorted(set(l.split("undefined symbol")[-1].strip() for l in out.splitlines()
                           if "undefined symbol" in l))
        print(out[:3000] if not undef else "undefined (%d): %s" % (len(undef), " ".join(undef)))
        return False
    print("built", exe, os.path.getsize(exe), "bytes")
    return True


def main():
    args = sys.argv[1:]
    if args == ["clean"]:
        shutil.rmtree(OBJ, ignore_errors=True)
        return
    targets = args or ["rep", "game", "sp", "sp1", "spsod"]
    os.makedirs(OBJ, exist_ok=True)
    copy_sources()
    ok = True
    for t in targets:
        for n in GAME + TARGETS[t][3]:
            ok &= compile_one(n, os.path.join(WSRC, n + ".C"), t)
        for n in COMMON + TARGETS[t][2]:
            src = gen_signon() if n == "w32sign" else os.path.join(HERE, "src", n + ".c")
            ok &= compile_one(n, src, t)
    if not ok:
        sys.exit("compile failed")
    for t in targets:
        ok &= link(t)
    if not ok:
        sys.exit("link failed")


if __name__ == "__main__":
    main()
