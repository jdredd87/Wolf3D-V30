"""Make stage/refsrc: id's own renderer and game logic with TIMEDEMO's
instruments, so a whole attract loop can be checked against id's picture.
StevenC & Claude, 2026.

    python refsrc.py
    set W3D_SRC=stage\\refsrc & set W3D_REMOTE=C:\\W3R & python w3dbuild.py build

The tree is HEAD (build files, TIMEDEMO/CRC, page manager, sound: none of it
draws) with every file that draws or decides taken from id's master.  Demo
playback runs on fixed tics, so the reference can run on any machine.
"""
import os
import shutil
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "stage", "refsrc")
# the renderer, the sprite scaler, the fizzle, the long divide, line of sight
FROM_ID = ["WL_DRAW.C", "WL_DR_A.ASM", "WL_SCALE.C", "WL_STATE.C", "ID_VH.C",
           "ID_VH_A.ASM", "H_LDIV.ASM"]


def git_show(rev, path):
    return subprocess.run(["git", "show", "%s:%s" % (rev, path)], cwd=HERE,
                          capture_output=True, check=True).stdout


if os.path.exists(OUT):
    shutil.rmtree(OUT)
os.makedirs(os.path.join(OUT, "OBJ"))
files = subprocess.run(["git", "ls-tree", "--name-only", "HEAD", "WOLFSRC/"], cwd=HERE,
                       capture_output=True, text=True, check=True).stdout.split()
for f in files:
    name = os.path.basename(f)
    if os.path.splitext(name)[1].upper() in (".C", ".H", ".ASM", ".EQU", ".ASI", ".BAT", ".CFG", ".RSP"):
        rev = "master" if name.upper() in FROM_ID else "HEAD"
        # the repository stores LF; DOS tools (COMMAND.COM above all) want CRLF
        data = git_show(rev, "WOLFSRC/" + name).replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
        open(os.path.join(OUT, name), "wb").write(data)
for f in ("GAMEPAL.OBJ", "SIGNON.OBJ"):
    shutil.copy(os.path.join(HERE, "WOLFSRC", "OBJ", f), os.path.join(OUT, "OBJ", f))


def edit(name, old, new):
    p = os.path.join(OUT, name)
    t = open(p, "rb").read().decode("latin-1")
    old = old.replace("\n", "\r\n")
    new = new.replace("\n", "\r\n")
    assert t.count(old) == 1, (name, old[:60])
    open(p, "wb").write(t.replace(old, new).encode("latin-1"))


# id's actor loop
edit("WL_PLAY.C", """		DoActors ();			// NEC V30 build: the same loop in WL_DR_A.ASM,
								// idle actors skipped without a call
""", """		for (obj = player;obj;obj = obj->next)
			DoActor (obj);
""")
# no WL_SC_A: id's ScaleShape is C
edit("BUILD86.BAT", " ID_VH_A WL_SC_A ID_PM_A)", " ID_VH_A ID_PM_A)")
edit("LINK86.RSP", " WL_SCALE.OBJ WL_SC_A.OBJ+", " WL_SCALE.OBJ+")
print("reference tree in", OUT)
