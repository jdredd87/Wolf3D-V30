// WL_BSP.C -- the BSP version (branch bsp), StevenC & Claude, 2026.
//
// Milestone 1 (BSPNOTES.md): the level's wall runs and a BSP over them,
// built when the level is set up.  Nothing draws from it yet.
//
// A run is a stretch of wall faces along one grid line, all facing the same
// way: every face between a solid tile and an open one (a door tile counts
// as open for now).  The BSP splits on grid lines; the line for each node is
// the one that best balances the runs on either side against the runs it
// cuts (|low - high| + 3 x cuts, as step 86's mkbsp.py), found for all 64
// candidate lines of both axes at once from per-coordinate counts -- O(n)
// a node, not O(n^2) -- and a run that crosses it is cut in two.  The runs
// lying on a node's line are kept with the node, in the order a front-to-
// back walk will meet them.
//
// Memory: built in a temporary block, then copied into one of exactly the
// size it needs.  All of this module's state is far data; DGROUP pays only
// the two block handles.

#include "WL_DEF.H"
#include <string.h>
#pragma hdrstop

#define MAXRUNS		3000
#define MAXLIST		7000
#define MAXNODES	2000

typedef struct
{
	byte	of;				// bit 0: 0 a line x = line (runs along y), 1 y = line;
							// bit 1: the open side is the higher coordinate
	byte	line, a1, a2;	// the run covers a1 .. a2-1 along its line
} bsprun;

typedef struct
{
	byte		axis, coord;	// splits on x = coord (axis 0) or y = coord (1)
	int			lo, hi;			// the children, -1 for none
	unsigned	first;			// its runs, in bspruns
	byte		count;
	byte		x1, y1, x2, y2;	// the bounding box of everything below it
} bspnode;

memptr	bsptemp, bsptree;		// DGROUP: the only cost there

typedef struct
{
	bsprun		far *r;			// runs while building, cuts appended
	unsigned	far *list;		// index lists, used like a stack
	bsprun		far *f;			// runs in node order
	bspnode		far *n;			// nodes, in preorder
	unsigned	nr, top, nf, nn, cuts, maxdepth, fail;
	bsprun		far *runs;		// the finished tree, in bsptree
	bspnode		far *nodes;
	unsigned	numruns, numnodes;
} bspbuild;

bspbuild	far bb;				// far data: a pointer here is 4 bytes of DGROUP

typedef struct
{
	unsigned	map, runs, cuts, nodes, depth, bytes, ticks, talloc, tfind, tbuild;
} bsplogent;

bsplogent	far bsplog[8];
int			far bsplogn;

char far bspfmt[] = "bsp: floor %2u  %4u runs (%u cut)  %4u nodes  depth %2u  %5u bytes  %u ticks (alloc %u, runs %u, tree %u)\n";
char far bspfail[] = "bsp: floor %2u  NOT BUILT -- more runs or nodes than it has room for\n";

static void AddRun (int of, int line, int a1, int a2)
{
	bsprun	far *r;

	if (bb.nr >= MAXRUNS)
	{
		bb.fail = 1;
		return;
	}
	r = &bb.r[bb.nr++];
	r->of = of;
	r->line = line;
	r->a1 = a1;
	r->a2 = a2;
}

//
// every wall face between a solid tile and an open one, merged into runs.
// tilemap is scanned directly -- a column of it is 64 bytes in a row -- as
// an edge code a pair: 0 no face, 1 the high side solid (the face looks
// down), 2 the low side solid (it looks up).  (A first version called a
// bounds-checking Solid() four times a cell: a second of the V30's load.)
//
#define SOLID(t)	((t) && !((t) & 0x80))
#define EDGE(lo,hi)	(SOLID(lo) ? (SOLID(hi) ? 0 : 2) : (SOLID(hi) ? 1 : 0))

