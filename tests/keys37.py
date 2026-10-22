"""keys37.py SEQ [SHOT] -- keys held in the game's window on .37, in turn:
SEQ is NAME:ms,NAME:ms,... (up down left right space ctrl alt esc enter y n
tab 1-4, or wait:ms), then a screenshot to SHOT."""
import os
import subprocess
import sys

KEYS = {"up": (0x26, 0x48), "down": (0x28, 0x50), "left": (0x25, 0x4B), "right": (0x27, 0x4D),
        "space": (0x20, 0x39), "ctrl": (0x11, 0x1D), "alt": (0x12, 0x38), "esc": (0x1B, 0x01),
        "enter": (0x0D, 0x1C), "y": (0x59, 0x15), "n": (0x4E, 0x31), "tab": (0x09, 0x0F),
        "1": (0x31, 0x02), "2": (0x32, 0x03), "3": (0x33, 0x04), "4": (0x34, 0x05),
        "f2": (0x71, 0x3C), "f3": (0x72, 0x3D), "a": (0x41, 0x1E), "b": (0x42, 0x30),
        "c": (0x43, 0x2E), "bs": (0x08, 0x0E), "lshift": (0x10, 0x2A), "e": (0x45, 0x12), "g": (0x47, 0x22), "h": (0x48, 0x23), "w": (0x57, 0x11), "f1": (0x70, 0x3B), "f10": (0x79, 0x44), "f11": (0x7A, 0x57), "m": (0x4D, 0x32), "l": (0x4C, 0x26), "i": (0x49, 0x17)}
AGENT = [r"powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
         r"C:\delphi projects\UVSCAN Projects\UVScanner-CLAUDE\tools\agent.ps1"]
PROC = os.environ.get("W3DPROC", "WOLF3DW")     # (W3DPROC: WOLF3DW1, SPEARW ...)
lines = [r"""Add-Type -Name K -Namespace W -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(System.IntPtr h, uint m, System.IntPtr w, System.IntPtr l);'
$h = (Get-Process %s | Select-Object -First 1).MainWindowHandle
function D($vk,$sc) { [W.K]::PostMessage($h, 0x100, [System.IntPtr]$vk, [System.IntPtr](($sc -shl 16) -bor 1)) | Out-Null }
function U($vk,$sc) { [W.K]::PostMessage($h, 0x101, [System.IntPtr]$vk, [System.IntPtr](($sc -shl 16) -bor 0xC0000001)) | Out-Null }
function C($ch) { [W.K]::PostMessage($h, 0x102, [System.IntPtr]$ch, [System.IntPtr]1) | Out-Null }""" % PROC]
total = 0
for item in sys.argv[1].split(","):
    name, ms = item.split(":")
    ms = int(ms)
    total += ms
    if name == "wait":
        lines.append("Start-Sleep -Milliseconds %d" % ms)
    elif name.startswith("text="):
        for ch in name[5:]:
            lines.append("C %d; Start-Sleep -Milliseconds 60" % ord(ch))
        lines.append("Start-Sleep -Milliseconds %d" % ms)
    else:
        names = name.split("+")
        for n in names:
            vk, sc = KEYS[n]
            lines.append("D %d %d" % (vk, sc))
        lines.append("Start-Sleep -Milliseconds %d" % ms)
        for n in reversed(names):
            vk, sc = KEYS[n]
            lines.append("U %d %d" % (vk, sc))
        lines.append("Start-Sleep -Milliseconds 80")
lines.append("'done'")
r = subprocess.run(AGENT + ["ps", "\n".join(lines), str(total // 1000 + 30)], capture_output=True, text=True)
print((r.stdout + r.stderr).strip()[-200:])
if len(sys.argv) > 2:
    subprocess.run(AGENT + ["shot", sys.argv[2]], capture_output=True)
    try:
        from PIL import Image
        Image.open(sys.argv[2]).crop((205, 170, 1405, 1030)).resize((600, 430)).save(sys.argv[2][:-4] + "s.png")
    except Exception as e:
        print("crop:", e)
