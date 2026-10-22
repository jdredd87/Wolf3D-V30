"""winlocal.py -- WOLF3DW's local play on .37, start to quit, a screenshot at
each stage into tmp/winlocal: the signon, the title loop and a demo, the
menu, a new game, the cell door, a save, the debug keys' floor end and its
tally, Floor 2, a load, widescreen on and off (F11), Quit.  Then the log (a
crash is printed there) and the files the game wrote."""
import os
import subprocess
import sys
import time

T = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(T, "winlocal")
os.makedirs(OUT, exist_ok=True)
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]


def agent(*a, timeout=60):
    r = subprocess.run(AGENT + list(a), capture_output=True, text=True, timeout=timeout)
    return (r.stdout + r.stderr).strip()


def keys(seq, shot):
    subprocess.run([sys.executable, os.path.join(T, "keys37.py"), seq, os.path.join(OUT, shot + ".png")],
                   capture_output=True, timeout=300)
    print("%s  %s" % (time.strftime("%H:%M:%S"), shot), flush=True)


agent("kill", "WOLF3DW")
for f in ("SAVEGAW0.WL6", "CONFIGW.WL6", "W32VIEW.CFG"):
    agent("rm", "C:\\W3DWIN\\" + f)
# the launcher: W3DCRASH writes a crash's place into WOLF3DW.LOG
bat = os.path.join(OUT, "W3DCR.BAT")
open(bat, "wb").write(b"@cd /d %~dp0\r\n@set W3DCRASH=1\r\n@WOLF3DW.EXE %*\r\n")
agent("put", bat, "C:\\W3DWIN\\W3DCR.BAT")
print(agent("start", r"C:\W3DWIN\W3DCR.BAT goobers", r"C:\W3DWIN"))
keys("wait:3000", "01-signon")
keys("space:120,wait:6000", "02-pg13-title")
keys("wait:22000", "03-scores")
keys("wait:12000", "04-demo")
keys("space:120,wait:2500", "05-menu")
keys("enter:120,wait:1500,enter:120,wait:1500,enter:120,wait:5000", "06-newgame")
keys("space:150,wait:1500,up:1200,wait:300", "07-door")
keys("f2:150,wait:2000,enter:120,wait:800,text=MATRIX:300,enter:120,wait:2500", "08-saved")
keys("bs+lshift+alt:300,wait:1500,space:150,wait:800,tab+e:300,wait:5000", "09-tally")
keys("space:150,wait:5000", "10-floor2")
keys("f3:150,wait:2000,enter:120,wait:4000", "11-loaded")
keys("f11:150,wait:2000", "12-wide")
keys("f11:150,wait:2000", "13-narrow")
keys("f10:150,wait:1500", "14-quitask")
keys("y:120,wait:3000", "15-quit")
print("running after quit:", agent("ps", "[bool](Get-Process WOLF3DW -ErrorAction SilentlyContinue)", "20")[-6:])
print("log:", agent("ps", "Get-Content C:\\W3DWIN\\WOLF3DW.LOG", "20")[:400] or "(empty)")
print(agent("ps", "Get-ChildItem C:\\W3DWIN\\SAVEGAW*,C:\\W3DWIN\\CONFIGW*,C:\\W3DWIN\\W32VIEW* | "
                  "Select-Object Name,Length | Format-Table | Out-String", "20"))
