"""Which globals sit at odd addresses, and which odd-sized ones put them there?
StevenC & Claude, 2026.

    python aligncheck.py WOLFSRC\\WOLF3DV.MAP

On the V30's 16-bit bus a word at an odd address takes two bus cycles.
Borland word-aligns each module's _DATA and _BSS, but with -Fc (which id's
headers need) every uninitialized global is a communal, and TLINK packs all
of them into one _COMDEF_ segment with no alignment at all -- so one
odd-sized communal shifts every communal allocated after it.  This lists
DGROUP's publics in address order with their sizes (the gap to the next),
and marks the odd-sized ones and the ones left at odd addresses.
"""
import re
import sys


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else r"WOLFSRC\WOLF3DV.MAP"
    txt = open(path, errors="replace").read()
    segs = re.findall(r"^\s*([0-9A-F]{4}):([0-9A-F]{4}) ([0-9A-F]{4}) C=(\S+)\s+S=(\S+)\s+G=(\S+)\s+M=(\S+)", txt, re.M)
    dgroup = [(int(o, 16), int(l, 16), s, m) for f, o, l, c, s, g, m in segs if g == "DGROUP"]
    comdef = [d for d in dgroup if d[2].startswith("_COMDEF")]
    if not comdef:
        sys.exit("no _COMDEF_ segment in DGROUP")
    cstart = min(d[0] for d in comdef)
    cend = max(d[0] + d[1] for d in comdef)
    pubs = re.findall(r"^\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:idle\s+)?(_\w+)\s*$",
                      txt.split("Publics by Value", 1)[1], re.M)
    dgseg = segs[0] and [f for f, o, l, c, s, g, m in segs if g == "DGROUP"][0]
    rows = sorted((int(o, 16), n) for s, o, n in pubs if s == dgseg)
    inside = [(a, n) for a, n in rows if cstart <= a < cend]
    print("_COMDEF_ in DGROUP: %04X-%04X (%d bytes), %d communals" % (cstart, cend, cend - cstart, len(inside)))
    odd_sized, odd_placed = [], []
    for i, (a, n) in enumerate(inside):
        size = (inside[i + 1][0] if i + 1 < len(inside) else cend) - a
        if size & 1:
            odd_sized.append((a, n, size))
        if a & 1:
            odd_placed.append((a, n, size))
    print("\nodd-sized communals (each shifts everything after it):")
    for a, n, s in odd_sized:
        print("  %04X  %-28s %5d bytes" % (a, n, s))
    print("\ncommunals left at odd addresses: %d" % len(odd_placed))
    for a, n, s in odd_placed[:60]:
        print("  %04X  %-28s %5d bytes" % (a, n, s))


if __name__ == "__main__":
    main()