static void FindRuns (void)
{
	int		x, y, start, code;
	byte	*a, *b;

	for (x = 1; x < MAPSIZE; x++)			// lines x = constant: columns x-1, x
	{
		a = tilemap[x-1];
		b = tilemap[x];
		for (y = 0; y < MAPSIZE; )
		{
			code = EDGE(a[y],b[y]);
			if (!code)
			{
				y++;
				continue;
			}
			start = y;
			do
				y++;
			while (y < MAPSIZE && EDGE(a[y],b[y]) == code);
			AddRun (code == 2 ? 2 : 0, x, start, y);
		}
	}
	for (y = 1; y < MAPSIZE; y++)			// lines y = constant: rows y-1, y
		for (x = 0; x < MAPSIZE; )
		{
			a = &tilemap[x][y-1];
			code = EDGE(a[0],a[1]);
			if (!code)
			{
				x++;
				continue;
			}
			start = x;
			do
			{
				x++;
				a += MAPSIZE;
			}
			while (x < MAPSIZE && EDGE(a[0],a[1]) == code);
			AddRun (1 | (code == 2 ? 2 : 0), y, start, x);
		}
}

//
// ChooseSplit: the line for a node over bb.list[base .. base+count-1] --
// |below - above| + 3 x cut, least, over every line of both axes within the
// runs' extent.  Its counts are near, on the stack, and it returns before
// Build recurses, so one frame of them is all the stack ever holds (a first
// version kept them in Build's own frame and overran the stack 15 levels
// down; a second kept them far, and the V30 took 15 s a tree on far
// accesses).
//
static void ChooseSplit (unsigned base, unsigned count, int *paxis, int *pc)
{
	byte		par0[MAPSIZE+1], par1[MAPSIZE+1], ends0[MAPSIZE+1], ends1[MAPSIZE+1];
	byte		starts0[MAPSIZE+1], starts1[MAPSIZE+1];
	byte		*pa, *pe, *ps;		// bytes: a line holds at most 32 runs, a coordinate
								// starts or ends at most 64 -- as ints this frame was
								// 780 bytes, which with Build 15 deep overran the
								// game's 4 KB stack (both machines hung)
	int			lo0, hi0, lo1, hi1, ptot0, ptot1, totpar0, totpar1;
	int			axis, c, lo, hi, ptot, totpar, below, above, cut, best, k;
	int			lowpar, endsle, startsge;
	unsigned	i;
	bsprun		far *R = bb.r, far *r;
	unsigned	far *L = bb.list + base;

	memset (par0,0,sizeof(par0));
	memset (par1,0,sizeof(par1));
	memset (ends0,0,sizeof(ends0));
	memset (ends1,0,sizeof(ends1));
	memset (starts0,0,sizeof(starts0));
	memset (starts1,0,sizeof(starts1));
	lo0 = lo1 = MAPSIZE;
	hi0 = hi1 = 0;
	ptot0 = ptot1 = totpar0 = totpar1 = 0;
	for (i = 0; i < count; i++)
	{
		r = R + L[i];
		if (r->of & 1)
		{									// y = line: along axis 1, across axis 0
			par1[r->line]++;
			totpar1++;
			if (r->line < lo1) lo1 = r->line;
			if (r->line > hi1) hi1 = r->line;
			starts0[r->a1]++;
			ends0[r->a2]++;
			ptot0++;
			if (r->a1 < lo0) lo0 = r->a1;
			if (r->a2 > hi0) hi0 = r->a2;
		}
		else
		{
			par0[r->line]++;
			totpar0++;
			if (r->line < lo0) lo0 = r->line;
			if (r->line > hi0) hi0 = r->line;
			starts1[r->a1]++;
			ends1[r->a2]++;
			ptot1++;
			if (r->a1 < lo1) lo1 = r->a1;
			if (r->a2 > hi1) hi1 = r->a2;
		}
	}

	best = 0x7fff;
	*paxis = *pc = 0;
	for (axis = 0; axis < 2; axis++)
	{
		if (axis)
		{
			pa = par1;  pe = ends1;  ps = starts1;
			lo = lo1;  hi = hi1;  ptot = ptot1;  totpar = totpar1;
		}
		else
		{
			pa = par0;  pe = ends0;  ps = starts0;
			lo = lo0;  hi = hi0;  ptot = ptot0;  totpar = totpar0;
		}
		if (!totpar)
			continue;
		lowpar = endsle = 0;
		startsge = ptot;
		// (no run starts or ends below lo: it is the least coordinate of all)
		for (c = lo; c <= hi; c++)
		{
			endsle += pe[c];					// runs across with a2 <= c ...
			if (c)
				startsge -= ps[c-1];			// ... and with a1 >= c
			if (pa[c])
			{
				below = lowpar + endsle;
				above = totpar - lowpar - pa[c] + startsge;
				cut = ptot - endsle - startsge;
				k = (below > above ? below - above : above - below) + 3*cut;
				if (k < best)
				{
					best = k;
					*paxis = axis;
					*pc = c;
				}
			}
			lowpar += pa[c];
		}
	}
}

