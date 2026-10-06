"""Multiplayer demos for TIMEDEMO MGEN n -- StevenC & Claude, 2026.

    python mp/mpdemo.py [frames] [--ship BOX ...]

Mn.DEM: 'M', the number of players, a start for each (tile x, y, direction,
0; x 0 for P1 = the map's own start), then id's demo format -- map, length
(4 + 3 * players * frames), pad -- with every player's 3 bytes in each step,
P1 first.  WL_MP.C reads it.

The set (n): for each of the 10 maps of episode 1, a 2-player demo (n = map)
and a 4-player one (n = 10 + map).  P1 starts at the map's own start; the
others on open floor tiles next to it, in the same area, facing the same way,
so they meet at once.  Each player's input is gendemo.py's structured random
input (runs, turns, strafes, "use" now and then, bursts of fire), each from
its own seed.  The map data is the player's own (stage/bsp, never committed).

--ship sends them in one zip to each BOX's C:\\WOLF3D (dx486, v30).
"""
import os
import struct
import sys
import random

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, ROOT)
import gendemo                      # noqa: E402  (load_map, inputs, AREATILE)

OUT = os.path.join(ROOT, "stage", "mpgen")
START = {19: 0, 20: 1, 21: 2, 22: 3}    # the map's player-start objects: N E S W
DIRS = {0: 0, 1: 1, 2: 2, 3: 3}         # SpawnPlayer takes them as they are


def own_start(objs):
    for y in range(64):
        for x in range(64):
            if objs[y * 64 + x] in START:
                return x, y, DIRS[START[objs[y * 64 + x]]]
    raise SystemExit("no player start")


def beside(walls, objs, x0, y0, n):
    """n open tiles near (x0, y0), in its area, nearest first."""
    area = walls[y0 * 64 + x0]
    got = []
    for r in range(1, 6):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = x0 + dx, y0 + dy
                if 0 < x < 63 and 0 < y < 63 and walls[y * 64 + x] == area \
                        and objs[y * 64 + x] == 0 and (x, y) not in got:
                    got.append((x, y))
                    if len(got) == n:
                        return got
    raise SystemExit("no room beside the start")


def make(m, players, frames, seed):
    name, (walls, objs) = gendemo.load_map(m)
    sx, sy, sd = own_start(objs)
    starts = [(0, 0, 0, 0)] + [(x, y, sd, 0) for x, y in beside(walls, objs, sx, sy, players - 1)]
    streams = [gendemo.inputs(random.Random(seed * 7919 + p), frames) for p in range(players)]
    body = b"".join(bytes(streams[p][f]) for f in range(frames) for p in range(players))
    demo = bytes([m]) + struct.pack("<H", 4 + 3 * players * frames) + b"\0" + body
    head = b"M" + bytes([players]) + b"".join(bytes(s) for s in starts)
    return name, starts, head + demo


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 and sys.argv[1].isdigit() else 500
    os.makedirs(OUT, exist_ok=True)
    index = []
    for m in range(10):
        for k, players in ((0, 2), (10, 4)):
            n = k + m
            name, starts, data = make(m, players, frames, 1000 + n)
            open(os.path.join(OUT, "M%d.DEM" % n), "wb").write(data)
            index.append("M%d.DEM map %d (%s), %d players, starts %s" % (n, m, name, players, starts[1:]))
    open(os.path.join(OUT, "INDEX.TXT"), "w").write("\n".join(index) + "\n")
    print("%d demos of %d steps in %s" % (len(index), frames, OUT))
    if "--ship" in sys.argv:
        import w3dbuild
        import zipfile
        z = os.path.join(ROOT, "stage", "MPGEN.ZIP")
        with zipfile.ZipFile(z, "w", zipfile.ZIP_DEFLATED) as zf:
            for n in range(20):
                zf.write(os.path.join(OUT, "M%d.DEM" % n), "M%d.DEM" % n)
        for box in sys.argv[sys.argv.index("--ship") + 1:]:
            w3dbuild.BUILD_BOX = box
            w3dbuild.ship_zip(z, r"C:\WOLF3D")


if __name__ == "__main__":
    main()
