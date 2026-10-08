"""huntbot.py -- a TEST build of WOLF3DM whose NETBOT plays like a player, so
what only a keyboard can do is tested with nobody at one.  StevenC & Claude
(Anthropic), 2026-10-08.  It found two bugs on its first day: ESC ending the
486 ("PML_TransferPageSpace: Zero replacement") and a deathmatch starting
some players with 8 bullets and some with 50.

    python mp/huntbot.py            patch, build on the 486, put the source
                                    back: stage/WOLF3DT.EXE
    python mp/huntbot.py --restore  only put the source back (after a failure)

The game reads the keyboard itself (INT 9), so neither KINJ nor KNET can
press TAB, T, SPACE or ESC in it.  This build's NETBOT does instead:

  * hunts: turns toward the nearest other player and runs at them, wanders
    at random a while when it has got nowhere in half a second, fires only
    when aimed and within 8 tiles;
  * dead, waits 4 s (the death screen, for a camera) and presses SPACE;
  * presses ESC every 60 s of a floor and N 4 s later -- Y the fifth time
    if its NAME starts with Q, which is how a test run ends;
  * in deathmatch every start and respawn is BESIDE P1's start, not
    scattered, so two bots meet (a straight-line hunt is lost in a maze).

Also: the memory id's start-up check sees ("mainmem N", on stdout), with the
check lowered to 150,000 so a build a little bigger than the real one runs.

Never commit a patched WOLFSRC: the real files wait in stage/*.keep and are
copied back whatever happens.  Deploy stage/WOLF3DT.EXE beside WOLF3DM.EXE
(not over it), run both machines against one server, e.g.

    WOLF3DT NET <server> NAME QBOTV30 NETBOT LOWEST VIEW 10     (V30)
    WOLF3DT NET <server> NAME QBOT486 NETBOT                    (486)

and photograph the V30 (doscap burst 150 --every 2).  The bots quit about
five minutes in; the exit reports give frags, deaths and both sums.
"""
import io
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "WOLFSRC")
STAGE = os.path.join(ROOT, "stage")
FILES = ("WL_MP.C", "WL_MAIN.C")


def keep(name):
    return os.path.join(STAGE, name + ".keep")


def restore():
    for f in FILES:
        if os.path.exists(keep(f)):
            shutil.copyfile(keep(f), os.path.join(SRC, f))
            os.remove(keep(f))
            print("restored", f)


def patch(name, pairs):
    p = os.path.join(SRC, name)
    shutil.copyfile(p, keep(name))
    raw = io.open(p, "rb").read().decode("latin-1")
    for a, b in pairs:
        a, b = a.replace("\n", "\r\n"), b.replace("\n", "\r\n")
        assert raw.count(a) == 1, (name, a[:60])
        raw = raw.replace(a, b)
    io.open(p, "wb").write(raw.encode("latin-1"))


