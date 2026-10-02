"""Every map against id's renderer: the generated demos on two builds.
StevenC & Claude, 2026.

    python gendemo.py 500 --ship          the demos, onto the 486
    python allmaps.py OURS.EXE REF.EXE [first last] [--box dx486]

Both EXEs must already be in C:\\WOLF3D on the box -- ours, and id's
renderer with TIMEDEMO's instruments (refsrc.py's tree, which takes GEN
from HEAD too).  Each demo Gn.DEM runs on both with `TIMEDEMO CRC GEN n`
(sound effects off, god mode on), several demos to a job, and the view
and whole-screen checksums -- every 50th frame folded into one each --
must agree.  A mismatch is reported with its map and the first of the
first eight checkpoints that differs.  Results go to stage/allmaps.txt.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = r"C:\dosbridgeDEV"
ENV = dict(os.environ, PYTHONIOENCODING="utf-8")
PER_JOB = 6


def dosctl(*args, timeout=1500):
    r = subprocess.run([sys.executable, os.path.join(BRIDGE, "dosctl.py")] + list(args),
                       capture_output=True, text=True, encoding="utf-8", errors="replace",
                       env=ENV, timeout=timeout)
    return r.stdout + r.stderr


def runs(out):
    """Split a job's output into runs: (frames, [checkpoints], view, screen)."""
    res = []
    for block in re.split(r"(?m)^view \d+ x \d+", out)[1:]:
        fr = re.search(r"demo 0  floor\s+(\d+)\s+(\d+) frames", block)
        cps = re.findall(r"view checksum \d+: (\w+)", block)
        v = re.search(r"view checksum, all \d+: (\w+)", block)
        s = re.search(r"screen checksum, all \d+: (\w+)", block)
        res.append((int(fr.group(2)) if fr else None, cps,
                    v.group(1) if v else None, s.group(1) if s else None))
    return res


def main():
    args = sys.argv[1:]
    box = "dx486"
    if "--box" in args:
        i = args.index("--box")
        box = args[i + 1]
        del args[i:i + 2]
    ours, ref = args[0].upper(), args[1].upper()
    first = int(args[2]) if len(args) > 2 else 0
    last = int(args[3]) if len(args) > 3 else 119
    names = {}
    idx = os.path.join(HERE, "stage", "gen", "INDEX.TXT")
    for line in open(idx):
        m = re.match(r"G(\d+)\.DEM (.*)", line.strip())
        if m:
            names[int(m.group(1))] = m.group(2)
    report = open(os.path.join(HERE, "stage", "allmaps.txt"), "a")
    bad = 0
    good = 0
    for start in range(first, last + 1, PER_JOB):
        demos = list(range(start, min(start + PER_JOB, last + 1)))
        cmds = ["CD C:\\WOLF3D"]
        for n in demos:
            cmds += ["%s timedemo crc gen %d" % (ours[:-4], n), "%s timedemo crc gen %d" % (ref[:-4], n)]
        out = dosctl("exec", "--box", box, "--timeout", "1400", *cmds)
        r = runs(out)
        if len(r) != 2 * len(demos):
            msg = "demos %d-%d: %d runs reported of %d -- the box may have hung:\n%s" % (
                demos[0], demos[-1], len(r), 2 * len(demos), out[-600:])
            print(msg)
            report.write(msg + "\n")
            sys.exit(2)
        for k, n in enumerate(demos):
            a, b = r[2 * k], r[2 * k + 1]
            same = a[2] == b[2] and a[3] == b[3] and a[2] is not None
            line = "G%-3d %-40s %4s frames  ours %s %s  id %s %s  %s" % (
                n, names.get(n, ""), a[0], a[2], a[3], b[2], b[3], "same" if same else "*** DIFFERENT ***")
            if not same:
                bad += 1
                for i, (x, y) in enumerate(zip(a[1], b[1])):
                    if x != y:
                        line += "  (checkpoint %d first, frame %d)" % (i + 1, 50 * (i + 1))
                        break
            else:
                good += 1
            print(line, flush=True)
            report.write(line + "\n")
            report.flush()
    print("%d same, %d different" % (good, bad))
    report.write("%d same, %d different\n" % (good, bad))
    sys.exit(1 if bad else 0)


main()
