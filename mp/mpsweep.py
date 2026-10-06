"""Play every multiplayer demo from more than one player's eyes, and compare
-- StevenC & Claude, 2026.

    python mp/mpsweep.py [--box dx486] [--demos 0-19] [--locals 1,2] [--deploy]
                         [--against FILE]

Multiplayer runs on lockstep: every machine plays the same controls, so
every machine must play the same game -- whoever's eyes it is drawing, and
whatever CPU it has.  WOLF3DM's report ends with a checksum of the whole
game state (every actor, door, item and player) every 50 steps; this runs
TIMEDEMO MGEN n LOCAL k for each demo and camera, all in one job on the box
(MPSWEEP.BAT), and says which demos disagree between cameras -- and, with
--against, with another run's results (another box's).  --deploy sends
WOLFSRC\\WOLF3DV.EXE as WOLF3DM.EXE first.  Results are saved as
stage/mpsweep-BOX.txt.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
STAGE = os.path.join(ROOT, "stage")
CTL = [sys.executable, os.path.join(os.environ.get("DOSBRIDGE", r"C:\dosbridgeDEV"), "dosctl.py")]


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


def ctl(*a, timeout=900):
    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    r = subprocess.run(CTL + list(a) + ["--timeout", str(timeout)], capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=env)
    return r.stdout + r.stderr


def parse(text):
    """{(demo, camera): {'sum': ..., 'checks': [...], 'players': [...]}}"""
    res, cur = {}, None
    for line in text.splitlines():
        m = re.match(r"\s*M(\d+) L(\d)\s*$", line)
        if m:
            cur = (int(m.group(1)), int(m.group(2)))
            res[cur] = {"sum": None, "checks": [], "players": []}
            continue
        if not cur:
            continue
        m = re.search(r"state sum ([0-9A-F]{8})", line)
        if m:
            res[cur]["sum"] = m.group(1)
        m = re.search(r"mp step\s+(\d+): ([0-9A-F]{8})", line)
        if m:
            res[cur]["checks"].append((int(m.group(1)), m.group(2)))
        m = re.search(r"(P\d) at (\d+,\d+)\s+health (\d+)\s+ammo (\d+)\s+keys (\d+)\s+score (\d+)", line)
        if m:
            res[cur]["players"].append(m.groups())
    return res


def first_diff(a, b):
    for (s1, c1), (s2, c2) in zip(a["checks"], b["checks"]):
        if c1 != c2:
            return s1
    return None


def main():
    box = arg("--box", "dx486")
    lo, hi = (int(x) for x in arg("--demos", "0-19").split("-"))
    cams = [int(x) for x in arg("--locals", "1,2").split(",")]
    if "--deploy" in sys.argv:
        import shutil
        shutil.copy(os.path.join(ROOT, "WOLFSRC", "WOLF3DV.EXE"), os.path.join(STAGE, "WOLF3DM.EXE"))
        print(ctl("deploy", os.path.join(STAGE, "WOLF3DM.EXE"), r"C:\WOLF3D", "--box", box).strip().splitlines()[-1])
    lines = ["@ECHO OFF", "REM WOLF3DM: every MGEN demo, every camera -- mp\\mpsweep.py (StevenC & Claude)",
             "C:", "CD \\WOLF3D", "IF EXIST MPSWEEP.TXT DEL MPSWEEP.TXT"]
    for n in range(lo, hi + 1):
        for k in cams:
            lines += ["WOLF3DM TIMEDEMO MGEN %d LOCAL %d > MPS.TXT" % (n, k),
                      "ECHO M%d L%d >> MPSWEEP.TXT" % (n, k),
                      'FIND "mp" MPS.TXT >> MPSWEEP.TXT',
                      'FIND " at " MPS.TXT >> MPSWEEP.TXT']
    bat = os.path.join(STAGE, "MPSWEEP.BAT")
    open(bat, "w", newline="\r\n").write("\n".join(lines) + "\n")
    print(ctl("deploy", bat, r"C:\WOLF3D", "--box", box).strip().splitlines()[-1])
    runs = (hi - lo + 1) * len(cams)
    out = ctl("exec", "C:", r"CD \WOLF3D", "CALL MPSWEEP.BAT", "C:", r"CD \WOLF3D",
              "TYPE MPSWEEP.TXT", "--box", box, "--quiet", timeout=120 + runs * (150 if box == "v30" else 30))
    path = os.path.join(STAGE, "mpsweep-%s.txt" % box)
    open(path, "w").write(out)
    res = parse(out)
    other = parse(open(arg("--against", ""), errors="replace").read()) if "--against" in sys.argv else {}
    bad = 0
    for n in range(lo, hi + 1):
        r = [res.get((n, k)) for k in cams]
        if not all(x and x["sum"] for x in r):
            print("M%-2d  MISSING a result" % n)
            bad += 1
            continue
        sums = {x["sum"] for x in r}
        note = ""
        if len(sums) > 1:
            note = "  cameras differ from step %s" % first_diff(r[0], r[1])
            bad += 1
        o = other.get((n, cams[0]))
        if o and o["sum"] != r[0]["sum"]:
            note += "  differs from --against from step %s" % first_diff(r[0], o)
            bad += 1
        print("M%-2d %s %s%s" % (n, "SAME" if not note else "DIFF", r[0]["sum"], note))
    print("%d of %d demos agree; results in %s" % (hi - lo + 1 - bad, hi - lo + 1, path))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