//
// Build: a node over the runs bb.list[base .. base+count-1]; -1 for none
//
static int Build (unsigned base, unsigned count, int depth)
{
	int			axis, c, x1, y1, x2, y2, bx1, by1, bx2, by2;
	unsigned	i, k, ri, lowbase, highbase, nlow, nhigh, me, oncount;
	bsprun		far *r, far *R;
	bspnode		far *n;
	unsigned	far *L, far *LL;

	if (!count || bb.fail)
		return -1;
	if (depth > bb.maxdepth)
		bb.maxdepth = depth;
	ChooseSplit (base,count,&axis,&c);
	R = bb.r;							// the far pointers once: each bb.x
	LL = bb.list;						// reloads bb's segment
	L = LL + base;

	if (bb.nn >= MAXNODES)
	{
		bb.fail = 1;
		return -1;
	}
	me = bb.nn++;

	//
	// how many go below the line and how many above (a run across it, both)
	//
	nlow = nhigh = 0;
	for (i = 0; i < count; i++)
	{
		r = R + L[i];
		if ((r->of & 1) == axis)
		{
			if (r->line < c)
				nlow++;
			else if (r->line > c)
				nhigh++;
		}
		else if (r->a2 <= c)
			nlow++;
		else if (r->a1 >= c)
			nhigh++;
		else
		{
			nlow++;
			nhigh++;
		}
	}
	lowbase = bb.top;
	highbase = lowbase + nlow;
	if (highbase + nhigh > MAXLIST)
	{
		bb.fail = 1;
		return -1;
	}
	bb.top = highbase + nhigh;

	//
	// sort them there, the runs on the line into the node, cutting the runs
	// across it; the bounding box in locals, written once
	//
	n = &bb.n[me];
	n->first = bb.nf;
	bx1 = by1 = 255;
	bx2 = by2 = 0;
	oncount = 0;
	nlow = nhigh = 0;
	for (i = 0; i < count; i++)
	{
		ri = L[i];
		r = R + ri;
		if (r->of & 1)
		{
			x1 = r->a1;  x2 = r->a2;  y1 = y2 = r->line;
		}
		else
		{
			y1 = r->a1;  y2 = r->a2;  x1 = x2 = r->line;
		}
		if (x1 < bx1) bx1 = x1;
		if (y1 < by1) by1 = y1;
		if (x2 > bx2) bx2 = x2;
		if (y2 > by2) by2 = y2;

		if ((r->of & 1) == axis)
		{
			if (r->line < c)
				LL[lowbase + nlow++] = ri;
			else if (r->line > c)
				LL[highbase + nhigh++] = ri;
			else
			{
				bb.f[bb.nf++] = *r;			// on the line: the node's own
				oncount++;
			}
		}
		else if (r->a2 <= c)
			LL[lowbase + nlow++] = ri;
		else if (r->a1 >= c)
			LL[highbase + nhigh++] = ri;
		else
		{
			if (bb.nr >= MAXRUNS)			// cut in two at the line
			{
				bb.fail = 1;
				return -1;
			}
			k = bb.nr++;
			R[k] = *r;
			R[k].a1 = c;
			r->a2 = c;
			LL[lowbase + nlow++] = ri;
			LL[highbase + nhigh++] = k;
			bb.cuts++;
		}
	}
	n->axis = axis;
	n->coord = c;
	n->count = oncount;
	n->x1 = bx1;
	n->y1 = by1;
	n->x2 = bx2;
	n->y2 = by2;

	k = Build (lowbase, nlow, depth+1);
	bb.n[me].lo = k;
	k = Build (highbase, nhigh, depth+1);
	bb.n[me].hi = k;
	bb.top = lowbase;
	return me;
}

