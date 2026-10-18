"""profbuild.py -- a TEST build of WOLF3DM with the sampling profiler back
in.  StevenC & Claude (Anthropic), 2026-10-17.

The network game's NETGAME leaves WL_PROF.C out for the V30's memory, so
WOLF3DM ... PROFILE profiles nothing any more.  This patches it back in
(and lowers id's memory check, as huntbot.py's builds do), builds on the
486, puts the sources back, and leaves stage/WOLF3DP.EXE and its map:

    python mp/profbuild.py [--live]

What it is for: the game logic, which is what a machine catching up does
-- a recording replayed FAST on a V30 is all catching up, the same work
every time:

    WOLF3DP REPLAY C1.MPR FAST PROFILE NOAL LOWEST VIEW 10   (on the V30)
    python profmap.py PROF.BIN stage/WOLF3DP.MAP --top 40    (here)

--live samples the whole of play, the pictures too -- not only catching
up -- for a recording replayed at its own speed (no FAST):

    WOLF3DP REPLAY C1.MPR PROFILE NOAL LOWEST VIEW 10

The real WOLFSRC/WOLF3DV.EXE is put back afterwards.
"""
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import huntbot as H                 # noqa: E402  (patch, keep, restore)

H.FILES = H.FILES + ("WL_PROF.C",)
# --live: the whole game, every picture drawn included -- not only catching up
LIVE = [("\t\tif (Due () - mpplayed > 35)\t\t// two seconds behind: catch up",
         "\t\tProfStart ();\t\t\t\t\t// TEST (profbuild --live): always\n"
         "\t\tif (Due () - mpplayed > 35)\t\t// two seconds behind: catch up"),
        ("\t\t\tProfStop ();\n\t\t\tmpcatching = 0;", "\t\t\tmpcatching = 0;")]
PROF = [("#ifdef NETGAME\n// The network game (WOLF3DM) has no profiler",
         "#if 0\t\t// TEST (mp/profbuild.py): the profiler back in\n// The network game (WOLF3DM) has no profiler")]


def main():
    if any(os.path.exists(H.keep(f)) for f in H.FILES):
        raise SystemExit("stage/*.keep exist: a run did not finish -- python mp/huntbot.py --restore")
    real = {}
    for f in ("WOLF3DV.EXE", "WOLF3DV.MAP"):
        p = os.path.join(H.SRC, f)
        if os.path.exists(p):
            real[f] = open(p, "rb").read()
    try:
        H.patch("WL_PROF.C", PROF)
        H.patch("WL_MAIN.C", H.MAIN)
        if "--live" in sys.argv:
            H.patch("WL_MP.C", LIVE)
        H.patch("TURBOC.CFG", H.CFG)        # line numbers, in the objects and the map
        H.patch("LINK86.RSP", H.RSP)
        rc = subprocess.call([sys.executable, os.path.join(H.ROOT, "w3dbuild.py"), "build"], cwd=H.ROOT)
    finally:
        H.restore()
    if not rc:
        shutil.copyfile(os.path.join(H.SRC, "WOLF3DV.EXE"), os.path.join(H.STAGE, "WOLF3DP.EXE"))
        shutil.copyfile(os.path.join(H.SRC, "WOLF3DV.MAP"), os.path.join(H.STAGE, "WOLF3DP.MAP"))
    for f, b in real.items():
        open(os.path.join(H.SRC, f), "wb").write(b)
    if rc:
        return rc
    print("stage/WOLF3DP.EXE, stage/WOLF3DP.MAP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
