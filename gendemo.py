"""Generated demos for every map, for TIMEDEMO GEN n.  StevenC & Claude.

    python gendemo.py [frames] [--ship]

For each of the 60 maps of the WL6 data, two demos: one from the map's own
start, one from a random open floor tile (an area tile with no object on
it), facing a random way.  Each is `frames` (default 500) frames of
structured random input -- runs, turns, strafes, now and then backing up,
"use" pressed every few frames (doors, pushwalls, elevator switches) and
bursts of fire.  The input is what a demo records, so the game plays it
deterministically; GEN turns on god mode so a demo is not ended by dying.

Gn.DEM, n = 2*map + k: 4 bytes of start (x, y, direction, 0; x 0 = the
map's own), then id's format -- map, length (4 + 3*frames), pad, and per
frame the button bits, the turn and the move as signed bytes.  The map
data is read from stage/bsp's copy of GAMEMAPS.WL6 (pulled off the box; never committed) and MAPHEAD.WL6.
--ship sends them to the 486's C:\\WOLF3D in one zip.
"""
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "stage", "gen")
BSPDIR = os.path.join(HERE, "stage", "bsp")    # GAMEMAPS.WL6 and MAPHEAD.WL6: your own
AREATILE = 107
BT_ATTACK, BT_STRAFE, BT_RUN, BT_USE = 1, 2, 4, 8


def carmack(src, explen):
    out, i = [], 0
    while len(out) < explen // 2:
        ch = src[i] | (src[i + 1] << 8)
        i += 2
        hi = ch >> 8
        if hi in (0xA7, 0xA8):
            count = ch & 0xFF
            if count == 0:
                out.append((ch & 0xFF00) | src[i])
                i += 1
            elif hi == 0xA7:
                base = len(out) - src[i]
                i += 1
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


def rlew(words, tag, n):
    out, i = [], 0
    while len(out) < n:
        v = words[i]
        i += 1
        if v != tag:
            out.append(v)
        else:
            out.extend([words[i + 1]] * words[i])
            i += 2
    return out


def load_map(n):
    head = open(os.path.join(BSPDIR, "MAPHEAD.WL6"), "rb").read()
    tag = struct.unpack_from("<H", head, 0)[0]
    offs = struct.unpack_from("<100L", head, 2)
    g = open(os.path.join(BSPDIR, "GAMEMAPS.WL6"), "rb").read()
    ps = struct.unpack_from("<3L", g, offs[n])
    pl = struct.unpack_from("<3H", g, offs[n] + 12)
    name = g[offs[n] + 22:offs[n] + 38].split(b"\0")[0].decode("latin-1")
    planes = []
    for k in (0, 1):
        src = g[ps[k]:ps[k] + pl[k]]
        explen = src[0] | (src[1] << 8)
        planes.append(rlew(carmack(src[2:], explen)[1:], tag, 64 * 64))
    return name, planes


def inputs(rnd, frames):
    out = []
    while len(out) < frames:
        kind = rnd.choices(["run", "walk", "turnrun", "turn", "strafe", "back"],
                           [30, 15, 25, 15, 10, 5])[0]
        n = rnd.randint(4, 30)
        x = y = 0
        bits = 0
        if kind == "run":
            y, bits = -70, BT_RUN
        elif kind == "walk":
            y = -35
        elif kind == "turnrun":
            y, x, bits = -70, rnd.choice([-1, 1]) * rnd.randint(15, 70), BT_RUN
        elif kind == "turn":
            x = rnd.choice([-1, 1]) * rnd.randint(25, 70)
        elif kind == "strafe":
            x, y, bits = rnd.choice([-35, 35]), rnd.choice([0, -35]), BT_STRAFE
        else:
            y = 35
        fire = rnd.random() < 0.35
        for i in range(n):
            b = bits
            if len(out) % 9 == 4:
                b |= BT_USE                    # one frame in nine: open what is ahead
            if fire and i < 8:
                b |= BT_ATTACK
            out.append((b, x & 0xFF, y & 0xFF))
    return out[:frames]


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 500
    os.makedirs(OUT, exist_ok=True)
    index = []
    for m in range(60):
        name, (walls, objs) = load_map(m)
        open_tiles = [(x, y) for y in range(64) for x in range(64)
                      if walls[y * 64 + x] >= AREATILE and objs[y * 64 + x] == 0]
        for k in range(2):
            rnd = random.Random(1000 * m + k)
            if k == 0:
                start = (0, 0, 0, 0)
            else:
                x, y = rnd.choice(open_tiles)
                start = (x, y, rnd.randrange(4), 0)
            body = inputs(rnd, frames)
            demo = bytes([m]) + struct.pack("<H", 4 + 3 * frames) + b"\0"
            demo += b"".join(bytes(f) for f in body)
            n = 2 * m + k
            open(os.path.join(OUT, "G%d.DEM" % n), "wb").write(bytes(start) + demo)
            index.append("G%d.DEM map %2d (%s) %s" % (n, m, name,
                         "own start" if k == 0 else "start %d,%d dir %d" % start[:3]))
    open(os.path.join(OUT, "INDEX.TXT"), "w").write("\n".join(index) + "\n")
    print("%d demos of %d frames in %s" % (len(index), frames, OUT))
    if "--ship" in sys.argv:
        import w3dbuild
        import zipfile
        z = os.path.join(HERE, "stage", "GEN.ZIP")
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
            for i in range(len(index)):
                zf.write(os.path.join(OUT, "G%d.DEM" % i), "G%d.DEM" % i)
        w3dbuild.ship_zip(z, r"C:\WOLF3D")


main()