/*
=====================
=
= BuildBSP
=
= Called by SetupGameLevel once the tile map is final
=
=====================
*/

void BuildBSP (void)
{
	long		t0, t1, t2, t3;
	unsigned	i, bytes;
	bsplogent	far *l;

	t0 = BiosTicks ();
	if (bsptree)
	{
		MM_FreePtr (&bsptree);
		bsptree = 0;
	}
	MM_GetPtr (&bsptemp,(long)MAXRUNS*sizeof(bsprun)*2 + (long)MAXLIST*2
		+ (long)MAXNODES*sizeof(bspnode));
	MM_SetLock (&bsptemp,true);
	t1 = BiosTicks ();
	bb.r = (bsprun far *)bsptemp;
	bb.f = bb.r + MAXRUNS;
	bb.list = (unsigned far *)(bb.f + MAXRUNS);
	bb.n = (bspnode far *)(bb.list + MAXLIST);
	bb.nr = bb.top = bb.nf = bb.nn = bb.cuts = bb.maxdepth = bb.fail = 0;

	FindRuns ();
	t2 = BiosTicks ();
	for (i = 0; i < bb.nr; i++)
		bb.list[i] = i;
	bb.top = bb.nr;
	Build (0,bb.nr,1);
	t3 = BiosTicks ();

	bb.numruns = bb.numnodes = 0;
	bytes = 0;
	if (!bb.fail)
	{
		bytes = bb.nf*sizeof(bsprun) + bb.nn*sizeof(bspnode);
		MM_GetPtr (&bsptree,bytes);
		MM_SetLock (&bsptree,true);
		bb.runs = (bsprun far *)bsptree;
		bb.nodes = (bspnode far *)(bb.runs + bb.nf);
		_fmemcpy (bb.runs,bb.f,bb.nf*sizeof(bsprun));
		_fmemcpy (bb.nodes,bb.n,bb.nn*sizeof(bspnode));
		bb.numruns = bb.nf;
		bb.numnodes = bb.nn;
	}
	MM_FreePtr (&bsptemp);

	if (bsplogn < 8)
	{
		l = &bsplog[bsplogn++];
		l->map = gamestate.mapon + 10*gamestate.episode + 1;
		l->runs = bb.fail ? 0xffff : bb.nf;
		l->cuts = bb.cuts;
		l->nodes = bb.nn;
		l->depth = bb.maxdepth;
		l->bytes = bytes;
		l->ticks = (unsigned)(BiosTicks () - t0);
		l->talloc = (unsigned)(t1 - t0);
		l->tfind = (unsigned)(t2 - t1);
		l->tbuild = (unsigned)(t3 - t2);
	}
}

/*
=====================
=
= BSPReport
=
= TIMEDEMO: a line for each tree built.  The format strings are far data,
= copied to the stack for printf -- DGROUP has no room for them.
=
=====================
*/

void BSPReport (void)
{
	char		fmt[160];			// longer than any format here (a 100-byte one
								// overflowed, and the V30 hung on the return)
	int			i;
	bsplogent	far *l;

	for (i = 0; i < bsplogn; i++)
	{
		l = &bsplog[i];
		if (l->runs == 0xffff)
		{
			if (_fstrlen (bspfail) >= sizeof(fmt))
				return;
			_fstrcpy ((char far *)fmt,bspfail);
			printf (fmt,l->map);
		}
		else
		{
			if (_fstrlen (bspfmt) >= sizeof(fmt))
				return;
			_fstrcpy ((char far *)fmt,bspfmt);
			printf (fmt,l->map,l->runs,l->cuts,l->nodes,l->depth,l->bytes,l->ticks,
				l->talloc,l->tfind,l->tbuild);
		}
	}
}
