"""dmicheck.py -- after tests/dmitems.py: each floor's guns and clips on its
main floor (DMITEMS.md, "Find the floor"), worked out here from id's map --
not from the game's code -- and counted in the replay's statics with the
items on (W3DDMI=1: as the floor is set up, before anyone takes one).  Fails a floor with fewer than it should have.  StevenC & Claude
(Anthropic), 2026-11-04.

    python tests/dmicheck.py [--sod] [SLOTS]      (SLOTS: dmitems.py's 4)
"""
import os
import re
import struct
import subprocess
import sys

ROOT = r"C:\wolf3d"
SOD = "--sod" in sys.argv
RUN = os.path.join(ROOT, "SOD") if SOD else os.path.join(ROOT, "win32", "run")
EXT = "SOD" if SOD else "WL6"
REP = os.path.join(ROOT, "win32", os.environ.get("REP") or ("W3DREPS.EXE" if SOD else "W3DREP.EXE"))
OUT = os.path.join(ROOT, "stage", "dmi")
slots = next((int(a) for a in sys.argv[1:] if a.isdigit()), 4)
WANTMG = 2 if slots > 2 else 1

# id's blocking statics: statinfo's "block" entries, read out of WL_ACT1.C (map code = index + 23)
src = open(os.path.join(ROOT, "WOLFSRC", "WL_ACT1.C"), errors="replace").read()
table = src[src.index("statinfo[] ="):src.index("{-1}")]
if SOD:     # the Spear's own entries, as the preprocessor would take them
    table = re.sub(r"#ifndef SPEAR.*?#else(.*?)#endif", r"\1", table, flags=re.S)
else:
    table = re.sub(r"#ifndef SPEAR(.*?)#else.*?#endif", r"\1", table, flags=re.S)
entries = re.findall(r"\{SPR_STAT_\d+[^}]*\}", table)
BLOCK = {i + 23 for i, e in enumerate(entries) if ",block" in e.replace(" ", "")}


def carmack(src, nwords):
    out, i = [], 0
    while len(out) < nwords:
        w = src[i] | src[i + 1] << 8
        i += 2
        hi, count = w >> 8, w & 0xff
        if hi in (0xA7, 0xA8):
            if count == 0:
                out.append((hi << 8) | src[i])
                i += 1
            elif hi == 0xA7:
                off = src[i]
                i += 1
                start = len(out) - off
                out.extend(out[start + k] for k in range(count))
            else:
                off = src[i] | src[i + 1] << 8
                i += 2
                out.extend(out[off + k] for k in range(count))
        else:
            out.append(w)
    return out


def rlew(words, tag):
    out, i, n = [], 1, words[0] // 2
    while len(out) < n:
        w = words[i]
        i += 1
        if w == tag:
            out.extend([words[i + 1]] * words[i])
            i += 2
        else:
            out.append(w)
    return out


mh = open(os.path.join(RUN, "MAPHEAD." + EXT), "rb").read()
gm = open(os.path.join(RUN, "GAMEMAPS." + EXT), "rb").read()
tag = struct.unpack_from("<H", mh, 0)[0]
offs = struct.unpack_from("<100l", mh, 2)


def floor(m):
    hdr = offs[m]
    ps = struct.unpack_from("<3l", gm, hdr)
    pl = struct.unpack_from("<3H", gm, hdr + 12)
    p = []
    for k in range(2):
        raw = gm[ps[k]:ps[k] + pl[k]]
        p.append(rlew(carmack(raw[2:], (raw[0] | raw[1] << 8) // 2), tag))
    p0, p1 = p

    def open_(x, y):
        t0, t1 = p0[y * 64 + x], p1[y * 64 + x]
        if 90 <= t0 <= 101:
            return True                     # a door
        return t0 >= 106 and t1 not in BLOCK and t1 != 98   # a floor; not a pushwall
    start = next((i % 64, i // 64) for i, t in enumerate(p1) if 19 <= t <= 22)
    tiles = [(x, y) for x in range(1, 63) for y in range(1, 63) if open_(x, y)]
    left, best = set(tiles), set()
    seeds = [start] + tiles
    for s in seeds:
        if s not in left or len(best) * 2 >= len(tiles):
            continue
        reg, st = {s}, [s]
        left.discard(s)
        while st:
            x, y = st.pop()
            for n in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                if n in left:
                    left.discard(n)
                    reg.add(n)
                    st.append(n)
        if len(reg) > len(best):
            best = reg
    return best


bad = 0
maps = range(21 if SOD else 60)
for m in maps:
    mpr = os.path.join(OUT, "D%02dI.MPR" % m)
    if not os.path.exists(mpr):
        print("map %2d: no recording (tests/dmitems.py first)" % m)
        bad += 1
        continue
    local = os.path.join(RUN, "CHK.MPR")
    with open(mpr, "rb") as f, open(local, "wb") as g:
        g.write(f.read())
    out = subprocess.run([REP, "REPLAY", "CHK.MPR", "FAST", "NOAL"], cwd=RUN, capture_output=True, text=True,
                         errors="replace", env=dict(os.environ, W3DDMI="1")).stdout
    os.remove(local)
    fl = floor(m)
    n = {"MG": 0, "CG": 0, "clip": 0}
    for g in re.finditer(r"^dmi st\d+ (-?\d+) at (\d+),(\d+)", out, re.M):
        k = {28: "clip", 29: "MG", 30: "CG", 51: "clip" if SOD else None}.get(int(g.group(1)))
        if k and (int(g.group(2)), int(g.group(3))) in fl:
            n[k] += 1
    ok = n["MG"] >= WANTMG and n["CG"] >= 1 and n["clip"] >= 6
    bad += not ok
    print("map %2d: floor %4d tiles, on it MG %d CG %d clips %2d  %s" % (m, len(fl), n["MG"], n["CG"], n["clip"],
                                                                    "ok" if ok else "SHORT"))
print("%d floors short" % bad)
sys.exit(1 if bad else 0)
