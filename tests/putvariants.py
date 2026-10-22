"""putvariants.py -- the Windows shareware (WOLF3DW1) and Spear of Destiny
(SPEARW) onto .37, each in its own folder with its data: C:\\W3DWIN1 (the
*.WL1 files) and C:\\W3DSOD (*.SOD), from DOS Bridge's staging copy -- id's
data, which never goes into git.  StevenC & Claude (Anthropic), 2026-10-22."""
import glob
import os
import subprocess

AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
DATA = r"C:\dosbridgeDEV\files\local"
for exe, ext, folder in (("WOLF3DW1.EXE", "WL1", r"C:\W3DWIN1"), ("SPEARW.EXE", "SOD", r"C:\W3DSOD")):
    files = [os.path.join(r"C:\wolf3d\win32", exe)] + sorted(glob.glob(os.path.join(DATA, "*." + ext)))
    for f in files:
        r = subprocess.run(AGENT + ["put", f, folder + "\\" + os.path.basename(f)], capture_output=True, text=True)
        print(r.stdout.strip() or r.stderr.strip()[-200:])
