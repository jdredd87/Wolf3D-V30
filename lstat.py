"""Show TASM listing lines around a code offset -- StevenC & Claude, 2026.

    python lstat.py LISTING.LST PROC OFFSET [OFFSET...] [--span N]

OFFSET is relative to PROC (as profmap.py prints it, e.g. ScaleShape+182),
in hex.  Prints the listing lines whose address falls in [OFFSET, OFFSET+N)
(default N = 16, one profile bucket) with a little context before.
"""
import re
import sys


def main():
    a = sys.argv[1:]
    span = 16
    if "--span" in a:
        i = a.index("--span")
        span = int(a[i + 1], 0)
        del a[i:i + 2]
    if len(a) < 3:
        sys.exit(__doc__)
    path, proc, offs = a[0], a[1].lstrip("_"), [int(x, 16) for x in a[2:]]
    lines = open(path, errors="replace").read().splitlines()
    rows = []                         # (address, text)
    base = None
    for ln in lines:
        m = re.match(r"\s*\d+\s+([0-9A-F]{4})\s", ln)
        addr = int(m[1], 16) if m else None
        if base is None and re.search(r"\b_?%s\s+proc\b|PROC\s+_?%s\b" % (proc, proc), ln, re.I):
            base = addr
        rows.append((addr, ln))
    if base is None:
        sys.exit("no PROC %s in %s" % (proc, path))
    for off in offs:
        lo, hi = base + off, base + off + span
        print("---- %s+%X  (listing %04X-%04X)" % (proc, off, lo, hi - 1))
        idx = [i for i, (ad, _) in enumerate(rows) if ad is not None and lo <= ad < hi]
        if not idx:
            continue
        for i in range(max(0, idx[0] - 3), idx[-1] + 1):
            print(rows[i][1].rstrip()[:110])


if __name__ == "__main__":
    main()
