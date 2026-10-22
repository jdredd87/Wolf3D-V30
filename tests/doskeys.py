"""doskeys.py [BOX...] -- the DOS game played by keys, on the machines whose
keyboard controller takes D2h (the 486 and P3; K9INJ.COM, k9inj.asm): in a
scratch folder (C:\\W3TEST: the game's data copied, never anyone's config or
saves), two runs of WOLF3DV --

  1. the signon, the title, the menu, a new game, to the cell door, two shots,
     F2: a save named K9TEST in slot 0, F10 and Y: Quit
  2. a new game, then F3: slot 0 loaded; F2: a save named LOADED in slot 1; Quit

-- id's god mode on in each (GOOBERS; Backspace+LShift+Alt, Tab+G) once the
floor is in, 14 s after the new game for P3's SD card: the guards RUN1's shots
woke are in its save, and they open the cell door after the load -- and then
the files: both saves there, under their names, the second
holding the first's floor, health, ammo, score and lives (it was loaded
from it), the config written by Quit.  StevenC & Claude (Anthropic), 2026-10-22."""
import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = r"C:\dosbridgeDEV"
OUT = os.path.join(os.path.dirname(HERE), "stage", "tests", "doskeys")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
GAME = os.environ.get("W3DGAME", "WOLF3DV")

RUN1 = ("wait:4500,space:150,wait:9000,space:150,wait:2500,"
        "enter:150,wait:1500,enter:150,wait:1500,enter:150,wait:14000,"  # (P3's floor off its SD card)
        "bs+lshift+alt:300,wait:1500,space:150,wait:1000,tab+g:300,wait:1500,space:150,wait:1000,"   # god mode (GOOBERS)
        "up:1200,wait:800,"                          # to the cell door, left shut: no guard sees
        "ctrl:150,wait:700,ctrl:150,wait:700,"       # him after a load; two shots: 6 ammo -- what
                                                     # the load must bring back
        "f2:150,wait:2500,enter:150,wait:1000,text=K9TEST:400,enter:150,wait:3000,"
        "f10:150,wait:2000,y:150,wait:4000,"
        "esc:150,wait:1500,f10:150,wait:2000,y:150,wait:3000")        # (a second try at the end)
RUN2 = ("wait:4500,space:150,wait:9000,space:150,wait:2500,"
        "enter:150,wait:1500,enter:150,wait:1500,enter:150,wait:14000,"  # a new game (8 ammo), then
        "bs+lshift+alt:300,wait:1500,space:150,wait:1000,tab+g:300,wait:1500,space:150,wait:1000,"   # god mode (GOOBERS)
        "wait:4000,"
        "f3:150,wait:4000,enter:150,wait:25000,"                        # F3: slot 0 (6).  Long waits:
                                                                        # P3's floors come off its SD
                                                                        # card, and the 486's disk is
                                                                        # slow while AdLib music plays
                                                                        # (docs/hardware.md) -- safe in
                                                                        # the shut cell meanwhile
        "f2:150,wait:2500,down:150,wait:600,enter:150,wait:1000,text=LOADED:400,enter:150,wait:3000,"
        "f10:150,wait:2000,y:150,wait:4000,"
        "esc:150,wait:1500,f10:150,wait:2000,y:150,wait:3000")


def dosctl(*a, timeout=900):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def k9(name, seq):
    p = os.path.join(OUT, name)
    subprocess.run([sys.executable, os.path.join(HERE, "k9.py"), p, seq], check=True)
    return p


def gamestate(path):
    d = open(path, "rb").read()
    name = d[:32].split(b"\0")[0].decode("latin-1")
    # gametype's first fields, 16-bit ints (DOS): difficulty, mapon, oldscore (long),
    # score (long), nextextra (long), lives, health, ammo
    diff, mapon, olds, score, nextx, lives, health, ammo = struct.unpack("<hhlllhhh", d[32:54])
    return name, dict(map=mapon, score=score, lives=lives, health=health, ammo=ammo)


for box in sys.argv[1:] or ["dx486", "p3"]:
    print("== %s" % box, flush=True)
    dosctl("exec", "--box", box, "--quiet", r"MD C:\W3TEST", r"COPY C:\WOLF3D\*.WL6 C:\W3TEST",
           r"COPY C:\WOLF3D\%s.EXE C:\W3TEST" % GAME,
           r"DEL C:\W3TEST\CONFIG.WL6", r"DEL C:\W3TEST\SAVEGAM?.WL6")
    for f in (os.path.join(HERE, "K9INJ.COM"), k9("RUN1.K9", RUN1), k9("RUN2.K9", RUN2)):
        dosctl("deploy", f, r"C:\W3TEST", "--box", box)
    for run in ("RUN1", "RUN2"):
        out = dosctl("exec", "--box", box, "--quiet", "--timeout", "240", r"CD C:\W3TEST",
                     r"K9INJ %s.K9" % run, GAME + " GOOBERS", r"K9INJ /S", r"K9INJ /U", timeout=400)
        open(os.path.join(OUT, "%s-%s.txt" % (box, run)), "w").write(out)
        st = [l for l in out.splitlines() if "K9INJ:" in l]
        print("  %s: %s" % (run, " / ".join(st) or out.strip()[-300:]), flush=True)
    for f in ("SAVEGAM0.WL6", "SAVEGAM1.WL6", "CONFIG.WL6"):
        if os.path.exists(os.path.join(OUT, "%s-%s" % (box, f))):
            os.remove(os.path.join(OUT, "%s-%s" % (box, f)))     # (never a last run's)
        dosctl("pull", r"C:\W3TEST\%s" % f, "--out", os.path.join(OUT, "%s-%s" % (box, f)), "--box", box)
    ok = True
    try:
        n0, g0 = gamestate(os.path.join(OUT, box + "-SAVEGAM0.WL6"))
        n1, g1 = gamestate(os.path.join(OUT, box + "-SAVEGAM1.WL6"))
        print("  slot 0: %r %s" % (n0, g0))
        print("  slot 1: %r %s" % (n1, g1))
        # (the game types names in lower case); the load proved by the ammo:
        # two shots before the save, so a fresh game's 8 would not do
        # health is not compared: between the load and the second save a
        # guard may shoot (the 486's did, 100 -> 69)
        same = all(g0[k] == g1[k] for k in ("map", "score", "lives", "ammo"))
        ok = n0.upper() == "K9TEST" and n1.upper() == "LOADED" and same and g0["ammo"] < 8
    except (OSError, struct.error) as e:
        print("  saves: %s" % e)
        ok = False
    cfg = os.path.join(OUT, box + "-CONFIG.WL6")
    print("  config written by Quit: %s" % (os.path.exists(cfg) and os.path.getsize(cfg) > 0))
    ok &= os.path.exists(cfg)
    # one file at a time: DEL *.* asks "Are you sure (Y/N)?" and the box waits for
    # an answer nobody gives (it took the 486 and P3 down, 2026-10-22)
    dosctl("exec", "--box", box, "--quiet", r"FOR %%F IN (C:\W3TEST\*.*) DO DEL %%F", r"RD C:\W3TEST")
    print("RESULT doskeys %s: %s" % (box, "PASS" if ok else "FAIL"), flush=True)
