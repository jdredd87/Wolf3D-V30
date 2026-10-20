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

  * capturing the flag (2026-10-17), goes for the flags first: the other
    team's, then home with it, or its own when dropped -- and hunts only
    when there is nothing to do with a flag;
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
HANG.LOG too.

And the screen (2026-10-11), for a hang that takes the network or the tick
with it: every BIOS tick, INT 8 paints in the status bar's left corner, in
white on black, the CS and IP the tick interrupted, a "where" code and the
tick's low byte; the code is also painted at once on the way into and out
of the calls that wait on hardware -- 11 the SB's stop, 12 its DMA start,
13 its 0D4h, 22 an XMS move, 31 the packet driver's send, 41 a DOS read
(the PicoMEM's disk), 00 none of them.  A tick count that still moves: the
game is stuck at that CS:IP with interrupts on.  One that stopped:
interrupts went off (or the machine froze) -- where the code says, or soon
after the CS:IP.  Read it off the screen before cycling the power.

The build compiles with -y and links with /l, so its map
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
FILES = ("WL_MP.C", "WL_MAIN.C", "WL_NET.C", "WL_NETA.ASM", "ID_SD.C", "ID_MM.C",
         "ID_CA.C", "ID_PM.C", "WL_SC_A.ASM", "WL_SCALE.C", "TURBOC.CFG", "LINK86.RSP")


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
		long	best = 0x7fffffffl, dx, dy, d, fx, fy, cr, dt, tx, ty;
		int		j, bj = -1, flag = 0, mt, et;

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
		if (flagobj[0])						// capture the flag: the flags first
		{
			mt = TEAM (mplocal);
			et = !mt;
			flag = 1;
			if (flagby_[et] == mplocal)		// carrying theirs: home
			{
				tx = flagbx[mt];
				ty = flagby[mt];
			}
			else if (flagby_[et] < 0)		// theirs, lying: take it
			{
				tx = flagx[et];
				ty = flagy[et];
			}
			else if (flagby_[mt] < 0 && (flagx[mt] != flagbx[mt] || flagy[mt] != flagby[mt]))
			{								// ours, dropped: send it home
				tx = flagx[mt];
				ty = flagy[mt];
			}
			else
				flag = 0;					// nothing to do with a flag: hunt
			if (flag)
			{
				tx = (tx << 16) + 0x8000l;
				ty = (ty << 16) + 0x8000l;
				best = labs (tx - o->x) + labs (ty - o->y);
				bj = mplocal;
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
			if (!flag)
			{
				t = mpctx[bj].ob;
				tx = t->x;
				ty = t->y;
			}
			dx = (tx - o->x) >> 8;
			dy = -((ty - o->y) >> 8);		// map y runs south
			fx = costable[o->angle] >> 8;
			fy = sintable[o->angle] >> 8;
			cr = fx*dy - fy*dx;				// > 0: the target is to the left
			dt = fx*dx + fy*dy;
			if (dt > 0 && labs (cr) < dt/12)
			{
				long	sx = o->x, sy = o->y, ddx = (tx - o->x)/16, ddy = (ty - o->y)/16;
				int		k, n, see = !flag && best < 8*65536l;

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
			*y = (dt > 0 && labs (cr) < dt && (flag || best > 2*65536l)) ? -60 : 0;
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
    ('''	if (mpbot && mpbotshow && mpnet && (TimeCount / 350) % 4 == 2)''', '''	if (0)'''),
    # SHOW's scores and chat line always (2026-10-20, when plain NETBOT
    # stopped showing them): the soaks read the "here, step N" lines
    ('''int		far	mpbotshow;''', '''int		far	mpbotshow = 1;	// TEST: always SHOW'''),
    ('''	if (mpchatting)
	{
		Fmt (u,fsay''', '''	if (mpchatting || (mpbot && (ovnow / 350) % 4 == 3))	// TEST: a typed line
	{
		static char far tl[] = "testing the chat line, forty letters...";

		if (!mpchatting)
			_fstrcpy (chatline,tl);
		Fmt (u,fsay'''),
    ('''	static char far f[] = "%Fs here, step %ld";''',
     '''	static char far f[] = "%Fs %ld h%d u%ld p%d k%x m%d";	// TEST: handles, memory, pages, stack, map
	int MM_FreeBlocks (void);
	unsigned StackLow (void);
	extern int MainPagesAvail;'''),
    ('''		Fmt (s,f,(char far *)mpname,mpplayed);''',
     '''		Fmt (s,f,(char far *)mpname,mpplayed,MM_FreeBlocks (),MM_UnusedMemory (),MainPagesAvail,StackLow (),gamestate.episode*10+gamestate.mapon);'''),
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
int HangMark (int where);		// TEST build: WL_NETA.ASM, the screen report
'''),
    ('''	r.x.cx = len;
	int86x (netvec,&r,&r,&s);
	netsentn++;
''', '''	r.x.cx = len;
	{
		int	hw = HangMark (0x31);	// TEST
		int86x (netvec,&r,&r,&s);
		HangMark (hw);
	}
	netsentn++;
'''),
]

NETA = [("MODEL\tMEDIUM\n", "MODEL\tMEDIUM\nHANGDUMP = 1\t\t\t\t; TEST build: mp/huntbot.py\n"),
        # the screen report: Hang8 paints it every BIOS tick
        ('''	mov		[_hang8ss],ss
	mov		[_hang8sp],sp
	pop		ax
	pop		ds
	jmp		[DWORD PTR cs:hang8next]
ENDP
''', '''	mov		[_hang8ss],ss
	mov		[_hang8sp],sp
	push	es
	mov		ax,40h
	mov		es,ax
	mov		ax,[es:6Ch]				; the BIOS tick: once each, not at 700 Hz
	cmp		ax,[hanglastt]
	je		@@go
	mov		[hanglastt],ax
	push	bp
	mov		bp,sp
	mov		ax,[bp+8]				; bp es ax ds, then the IP and CS
	mov		[hangip],ax
	mov		ax,[bp+10]
	mov		[hangcs],ax
	pop		bp
	push	bx
	mov		bl,1
	call	HangPaint
	pop		bx
@@go:
	pop		es
	pop		ax
	pop		ds
	jmp		[DWORD PTR cs:hang8next]
ENDP

;
; int HangMark (int where) -- set the where code and paint it now (from
; code with interrupts off too); returns the one before
;
PROC	_HangMark FAR
PUBLIC	_HangMark
	push	bp
	mov		bp,sp
	push	ds
	push	bx
	mov		ax,@data
	mov		ds,ax
	mov		bl,[_hangwhere]
	push	bx
	mov		ax,[bp+6]
	mov		[_hangwhere],al
	xor		bl,bl
	call	HangPaint
	pop		ax
	xor		ah,ah
	pop		bx
	pop		ds
	pop		bp
	retf
ENDP

;
; HangPaint: BL = 1 everything, 0 the where code only.  DS = DGROUP.
; Only in a graphics mode (the GC maps A000, 64 KB), and into the page on
; screen; every VGA register it changes is read first and put back, so it
; can interrupt the game between an index and its data.  Keeps everything.
;
PROC	HangPaint NEAR
	pusha
	push	es
	pushf
	cli
	cld
	mov		dx,3CEh
	in		al,dx
	mov		ah,al					; the GC's index
	mov		al,6
	out		dx,al
	inc		dx
	in		al,dx
	dec		dx
	and		al,0Ch
	cmp		al,04h
	je		@@gfx
	mov		al,ah
	out		dx,al
	jmp		@@out
@@gfx:
	push	ax
	mov		al,1					; enable set/reset: none
	out		dx,al
	inc		dx
	in		al,dx
	push	ax
	xor		al,al
	out		dx,al
	dec		dx
	mov		al,3					; rotate and function: none
	out		dx,al
	inc		dx
	in		al,dx
	push	ax
	xor		al,al
	out		dx,al
	dec		dx
	mov		al,5					; write mode 0
	out		dx,al
	inc		dx
	in		al,dx
	push	ax
	and		al,0FCh
	out		dx,al
	dec		dx
	mov		al,8					; bit mask: all
	out		dx,al
	inc		dx
	in		al,dx
	push	ax
	mov		al,0FFh
	out		dx,al
	mov		dx,3C4h
	in		al,dx
	mov		ah,al					; the sequencer's index
	mov		al,2
	out		dx,al
	inc		dx
	in		al,dx
	push	ax						; AH its index, AL the map mask
	mov		al,0Fh
	out		dx,al
	mov		ax,0A000h
	mov		es,ax
	call	HangDraw
	pop		ax
	mov		dx,3C5h
	out		dx,al
	dec		dx
	mov		al,ah
	out		dx,al
	mov		dx,3CEh
	mov		al,8
	out		dx,al
	inc		dx
	pop		ax
	out		dx,al
	dec		dx
	mov		al,5
	out		dx,al
	inc		dx
	pop		ax
	out		dx,al
	dec		dx
	mov		al,3
	out		dx,al
	inc		dx
	pop		ax
	out		dx,al
	dec		dx
	mov		al,1
	out		dx,al
	inc		dx
	pop		ax
	out		dx,al
	dec		dx
	pop		ax
	mov		al,ah
	out		dx,al
@@out:
	popf
	pop		es
	popa
	ret
ENDP

;
; rows 161-196, bytes 0-21 of the page on screen: CS, IP, where and tick
;
PROC	HangDraw NEAR
	or		bl,bl
	jz		@@where
	mov		di,[_displayofs]
	add		di,161*80
	mov		cx,36
	xor		ax,ax
@@bg:
	push	cx
	push	di
	mov		cx,11
	rep		stosw
	pop		di
	pop		cx
	add		di,80
	loop	@@bg
	mov		di,[_displayofs]
	add		di,162*80+1
	mov		ax,[hangcs]
	call	HWord
	add		di,12*80
	mov		ax,[hangip]
	call	HWord
	add		di,12*80+12
	mov		al,[BYTE PTR hanglastt]
	call	HByte
@@where:
	mov		di,[_displayofs]
	add		di,186*80+1
	mov		al,[_hangwhere]
	call	HByte
	ret
ENDP

PROC	HWord NEAR					; AX at ES:DI, four digits; keeps DI
	push	ax
	mov		al,ah
	call	HByte
	add		di,8
	pop		ax
	call	HByte
	sub		di,8
	ret
ENDP

PROC	HByte NEAR					; AL at ES:DI, two digits; keeps DI
	push	ax
	shr		al,4
	call	HDigit
	add		di,4
	pop		ax
	call	HDigit
	sub		di,4
	ret
ENDP

PROC	HDigit NEAR					; AL's low digit, 3x5, each dot 4x2 pixels
	push	cx
	push	si
	push	di
	and		ax,0Fh
	mov		si,ax
	shl		si,2
	add		si,ax
	add		si,OFFSET hfont
	mov		cx,5
@@row:
	mov		ah,[cs:si]
	inc		si
	xor		al,al
	test	ah,4
	jz		@@a
	mov		al,15
@@a:
	mov		[es:di],al
	mov		[es:di+80],al
	xor		al,al
	test	ah,2
	jz		@@b
	mov		al,15
@@b:
	mov		[es:di+1],al
	mov		[es:di+81],al
	xor		al,al
	test	ah,1
	jz		@@c
	mov		al,15
@@c:
	mov		[es:di+2],al
	mov		[es:di+82],al
	add		di,160
	loop	@@row
	pop		di
	pop		si
	pop		cx
	ret
ENDP

hfont	db	7,5,5,5,7, 2,6,2,2,7, 7,1,7,4,7, 7,1,7,1,7
		db	5,5,7,1,1, 7,4,7,1,7, 7,4,7,5,7, 7,1,1,1,1
		db	7,5,7,5,7, 7,5,7,1,7, 7,5,7,5,5, 6,5,6,5,6
		db	7,4,4,4,7, 6,5,5,5,6, 7,4,7,4,7, 7,4,7,4,4
'''),
        ('''PUBLIC	_hang8ss, _hang8sp
_hang8ss	dw	0
_hang8sp	dw	0
''', '''PUBLIC	_hang8ss, _hang8sp
_hang8ss	dw	0
_hang8sp	dw	0
EXTRN	_displayofs:WORD
PUBLIC	_hangwhere
_hangwhere	db	0				; the screen report's where code
hanglastt	dw	0				; the BIOS tick it was last painted at
hangcs		dw	0				; what that tick interrupted
hangip		dw	0
''')]

# id's timer service goes in behind the watchdog's INT 8 entry, not over it;
# and the screen report's where codes around the Sound Blaster's waits
SD = [
    ('''//	Imports from ID_SD_A.ASM
''', '''void HangSet8 (void interrupt (*isr)(void));	// TEST build: WL_NET.C
//	Imports from ID_SD_A.ASM
'''),
    ('''		setvect(8,isr);
''', '''		HangSet8(isr);			// TEST build: behind the hang watchdog
'''),
    ('''//	Imports from ID_SD_A.ASM
''', '''int HangMark (int where);		// TEST build: WL_NETA.ASM, the screen report
//	Imports from ID_SD_A.ASM
'''),
    ('''	byte	is;

asm	pushf
asm	cli

	if (sbSamplePlaying)
	{
		sbSamplePlaying = false;

		sbWriteDelay();
		sbOut(sbWriteCmd,0xd0);	// Turn off DSP DMA
''', '''	byte	is;
	int		hw;

asm	pushf
asm	cli

	if (sbSamplePlaying)
	{
		sbSamplePlaying = false;

		hw = HangMark (0x11);	// TEST
		sbWriteDelay();
		sbOut(sbWriteCmd,0xd0);	// Turn off DSP DMA
		HangMark (hw);
'''),
    ('''	unsigned		datapage;
	longword		dataofs,uselen;
''', '''	unsigned		datapage;
	longword		dataofs,uselen;
	int				hw;
'''),
    ('''	// Start playing the thing
	sbWriteDelay();
	sbOut(sbWriteCmd,0x14);
	sbWriteDelay();
	sbOut(sbWriteData,(byte)uselen);
	sbWriteDelay();
	sbOut(sbWriteData,(byte)(uselen >> 8));
''', '''	// Start playing the thing
	hw = HangMark (0x12);	// TEST
	sbWriteDelay();
	sbOut(sbWriteCmd,0x14);
	sbWriteDelay();
	sbOut(sbWriteData,(byte)uselen);
	sbWriteDelay();
	sbOut(sbWriteData,(byte)(uselen >> 8));
	HangMark (hw);
'''),
    ('''SDL_SBPlaySample(byte huge *data,longword len)
{
	longword	used;
''', '''SDL_SBPlaySample(byte huge *data,longword len)
{
	longword	used;
	int			hw;
'''),
    ('''	sbWriteDelay();
	sbOut(sbWriteCmd,0xd4);						// Make sure DSP DMA is enabled
''', '''	hw = HangMark (0x13);	// TEST
	sbWriteDelay();
	sbOut(sbWriteCmd,0xd4);						// Make sure DSP DMA is enabled
	HangMark (hw);
'''),
]

CA = [
    ('''boolean CA_FarRead (int handle, byte far *dest, long length)
{
''', '''int HangMark (int where);		// TEST build: WL_NETA.ASM, the screen report
boolean CA_FarRead (int handle, byte far *dest, long length)
{
	int		hw;

'''),
    ('''		Quit ("CA_FarRead doesn't support 64K reads yet!");

asm		push	ds
''', '''		Quit ("CA_FarRead doesn't support 64K reads yet!");

	hw = HangMark (0x41);	// TEST
asm		push	ds
'''),
    ('''	errno = _AX;
	return	false;
good:
asm		cmp	ax,[WORD PTR length]
asm		je	done
	errno = EINVFMT;			// user manager knows this is bad read
	return	false;
done:
	return	true;
}''', '''	errno = _AX;
	HangMark (hw);
	return	false;
good:
asm		cmp	ax,[WORD PTR length]
asm		je	done
	errno = EINVFMT;			// user manager knows this is bad read
	HangMark (hw);
	return	false;
done:
	HangMark (hw);
	return	true;
}'''),
]

PM = [
    ('''		longword	target_offset;
	} copy;
''', '''		longword	target_offset;
	} copy;
	int			hw;
'''),
    ('''asm	push si
	_SI = (word)&copy;
	XMS_CALL(XMS_MOVE);
asm	pop	si
	if (!_AX)
		Quit("PML_XMSCopy: Error on copy");
''', '''	hw = HangMark (0x22);	// TEST
asm	push si
	_SI = (word)&copy;
	XMS_CALL(XMS_MOVE);
asm	pop	si
	if (!_AX)
		Quit("PML_XMSCopy: Error on copy");
	HangMark (hw);
'''),
    ('''void
PML_XMSCopy(boolean toxms,''', '''int HangMark (int where);		// TEST build: WL_NETA.ASM, the screen report
void
PML_XMSCopy(boolean toxms,'''),
    ('''void
PM_CheckMainMem(void)
{''', '''//
// TEST build: the main-memory pages, checked -- 0, or what is wrong, in s.
// A used slot has a block and a page that says it is there; a page in main
// memory names a used slot that names it back; the counts agree
//
int PM_Check (char *s)
{
	static char far f1[] = "PM slot %d pg %d seg %x", far f2[] = "PM pg %d slot %d lk %d",
		far f3[] = "PM used %d/%u av %d/%d";
	char			f[32];
	int				i,p,u = 0,a = 0;
	PageListStruct	far *page;

	for (i = 0;i < PMMaxMainMem;i++)
	{
		if (MainMemUsed[i] & pmba_Allocated)
			a++;
		if (MainMemUsed[i] & pmba_Used)
		{
			u++;
			p = mainOwner[i];
			if (!MainMemPages[i] || p < 0 || p >= ChunksInFile || PMPages[p].mainPage != i)
			{
				_fstrcpy ((char far *)f,f1);
				sprintf (s,f,i,p,(unsigned)MainMemPages[i]);
				return 1;
			}
		}
	}
	for (p = 0,page = PMPages;p < ChunksInFile;p++,page++)
	{
		i = page->mainPage;
		if (i != -1 && (i < 0 || i >= PMMaxMainMem || !(MainMemUsed[i] & pmba_Used)
		|| mainOwner[i] != p || page->locked < 0 || page->locked > 2))
		{
			_fstrcpy ((char far *)f,f2);
			sprintf (s,f,p,i,(int)page->locked);
			return 1;
		}
	}
	if (u != MainPagesUsed || a != MainPagesAvail)
	{
		_fstrcpy ((char far *)f,f3);
		sprintf (s,f,u,MainPagesUsed,a,MainPagesAvail);
		return 1;
	}
	return 0;
}

void
PM_CheckMainMem(void)
{'''),
]

# the memory manager's block handles left (700 in all), in the bot's chat line
MM = [('''void MML_ClearBlock (void)
{
''', '''int MM_FreeBlocks (void)		// TEST build: mp/huntbot.py
{
	mmblocktype far *s;
	int		n = 0;

	for (s = mmfree; s; s = s->next)
		n++;
	return n;
}

//
// TEST build: the block list, checked -- 0, or what is wrong, in s.  In
// order, not overlapping, and each block's owner still holding its start
//
int MM_Check (char *s)
{
	static char far f1[] = "MM loop", far f2[] = "MM %x+%x>%x n%d",
		far f3[] = "MM own %x=%x not %x n%d";
	char		f[32];
	mmblocktype	far *scan;
	int			n = 0;

	for (scan = mmhead; scan; scan = scan->next)
	{
		if (++n > MAXBLOCKS)
		{
			_fstrcpy ((char far *)f,f1);
			sprintf (s,f);
			return 1;
		}
		if (scan->next && (long)scan->start + scan->length > scan->next->start)
		{
			_fstrcpy ((char far *)f,f2);
			sprintf (s,f,scan->start,scan->length,scan->next->start,n);
			return 1;
		}
		if (scan->useptr && *(unsigned *)scan->useptr != scan->start)
		{
			_fstrcpy ((char far *)f,f3);
			sprintf (s,f,(unsigned)scan->useptr,*(unsigned *)scan->useptr,scan->start,n);
			return 1;
		}
	}
	return 0;
}

void MML_ClearBlock (void)
{
''')]

CFG = [("-w-aus\n", "-w-aus\n-y\n")]          # line numbers in the objects...
RSP = [("/c /m /s C0.OBJ+", "/c /m /s /l C0.OBJ+")]    # ...and in the map

MAIN = [
    ('''	if (mminfo.mainmem < 200000L)	// multiplayer''',
     '''	{ static char far f[] = "mainmem %ld\\n"; char s[16]; _fstrcpy ((char far *)s,f); printf (s,mminfo.mainmem); }
	if (mminfo.mainmem < 150000L)	// multiplayer'''),
]


# TEST: the heap checked every pass of the game's loop; the first fault found
# goes to the server at once as a chat line ("says: MM ..." / "PM ...")
CHECK = [('''		UpdateSoundLoc ();
		if (screenfaded)''', '''		{								// TEST: the heap, every pass (huntbot.py)
			static int far told;
			char	cs[64];
			int		MM_Check (char *s), PM_Check (char *s);

			if (!told && (MM_Check (cs) || PM_Check (cs)))
			{
				told = 1;
				cs[40] = 0;
				_fstrcpy (chatsend,(char far *)cs);
				chatnum = chatnum % 255 + 1;
				chatwait = chatnum;
				chattries = 0;
				ChatOut ();
			}
		}
		UpdateSoundLoc ();
		if (screenfaded)''')]

# --leak: the music fix (3382761) taken out again, to bring the crash back
LEAK = [('''	StopMusic ();					// as id's floor end''',
         '''	if (0) StopMusic ();			// TEST --leak: as id's floor end''')]


# --trace: breadcrumbs from the ninth floor on, each its own HANG packet the
# moment it happens (stage/hang-<address>.log, and the server's log), so the
# last one the server has is the last thing the machine did.  T<n> numbers
# them; F/f a frame's start and end, S a sprite (shape, height) and s its
# page's segment, M/m a page fetched from XMS or disk (page; page, segment),
# X a page's memory given to another (old>new, segment), D/d digitized sound
# (which; page, segment)
TRACENET = [('''//
// The first line of every report''', '''#include <stdarg.h>
int		tracing;					// TEST --trace: from the ninth floor
static unsigned far traceno;

void Trace (char far *fmt, ...)
{
	static char far tf[] = "T%u %x %x ", far tv[] = "T%u V %d %x:%x>%x:%x";
	unsigned StackLow (void);
	static unsigned far ivt[512];
	static int far ivtset, far ivttold;
	unsigned far *v = (unsigned far *)MK_FP (0,0);
	unsigned sp = _SP;
	char	f[48], s[100];
	int		n,k;
	va_list	ap;

	if (!tracing)
		return;
	if (!ivtset)
	{
		_fmemcpy (ivt,v,1024);
		ivtset = 1;
	}
	else if (ivttold < 8)
		for (k = 0;k < 256;k++)
			if (v[2*k] != ivt[2*k] || v[2*k+1] != ivt[2*k+1])
			{
				_fstrcpy ((char far *)f,tv);
				sprintf (s,f,traceno++,k,ivt[2*k+1],ivt[2*k],v[2*k+1],v[2*k]);
				HangSend ((char far *)s,strlen (s));
				ivt[2*k] = v[2*k];
				ivt[2*k+1] = v[2*k+1];
				ivttold++;
			}
	_fstrcpy ((char far *)f,tf);
	n = sprintf (s,f,traceno++,sp,StackLow ());
	_fstrcpy ((char far *)f,fmt);
	va_start (ap,fmt);
	vsprintf (s+n,f,ap);
	va_end (ap);
	HangSend ((char far *)s,strlen (s));
}

void far TraceShape (int shapenum, int height)
{
	static char far f[] = "S %d %d";
	Trace (f,shapenum,height);
}

void far TraceSeg (unsigned seg)
{
	static char far f[] = "s %x";
	Trace (f,seg);
}

//
// The first line of every report''')]

TRACEMP = [
    ('''	VW_FadeOut ();					// a machine go after 30 s of nothing, and a V30
''', '''	{ static char far f[] = "L1"; Trace (f); }
	VW_FadeOut ();					// a machine go after 30 s of nothing, and a V30
	{ static char far f[] = "L2"; Trace (f); }
'''),
    ('''	ClearMemory ();					// loading a floor is quiet for 15
	SETFONTCOLOR (0,15);
	DrawPlayScreen ();
	VW_FadeIn ();
	SendInput ();
	SetupGameLevel ();
	SendInput ();''', '''	ClearMemory ();					// loading a floor is quiet for 15
	{ static char far f[] = "L3"; Trace (f); }
	SETFONTCOLOR (0,15);
	DrawPlayScreen ();
	{ static char far f[] = "L4"; Trace (f); }
	VW_FadeIn ();
	{ static char far f[] = "L5"; Trace (f); }
	SendInput ();
	SetupGameLevel ();
	{ static char far f[] = "L6"; Trace (f); }
	SendInput ();'''),
    ('''	StartMusic ();
	PM_CheckMainMem ();
	fizzlein = true;
	DrawLevel ();
}''', '''	{ static char far f[] = "L7"; Trace (f); }
	StartMusic ();
	{ static char far f[] = "L8"; Trace (f); }
	PM_CheckMainMem ();
	{ static char far f[] = "L9"; Trace (f); }
	fizzlein = true;
	DrawLevel ();
	{ static char far f[] = "L10"; Trace (f); }
}'''),
    ('''#include <stdarg.h>
''', '''#include <stdarg.h>
void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
'''),
    ('''		mpsrc = ob;					// an enemy's sounds come from the enemy
		DoActor (ob);''', '''		mpsrc = ob;					// an enemy's sounds come from the enemy
		{
			static char far f[] = "A %x %d %x %Fp %Fp";
			Trace (f,(unsigned)ob,ob->obclass,(unsigned)ob->state,
				(void far *)ob->state->think,(void far *)ob->state->action);
		}
		DoActor (ob);'''),
    ('''		NetPump (Take);
		if (TimeCount - lastsend >= 2)
		{
			lastsend = TimeCount;
			SendInput ();
		}
		if (mphave - mpplayed > 35)''', '''		{ static char far f[] = "N"; Trace (f); }
		NetPump (Take);
		{ static char far f[] = "n"; Trace (f); }
		if (TimeCount - lastsend >= 2)
		{
			lastsend = TimeCount;
			SendInput ();
		}
		if (mphave - mpplayed > 35)'''),
    ('''			madenoise = false;
			MoveDoors ();
			MovePWalls ();
			MPDoActors ();
			MPStep ();''', '''			madenoise = false;
			{ static char far f[] = "G %ld"; Trace (f,mpplayed); }
			MoveDoors ();
			MovePWalls ();
			{ static char far f[] = "g1"; Trace (f); }
			MPDoActors ();
			{ static char far f[] = "g2"; Trace (f); }
			MPStep ();
			{ static char far f[] = "g3"; Trace (f); }'''),
    ('''			if (n)
				Status ();''', '''			if (n)
				Status ();
			{ static char far f[] = "Z"; Trace (f); }'''),
    ('''			if (mpbot && mpbotshow)
				BotShow ();''', '''			{ static char far f[] = "z"; Trace (f); }
			if (mpbot && mpbotshow)
				BotShow ();
			{ static char far f[] = "B"; Trace (f); }'''),
    ('''			if (!asking && !mpchatting)
				Picture ();
		}''', '''			if (!asking && !mpchatting)
				Picture ();
			{ static char far f[] = "P"; Trace (f); }
		}'''),
    ('''		UpdateSoundLoc ();
		if (screenfaded)''', '''		{ static char far f[] = "U"; Trace (f); }
		UpdateSoundLoc ();
		{ static char far f[] = "u"; Trace (f); }
		if (screenfaded)'''),
    ('''	gamestate.keys = 0;
	gamestate.oldscore = gamestate.score;''', '''	{								// TEST --trace: on from the ninth floor
		extern int tracing;
		static int far floors;
		static char far f[] = "FLOOR %d nh %x+%lx ss %x";
		extern void *nearheap;

		if (++floors >= 8)
			tracing = 1;
		Trace (f,floors+1,(unsigned)nearheap,mminfo.nearheap,_SS);
	}
	gamestate.keys = 0;
	gamestate.oldscore = gamestate.score;'''),
    ('''				MPCamera (true);
				ThreeDRefresh ();
				MPCamera (false);''', '''				{
					static char far f1[] = "F %ld", far f2[] = "f";
					Trace (f1,mpplayed);
					MPCamera (true);
					ThreeDRefresh ();
					MPCamera (false);
					Trace (f2);
				}'''),
]

TRACEPM = [
    ('''//	Main Mem specific variables''', '''void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
//	Main Mem specific variables'''),
    ('''		boolean mainonly = (pagenum >= PMSoundStart);
if (!PMPages[pagenum].offset)	// JDC: sparse page''', '''		boolean mainonly = (pagenum >= PMSoundStart);
		static char far tm[] = "M %d";
		Trace (tm,pagenum);
if (!PMPages[pagenum].offset)	// JDC: sparse page'''),
    ('''	if (!addr)
		Quit("PML_TransferPageSpace: Zero replacement");''', '''	{
		static char far f[] = "X %d>%d %x";
		Trace (f,orig,new,(unsigned)addr);
	}
	if (!addr)
		Quit("PML_TransferPageSpace: Zero replacement");'''),
]

TRACESD = [
    ('''static	boolean			DigiMissed,DigiLastSegment;''', '''void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
static	boolean			DigiMissed,DigiLastSegment;'''),
    ('''	DigiPage = DigiList[(which * 2) + 0];''', '''	{
		static char far f[] = "D %d";
		Trace (f,which);
	}
	DigiPage = DigiList[(which * 2) + 0];'''),
    ('''	addr = PM_GetSoundPage(page);
	PM_SetPageLock(PMSoundStart + page,pml_Locked);''', '''	addr = PM_GetSoundPage(page);
	{
		static char far f[] = "d %d %x";
		Trace (f,page,(unsigned)addr);
	}
	PM_SetPageLock(PMSoundStart + page,pml_Locked);'''),
]

TRACESC = [
    ('''EXTRN	PM_GetPage:FAR''', '''EXTRN	PM_GetPage:FAR
EXTRN	TraceShape:FAR				; TEST --trace (WL_NET.C)
EXTRN	TraceSeg:FAR'''),
    ('''@@onceback:
	push	bp
	mov	bp,sp
	push	si
	push	di
''', '''@@onceback:
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	[WORD bp+10]			; TEST --trace: height
	push	[WORD bp+8]				; shapenum
	call	TraceShape
	add	sp,4
'''),
    ('''	mov	[shapeseg],ax
	mov	[WORD linecmds+2],ax	; seg of shape''', '''	mov	[shapeseg],ax
	push	ax						; TEST --trace: its segment
	push	ax
	call	TraceSeg
	add	sp,2
	pop	ax
	mov	[WORD linecmds+2],ax	; seg of shape'''),
]


# --nodigi9: no digitized sound from the ninth floor on (with --trace, which
# turns on there) -- everything else the same, for an A/B on the 486's crash
NODIGI9 = [('''	if (!DigiMode)
		return;

	SD_StopDigitized();
	if (which >= NumDigi)''', '''	if (!DigiMode)
		return;
	{								// TEST --nodigi9
		extern int tracing;
		static char far f[] = "D- %d";

		if (tracing)
		{
			Trace (f,which);
			return;
		}
	}

	SD_StopDigitized();
	if (which >= NumDigi)''')]


# the stack's low-water mark (always in a test build)
STACKMARK = [('''void		*nearheap;''', '''void		*nearheap;
unsigned	stackfloor;				// TEST: the near heap's end (huntbot.py)'''),
    ('''	MML_UseSpace (segstart,seglength);
	mminfo.nearheap = length;''', '''	MML_UseSpace (segstart,seglength);
	mminfo.nearheap = length;
	{								// TEST: the stack's reserve, marked
		byte	*p;

		stackfloor = (segstart+seglength-_DS)*16;
		for (p = (byte *)stackfloor;(unsigned)p < _SP-64;p++)
			*p = 0xAA;
	}'''),
    ('''void MML_ClearBlock (void)
{''', '''//
// TEST: the lowest address the stack has reached since MM_Startup marked
// its reserve (stackfloor itself: it got to the near heap's top)
//
unsigned StackLow (void)
{
	byte	*p = (byte *)stackfloor;

	while (*p == 0xAA && (unsigned)p < _SP)
		p++;
	return (unsigned)p;
}

void MML_ClearBlock (void)
{''')]


# --trace: the out-of-memory paths -- id's "size the view down" in MM_GetPtr,
# the scalers rebuilt, and Quit's message
TRACEOOM_MM = [('''void		*nearheap;''', '''void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
void		*nearheap;'''),
    ('''			viewsize -= 2;''', '''			{
				static char far f[] = "HACK view %d need %u";
				Trace (f,viewsize,needed);
			}
			viewsize -= 2;''')]
TRACEOOM_MAIN = [('''void Quit (char *error)
{''', '''void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
void Quit (char *error)
{'''),
    ('''	if (virtualreality)
		geninterrupt(0x61);''', '''	{
		static char far f[] = "QUIT %s";
		Trace (f,error);
	}
	if (virtualreality)
		geninterrupt(0x61);''')]
TRACEOOM_SCALE = [('''void SetupScaling (int maxscaleheight)
{''', '''void Trace (char far *fmt, ...);	// TEST --trace (WL_NET.C)
void SetupScaling (int maxscaleheight)
{'''),
    ('''	insetupscaling = true;''', '''	insetupscaling = true;
	{
		static char far f[] = "SS %d view %d";
		Trace (f,maxscaleheight,viewsize);
	}'''),
    ('''	insetupscaling = false;''', '''	{
		static char far f[] = "ss";
		Trace (f);
	}
	insetupscaling = false;''')]


def main():
    if "--restore" in sys.argv:
        restore()
        return 0
    if any(os.path.exists(keep(f)) for f in FILES):
        raise SystemExit("stage/*.keep exist: a run did not finish -- check them, then --restore")
    quit = sys.argv[sys.argv.index("--quit")+1] if "--quit" in sys.argv else "5"
    mp = [(a, b.replace("QUITAT", quit)) for a, b in MP] + CHECK
    if "--leak" in sys.argv:
        mp += LEAK
    trace = "--trace" in sys.argv
    if trace:
        mp += TRACEMP
    try:
        if "--memonly" not in sys.argv:
            patch("WL_MP.C", mp)
        patch("WL_MAIN.C", MAIN + (TRACEOOM_MAIN if "--trace" in sys.argv else []))
        if "--memonly" not in sys.argv:
            patch("WL_NET.C", NET + (TRACENET if trace else []))
            patch("WL_NETA.ASM", NETA)
            patch("ID_SD.C", SD + (TRACESD if trace else [])
                  + (NODIGI9 if "--nodigi9" in sys.argv else []))
            patch("ID_MM.C", MM + STACKMARK + (TRACEOOM_MM if trace else []))
            if trace:
                patch("WL_SCALE.C", TRACEOOM_SCALE)
            patch("ID_CA.C", CA)
            patch("ID_PM.C", PM + (TRACEPM if trace else []))
            if trace:
                patch("WL_SC_A.ASM", TRACESC)
            patch("TURBOC.CFG", CFG)
            patch("LINK86.RSP", RSP)
        # the patched sources, for reading a trace's line numbers against
        keepsrc = os.path.join(STAGE, "wolf3dt-src")
        os.makedirs(keepsrc, exist_ok=True)
        for f in FILES:
            if os.path.exists(keep(f)):
                shutil.copyfile(os.path.join(SRC, f), os.path.join(keepsrc, f))
        for f in ("WOLF3DV.EXE", "WOLF3DV.MAP"):
            if os.path.exists(os.path.join(SRC, f)):
                shutil.copyfile(os.path.join(SRC, f), os.path.join(STAGE, "real-" + f))
        rc = subprocess.call([sys.executable, os.path.join(ROOT, "w3dbuild.py"), "build"], cwd=ROOT)
    finally:
        restore()
    if not rc:
        shutil.copyfile(os.path.join(SRC, "WOLF3DV.EXE"), os.path.join(STAGE, "WOLF3DT.EXE"))
        shutil.copyfile(os.path.join(SRC, "WOLF3DV.MAP"), os.path.join(STAGE, "WOLF3DT.MAP"))
    # the real EXE back where it was, whatever happened
    for f in ("WOLF3DV.EXE", "WOLF3DV.MAP"):
        if os.path.exists(os.path.join(STAGE, "real-" + f)):
            shutil.copyfile(os.path.join(STAGE, "real-" + f), os.path.join(SRC, f))
            os.remove(os.path.join(STAGE, "real-" + f))
    if rc:
        return rc
    print("stage/WOLF3DT.EXE, stage/WOLF3DT.MAP")
    return 0


if __name__ == "__main__":
    sys.exit(main())
