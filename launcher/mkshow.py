"""Write the showcase: a demo reel of every version, mode and ability, for
recording -- StevenC & Claude, 2026.

    python launcher/mkshow.py      (w3dbuild.py deploy runs it and sends the
                                   files to the V30's C:\\WOLF3D)

On the DOS machine, in C:\\WOLF3D, type SHOWCASE and pick a version:

    V  WOLF3DV -- id's picture exactly, and every detail option
    B  WOLF3DB -- id's rays with far walls in less detail, and every option
    T  WOLF3DB with the BSP tree finding the walls
    A  all three, one after another (the long video)
    C  choose: Y or N for each of V, B and T -- any combination, in that
       order (StevenC, 2026-10-06: "what if I just want B and T?")

Two questions follow (each answers itself after 15 seconds): whether to
start with id Software's own 1992 code (WOLF3DO.EXE: id's renderer and
game code, rebuilt for the 8086 -- the original needs a 286 -- with the
same timing harness), so every speed after it has the original's to be
measured against (Y by default); and whether to show the map, TAB, too
(N by default: the map's runs come at the end of each reel).  Then, for each mode: a title screen saying what it
shows and with which switches (8 seconds), SECS seconds of the game's own
demos with them (TIMEDEMO SECS: the same time each, so a faster mode gets
further), and its speed report (10 seconds).  At the end, every run's
figures together.  Each screen names the processor (W3MENU /CPU).  S skips
a wait, Q quits.

The files: SHOWCASE.BAT (the menu), SHOWO.BAT (id's code), SHOWV.BAT,
SHOWB.BAT and SHOWT.BAT (the reels).  Each reel runs straight down, no GOTO
but to its end -- COMMAND.COM finds a label by reading the file from the
top.  Q in a reel leaves SHOWQ.FLG, so SHOWCASE stops too; SHOWMAP.FLG
says to run the map, SHOWNOID.FLG to leave out id's code, and SHOWV.RUN,
SHOWB.RUN and SHOWT.RUN say which reels were picked (the questions after
the pick overwrite ERRORLEVEL).  The game's
report goes to SHOWRES.TXT and is shown from there, and each run's "secs"
line -- its frames and speed over all its play -- is gathered into
SHOWSUM.TXT for the summary.
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))
INTRO, AFTER, ASK = 8, 10, 15           # seconds
SECS = 180                              # of play a mode (TIMEDEMO SECS); 60 left
                                        # demo 0 near its start on a V30
TITLE = "Wolfenstein 3-D  --  optimized by StevenC and Claude"
EVERY = "LOWWALLS4 LOWSPRITES FLATART LOWVERT FARBLOBS FASTOPL"

ORIGINAL = [
    ("", "ID SOFTWARE'S ORIGINAL CODE  (1992)",
     ["id's own renderer and game code, rebuilt for the 8086 (the original",
      "needs a 286).  The speed everything after this is measured against."]),
]

DETAIL = [                              # (switches, title, what it shows)
    ("LOWSPRITES", "LOWSPRITES",
     ["Enemies and items in two-pixel-wide columns.",
      "The walls stay as they are.  A small gain."]),
    ("FARBLOBS", "FARBLOBS",
     ["Distant enemies and items as flat shapes, each run of pixels",
      "in its middle colour.  For faster machines."]),
    ("FLATWALLS", "FLATWALLS",
     ["Every wall one solid colour, its texture's own, kept apart from",
      "floor and ceiling.  The artwork -- portraits, banners -- stays."]),
    ("FLATART", "FLATART",
     ["The artwork solid too.  The elevator switch, the way out,",
      "turns magenta so it can still be found."]),
    ("LOWVERT", "LOWVERT",
     ["Half the vertical resolution: the VGA shows every other row,",
      "each twice as tall."]),
    ("LOWWALLS", "LOWWALLS",
     ["One ray for every two screen columns: walls in two-pixel columns."]),
    ("LOWWALLS4", "LOWWALLS4",
     ["One ray in four: walls in four-pixel columns.",
      "The biggest single option on a V30."]),
    ("LOWDETAIL", "LOWDETAIL  (LOWWALLS and LOWSPRITES)",
     ["Walls, enemies and items all in two-pixel columns."]),
    ("LOWDETAIL LOWVERT", "LOWDETAIL and LOWVERT",
     ["Two-pixel columns and half the rows: a quarter of the view's pixels."]),
    (EVERY, "EVERYTHING",
     ["Four-pixel walls, two-pixel sprites, solid colours, half the rows,",
      "flat far sprites and AdLib with no waits.  The fastest."]),
]

MAP = [                                 # run only when SHOWCASE is told Y to the map
    ("AUTOMAP", "THE MAP  (TAB in the game)",
     ["The rooms explored, walls, doors in their keys' colours, items,",
      "enemies in sight and the player.  The game goes on under it."]),
]

REELS = {
    "V": ("WOLF3DV", "WOLF3DV -- id's picture exactly",
          [("", "FULL DETAIL",
            ["Every pixel as id's renderer draws it -- the same picture, from",
             "faster code: assembly for the 8086, every step checked against id's."])]
          + DETAIL, MAP),
    "B": ("WOLF3DB", "WOLF3DB -- the faster version",
          [("", "FAR WALLS IN LESS DETAIL  (the default)",
            ["id's rays, but a wall under 64 pixels tall is textured every second",
             "column, under 32 every fourth.  Near walls and every edge exact."]),
           ("NOLOD", "NOLOD  (full detail)",
            ["The same program with every wall at full detail: id's picture."])]
          + DETAIL, MAP),
    "T": ("WOLF3DB", "WOLF3DB with the BSP tree",
          [("BSP", "THE BSP TREE  (as the SNES version)",
            ["The walls found by a tree built from the level, front to back,",
             "instead of id's rays.  Far walls in less detail."]),
           ("BSP NOLOD", "THE BSP TREE, full detail",
            ["The tree, every wall at full detail."]),
           ("BSP LOWSPRITES", "BSP and LOWSPRITES",
            ["The tree, enemies and items in two-pixel columns."]),
           ("BSP LOWVERT", "BSP and LOWVERT",
            ["The tree, half the rows."]),
           ("BSP LOWSPRITES LOWVERT FASTOPL", "BSP, LOWSPRITES, LOWVERT, FASTOPL",
            ["The tree with every option it draws itself.  (The wall options --",
             "LOWWALLS, FLATWALLS -- go back to id's rays, which are faster.)"])],
          [("BSP AUTOMAP", "BSP and THE MAP",
            ["The tree, with the map up: the walls it drew are what is explored."])]),
}


def reel(fname, label, short, exe, modes, maps=()):
    """One reel: straight down, a mode at a time; the map's runs come last,
    and only when SHOWMAP.FLG is there."""
    n = len(modes)
    out = [
        "@ECHO OFF",
        "REM Wolfenstein 3-D: the showcase's %s reel." % short,
        "REM Written by launcher\\mkshow.py (StevenC & Claude): edit that, not this.",
    ]
    runs = [(sw, title, lines, "%d of %d" % (i, n)) for i, (sw, title, lines) in enumerate(modes, 1)]
    runs += [(sw, title, lines, "And") for sw, title, lines in maps]
    for i, (sw, title, lines, count) in enumerate(runs):
        if i == n:
            out.append("IF NOT EXIST SHOWMAP.FLG GOTO END")
        cmd = "%s TIMEDEMO PRELOAD SECS %d" % (exe, SECS) + (" " + sw if sw else "")
        out += [
            "CLS",
            "ECHO.",
            "ECHO   " + TITLE,
            "IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT",
            "ECHO   ------------------------------------------------------------------",
            "ECHO   %s" % label,
            "ECHO.",
            "ECHO   %s:  %s" % (count, title),
            "ECHO.",
        ]
        out += ["ECHO   " + l for l in lines]
        out += [
            "ECHO.",
            "ECHO   %d seconds of the game's own demos, then the speed: the faster" % SECS,
            "ECHO   the mode, the further it gets.",
            "ECHO.",
            "ECHO   %s" % cmd,
            "ECHO.",
            "ECHO   Starting in %d seconds  (S starts it now, Q quits)" % INTRO,
            "CHOICE /C:SQ /N /T:S,%02d > NUL" % INTRO,
            "IF ERRORLEVEL 2 GOTO QUIT",
            cmd + " > SHOWRES.TXT",
            "CLS",
            "ECHO.",
            "ECHO   %s -- %s" % (label, title),
            "ECHO.",
            "TYPE SHOWRES.TXT",
            "ECHO %s: %s >> SHOWSUM.TXT" % (short, title),
            'FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT',
            "ECHO.",
            "ECHO   Next in %d seconds  (S goes on now, Q quits)" % AFTER,
            "CHOICE /C:SQ /N /T:S,%02d > NUL" % AFTER,
            "IF ERRORLEVEL 2 GOTO QUIT",
        ]
    out += [
        "GOTO END",
        ":QUIT",
        "ECHO Q > SHOWQ.FLG",
        ":END",
    ]
    return fname, out


def menu():
    out = [
        "@ECHO OFF",
        "REM Wolfenstein 3-D: the showcase -- a demo reel of every version, mode and",
        "REM ability, for recording.  Written by launcher\\mkshow.py (StevenC & Claude).",
        "C:",
        "CD \\WOLF3D",
        "IF EXIST SHOWSUM.TXT DEL SHOWSUM.TXT",
        "IF EXIST SHOWQ.FLG DEL SHOWQ.FLG",
        "IF EXIST SHOWMAP.FLG DEL SHOWMAP.FLG",
        "IF EXIST SHOWNOID.FLG DEL SHOWNOID.FLG",
        "IF EXIST SHOWV.RUN DEL SHOWV.RUN",
        "IF EXIST SHOWB.RUN DEL SHOWB.RUN",
        "IF EXIST SHOWT.RUN DEL SHOWT.RUN",
        "IF EXIST SHOWCPU.TXT DEL SHOWCPU.TXT",
        "IF NOT EXIST W3MENU.EXE GOTO NOCPU",     # (a redirect on an IF line
        "W3MENU /CPU > SHOWCPU.TXT",              # happens either way)
        ":NOCPU",
        "CLS",
        "ECHO.",
        "ECHO   " + TITLE,
        "IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT",
        "ECHO   ------------------------------------------------------------------",
        "ECHO.",
        "ECHO   The showcase: a version with every one of its modes, %d seconds" % SECS,
        "ECHO   of the game's demos each -- after id Software's original code, if wanted.",
        "ECHO.",
        "ECHO     V  WOLF3DV -- id's picture exactly, and every detail option",
        "ECHO     B  WOLF3DB -- far walls in less detail, and every detail option",
        "ECHO     T  WOLF3DB with the BSP tree finding the walls",
        "ECHO     A  all three, one after another",
        "ECHO     C  choose: any of the three, asked one by one",
        "ECHO     Q  quit",
        "ECHO.",
        "CHOICE /C:VBTACQ /N    Which? ",
        "IF ERRORLEVEL 6 GOTO END",
        # the reels picked are kept as SHOWV.RUN, SHOWB.RUN and SHOWT.RUN,
        # because the questions after them overwrite ERRORLEVEL.  Never
        # "IF ... ECHO x > FILE": COMMAND.COM opens the redirection before it
        # tests the IF, so the file is created whether or not the IF holds
        "IF ERRORLEVEL 5 GOTO PICKC",
        "IF ERRORLEVEL 4 GOTO PICKA",
        "IF ERRORLEVEL 3 GOTO PICKT",
        "IF ERRORLEVEL 2 GOTO PICKB",
        "ECHO V > SHOWV.RUN",
        "GOTO ASK",
        ":PICKB",
        "ECHO B > SHOWB.RUN",
        "GOTO ASK",
        ":PICKT",
        "ECHO T > SHOWT.RUN",
        "GOTO ASK",
        ":PICKA",
        "ECHO V > SHOWV.RUN",
        "ECHO B > SHOWB.RUN",
        "ECHO T > SHOWT.RUN",
        "GOTO ASK",
        ":PICKC",
        "ECHO.",
        "ECHO   V  WOLF3DV?  Y or N",
        "CHOICE /C:YN /N > NUL",
        "IF ERRORLEVEL 2 GOTO PICKC2",
        "ECHO V > SHOWV.RUN",
        ":PICKC2",
        "ECHO   B  WOLF3DB?  Y or N",
        "CHOICE /C:YN /N > NUL",
        "IF ERRORLEVEL 2 GOTO PICKC3",
        "ECHO B > SHOWB.RUN",
        ":PICKC3",
        "ECHO   T  WOLF3DB with the BSP tree?  Y or N",
        "CHOICE /C:YN /N > NUL",
        "IF ERRORLEVEL 2 GOTO PICKED",
        "ECHO T > SHOWT.RUN",
        ":PICKED",
        "IF EXIST SHOWV.RUN GOTO ASK",          # none of the three: nothing to do
        "IF EXIST SHOWB.RUN GOTO ASK",
        "IF EXIST SHOWT.RUN GOTO ASK",
        "GOTO END",
        ":ASK",
        "ECHO.",
        "ECHO   Start with id's original code, for its speed?  Y or N  (Y in %d seconds)" % ASK,
        "CHOICE /C:YN /N /T:Y,%02d > NUL" % ASK,
        "IF ERRORLEVEL 2 GOTO NOID",
        "GOTO ASKMAP",
        ":NOID",
        "ECHO N > SHOWNOID.FLG",
        ":ASKMAP",
        "ECHO   Show the map (TAB) too?  Y or N  (N in %d seconds)" % ASK,
        "CHOICE /C:YN /N /T:N,%02d > NUL" % ASK,
        "IF ERRORLEVEL 2 GOTO GO",
        "ECHO Y > SHOWMAP.FLG",
        ":GO",
        "IF NOT EXIST SHOWNOID.FLG CALL SHOWO",
        "IF EXIST SHOWQ.FLG GOTO END",
        "IF EXIST SHOWV.RUN CALL SHOWV",
        "IF EXIST SHOWQ.FLG GOTO END",
        "IF EXIST SHOWB.RUN CALL SHOWB",
        "IF EXIST SHOWQ.FLG GOTO END",
        "IF EXIST SHOWT.RUN CALL SHOWT",
        ":END",
        "IF EXIST SHOWQ.FLG DEL SHOWQ.FLG",
        "IF EXIST SHOWMAP.FLG DEL SHOWMAP.FLG",
        "IF EXIST SHOWNOID.FLG DEL SHOWNOID.FLG",
        "IF EXIST SHOWV.RUN DEL SHOWV.RUN",
        "IF EXIST SHOWB.RUN DEL SHOWB.RUN",
        "IF EXIST SHOWT.RUN DEL SHOWT.RUN",
        "IF EXIST SHOWPICK.SEL DEL SHOWPICK.SEL",   # left by the 10-05 version
        "IF NOT EXIST SHOWSUM.TXT GOTO BYE",
        "CLS",
        "ECHO   " + TITLE,
        "IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT",
        "ECHO   -- every run, its frames and speed over %d seconds of play:" % SECS,
        "ECHO.",
        "TYPE SHOWSUM.TXT",
        "ECHO.",
        "ECHO   ORIGINAL is id's own code; WOLF3DV's full detail is its picture exactly.",
        ":BYE",
    ]
    return "SHOWCASE.BAT", out


def write():
    files = [menu(), reel("SHOWO.BAT", "ID'S ORIGINAL CODE", "ORIGINAL", "WOLF3DO", ORIGINAL)]
    for key, fname, short in (("V", "SHOWV.BAT", "WOLF3DV"), ("B", "SHOWB.BAT", "WOLF3DB"),
                              ("T", "SHOWT.BAT", "BSP")):
        exe, label, modes, maps = REELS[key]
        files.append(reel(fname, label, short, exe, modes, maps))
    paths = []
    for fname, out in files:
        for line in out:
            assert "|" not in line and ">=" not in line, line
            assert "%" not in line, line
            assert len(line) <= 127, line
        path = os.path.join(HERE, fname)
        with open(path, "w", newline="\r\n") as f:
            f.write("\n".join(out) + "\n")
        paths.append(path)
    return paths


if __name__ == "__main__":
    for p in write():
        print("wrote", p)
