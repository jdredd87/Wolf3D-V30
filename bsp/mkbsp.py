"""BSP proof of concept, the build half -- StevenC & Claude, 2026.

    python mkbsp.py            -> BSP38.DAT BSP44.DAT BSP57.DAT BSP32.DAT

For each of the timedemo's four floors: the map's walls from GAMEMAPS.WL6
(id's Carmack and RLEW compression), every wall face that borders an open
cell, faces merged into runs along their grid line, a BSP built over them
offline -- as the SNES port built its BSPs offline -- and a set of camera
positions in the level's open cells.  BSPTEST.EXE (bsptest.pas) renders the
same views with Wolf's grid walk and with the BSP and times both.

Doors are left open in both (no door plane), so both find the same walls.
"""
import random
import struct

RLEWTAG_OFS = 0
NEARTAG, FARTAG = 0xA7, 0xA8
FLOORS = [38, 44, 57, 32]          # the timedemo's demos 0-3
CAMERAS = 64


def carmack(src, explen):
    out = []
    i = 0
    nwords = explen // 2
    while len(out) < nwords:
        ch = src[i] | (src[i + 1] << 8)
        i += 2
        hi = ch >> 8
        if hi in (NEARTAG, FARTAG):
            count = ch & 0xFF
            if count == 0:
                ch = (ch & 0xFF00) | src[i]
                i += 1
                out.append(ch)
            elif hi == NEARTAG:
                off = src[i]
                i += 1
                base = len(out) - off
                for k in range(count):
                    out.append(out[base + k])
            else:
                off = src[i] | (src[i + 1] << 8)
                i += 2
                for k in range(count):
                    out.append(out[off + k])
        else:
            out.append(ch)
    return out


def rlew(words, tag, nwords):
    out = []
    i = 0
    while len(out) < nwords:
        v = words[i]
        i += 1
        if v != tag:
            out.append(v)
        else:
            count, value = words[i], words[i + 1]
            i += 2
            out.extend([value] * count)
    return out


def load_map(n):
    head = open("MAPHEAD.WL6", "rb").read()
    tag = struct.unpack_from("<H", head, 0)[0]
    offs = struct.unpack_from("<100L", head, 2)
    g = open("GAMEMAPS.WL6", "rb").read()
    ps0, ps1, ps2, pl0, pl1, pl2, w, h = struct.unpack_from("<3L3H2H", g, offs[n])
    name = g[offs[n] + 22:offs[n] + 38].split(b"\0")[0].decode("latin-1")
    src = g[ps0:ps0 + pl0]
    explen = src[0] | (src[1] << 8)
    words = carmack(src[2:], explen)
    plane = rlew(words[1:], tag, w * h)
    return name, w, h, plane


def solid(v):
    return 1 <= v <= 89 or 102 <= v <= 106      # walls; 90-101 are doors (left open)


