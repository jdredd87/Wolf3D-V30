"""pushrec.py -- a recording in which a pushwall moves (2026-10-19).

    python mp/pushrec.py [MAP] [OUT.MPR] [STEPS]

Two players on floor MAP (default 0): player 1 at the map's own start,
player 2 standing beside a pushwall that has room to move, facing it, who
presses USE at step 10 and at 410 steps forward onto the wall's first tile;
player 1 starts beside a door and opens it at 450 and 520.  Written as a server's
--record is ("WMR1", then each packet after its u16 length: a watcher's
WELCOME, START, STEPS), so `WOLF3DM REPLAY OUT.MPR FAST SNAPTEST n` proves
the snapshot on a floor whose map planes changed in play -- the case the
long20 soak found: a rejoin after a pushwall desynced from its first check.
A snapshot at 300 without the planes puts the wall's number back in plane
0 there, so player 2's area is garbage, and the door's ConnectAreas indexes
areabyplayer with it.

By StevenC and Claude (Anthropic).
"""
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import gendemo                      # noqa: E402
import mpproto as P                 # noqa: E402

PUSHABLE = 98                       # PUSHABLETILE, in the object plane
STEP = {0: (0, -1), 1: (1, 0), 2: (0, 1), 3: (-1, 0)}     # SpawnPlayer's dir: N E S W


def floor(walls, objs, x, y):
    return 0 < x < 63 and 0 < y < 63 and walls[y * 64 + x] >= gendemo.AREATILE and objs[y * 64 + x] == 0


def find(walls, objs):
    """(x, y, dir) for the player: beside a pushwall, facing it, with two
    free tiles beyond it for the wall to slide into"""
    for i, o in enumerate(objs):
        if o != PUSHABLE:
            continue
        wx, wy = i % 64, i // 64
        for d, (dx, dy) in STEP.items():
            px, py = wx - dx, wy - dy
            if floor(walls, objs, px, py) and all(floor(walls, objs, wx + k * dx, wy + k * dy) for k in (1, 2)):
                return px, py, d, wx, wy
    raise SystemExit("no pushwall with room on this floor")


def door(walls, objs):
    """(x, y, dir) beside a door (90-101), facing it -- for P1, whose USE
    makes ConnectAreas read every player's area out of plane 0"""
    for i, t in enumerate(walls):
        if 90 <= t <= 101:
            wx, wy = i % 64, i // 64
            for d, (dx, dy) in STEP.items():
                if floor(walls, objs, wx - dx, wy - dy) and floor(walls, objs, wx + dx, wy + dy):
                    return wx - dx, wy - dy, d
    raise SystemExit("no door")


def main():
    m = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    out = sys.argv[2] if len(sys.argv) > 2 else "PUSH%d.MPR" % m
    n = int(sys.argv[3]) if len(sys.argv) > 3 else 600
    name, (walls, objs) = gendemo.load_map(m)
    px, py, d, wx, wy = find(walls, objs)
    dx, dy, dd = door(walls, objs)
    players, skill, rules = 2, 2, 0
    rows = []
    for s in range(n):
        b = gendemo.BT_USE if s == 10 else 0
        move = -70 & 0xFF if 410 <= s < 412 else 0     # forward a tile: onto where the wall was
        b1 = gendemo.BT_USE if s in (450, 520) else 0  # the door: open, and (if shut again) open
        rows.append(bytes([b1, 0, 0]) + bytes([b | (gendemo.BT_RUN if move else 0), 0, move]))
    with open(out, "wb") as f:
        def pkt(b):
            f.write(struct.pack("<H", len(b)) + b)
        f.write(b"WMR1")
        pkt(P.welcome(4, players, m, skill, rules, 0, 0, 0))
        pkt(P.start(players, m, skill, rules, [(dx, dy, dd, 0), (px, py, d, 0)]))
        for first in range(0, n, P.STEPS_MAX):
            pkt(P.steps(first, players, rows[first:first + P.STEPS_MAX]))
    print("%s: floor %d (%s), player 1 at %d,%d facing %s (a door), player 2 at %d,%d facing %s, the pushwall at %d,%d; %d steps"
          % (out, m, name, dx, dy, "NESW"[dd], px, py, "NESW"[d], wx, wy, n))


if __name__ == "__main__":
    main()
