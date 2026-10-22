"""winattract.py [MINUTES] -- WOLF3DW's attract loop left to run on .37: the
title, the credits, the high scores and id's four demos, round and round --
the demos play the game through w32vis.c's decisions (the actors seen, the
items taken) with nobody at the keys.  A screenshot every 5 minutes; at the
end, still running, and nothing in the log (W3DCRASH puts a crash there).
StevenC & Claude (Anthropic), 2026-10-22."""
import os
import subprocess
import sys
import time

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "winattract")
os.makedirs(OUT, exist_ok=True)
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
MINUTES = int(sys.argv[1]) if len(sys.argv) > 1 else 30


def agent(*a):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=120)
    return (r.stdout + r.stderr).strip()


bat = os.path.join(OUT, "W3DCR.BAT")
open(bat, "wb").write(b"@cd /d %~dp0\r\n@set W3DCRASH=1\r\n@WOLF3DW.EXE %*\r\n")
agent("put", bat, "C:\\W3DWIN\\W3DCR.BAT")
agent("kill", "WOLF3DW")
print(agent("start", r"C:\W3DWIN\W3DCR.BAT", r"C:\W3DWIN"))
time.sleep(4)
subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "keys37.py"),
                "space:120,wait:500"], capture_output=True)      # past the signon's "Press a key"
t0 = time.time()
k = 0
while time.time() - t0 < MINUTES*60:
    time.sleep(30)
    if int((time.time() - t0) // 300) > k:
        k = int((time.time() - t0) // 300)
        agent("shot", os.path.join(OUT, "a%02d.png" % k))
        print("%s  %d min" % (time.strftime("%H:%M:%S"), k*5), flush=True)
alive = agent("ps", "[bool](Get-Process WOLF3DW -ErrorAction SilentlyContinue)", "20")
log = agent("ps", "Get-Content C:\\W3DWIN\\WOLF3DW.LOG", "20")
print("running after %d minutes: %s" % (MINUTES, alive[-5:]))
print("log: " + (log[:500] if log else "(empty)"))
agent("kill", "WOLF3DW")
print("RESULT attract: %s" % ("PASS" if alive.endswith("True") and "CRASH" not in log else "FAIL"))
