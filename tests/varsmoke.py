"""varsmoke.py -- the Windows shareware (WOLF3DW1) and Spear (SPEARW) on .37:
started, a picture of the signon, the title and the attract loop's demo,
still running after, nothing in their logs.  StevenC & Claude, 2026-10-22."""
import os
import subprocess
import sys
import time

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "varsmoke")
os.makedirs(OUT, exist_ok=True)
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
KEYS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "keys37.py")


def agent(*a):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=120)
    return (r.stdout + r.stderr).strip()


def keys(exe, seq, shot):
    subprocess.run([sys.executable, KEYS, seq, os.path.join(OUT, shot)], capture_output=True,
                   env=dict(os.environ, W3DPROC=exe), timeout=300)


for exe, folder in (("WOLF3DW1", r"C:\W3DWIN1"), ("SPEARW", r"C:\W3DSOD")):
    print(exe, agent("start", folder + "\\" + exe + ".EXE", folder))
    keys(exe, "wait:3500", exe + "-1.png")
    keys(exe, "space:120,wait:9000", exe + "-2.png")
    keys(exe, "wait:30000", exe + "-3.png")
    print("  running:", agent("ps", "[bool](Get-Process %s -ErrorAction SilentlyContinue)" % exe, "20")[-5:])
    print("  log:", agent("ps", "Get-Content %s\\%s.LOG" % (folder, exe), "20")[:300] or "(empty)")
    agent("kill", exe)