MP = [
    ('''	if (mpbot)
	{
		if (--mpbotleft <= 0)''', '''	if (mpbot)
	{
		static int far tog, far wander, far calls;
		static long far lastx, far lasty;
		mpctx_t	far *me = &mpctx[mplocal];
		objtype	*o = me->ob, *t;
		long	best = 0x7fffffffl, dx, dy, d, fx, fy, cr, dt;
		int		j, bj = -1;

		tog ^= 1;
		if (me->dead)
		{
			*bits = (me->deadtime > 280 && tog) ? 8 : 0;	// SPACE, after 4 s
			*x = *y = 0;
			wander = 0;
			return;
		}
		for (j=0;j<mpplayers;j++)
			if (j != mplocal && !mpctx[j].absent && !mpctx[j].dead && mpctx[j].ob)
			{
				t = mpctx[j].ob;
				d = labs (t->x - o->x) + labs (t->y - o->y);
				if (d < best)
				{
					best = d;
					bj = j;
				}
			}
		if (++calls >= 35)					// got nowhere in a while: wander
		{
			calls = 0;
			if (labs (o->x - lastx) + labs (o->y - lasty) < 0x6000l && !wander)
			{
				mpbotrnd = mpbotrnd*25173 + 13849;
				wander = 20 + (mpbotrnd >> 10);
			}
			lastx = o->x;
			lasty = o->y;
		}
		if (bj >= 0 && !wander)
		{
			t = mpctx[bj].ob;
			dx = (t->x - o->x) >> 8;
			dy = -((t->y - o->y) >> 8);		// map y runs south
			fx = costable[o->angle] >> 8;
			fy = sintable[o->angle] >> 8;
			cr = fx*dy - fy*dx;				// > 0: the target is to the left
			dt = fx*dx + fy*dy;
			if (dt > 0 && labs (cr) < dt/12)
			{
				*x = 0;
				*bits = 4 | (best < 8*65536l ? tog : 0);	// fire, pressed and let go
			}
			else
			{
				*x = (dt <= 0 || labs (cr) > dt/3) ? 60 : 12;
				if (cr > 0)
					*x = -*x;
				*bits = 4;
			}
			*y = (dt > 0 && labs (cr) < dt && best > 2*65536l) ? -60 : 0;
			return;
		}
		if (wander)
			wander--;
		if (--mpbotleft <= 0)'''),
    ('''		*bits = mpbotb | ((mpbotrnd & 0x700) == 0x700 ? 8 : 0);	// use, now and then''',
     '''		*bits = (mpbotb & ~1) | ((mpbotrnd & 0x700) == 0x700 ? 8 : 0);	// no fire'''),
    ('''		if (Keyboard[sc_Escape] && !asking && !mpchatting)''', '''		if (mpbot && !mpcatching)			// TEST: ESC every 60 s, N 4 s on
		{
			static long far escat = -1;
			static int far escs;

			if (!asking && TimeCount >= 60*70 && (TimeCount / 70) % 60 == 0
			&& escat != TimeCount / 70)
			{
				escat = TimeCount / 70;
				escs++;
				Keyboard[sc_Escape] = 1;
			}
			if (asking && TimeCount / 70 == escat + 4)
				Keyboard[(escs >= 5 && mpname[0] == 'Q') ? sc_Y : sc_N] = 1;
		}
		if (Keyboard[sc_Escape] && !asking && !mpchatting)'''),
    # the real NETBOT's pretend death (MPDeadLook) would hide the real one
    ('''	if (mpbot && mpnet && (TimeCount / 350) % 4 == 2)''', '''	if (0)'''),
    ('''DMStart (i,&sx,&sy);		// deathmatch: scattered, as DOOM''',
     '''Beside (i,&sx,&sy);		// TEST: start beside P1'''),
    ('''static void Respawn (objtype *ob, int i)
{''', '''static void Beside (int i, byte *x, byte *y);
static void Respawn (objtype *ob, int i)
{'''),
    ('''		DMStart (i,&x,&y);
		gamestate.keys = 3;''', '''		Beside (i,&x,&y);	// TEST
		gamestate.keys = 3;'''),
]

MAIN = [
    ('''	if (mminfo.mainmem < 200000L)	// multiplayer''',
     '''	{ static char far f[] = "mainmem %ld\\n"; char s[16]; _fstrcpy ((char far *)s,f); printf (s,mminfo.mainmem); }
	if (mminfo.mainmem < 150000L)	// multiplayer'''),
]


def main():
    if "--restore" in sys.argv:
        restore()
        return 0
    if any(os.path.exists(keep(f)) for f in FILES):
        raise SystemExit("stage/*.keep exist: a run did not finish -- check them, then --restore")
    try:
        patch("WL_MP.C", MP)
        patch("WL_MAIN.C", MAIN)
        rc = subprocess.call([sys.executable, os.path.join(ROOT, "w3dbuild.py"), "build"], cwd=ROOT)
    finally:
        restore()
    if rc:
        return rc
    shutil.copyfile(os.path.join(SRC, "WOLF3DV.EXE"), os.path.join(STAGE, "WOLF3DT.EXE"))
    print("stage/WOLF3DT.EXE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
