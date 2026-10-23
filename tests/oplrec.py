"""oplrec.py -- the title music, NAZI_NOR, recorded twice: off the V30 (its
PicoMEM's AdLib, through the capture card: WOLF3DV NOWAIT) and out of
WOLF3DW on .37 (its OPL2 in C, W3DRAW: the mix to a file).  Both into
stage/tests/opl/ for oplcmp.py.  The V30 is power-cycled afterwards (the
game does not end by itself).  StevenC & Claude (Anthropic), 2026-10-23."""
import os
import subprocess
import sys
import time

BRIDGE = r"C:\dosbridgeDEV"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "opl")
os.makedirs(OUT, exist_ok=True)
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
SECS = 45


def dosctl(*a, **k):
    return subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                          text=True, encoding="utf-8", errors="replace", env=ENV, **k)


def agent(*a, timeout=120):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


if "--nodos" not in sys.argv:
    # the V30: the recording first, then the game into it
    rec = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "capture", "rec", str(SECS + 15),
                            os.path.join(OUT, "v30.mp4"), "--audio"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, env=ENV)
    time.sleep(3)
    game = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", "v30",
                             r"CD C:\WOLF3D", "WOLF3DV NOWAIT", "--timeout", str(SECS + 60)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=ENV)
    rec.wait(SECS + 120)
    print("V30 recorded:", os.path.exists(os.path.join(OUT, "v30.mp4")))
    game.kill()
    print(dosctl("power", "cycle", "--box", "v30").stdout.strip().splitlines()[-1:])

if "--nowin" not in sys.argv:
    bat = os.path.join(OUT, "W3DRAW.BAT")
    open(bat, "wb").write(b"@cd /d %~dp0\r\n@set W3DRAW=C:\\W3DWIN\\TITLE.RAW\r\n@WOLF3DW.EXE NOWAIT\r\n")
    agent("put", bat, r"C:\W3DWIN\W3DRAW.BAT")
    agent("rm", r"C:\W3DWIN\TITLE.RAW")
    print(agent("start", r"C:\W3DWIN\W3DRAW.BAT", r"C:\W3DWIN"))
    time.sleep(SECS + 5)
    agent("kill", "WOLF3DW")
    time.sleep(2)
    print(agent("get", r"C:\W3DWIN\TITLE.RAW", os.path.join(OUT, "w37.raw"), timeout=300))
    agent("rm", r"C:\W3DWIN\TITLE.RAW")
    agent("rm", r"C:\W3DWIN\W3DRAW.BAT")
