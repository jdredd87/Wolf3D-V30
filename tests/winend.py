"""winend.py [CASE...] -- each episode's end on Windows, on .37: a TEST build
(win32/build.py spend, sp1end, spsodend: WL_PLAY.C's ENDTEST wins the floor
after 70 frames) started on the episode's last floor with TEDLEVEL, then
id's own end -- the victory screen, the end text page by page, the high
scores (Spear: its end screens) -- a picture of each, to the program's exit.
No test playing the game could reach these; the logic that leads there is
the demos' and the gate's, frame for frame the same as DOS.

    e1 .. e6     WOLF3DW's six episodes (floors 8, 18 ... 58)
    wl1          WOLF3DW1, the shareware's episode 1
    sod          SPEARW, the Angel of Death's floor (20)

Pictures in stage/tests/winend/.  StevenC & Claude (Anthropic), 2026-10-23."""
import os
import subprocess
import sys
import time

T = os.path.dirname(os.path.abspath(__file__))
WIN = os.path.join(os.path.dirname(T), "win32")
OUT = os.path.join(os.path.dirname(T), "stage", "tests", "winend")
os.makedirs(OUT, exist_ok=True)
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
CASES = {"e%d" % e: ("W3DWEND", r"C:\W3DWIN", 10 * (e - 1) + 8) for e in range(1, 7)}
CASES["wl1"] = ("W3D1END", r"C:\W3DWIN1", 8)
CASES["sod"] = ("SPEAREND", r"C:\W3DSOD", 20)


def agent(*a, timeout=60):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


def running(proc):
    return agent("ps", "[bool](Get-Process %s -ErrorAction SilentlyContinue)" % proc, "20").endswith("True")


def keys(proc, seq, shot):
    subprocess.run([sys.executable, os.path.join(T, "keys37.py"), seq, os.path.join(OUT, shot + ".png")],
                   capture_output=True, timeout=300, env=dict(os.environ, W3DPROC=proc))


put = set()
for case in sys.argv[1:] or list(CASES):
    exe, folder, level = CASES[case]
    if exe not in put:
        print(agent("put", os.path.join(WIN, exe + ".EXE"), folder + "\\" + exe + ".EXE"))
        put.add(exe)
    agent("kill", exe)
    print("%s  %s: %s TEDLEVEL %d" % (time.strftime("%H:%M:%S"), case, exe, level), flush=True)
    print(agent("start", r"%s\%s.EXE TEDLEVEL %d" % (folder, exe, level), folder))
    keys(exe, "wait:3500", "%s-01-signon" % case)          # (id's "Press a key")
    keys(exe, "space:150,wait:6000", "%s-02-victory" % case)
    # then a key at a time -- the victory's Ack, each page of the end text
    # (Down), Escape out of it, the high scores -- a picture after each,
    # until the program has gone
    step = 3
    for k in ["space"] + ["down"] * 9 + ["esc", "space", "space", "space", "esc"]:
        if not running(exe):
            break
        keys(exe, "%s:150,wait:2500" % k, "%s-%02d-%s" % (case, step, k))
        step += 1
    print("  %d pictures; still running: %s" % (step - 1, running(exe)), flush=True)
    log = agent("ps", "Get-Content %s\\WOLF3DW.LOG -ErrorAction SilentlyContinue | Select-Object -Last 5" % folder, "20")
    print("  log:", log[:300] or "(empty)")
    agent("kill", exe)
