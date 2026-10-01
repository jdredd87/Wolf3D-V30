"""Write SHOWCASE.BAT, a demo reel of the detail switches for recording --
StevenC & Claude, 2026.

    python launcher/mkshow.py      (w3dbuild.py deploy runs it and sends
                                   SHOWCASE.BAT to the V30's C:\\WOLF3D)

On the DOS machine, in C:\\WOLF3D, type SHOWCASE.  For each mode, in order
from id's own picture to the fastest: a title screen saying what it shows
and with which switches (8 seconds), SECS seconds of the game's demos with
them (TIMEDEMO SECS: the same time each, so the faster modes get further,
and a fast PC plays on into the next demo), and its speed report (10
seconds); at the end, every run's figures together.  Each screen names
the processor, from W3MENU /CPU.  S skips a wait, Q quits.

It runs straight down, no GOTO but to the end -- COMMAND.COM finds a label
by reading the file from the top.  The game's report goes to SHOWRES.TXT
and is shown from there, and each run's "secs" line -- its frames and speed over all its play, one short line --
is gathered into SHOWSUM.TXT for the summary (FIND reading its
input from a redirect prints the matching lines and nothing else).
"""
import os

HERE = os.path.dirname(os.path.abspath(__file__))

# switches, title, what it shows (two lines at most)
MODES = [
    ("", "FULL DETAIL -- id's own picture",
     ["None of our options: every pixel as id Software's 1992 renderer",
      "draws it.  The starting point -- every run after this is faster."]),
    ("LOWSPRITES", "LOWSPRITES",
     ["Enemies and items in two-pixel-wide columns.",
      "The walls stay as they are.  A small gain."]),
    ("FLATWALLS", "FLATWALLS",
     ["Every wall one solid colour, the texture's own, kept apart from",
      "floor and ceiling.  The artwork -- portraits, banners -- stays."]),
    ("LOWVERT", "LOWVERT",
     ["Half the vertical resolution: the VGA shows every other row,",
      "each twice as tall.  Walls, enemies and the gun lose half their rows."]),
    ("LOWWALLS", "LOWWALLS",
     ["One ray for every two screen columns: walls in two-pixel columns.",
      "The biggest single option."]),
    ("LOWDETAIL", "LOWDETAIL  (LOWWALLS and LOWSPRITES)",
     ["Walls, enemies and items all in two-pixel columns."]),
    ("LOWDETAIL FLATWALLS", "LOWDETAIL and FLATWALLS",
     ["Two-pixel columns, and solid-colour walls."]),
    ("LOWDETAIL LOWVERT", "LOWDETAIL and LOWVERT",
     ["Two-pixel columns and half the rows: a quarter of the view's pixels."]),
    ("LOWDETAIL FLATART LOWVERT", "EVERYTHING  (LOWDETAIL, FLATART, LOWVERT)",
     ["All of it at once, artwork walls solid too.  The fastest."]),
]
INTRO, AFTER, SUMMARY = 8, 10, 15       # seconds
SECS = 60                               # of play a mode (TIMEDEMO SECS)
TITLE = "Wolfenstein 3-D  --  optimized by StevenC and Claude"


def write():
    n = len(MODES)
    out = [
        "@ECHO OFF",
        "REM Wolfenstein 3-D (the NEC V30 build): a demo reel of the detail switches.",
        "REM Written by launcher\\mkshow.py (StevenC & Claude): edit that, not this.",
        "C:",
        "CD \\WOLF3D",
        "IF EXIST SHOWSUM.TXT DEL SHOWSUM.TXT",
        "IF EXIST SHOWCPU.TXT DEL SHOWCPU.TXT",
        "IF EXIST W3MENU.EXE W3MENU /CPU > SHOWCPU.TXT",   # this PC's processor, one line
    ]
    for i, (sw, title, lines) in enumerate(MODES, 1):
        cmd = "WOLF3DV TIMEDEMO PRELOAD SECS %d" % SECS + (" " + sw if sw else "")
        out += [
            "CLS",
            "ECHO.",
            "ECHO   " + TITLE,
            "IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT",
            "ECHO   ------------------------------------------------------------------",
            "ECHO.",
            "ECHO   Demo %d of %d:  %s" % (i, n, title),
            "ECHO.",
        ]
        out += ["ECHO   " + l for l in lines]
        out += [
            "ECHO.",
            "ECHO   %d seconds of the game's own demos, then the speed: the faster" % SECS,
            "ECHO   the mode, the further it gets (a fast PC plays on into the next).",
            "ECHO.",
            "ECHO   %s" % cmd,
            "ECHO.",
            "ECHO   Starting in %d seconds  (S starts it now, Q quits)" % INTRO,
            "CHOICE /C:SQ /N /T:S,%02d > NUL" % INTRO,
            "IF ERRORLEVEL 2 GOTO END",
            cmd + " > SHOWRES.TXT",
            "CLS",
            "ECHO.",
            "ECHO   Demo %d of %d:  %s" % (i, n, title),
            "ECHO.",
            "TYPE SHOWRES.TXT",
            "ECHO %d. %s >> SHOWSUM.TXT" % (i, title),
            'FIND "secs " < SHOWRES.TXT >> SHOWSUM.TXT',
            "ECHO.",
            "ECHO   Next in %d seconds  (S goes on now, Q quits)" % AFTER,
            "CHOICE /C:SQ /N /T:S,%02d > NUL" % AFTER,
            "IF ERRORLEVEL 2 GOTO END",
        ]
    out += [
        ":END",
        "CLS",
        "ECHO   " + TITLE,
        "IF EXIST SHOWCPU.TXT TYPE SHOWCPU.TXT",
        "ECHO   -- every run, its frames and speed over %d seconds of play:" % SECS,
        "ECHO.",
        "IF EXIST SHOWSUM.TXT TYPE SHOWSUM.TXT",
        "ECHO   Full detail is id's picture exactly; every switch is optional.",
    ]
    for line in out:
        assert "|" not in line and ">=" not in line, line
        assert len(line) <= 127, line
    path = os.path.join(HERE, "SHOWCASE.BAT")
    with open(path, "w", newline="\r\n") as f:
        f.write("\n".join(out) + "\n")
    return path


if __name__ == "__main__":
    print("wrote", write())
