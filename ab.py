"""A/B timing and picture checks of Wolf3D builds -- StevenC & Claude, 2026.

    python ab.py NEW.EXE OLD.EXE [...] [--rounds N]        time on the V30
    python ab.py NEW.EXE [...] --full [--box v30]          check on the 486

Each EXE is a file in stage/test/.

Timing (the default): the first EXE is checked with QUICK CRC against id's
demo-0 checksums, then every build runs N rounds, interleaved, with TIMEDEMO
QUICK PRELOAD on the V30, and the mean play ticks are printed.

--full: every EXE plays the whole attract loop with CRC -- 5,386 frames,
every 50th checksummed, the 3-D view and the whole screen -- and must give
id's own renderer's numbers (REF_VIEW / REF_SCREEN, made by refsrc.py's
tree).  CRC switches sound effects off, which is what makes a full run
deterministic, so the 486 (dx486, ~2 minutes a run) gives the same numbers
as the V30 (~25) and is the default box for it.

Two BEEP ALERTs precede a V30 run, so whoever is at the machine knows the
game is about to take the screen.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
REF_VIEW = "0707C966"               # id's renderer, all four demos, view
REF_SCREEN = "F2A10CEB"             # ... and the whole screen


def dosctl(*args, timeout=3600):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(args),
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def take(args, flag, default=None, value=True):
    if flag not in args:
        return default
    i = args.index(flag)
    if not value:
        del args[i]
        return True
    v = args[i + 1]
    del args[i:i + 2]
    return v


def main():
    args = sys.argv[1:]
    rounds = int(take(args, "--rounds", 2))
    full = take(args, "--full", False, value=False)
    deploy = not take(args, "--no-deploy", False, value=False)
    box = take(args, "--box", "dx486" if full else "v30")
    exes = [a.upper() for a in args]
    if not exes:
        sys.exit(__doc__)
    if deploy:
        for e in exes:
            out = dosctl("deploy", os.path.join(HERE, "stage", "test", e), "C:\\WOLF3D", "--box", box)
            if "deployed" not in out:
                sys.exit("deploy of %s failed:\n%s" % (e, out))
    cmds = ["CD C:\\WOLF3D"]
    if box == "v30":
        cmds = ["C:\\TOOLS\\BEEP.EXE ALERT", "C:\\TOOLS\\BEEP.EXE ALERT"] + cmds

    if full:
        ok = True
        for e in exes:
            out = dosctl("exec", "--box", box, "--timeout", "3500", *cmds,
                         "%s timedemo crc preload" % e, timeout=3700)
            view = re.search(r"view checksum, all \d+: (\w+)", out)
            scr = re.search(r"screen checksum, all \d+: (\w+)", out)
            tot = re.search(r"total .*", out)
            good = bool(view and scr and view.group(1) == REF_VIEW and scr.group(1) == REF_SCREEN)
            ok &= good
            print("%-12s view %s  screen %s  %s" % (e, view.group(1) if view else "?",
                  scr.group(1) if scr else "?", "IDENTICAL to id" if good else "*** DIFFERENT ***"))
            if tot:
                print("             " + tot.group(0))
        sys.exit(0 if ok else 1)

    cmds.append("%s timedemo quick crc preload" % exes[0])
    for _ in range(rounds):
        for e in exes:
            cmds.append("%s timedemo quick preload" % e)
    out = dosctl("exec", "--box", box, "--timeout", "3500", *cmds, timeout=3700)
    lines = [l for l in out.splitlines() if re.search(r"demo \d|checksum", l)]
    print("\n".join(lines))
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