def faces(grid):
    """Every wall face bordering a non-solid cell, merged into runs:
    (orient, line, a1, a2, facing) -- orient 0 a vertical line x=line
    spanning y a1..a2, 1 a horizontal line y=line spanning x; facing +1
    when the open side is the higher coordinate."""
    runs = {}
    for x in range(64):
        for y in range(64):
            if not grid[x][y]:
                continue
            for dx, dy, orient, line, a, facing in (
                    (1, 0, 0, x + 1, y, +1), (-1, 0, 0, x, y, -1),
                    (0, 1, 1, y + 1, x, +1), (0, -1, 1, y, x, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < 64 and 0 <= ny < 64 and not grid[nx][ny]:
                    runs.setdefault((orient, line, facing), []).append(a)
    segs = []
    for (orient, line, facing), alist in runs.items():
        alist.sort()
        start = prev = alist[0]
        for a in alist[1:] + [None]:
            if a is not None and a == prev + 1:
                prev = a
                continue
            segs.append((orient, line, start, prev + 1, facing))
            if a is not None:
                start = prev = a
    return segs


def build(segs, nodes):
    """A node: (axis, coord, low child, high child, the segments on its line).
    Children are node indices, -1 for none."""
    if not segs:
        return -1
    lines = sorted(set((s[0], s[1]) for s in segs))
    best = None
    for axis, coord in lines:
        low = high = split = 0
        for s in segs:
            if (s[0], s[1]) == (axis, coord):
                continue
            if s[0] == axis:
                if s[1] < coord: low += 1
                else: high += 1
            else:
                if s[3] <= coord: low += 1
                elif s[2] >= coord: high += 1
                else: split += 1
        score = abs(low - high) + 3 * split
        if best is None or score < best[0]:
            best = (score, axis, coord)
    _, axis, coord = best
    on, lo, hi = [], [], []
    for s in segs:
        if (s[0], s[1]) == (axis, coord):
            on.append(s)
        elif s[0] == axis:
            (lo if s[1] < coord else hi).append(s)
        elif s[3] <= coord:
            lo.append(s)
        elif s[2] >= coord:
            hi.append(s)
        else:
            lo.append((s[0], s[1], s[2], coord, s[4]))
            hi.append((s[0], s[1], coord, s[3], s[4]))
    me = len(nodes)
    nodes.append(None)
    l = build(lo, nodes)
    h = build(hi, nodes)
    nodes[me] = (axis, coord, l, h, on)
    return me


def main():
    random.seed(3)
    for floor in FLOORS:
        name, w, h, plane = load_map(floor - 1)
        assert w == 64 and h == 64
        grid = [[solid(plane[y * 64 + x]) for y in range(64)] for x in range(64)]
        segs = faces(grid)
        nodes = []
        root = build(segs, nodes)
        assert root == 0
        flat = []                       # the segments in node order
        out_nodes = []
        for axis, coord, l, hh, on in nodes:
            out_nodes.append((axis, coord, l, hh, len(flat), len(on)))
            flat.extend(on)
        cams = []
        open_cells = [(x, y) for x in range(64) for y in range(64) if plane[y * 64 + x] >= 107]
        for _ in range(CAMERAS):
            x, y = random.choice(open_cells)
            cams.append((x * 256 + random.randint(48, 208), y * 256 + random.randint(48, 208),
                         random.randrange(3600)))
        data = b"WBSP" + struct.pack("<HHH", len(flat), len(out_nodes), len(cams))
        data += bytes(1 if grid[x][y] else 0 for x in range(64) for y in range(64))
        for o, line, a1, a2, f in flat:
            data += struct.pack("<BbHHH", o, f, line, a1, a2)
        boxes = [None] * len(nodes)

        def box(n):
            if n < 0:
                return None
            axis, coord, l, hh, on = nodes[n]
            bb = [99, 99, -1, -1]
            for o, line, a1, a2, f in on:
                x1, y1, x2, y2 = (line, a1, line, a2) if o == 0 else (a1, line, a2, line)
                bb = [min(bb[0], x1), min(bb[1], y1), max(bb[2], x2), max(bb[3], y2)]
            for c in (box(l), box(hh)):
                if c:
                    bb = [min(bb[0], c[0]), min(bb[1], c[1]), max(bb[2], c[2]), max(bb[3], c[3])]
            boxes[n] = bb
            return bb
        box(0)
        for (axis, coord, l, hh, first, count), bb in zip(out_nodes, boxes):
            data += struct.pack("<HHhhHH4h", axis, coord, l, hh, first, count, *bb)
        for x, y, a in cams:
            data += struct.pack("<HHH", x, y, a)
        open("BSP%02d.DAT" % floor, "wb").write(data)
        depth = 0

        def d(n):
            return 0 if n < 0 else 1 + max(d(nodes[n][2]), d(nodes[n][3]))
        print("floor %d (%s): %d faces merged into %d segments after splits, %d nodes, depth %d"
              % (floor, name, sum(1 for _ in segs), len(flat), len(out_nodes), d(0)))


main()
