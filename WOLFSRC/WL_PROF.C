// WL_PROF.C -- a sampling profiler for the NEC V30 work
// StevenC & Claude, 2026
//
// WOLF3DV TIMEDEMO PROFILE samples where the CPU is, every timer interrupt,
// for the whole of each demo's play loop, and writes the histogram to
// PROF.BIN.  profmap.py (beside WOLFSRC) turns that into per-function time
// using WOLF3DV.MAP.
//
// Every code segment of this medium-model program is loaded at a fixed
// paragraph offset from the load segment (_psp+10h), which is exactly the
// address space the link map is written in -- so an interrupted CS:IP maps
// straight to a map address with no symbol lookup on the DOS side.
//
// What it cannot see: the sound manager's own timer ISR (sampling happens
// at interrupt entry, with interrupts off, so ISR time is never sampled),
// and it adds its own cost -- roughly a hundred clocks per interrupt.  Time
// a run with PROFILE and without before trusting absolute numbers.

#include "WL_DEF.H"
#pragma hdrstop

#define PROFSHIFT	4				// 16-byte buckets: seg + ip>>4, exact in 16 bits
#define PROFMAX		9216			// 147,456 bytes: all of the code, with room

boolean				profiling;

static	memptr		profmem;
static	unsigned long far *prof;
static	unsigned long	profother[3];	// 0 below the program (DOS, TSRs, drivers)
									// 1 above the code (the compiled scalers live
									//   in the heap)   2 ROM / BIOS (A000h up)
static	unsigned	profbase;
static	void interrupt (*profold)(void);
static	boolean		profhooked;


/*
===================
=
= ProfISR
=
= Classify the interrupted CS:IP and pass the interrupt on.  The bucket is
= ((cs-base)*16+ip)>>4, which is exactly (cs-base) + (ip>>4).
=
===================
*/

#pragma warn -par
static void interrupt ProfISR (unsigned bp, unsigned di, unsigned si,
	unsigned ds, unsigned es, unsigned dx, unsigned cx, unsigned bx,
	unsigned ax, unsigned ip, unsigned cs, unsigned flags)
{
	unsigned	seg,b;

	if (cs >= 0xa000)
		profother[2]++;
	else if (cs < profbase)
		profother[0]++;
	else
	{
		seg = cs - profbase;
		b = seg + (ip>>4);
		if (seg < PROFMAX && b < PROFMAX)
			prof[b]++;
		else
			profother[1]++;
	}
	profold ();
}
#pragma warn .par


/*
===================
=
= ProfInit
=
= Take the histogram out of the game's own memory manager, locked so it
= neither moves nor purges.  Only when PROFILE was asked for.
=
===================
*/

void ProfInit (void)
{
	if (!MS_CheckParm ("profile"))
		return;

	MM_GetPtr (&profmem,PROFMAX*4L);
	MM_SetLock (&profmem,true);
	prof = (unsigned long far *)profmem;
	_fmemset (prof,0,PROFMAX*4U);
	profbase = _psp + 0x10;
	profiling = true;
}


/*
===================
=
= ProfStart / ProfStop
=
= Around each play loop.  The sound manager rewrites INT 8 whenever the
= music mode changes, so the hook goes in after StartMusic and comes out
= before anything else can touch the vector.
=
===================
*/

void ProfStart (void)
{
	if (!profiling || profhooked)
		return;
	asm	pushf
	asm	cli
	profold = getvect (8);
	setvect (8,ProfISR);
	profhooked = true;
	asm	popf
}

void ProfStop (void)
{
	if (!profhooked)
		return;
	asm	pushf
	asm	cli
	setvect (8,profold);
	profhooked = false;
	asm	popf
}


/*
===================
=
= ProfWrite
=
= PROF.BIN: "WPRF", bucket shift, bucket count, the three outside counts,
= then the buckets.  All little-endian, no padding.  Returns the number of
= samples, or 0 if nothing was written.  Call it BEFORE ShutdownId, which
= hands the histogram's memory back to DOS.
=
===================
*/

unsigned long ProfWrite (void)
{
	int			handle;
	unsigned	n;
	unsigned	hdr[2];
	unsigned long	total;
	int			i;

	if (!profiling)
		return 0;
	ProfStop ();

	if (_dos_creat ("PROF.BIN",0,&handle))
		return 0;
	hdr[0] = PROFSHIFT;
	hdr[1] = PROFMAX;
	_dos_write (handle,(void far *)"WPRF",4,&n);
	_dos_write (handle,(void far *)hdr,sizeof(hdr),&n);
	_dos_write (handle,(void far *)profother,sizeof(profother),&n);
	_dos_write (handle,(void far *)prof,PROFMAX*4U,&n);
	_dos_close (handle);

	total = profother[0]+profother[1]+profother[2];
	for (i=0;i<PROFMAX;i++)
		total += prof[i];
	return total;
}
