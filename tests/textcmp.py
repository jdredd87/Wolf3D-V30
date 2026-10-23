"""textcmp.py OLD.EXE NEW.EXE -- the text over the view, two builds: the V30
replays the same recording (stage/tests/mprec/REC.MPR) with each, LOWEST
VIEW 10 as it plays, and the capture card photographs it at the same
moments -- the recording's chat lines and notices come at the same steps
each time -- into stage/tests/textcmp/.  StevenC & Claude (Anthropic),
2026-10-23."""
import os
import subprocess
import sys
import time

WOLF, BRIDGE = r"C:\wolf3d", r"C:\dosbridgeDEV"
OUT = os.path.join(WOLF, "stage", "tests", "textcmp")
os.makedirs(OUT, exist_ok=True)
REC = os.path.join(WOLF, "stage", "tests", "mprec", "REC.MPR")
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
AT = (20, 30, 40, 50, 60, 70, 80, 90)


def dosctl(*a, timeout=900):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(a), capture_output=True,
                       text=True, encoding="utf-8", errors="replace", env=ENV, timeout=timeout)
    return (r.stdout + r.stderr).strip()


print(dosctl("deploy", REC, r"C:\WOLF3D", "--box", "v30").splitlines()[-1])
for tag, exe in (("old", sys.argv[1]), ("new", sys.argv[2])):
    staged = os.path.join(OUT, "W3DTC.EXE")
    open(staged, "wb").write(open(exe, "rb").read())
    print(tag, dosctl("deploy", staged, r"C:\WOLF3D", "--box", "v30").splitlines()[-1])
    job = subprocess.Popen([sys.executable, os.path.join(BRIDGE, "dosctl.py"), "exec", "--box", "v30",
                            r"CD C:\WOLF3D", "W3DTC REPLAY REC.MPR LOWEST VIEW 10", "--timeout", "600"],
                           stdout=open(os.path.join(OUT, tag + ".txt"), "w"), stderr=subprocess.STDOUT, env=ENV)
    t0 = time.time()
    for t in AT:
        time.sleep(max(0, t0 + t - time.time()))
        dosctl("capture", "shot", os.path.join(OUT, "%s-%03d.png" % (tag, t)))
    job.wait(700)
    print(tag, open(os.path.join(OUT, tag + ".txt"), errors="replace").read().strip().splitlines()[-3:])
print(dosctl("exec", "--box", "v30", "--quiet", r"DEL C:\WOLF3D\W3DTC.EXE", r"DEL C:\WOLF3D\REC.MPR"))
