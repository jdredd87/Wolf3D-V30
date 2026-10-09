"""huntbot.py -- a TEST build of WOLF3DM whose NETBOT plays like a player, so
what only a keyboard can do is tested with nobody at one.  StevenC & Claude
(Anthropic), 2026-10-08.  It found two bugs on its first day: ESC ending the
486 ("PML_TransferPageSpace: Zero replacement") and a deathmatch starting
some players with 8 bullets and some with 50.

    python mp/huntbot.py            patch, build on the 486, put the source
                                    back: stage/WOLF3DT.EXE
    python mp/huntbot.py --restore  only put the source back (after a failure)
    python mp/huntbot.py --quit N   Y at the Nth ESC (a minute each), not the 5th
                                    -- alone on a server, a repeatable benchmark
                                    of the picture (the wander is mpbotrnd's)
    python mp/huntbot.py --memonly  only the "mainmem N" line, the bot as it is:
                                    what the real build leaves the 486 (run it
                                    with TIMEDEMO MGEN 0 LOCAL 1), 60-odd bytes
                                    under the truth for the printf

The game reads the keyboard itself (INT 9), so neither KINJ nor KNET can
press TAB, T, SPACE or ESC in it.  This build's NETBOT does instead:

  * hunts: turns toward the nearest other player and runs at them, wanders
    at random a while when it has got nowhere in half a second, fires only
    when aimed, within 8 tiles and with nothing between (no wall, no shut
    door -- without that it emptied its gun into a wall, 2026-10-08);
  * dead, waits 4 s (the death screen, for a camera) and presses SPACE;
  * presses ESC every 60 s of a floor and N 4 s later -- Y the fifth time
    if its NAME starts with Q, which is how a test run ends;
  * in deathmatch every start and respawn is BESIDE P1's start, not
    scattered, so two bots meet (a straight-line hunt is lost in a maze);
  * shows a typed chat line ("Say: ...") 5 s in every 20, for the camera;
  * named Q S..., stops for 24 s at its 2nd ESC (two minutes into a floor):
    a stall for the hang watchdog to report (below), short of the server's
    30 s drop, so the game goes on after it -- and leaves at its 3rd.

Also: the memory id's start-up check sees ("mainmem N", on stdout), with the
check lowered to 150,000 so a build a little bigger than the real one runs.

And the hang watchdog (WL_NET.C, HANGDUMP; 2026-10-09): 20 s with the game's
loop stopped sends the stack and the counters to the server as a HANG packet
-- the server keeps it in stage/hang-<address>.log -- and into the machine's
C:\\WOLF3D\\HANG.LOG; the network going quiet while the game runs goes into
HANG.LOG too.  The build compiles with -y and links with /l, so its map
(kept as stage/WOLF3DT.MAP) has line numbers: python mp/hangtrace.py names
every frame of a report -- in the patched files, kept in stage/wolf3dt-src.

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
FILES = ("WL_MP.C", "WL_MAIN.C", "WL_NET.C", "WL_NETA.ASM", "ID_SD.C", "TURBOC.CFG",
         "LINK86.RSP")


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
        if "ovnow" not in raw:          # a source before the overlay's clock
            b = b.replace("ovnow", "TimeCount")
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
				long	sx = o->x, sy = o->y, ddx = (t->x - o->x)/16, ddy = (t->y - o->y)/16;
				int		k, n, see = best < 8*65536l;

				for (k=1;k<16 && see;k++)		// nothing between: a wall or a shut
				{								// door, every 16th of the way
					sx += ddx;
					sy += ddy;
					n = tilemap[(int)(sx>>16)][(int)(sy>>16)];
					if (n && (!(n & 0x80) || doorposition[n & 0x7f] < 0xc000))
						see = 0;
				}
				*x = 0;
				*bits = 4 | (see ? tog : 0);	// fire, pressed and let go
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
				if (escs == 2 && mpname[1] == 'S')	// TEST: a stall, for the watchdog
				{
					long	t0 = TimeCount;

					while (TimeCount < t0 + 24*70)
						;
				}
			}
			if (asking && TimeCount / 70 == escat + 4)
				Keyboard[(escs >= (mpname[1] == 'S' ? 3 : QUITAT) && mpname[0] == 'Q')
				? sc_Y : sc_N] = 1;
		}
		if (Keyboard[sc_Escape] && !asking && !mpchatting)'''),
    # the real NETBOT's pretend death (MPDeadLook) would hide the real one
    ('''	if (mpbot && mpnet && (TimeCount / 350) % 4 == 2)''', '''	if (0)'''),
    ('''	if (mpchatting)
	{
		Fmt (u,fsay''', '''	if (mpchatting || (mpbot && (ovnow / 350) % 4 == 3))	// TEST: a typed line
	{
		static char far tl[] = "testing the chat line, forty letters...";

		if (!mpchatting)
			_fstrcpy (chatline,tl);
		Fmt (u,fsay'''),
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

NET = [
    ('''#pragma option -zEWL_NET_FAR
''', '''#pragma option -zEWL_NET_FAR
#define HANGDUMP				// TEST build: mp/huntbot.py
'''),
]

NETA = [("MODEL\tMEDIUM\n", "MODEL\tMEDIUM\nHANGDUMP = 1\t\t\t\t; TEST build: mp/huntbot.py\n")]

# id's timer service goes in behind the watchdog's INT 8 entry, not over it
SD = [
    ('''//	Imports from ID_SD_A.ASM
''', '''void HangSet8 (void interrupt (*isr)(void));	// TEST build: WL_NET.C
//	Imports from ID_SD_A.ASM
'''),
    ('''		setvect(8,isr);
''', '''		HangSet8(isr);			// TEST build: behind the hang watchdog
'''),
]

CFG = [("-w-aus\n", "-w-aus\n-y\n")]          # line numbers in the objects...
RSP = [("/c /m /s C0.OBJ+", "/c /m /s /l C0.OBJ+")]    # ...and in the map

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
    quit = sys.argv[sys.argv.index("--quit")+1] if "--quit" in sys.argv else "5"
    mp = [(a, b.replace("QUITAT", quit)) for a, b in MP]
    try:
        if "--memonly" not in sys.argv:
            patch("WL_MP.C", mp)
        patch("WL_MAIN.C", MAIN)
        if "--memonly" not in sys.argv:
            patch("WL_NET.C", NET)
            patch("WL_NETA.ASM", NETA)
            patch("ID_SD.C", SD)
            patch("TURBOC.CFG", CFG)
            patch("LINK86.RSP", RSP)
        # the patched sources, for reading a trace's line numbers against
        keepsrc = os.path.join(STAGE, "wolf3dt-src")
        os.makedirs(keepsrc, exist_ok=True)
        for f in FILES:
            if os.path.exists(keep(f)):
                shutil.copyfile(os.path.join(SRC, f), os.path.join(keepsrc, f))
        rc = subprocess.call([sys.executable, os.path.join(ROOT, "w3dbuild.py"), "build"], cwd=ROOT)
    finally:
        restore()
    if rc:
        return rc
    shutil.copyfile(os.path.join(SRC, "WOLF3DV.EXE"), os.path.join(STAGE, "WOLF3DT.EXE"))
    shutil.copyfile(os.path.join(SRC, "WOLF3DV.MAP"), os.path.join(STAGE, "WOLF3DT.MAP"))
    print("stage/WOLF3DT.EXE, stage/WOLF3DT.MAP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
