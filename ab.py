"""Interleaved A/B timing of Wolf3D builds on the V30 -- StevenC & Claude, 2026.

    python ab.py NEW.EXE OLD.EXE [NEW2.EXE ...] [--rounds N] [--full] [--no-deploy]

Each EXE is a file in stage/test/.  The first is checked with CRC against
stage/crc-ref.txt (QUICK) and every build is then run N rounds, interleaved,
with TIMEDEMO QUICK PRELOAD.  Prints the play ticks of each run and the mean
per build.  --full instead runs the whole attract loop with CRC once per
build and prints the run-wide checksum.  Two BEEP ALERTs first, so whoever
is at the machine knows the game is about to take the screen.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")


def dosctl(*args, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(args),
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def main():
    args = sys.argv[1:]
    rounds, full, deploy = 2, False, True
    if "--rounds" in args:
        i = args.index("--rounds")
        rounds = int(args[i + 1])
        del args[i:i + 2]
    if "--full" in args:
        full = True
        args.remove("--full")
    if "--no-deploy" in args:
        deploy = False
        args.remove("--no-deploy")
    exes = [a.upper() for a in args]
    if not exes:
        sys.exit(__doc__)
    if deploy:
        for e in exes:
            out = dosctl("deploy", os.path.join(HERE, "stage", "test", e), "C:\\WOLF3D", "--box", "v30")
            if "deployed" not in out:
                sys.exit("deploy of %s failed:\n%s" % (e, out))
    cmds = ["C:\\TOOLS\\BEEP.EXE ALERT", "C:\\TOOLS\\BEEP.EXE ALERT", "CD C:\\WOLF3D"]
    if full:
        for e in exes:
            cmds.append("%s timedemo crc preload" % e)
    else:
        cmds.append("%s timedemo quick crc preload" % exes[0])
        for _ in range(rounds):
            for e in exes:
                cmds.append("%s timedemo quick preload" % e)
    out = dosctl("exec", "--box", "v30", "--timeout", "3500", *cmds, timeout=3700)
    lines = [l for l in out.splitlines()
             if re.search(r"demo \d|total|checksum|fizzle|music log", l)]
    print("\n".join(lines))
    if full:
        return
    ref = [l.split(":")[1].strip() for l in open(os.path.join(HERE, "stage", "crc-ref.txt"))
           if re.match(r"view checksum \d", l)]
    got = [l.split(":")[1].strip() for l in lines if re.match(r"view checksum \d", l)]
    print("CRC:", "PIXEL-IDENTICAL" if got == ref and ref else "*** MISMATCH *** %s" % got)
    plays = [int(m.group(1)) for m in re.finditer(r"play\s+(\d+) ticks", "\n".join(lines))]
    plays = plays[1:]                       # the CRC run carries the checksums' cost
    for k, e in enumerate(exes):
        mine = plays[k::len(exes)]
        if mine:
            print("%-12s %s  mean %.1f" % (e, mine, sum(mine) / len(mine)))


if __name__ == "__main__":
    main()
