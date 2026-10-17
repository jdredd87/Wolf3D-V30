"""mapvars.py -- every public variable in a WOLF3DM build, by address, with
its size (to the next symbol) and the segment it is in: the raw material
for the snapshot's list of game state (item 15).  StevenC & Claude
(Anthropic), 2026-10-17.

    python mp/mapvars.py [WOLFSRC/WOLF3DV.MAP]
"""
import re
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "WOLFSRC/WOLF3DV.MAP"
text = open(path, encoding="latin-1").read()
segs = []                               # (start, stop, name, class), linear
for m in re.finditer(r"^ ([0-9A-F]{5})H ([0-9A-F]{5})H ([0-9A-F]{5})H (\S+)\s+(\S+)", text, re.M):
    a, b, n, name, cls = m.groups()
    segs.append((int(a, 16), int(b, 16), name, cls))
pub = text[text.index("Publics by Value"):]
syms = []
for m in re.finditer(r"^ ([0-9A-F]{4}):([0-9A-F]{4})\s+(?:Abs\s+|Idle\s+)?(\S+)", pub, re.M):
    seg, off, name = m.groups()
    syms.append((int(seg, 16) * 16 + int(off, 16), name))
syms.sort()
data = [s for s in segs if s[3] in ("DATA", "BSS", "FAR_DATA", "FAR_BSS")]


def segof(a):
    for s in data:
        if s[0] <= a <= s[1]:
            return s
    return None


rows = []
for k, (a, name) in enumerate(syms):
    s = segof(a)
    if not s:
        continue
    nxt = syms[k + 1][0] if k + 1 < len(syms) else s[1] + 1
    size = min(nxt, s[1] + 1) - a
    rows.append((a, size, s[2], name))
for a, size, seg, name in rows:
    print("%05X %6d %-14s %s" % (a, size, seg, name))
