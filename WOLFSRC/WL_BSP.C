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
#include <dos.h>
#include <io.h>
#include <fcntl.h>
#pragma hdrstop

#define MAXRUNS		2000		// the most of 60 maps: 1,198 and 145 cut (the
							// level's memory is tight: these are borrowed
							// from it at load; too many and the walk draws)
#define MAXLIST		7000
#define MAXNODES	1400		// the most: 987

typedef struct
{
	byte	of;				// bit 0: 0 a line x = line (runs along y), 1 y = line;
							// bit 1: the open side is the higher coordinate;
							// bit 2: a block's face, drawn only while one
							// stands in its tile (pushwalls)
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
long	far st_frames, far st_nodes, far st_culled, far st_runs, far st_hidden, far st_boxhid, far st_pwframes,
		far st_left;					// renderer counts, for BSPReport
int		far st_lframe = -1, far st_lmax, far st_lfirst, far st_llast, far st_lnone;
char far bspstat[] = "bsp: %ld frames from the tree, a frame: %ld nodes (%ld culled, %ld hidden), %ld runs (%ld hidden), %ld columns left to the fill\n";
char far bspstat2[] = "bsp: most left %d at frame %d (claimed %d..%d); %d frames none; %ld frames a wall moved\n";
char far bspfmtc[] = "bsp: floor %2u  %4u runs (%u cut)  %4u nodes  depth %2u  %5u bytes  %u ticks, read from BSPCACHE.WL6\n";
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
//
// ChooseSplit's counts, a byte a coordinate (a line holds at most 32 runs, a
// coordinate starts or ends at most 64).  As ints in its frame they were 780
// bytes, which with Build 15 deep overran the game's 4 KB stack; as bytes
// there, 390, and the pushwalls' faces made map 52's tree deeper still (the
// 486 hung loading it, with the walk as much as the tree).  ChooseSplit is
// never re-entered, so they are far statics now: no stack at all.
//
byte	far par0[MAPSIZE+1], far par1[MAPSIZE+1], far ends0[MAPSIZE+1],
		far ends1[MAPSIZE+1], far starts0[MAPSIZE+1], far starts1[MAPSIZE+1];

static void ChooseSplit (unsigned base, unsigned count, int *paxis, int *pc)
{
	byte		far *pa, far *pe, far *ps;
	int			lo0, hi0, lo1, hi1, ptot0, ptot1, totpar0, totpar1;
	int			axis, c, lo, hi, ptot, totpar, below, above, cut, best, k;
	int			lowpar, endsle, startsge;
	unsigned	i;
	bsprun		far *R = bb.r, far *r;
	unsigned	far *L = bb.list + base;

	_fmemset (par0,0,sizeof(par0));
	_fmemset (par1,0,sizeof(par1));
	_fmemset (ends0,0,sizeof(ends0));
	_fmemset (ends1,0,sizeof(ends1));
	_fmemset (starts0,0,sizeof(starts0));
	_fmemset (starts1,0,sizeof(starts1));
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
	if (depth > 24)						// (deeper than any map: the walk draws it,
	{									// rather than the stack running out)
		bb.fail = 1;
		return -1;
	}
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

//
// Pushwalls (milestone 4).  A pushable block moves, and the tiles it
// leaves open up for good: a tree built at load cannot follow it.  So the
// tree is built with every pushable tile open -- the walls around it are in
// the tree -- and every tile a block can be in (the pushable tile, and the
// open ones within two tiles of it, the farthest a push goes) gets its four
// faces in the tree as well, each drawn only while a block stands there
// (DrawRun).  The block on the move is drawn by itself, over the walls
// wherever it is nearer.  (The first version drew every standing block
// that way too, so the tree drew the secret behind each one first: the
// walls twice, and no occlusion -- two thirds of the walk's speed beside
// pushwalls on the V30.)
//
#define MAXPCAND	256

byte	far pcand[MAXPCAND][2];
byte	far psave[MAXPCAND];		// a pushable tile's wall, during the build
int		far npcand;

static void AddCand (int x, int y)
{
	int		i;

	for (i = 0; i < npcand; i++)
		if (pcand[i][0] == x && pcand[i][1] == y)
			return;
	if (npcand < MAXPCAND)
	{
		pcand[npcand][0] = x;
		pcand[npcand][1] = y;
		npcand++;
	}
}

static void FindPushwalls (void)
{
	int		x, y, d, k, tx, ty, i;

	npcand = 0;
	for (y = 0; y < MAPSIZE; y++)
		for (x = 0; x < MAPSIZE; x++)
			if (*(mapsegs[1]+farmapylookup[y]+x) == PUSHABLETILE
				&& SOLID(tilemap[x][y]))
				AddCand (x,y);
	for (i = npcand-1; i >= 0; i--)			// (the pushable ones come first)
	{
		x = pcand[i][0];
		y = pcand[i][1];
		for (d = 0; d < 4; d++)
			for (k = 1; k <= 2; k++)
			{
				tx = x + (d == 1 ? k : (d == 3 ? -k : 0));
				ty = y + (d == 2 ? k : (d == 0 ? -k : 0));
				if (tx < 1 || ty < 1 || tx >= MAPSIZE-1 || ty >= MAPSIZE-1
					|| SOLID(tilemap[tx][ty]) || (tilemap[tx][ty] & 0x80))
					break;
				AddCand (tx,ty);
			}
	}
}

//
// the candidates' faces, as runs of one tile marked as a block's: on every
// side where the next tile is open at load, or a candidate itself
//
static int OpenAtLoad (int x, int y)
{
	int		i;

	if (!SOLID(tilemap[x][y]))
		return 1;
	for (i = 0; i < npcand; i++)
		if (pcand[i][0] == x && pcand[i][1] == y)
			return 1;
	return 0;
}

static void AddBlockFaces (void)
{
	int		i, x, y;

	for (i = 0; i < npcand; i++)
	{
		x = pcand[i][0];
		y = pcand[i][1];
		if (OpenAtLoad (x-1,y))
			AddRun (4|0,x,y,y+1);			// west: looks to lower x
		if (OpenAtLoad (x+1,y))
			AddRun (4|2,x+1,y,y+1);			// east
		if (OpenAtLoad (x,y-1))
			AddRun (4|1,y,x,x+1);			// north
		if (OpenAtLoad (x,y+1))
			AddRun (4|1|2,y+1,x,x+1);		// south
	}
}

//
// The tree cache (StevenC & Claude).  A map's tree depends on nothing but
// the map, and building it took the V30 up to four seconds at "Get Psyched"
// (floor 38: 71 ticks), so each map's is built once and kept in
// BSPCACHE.WL6, beside the game: a header, an index of 64 maps, then the
// trees, 2-18 KB each.  An entry's key is a hash of the level's tilemap at
// load -- doors, pushable walls and all -- and its floor, and the header
// carries BSPCACHEVER: change the builder and the version, and every tree
// is built again.  A file that cannot be read or written costs nothing but
// the build; delete it at any time.
//
#define BSPCACHEVER	1
#define CACHESLOTS	64

typedef struct
{
	long		key;			// 0: a free slot
	long		offset;			// the runs, then the nodes
	unsigned	runs, nodes, cuts, depth;
} bspslot;

char far bspcachename[] = "BSPCACHE.WL6";

static long TreeKey (void)
{
	unsigned long	h = BSPCACHEVER;
	byte			far *t = &tilemap[0][0];
	unsigned		i;

	for (i = 0; i < MAPSIZE*MAPSIZE; i++)
		h = h*33 + t[i];
	h = h*33 + gamestate.mapon + 10*gamestate.episode;
	return h ? (long)h : 1;
}

static int CacheOpen (int create)
{
	char		name[16];
	int			h;
	unsigned	n;
	long		head[2];
	bspslot		empty;
	int			i;

	_fstrcpy ((char far *)name,bspcachename);
	if (!_dos_open (name,O_RDWR,&h))
	{
		if (!_dos_read (h,(void far *)head,sizeof(head),&n) && n == sizeof(head)
			&& head[0] == 0x43505342L && head[1] == BSPCACHEVER)	// "BSPC"
			return h;
		_dos_close (h);
		if (!create)
			return -1;
	}
	else if (!create)
		return -1;
	if (_dos_creat (name,0,&h))			// new, or another version's: started
		return -1;						// again
	head[0] = 0x43505342L;
	head[1] = BSPCACHEVER;
	memset (&empty,0,sizeof(empty));
	if (_dos_write (h,(void far *)head,sizeof(head),&n) || n != sizeof(head))
	{
		_dos_close (h);
		return -1;
	}
	for (i = 0; i < CACHESLOTS; i++)
		if (_dos_write (h,(void far *)&empty,sizeof(empty),&n) || n != sizeof(empty))
		{
			_dos_close (h);
			return -1;
		}
	return h;
}

//
// the slot holding key, or (want 0) the first free one; -1 for none.  The
// slot is left in *e and the file positioned after it
//
static int CacheFind (int h, long key, bspslot *e)
{
	int			i;
	unsigned	n;

	lseek (h,8L,SEEK_SET);
	for (i = 0; i < CACHESLOTS; i++)
	{
		if (_dos_read (h,(void far *)e,sizeof(*e),&n) || n != sizeof(*e))
			return -1;
		if (e->key == key)
			return i;
	}
	return -1;
}

static int CacheLoad (long key)
{
	int			h;
	unsigned	bytes, n;
	bspslot		e;

	if ((h = CacheOpen (0)) < 0)
		return 0;
	if (CacheFind (h,key,&e) < 0 || !e.runs || !e.nodes)
	{
		_dos_close (h);
		return 0;
	}
	bytes = e.runs*sizeof(bsprun) + e.nodes*sizeof(bspnode);
	MM_GetPtr (&bsptree,bytes);
	MM_SetLock (&bsptree,true);
	lseek (h,e.offset,SEEK_SET);
	if (_dos_read (h,(void far *)bsptree,bytes,&n) || n != bytes)
	{
		_dos_close (h);
		MM_FreePtr (&bsptree);
		bsptree = 0;
		return 0;
	}
	_dos_close (h);
	bb.runs = (bsprun far *)bsptree;
	bb.nodes = (bspnode far *)(bb.runs + e.runs);
	bb.numruns = e.runs;
	bb.numnodes = e.nodes;
	bb.cuts = e.cuts;
	bb.maxdepth = e.depth;
	return 1;
}

static void CacheSave (long key)
{
	int			h, slot;
	unsigned	bytes, n;
	bspslot		e;

	if ((h = CacheOpen (1)) < 0)
		return;
	if ((slot = CacheFind (h,0,&e)) >= 0)
	{
		bytes = bb.numruns*sizeof(bsprun) + bb.numnodes*sizeof(bspnode);
		e.key = key;
		e.offset = lseek (h,0L,SEEK_END);
		e.runs = bb.numruns;
		e.nodes = bb.numnodes;
		e.cuts = bb.cuts;
		e.depth = bb.maxdepth;
		if (!_dos_write (h,(void far *)bb.runs,bytes,&n) && n == bytes)
		{
			lseek (h,8L + (long)slot*sizeof(bspslot),SEEK_SET);
			_dos_write (h,(void far *)&e,sizeof(e),&n);	// the slot last: a
		}											// short write leaves it free
	}
	_dos_close (h);
}

void BuildBSP (void)
{
	long		t0, t1, t2, t3, key;
	unsigned	i, bytes;
	int			np;
	bsplogent	far *l;

	t0 = BiosTicks ();
	if (bsptree)
	{
		MM_FreePtr (&bsptree);
		bsptree = 0;
	}
	key = TreeKey ();
	if (CacheLoad (key))
	{
		if (bsplogn < 8)
		{
			l = &bsplog[bsplogn++];
			l->map = gamestate.mapon + 10*gamestate.episode + 1;
			l->runs = bb.numruns;
			l->cuts = bb.cuts;
			l->nodes = bb.numnodes;
			l->depth = bb.maxdepth;
			l->bytes = bb.numruns*sizeof(bsprun) + bb.numnodes*sizeof(bspnode);
			l->ticks = (unsigned)(BiosTicks () - t0);
			l->talloc = 0xffff;				// read from the cache
		}
		return;
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

	FindPushwalls ();
	for (np = 0; np < npcand && SOLID(tilemap[pcand[np][0]][pcand[np][1]]); np++)
	{										// the pushable tiles: open, for the
		psave[np] = tilemap[pcand[np][0]][pcand[np][1]];	// tree
		tilemap[pcand[np][0]][pcand[np][1]] = 0;
	}
	FindRuns ();
	for (i = 0; i < np; i++)
		tilemap[pcand[i][0]][pcand[i][1]] = psave[i];
	AddBlockFaces ();
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
	if (bb.numnodes)
		CacheSave (key);

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

	if (st_frames)
	{
		char	sfmt[140];
		if (_fstrlen (bspstat) < sizeof(sfmt))
		{
			_fstrcpy ((char far *)sfmt,bspstat);
			printf (sfmt,st_frames,st_nodes/st_frames,st_culled/st_frames,
				st_boxhid/st_frames,st_runs/st_frames,st_hidden/st_frames,
				st_left/st_frames);
			_fstrcpy ((char far *)sfmt,bspstat2);
			printf (sfmt,st_lmax,st_lframe,st_lfirst,st_llast,st_lnone,st_pwframes);
		}
	}
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
		else if (l->talloc == 0xffff)
		{
			if (_fstrlen (bspfmtc) >= sizeof(fmt))
				return;
			_fstrcpy ((char far *)fmt,bspfmtc);
			printf (fmt,l->map,l->runs,l->cuts,l->nodes,l->depth,l->bytes,l->ticks);
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

/*
=============================================================================

						THE RENDERER (milestone 2)

The walls from the tree: front to back, each run that faces the camera is
projected to its screen columns, and every column of it not yet claimed
gets its own exact intercept on the run's line, its height by id's
CalcHeight arithmetic, its texture column, and a post through ScalePostF --
so the compiled scalers draw it as ever.  Doors are not in the tree (they
move): each frame each door in front is projected and drawn over any column
where it is nearer than the wall there, a nearer face being always the
taller.  Then the visibility the walk used to mark ray by ray: an actor or a
static is visible when its tile's centre is in view and nearer than the
wall in its column -- the game play change this branch allows.

=============================================================================
*/

#define DOORWALL	(PMSpriteStart-8)		// as WL_DRAW.C
extern int		midangle;
extern long		postsource;
extern unsigned	postx, postwidth, postmin;
void	ScalePostF (void);
void	DropFillF (void);

int		far bspmode = 1;			// the tree draws the walls (WALK: the rays)
byte	far bspclaim[MAXVIEWWIDTH];	// columns drawn this frame
int		far bspleft;				// and how many are not

//
// The columns claimed so far, as sorted ranges [a,b) with a sentinel at
// each end (Doom's solidsegs): a run is stepped only through the gaps
// between them.  The first version stepped every column a run covered and
// skipped the claimed ones -- a far wall behind a near one cost all its
// columns -- and that loop was 37% of DrawRun on the V30.
//
typedef struct
{
	int		a, b;
} bsprange;

#define MAXSOLID	(MAXVIEWWIDTH/2+4)

bsprange	far solid[MAXSOLID];
int			far nsolid;

int BSPColRange (int x1, int y1, int x2, int y2, int *c1, int *c2);
void BSPWalk (void far *nodes, void far *runs, void far *solid, int far *left);
unsigned BSPWalkStat (int which);

#define HIDESLACK	4					// columns: BSPColRange's error, and more

static void ClaimInit (void)
{
	solid[0].a = -0x7fff;
	solid[0].b = 0;
	solid[1].a = viewwidth;
	solid[1].b = 0x7fff;
	nsolid = 2;
}

//
// Are the columns from c1 to c2 (either way round, BSPColRange's rough
// ones) all claimed already, or off the screen?
//
static int Covered (int c1, int c2)
{
	int		k;

	if (c1 > c2)
	{
		k = c1;
		c1 = c2;
		c2 = k;
	}
	c1 -= HIDESLACK;
	c2 += HIDESLACK+1;
	if (c1 < 0)
		c1 = 0;
	if (c2 > viewwidth)
		c2 = viewwidth;
	if (c1 >= c2)
		return 1;
	for (k = 0; solid[k].b <= c1; k++)
		;
	return solid[k].a <= c1 && solid[k].b >= c2;
}

//
// [cs,ce) is claimed: merged with every range it overlaps or touches
//
static void Claim (int cs, int ce)
{
	int		i, j;

	for (i = 0; solid[i].b < cs; i++)
		;
	for (j = i; j < nsolid && solid[j].a <= ce; j++)
		;
	if (i == j)							// touches nothing: a new range
	{
		if (nsolid >= MAXSOLID)
			return;
		_fmemmove (&solid[i+1],&solid[i],(nsolid-i)*sizeof(bsprange));
		solid[i].a = cs;
		solid[i].b = ce;
		nsolid++;
		return;
	}
	if (cs < solid[i].a)
		solid[i].a = cs;
	solid[i].b = ce > solid[j-1].b ? ce : solid[j-1].b;
	if (j - i > 1)
	{
		_fmemmove (&solid[i+1],&solid[j],(nsolid-j)*sizeof(bsprange));
		nsolid -= j - i - 1;
	}
}

//
// The arithmetic of a run's ends, on the 8086's own MUL and DIV.  Borland
// does every long multiply and divide in a helper (LXMUL@, LDIV@ -- the
// divide a 32-step loop), and a run's ends took two dozen of them: on the
// 486 it was 280 microseconds a run, the most of the renderer's time.  A
// 32/16 DIV and a 16x16 MUL are all any of it needs.
//
typedef union
{
	unsigned long	l;
	unsigned		w[2];
} bspword;

//
// a/d and a%d for any 32-bit a and 16-bit d, by two DIVs
//
static unsigned long UDiv16 (unsigned long a, unsigned d, unsigned *rem)
{
	bspword		q;
	unsigned	qh, ql, r;

asm	mov	cx,[d]
asm	mov	ax,word ptr [a+2]
asm	xor	dx,dx
asm	div	cx
asm	mov	[qh],ax
asm	mov	ax,word ptr [a]
asm	div	cx
asm	mov	[ql],ax
asm	mov	[r],dx
	*rem = r;
	q.w[0] = ql;
	q.w[1] = qh;
	return q.l;
}

//
// a*x, the low 32 bits
//
static unsigned long UMul16 (unsigned long a, unsigned x)
{
	bspword		p;
	unsigned	lo, hi;

asm	mov	ax,word ptr [a+2]
asm	mul	[x]
asm	mov	cx,ax
asm	mov	ax,word ptr [a]
asm	mul	[x]
asm	add	dx,cx
asm	mov	[lo],ax
asm	mov	[hi],dx
	p.w[0] = lo;
	p.w[1] = hi;
	return p.l;
}

static long MulS16 (long x, int k)
{
	int		neg = 0;
	long	r;

	if (x < 0)
	{
		x = -x;
		neg = 1;
	}
	if (k < 0)
	{
		k = -k;
		neg ^= 1;
	}
	r = (long)UMul16 (x,k);
	return neg ? -r : r;
}

//
// x*t, t a 16.16 fraction from 0 to 1
//
static long MulFrac (long x, unsigned long t)
{
	bspword		r;
	unsigned	tt, lo, hi;
	int			neg = 0;

	if (t >= 0x10000L)
		return x;
	if (x < 0)
	{
		x = -x;
		neg = 1;
	}
	tt = (unsigned)t;
asm	mov	ax,word ptr [x]
asm	mul	[tt]
asm	mov	cx,dx
asm	mov	ax,word ptr [x+2]
asm	mul	[tt]
asm	add	ax,cx
asm	adc	dx,0
asm	mov	[lo],ax
asm	mov	[hi],dx
	r.w[0] = lo;
	r.w[1] = hi;
	return neg ? -(long)r.l : (long)r.l;
}

//
// num/den as a 16.16 fraction, for 0 <= num/den <= 1 (signs alike)
//
static unsigned long Frac (long num, long den)
{
	bspword		n;
	unsigned	r;

	if (den < 0)
	{
		num = -num;
		den = -den;
	}
	if (num <= 0)
		return 0;
	if (num >= den)
		return 0x10000L;
	while (den > 0x7fffL)
	{
		num >>= 1;
		den >>= 1;
	}
	n.w[1] = (unsigned)num;
	n.w[0] = 0;
	return UDiv16 (n.l,(unsigned)den,&r);
}

#define NEARD	0x400L				// 1/64 tile

//
// A wall's height on the screen (id's heightnumerator/(nx>>8), as 1/depth)
// and its texture coordinate times that height are both linear across the
// screen, so a run is projected at its two ends only and stepped across its
// columns: an add for the height, an add and one 32/16 DIV for the texture.
// (Doom's way; the first version did per column two 32-bit multiplies, a
// 32-bit divide and a page lookup, and ran at a third of the walk's speed.)
//
typedef struct
{
	long	col;			// the screen column it lands on, in 64ths
	long	h;				// heightnumerator/(nx>>8)
	long	uh;				// texels along the run, times h
	int		ci;				// the whole column (col floored)
} bspend;

//
// Clip a view-space segment to one side of the view: d = ny*a + nx*b is
// the signed distance (scaled) from the edge, a column past it.  Without
// this, an end cut at the near plane could land thousands of columns off
// the screen, and the stepping below -- however exact per column -- was
// started from there: the texture slid along the near walls.
//
static int SideClip (long *nx1, long *ny1, long *u1, long *nx2, long *ny2,
	long *u2, int a, int b)
{
	long			d1, d2, dx, dy, du;
	unsigned long	t;

	d1 = MulS16 (*ny1 >> 4,a) + MulS16 (*nx1 >> 4,b);
	d2 = MulS16 (*ny2 >> 4,a) + MulS16 (*nx2 >> 4,b);
	if (d1 >= 0 && d2 >= 0)
		return 1;
	if (d1 < 0 && d2 < 0)
		return 0;
	t = Frac (d1,d1-d2);				// 16.16, from 1 towards 2: where d = 0
	dx = *nx2 - *nx1;
	dy = *ny2 - *ny1;
	du = *u2 - *u1;
	if (d1 < 0)
	{
		*nx1 += MulFrac (dx,t);
		*ny1 += MulFrac (dy,t);
		*u1 += MulFrac (du,t);
	}
	else
	{
		*nx2 = *nx1 + MulFrac (dx,t);
		*ny2 = *ny1 + MulFrac (dy,t);
		*u2 = *u1 + MulFrac (du,t);
	}
	return 1;
}

//
// A value linear across the screen, a at the column (in 64ths) where a
// segment starts to b where it ends, d 64ths later, stepped exactly a whole
// column at a time: a quotient and a remainder carried, as a line is drawn,
// from the first whole column, off 64ths in.  So every column is sampled
// where its own ray falls.  (A truncated step drifts by up to a unit a
// column, and u = uh/h turned that into texels; starting at a rounded
// column put every texel up to half a column out.)
//
typedef struct
{
	union
	{
		long		l;
		unsigned	w[2];		// w[1]: the whole part of a 16.16 height
	} v;
	long		q;
	unsigned	r, e, d;	// (unsigned: e + r can pass 32767)
} bspstep;

//
// floor(dv*x/d) and its remainder (0 <= rem < d): the product is 48 bits,
// divided by three DIVs, so nothing overflows on the way
//
static long MulDivFloor (long dv, unsigned x, unsigned d, unsigned *rem)
{
	unsigned	neg = 0, p0, q0, q1, r;
	bspword		w;

	if (dv < 0)
	{
		dv = -dv;
		neg = 1;
	}
asm	mov	ax,word ptr [dv]
asm	mul	word ptr [x]
asm	mov	[p0],ax
asm	mov	bx,dx
asm	mov	ax,word ptr [dv+2]
asm	mul	word ptr [x]
asm	add	ax,bx
asm	adc	dx,0
asm	mov	cx,[d]
asm	mov	bx,ax
asm	mov	ax,dx
asm	xor	dx,dx
asm	div	cx
asm	mov	ax,bx
asm	div	cx
asm	mov	[q1],ax
asm	mov	ax,[p0]
asm	div	cx
asm	mov	[q0],ax
asm	mov	[r],dx
	w.w[0] = q0;
	w.w[1] = q1;
	if (!neg)
	{
		*rem = r;
		return (long)w.l;
	}
	if (r)
	{
		*rem = d - r;
		return -(long)w.l - 1;
	}
	*rem = 0;
	return -(long)w.l;
}

static void StepInit (bspstep *s, long a, long b, unsigned off, unsigned d)
{
	s->d = d;
	s->q = MulDivFloor (b-a,64,d,&s->r);
	s->v.l = a + MulDivFloor (b-a,off,d,&s->e);
}

#define STEP(s)	((s).v.l += (s).q, ((s).e += (s).r) >= (s).d || (s).e < (s).r ? ((s).e -= (s).d, (s).v.l++) : 0)

//
// DrawRun's column loop, in WL_DR_A.ASM: the struct's layout is the
// assembly's (BC_ offsets there)
//
typedef struct
{
	int			col, end;		// the columns to do, [col,end)
	bspstep		H, UH;
	int			tile;			// the tile whose page is loaded
	int			a1;				// the run's first tile
	unsigned	umax;			// its last texel
	unsigned	page;			// the texture's segment
	unsigned	flip;			// 0, or 0FC0h: the texture column xored
} bspcols;

int BSPCols (bspcols *c);

//
// the view's planes, culling and object visibility, in WL_DR_A.ASM
//
void BSPSetPlanes (int cam8x, int cam8y, int p0x, int p0y, int p1x, int p1y,
	int p2x, int p2y);
void BSPSetBox (int x1, int y1, int x2, int y2);
int BSPOutside (int x1, int y1, int x2, int y2);
int BSPClassify (int x1, int y1, int x2, int y2);
void BSPMarkVis (void);


//
// A view-space point's column (in 64ths, and whole) and height, and u*h,
// in one routine on the 8086's MUL and DIV: the first version called a
// helper for every multiply and divide, sixty calls a run, and on the V30
// those calls were a third of the frame.  The column is centerx +
// ny*scale/nx, nx shifted to 15 bits so that one DIV (two, for the whole
// 32-bit quotient) does it; a point off the screen by more than 0x7fff
// columns reads as 0x7fff.  The height is id's heightnumerator/(nx>>8),
// clamped as ScalePost clamps it.
//
static void ColHeight (long nx, long ny, unsigned u, bspend *e)
{
	unsigned	h, n, q, f, neg, ulo, uhi, olo, ohi;
	bspword		w;

	neg = ny < 0;
	if (neg)
		ny = -ny;
asm	mov	cx,word ptr [nx+1]
asm	mov	ax,word ptr [heightnumerator]
asm	mov	dx,word ptr [heightnumerator+2]
asm	cmp	dx,cx
asm	jae	chclamp
asm	div	cx
asm	cmp	ax,7fffh
asm	jbe	chhok
chclamp:
asm	mov	ax,7fffh
chhok:
asm	mov	[h],ax
asm	mul	word ptr [u]
asm	mov	[ulo],ax
asm	mov	[uhi],dx
asm	mov	ax,word ptr [ny]
asm	mul	word ptr [scale]
asm	mov	cx,ax
asm	mov	bx,dx
asm	mov	ax,word ptr [ny+2]
asm	mul	word ptr [scale]
asm	add	bx,ax
asm	mov	ax,word ptr [nx]
asm	mov	dx,word ptr [nx+2]
chnorm:
asm	or	dx,dx
asm	jnz	chshift
asm	test	ax,8000h
asm	jz	chdiv
chshift:
asm	shr	dx,1
asm	rcr	ax,1
asm	shr	bx,1
asm	rcr	cx,1
asm	jmp	chnorm
chdiv:
asm	mov	[n],ax
asm	mov	ax,bx
asm	xor	dx,dx
asm	div	word ptr [n]
asm	or	ax,ax
asm	jnz	chfar
asm	mov	ax,cx
asm	div	word ptr [n]
asm	cmp	ax,7fffh
asm	ja	chfar
asm	mov	[q],ax
asm	mov	ax,dx
asm	mov	cx,64
asm	mul	cx
asm	div	word ptr [n]
asm	mov	[f],ax
asm	jmp	chcol
chfar:
asm	mov	word ptr [q],7fffh
asm	mov	word ptr [f],0
chcol:
asm	mov	ax,[q]
asm	mov	cx,64
asm	mul	cx
asm	add	ax,[f]
asm	adc	dx,0
asm	mov	[olo],ax
asm	mov	[ohi],dx
	e->h = h;
	w.w[0] = ulo;
	w.w[1] = uhi;
	e->uh = (long)w.l;
	w.w[0] = olo;
	w.w[1] = ohi;
	e->col = (long)(centerx << 6) + (neg ? -(long)w.l : (long)w.l);
	e->ci = neg ? centerx - q - (f != 0) : centerx + q;
}

//
// a point far enough off the screen that the run must be clipped to it
// first: the stepping's 64ths have to fit an int
//
#define COLLO	(-100*64L)
#define COLHI	((long)(viewwidth+100)*64)

//
// view-space ends (nx, ny) of a segment, texel positions u1, u2 along it,
// clipped to the near plane and the sides of the view; 0 if none is left
//
static int Ends (long gx1, long gy1, long gx2, long gy2, long u1, long u2,
	bspend *e1, bspend *e2)
{
	long			nx1, ny1, nx2, ny2;
	unsigned long	t;

	nx1 = FixedByFrac (gx1,viewcos) - FixedByFrac (gy1,viewsin);
	nx2 = FixedByFrac (gx2,viewcos) - FixedByFrac (gy2,viewsin);
	if (nx1 < NEARD && nx2 < NEARD)
		return 0;
	ny1 = FixedByFrac (gy1,viewcos) + FixedByFrac (gx1,viewsin);
	ny2 = FixedByFrac (gy2,viewcos) + FixedByFrac (gx2,viewsin);
	if (nx1 < NEARD || nx2 < NEARD)		// cut where nx = NEARD (linear along it)
	{
		t = Frac (NEARD-nx1,nx2-nx1);		// 16.16, from 1 towards 2
		if (nx1 < NEARD)
		{
			ny1 += MulFrac (ny2-ny1,t);
			u1 += MulFrac (u2-u1,t);
			nx1 = NEARD;
		}
		else
		{
			ny2 = ny1 + MulFrac (ny2-ny1,t);
			u2 = u1 + MulFrac (u2-u1,t);
			nx2 = NEARD;
		}
	}
	if (u1 < 0)
		u1 = 0;
	if (u2 < 0)
		u2 = 0;
	ColHeight (nx1,ny1,(unsigned)u1,e1);
	ColHeight (nx2,ny2,(unsigned)u2,e2);
	if (e1->col < COLLO || e1->col > COLHI || e2->col < COLLO || e2->col > COLHI)
	{
		if (!SideClip (&nx1,&ny1,&u1,&nx2,&ny2,&u2,(int)scale,centerx+2)
			|| !SideClip (&nx1,&ny1,&u1,&nx2,&ny2,&u2,-(int)scale,viewwidth+2-centerx))
			return 0;
		if (u1 < 0)
			u1 = 0;
		if (u2 < 0)
			u2 = 0;
		ColHeight (nx1,ny1,(unsigned)u1,e1);
		ColHeight (nx2,ny2,(unsigned)u2,e2);
	}
	return 1;
}

//
// one wall run: its unclaimed columns, each with its own post
//
void DrawRun (bsprun far *r)			// (called by BSPWalk, in WL_DR_A.ASM)
{
	bspend		e1, e2, t;
	int			col, cs, ce, c1, c2, k, end, vertical, up, a1, a2, rl, pic;
	long		line;
	bspcols		bc;
	bspword		hw1, hw2;
	unsigned	tilehitv;

	vertical = !(r->of & 1);
	up = r->of & 2;
	a1 = r->a1;
	a2 = r->a2;
	rl = r->line;
	if (r->of & 4)
	{									// a block's face: is one standing there?
		k = vertical ? tilemap[up ? rl-1 : rl][a1] : tilemap[a1][up ? rl-1 : rl];
		if (!k || (k & 0x80))
			return;						// open, or the one on the move
	}
	if ((vertical ? BSPColRange (rl,a1,rl,a2,&c1,&c2)
		: BSPColRange (a1,rl,a2,rl,&c1,&c2)) && Covered (c1,c2))
	{									// roughly where it lands is behind
		st_hidden++;					// what is drawn there already
		return;
	}
	line = (long)rl << TILESHIFT;
	if (vertical)
	{
		if (!Ends (line-viewx,((long)a1<<TILESHIFT)-viewy,line-viewx,
			((long)a2<<TILESHIFT)-viewy,0,(long)(a2-a1)<<6,&e1,&e2))
			return;
	}
	else if (!Ends (((long)a1<<TILESHIFT)-viewx,line-viewy,
		((long)a2<<TILESHIFT)-viewx,line-viewy,0,(long)(a2-a1)<<6,&e1,&e2))
		return;
	if (e1.col > e2.col)
	{
		t = e1;
		e1 = e2;
		e2 = t;
	}
	c1 = (int)e1.col;						// (an end is within COLLO..COLHI)
	c2 = (int)e2.col;
	cs = c1 < 0 ? 0 : (c1 + 63) >> 6;		// the columns whose rays cross it
	ce = c2 > viewwidth << 6 ? viewwidth : (c2 + 63) >> 6;
	if (cs >= ce)
		return;
	for (k = 0; solid[k].b <= cs; k++)
		;
	if (solid[k].a <= cs && solid[k].b >= ce)
	{
		st_hidden++;
		return;							// wholly behind what is drawn
	}
	hw1.w[0] = hw2.w[0] = 0;
	hw1.w[1] = (unsigned)e1.h;
	hw2.w[1] = (unsigned)e2.h;
	bc.flip = (vertical ? up : !up) ? 0xfc0 : 0;
	bc.a1 = a1;
	bc.umax = ((a2-a1) << 6) - 1;
	bc.tile = -1;
	bc.page = 0;

	col = cs;
	while (col < ce)
	{
		if (solid[k].a <= col)
		{
			col = solid[k].b;				// claimed: on past it
			k++;
			continue;
		}
		end = solid[k].a < ce ? solid[k].a : ce;
		bspleft -= end - col;
		StepInit (&bc.H,(long)hw1.l,(long)hw2.l,(col << 6) - c1,c2 - c1);
		StepInit (&bc.UH,e1.uh,e2.uh,(col << 6) - c1,c2 - c1);
		bc.col = col;
		bc.end = end;
		postwidth = 0;
		while (BSPCols (&bc))			// a new tile: its page
		{
			if (postwidth)
			{
				ScalePostF ();				// before PM_GetPage, which can
				postwidth = 0;				// evict the page it points into
			}
			if (vertical)
			{
				tilehitv = tilemap[up ? rl-1 : rl][bc.tile];
				if ((tilehitv & 0x40) && (tilemap[up ? rl : rl-1][bc.tile] & 0x80))
					pic = DOORWALL+3;
				else
					pic = vertwall[tilehitv & ~0x40];
			}
			else
			{
				tilehitv = tilemap[bc.tile][up ? rl-1 : rl];
				if ((tilehitv & 0x40) && (tilemap[bc.tile][up ? rl : rl-1] & 0x80))
					pic = DOORWALL+2;
				else
					pic = horizwall[tilehitv & ~0x40];
			}
			bc.page = (unsigned)PM_GetPage (pic);
		}
		if (postwidth)
			ScalePostF ();
		postwidth = 0;
		col = end;
	}
	Claim (cs,ce);
}

//
// The view's three planes -- behind the camera, left of the left edge,
// right of the right edge -- as 8.8 normals pointing in, set each frame.  A
// box (in tiles) is outside when the one corner of it furthest along some
// normal is still behind that plane: two 16-bit multiplies a plane.  Whole
// subtrees, and runs before they are projected, are skipped so.  (Without
// it the walk visited every node nearer than the farthest wall it drew,
// those behind the camera included, and projected every run there that
// faced it.)
//
int		far cam8x, far cam8y;
int		far pn[3][2];

//
// id's sintable is sign and magnitude (a negative entry is the magnitude
// with bit 31 set, which FixedByFrac takes) -- as an 8.8 int.  Read with a
// plain shift, every negative sine came out positive, and three of the
// four quadrants' planes pointed the wrong way: whole walls were culled.
//
static int SignMag (long v)
{
	int		m;

asm	mov	ax,word ptr [v+1]				/* the magnitude >> 8: it is under 2^17 */
asm	mov	[m],ax
	return (((byte *)&v)[3] & 0x80) ? -m : m;
}

static void SetPlanes (void)
{
	int		k, a, h;
	int		ang[3];

	cam8x = (int)(viewx >> 8);
	cam8y = (int)(viewy >> 8);
	h = pixelangle[0]/10 + 2;				// half the field of view, and a margin
	ang[0] = viewangle;
	ang[1] = viewangle + h - 90;
	ang[2] = viewangle - h + 90;
	for (k = 0; k < 3; k++)
	{
		a = ang[k];
		while (a < 0)
			a += ANGLES;
		while (a >= ANGLES)
			a -= ANGLES;
		pn[k][0] = SignMag (sintable[a+ANGLES/4]);	// cos
		pn[k][1] = -SignMag (sintable[a]);			// -sin: y grows south
	}
	BSPSetPlanes (cam8x,cam8y,pn[0][0],pn[0][1],pn[1][0],pn[1][1],pn[2][0],pn[2][1]);
}

//
// Is a box (in tiles) wholly behind what is drawn?  Its silhouette from the
// camera is two corners -- which two depends on where the camera is
// (Doom's checkcoord) -- and the columns between theirs are all it can
// cover.  Doom culls whole subtrees so, and so does this.
//
static int BoxHidden (int x1, int y1, int x2, int y2)
{
	int		ax, ay, bx, by, c1, c2;

	ax = cam8x < x1 << 8 ? 0 : (cam8x <= x2 << 8 ? 1 : 2);
	ay = cam8y < y1 << 8 ? 0 : (cam8y <= y2 << 8 ? 1 : 2);
	switch (ay*3 + ax)
	{
	case 0:	ax = x2; ay = y1; bx = x1; by = y2; break;
	case 1:	ax = x1; ay = y1; bx = x2; by = y1; break;
	case 2:	ax = x1; ay = y1; bx = x2; by = y2; break;
	case 3:	ax = x1; ay = y1; bx = x1; by = y2; break;
	case 5:	ax = x2; ay = y1; bx = x2; by = y2; break;
	case 6:	ax = x1; ay = y1; bx = x2; by = y2; break;
	case 7:	ax = x1; ay = y2; bx = x2; by = y2; break;
	case 8:	ax = x2; ay = y1; bx = x1; by = y2; break;
	default:
		return 0;							// the camera is in it
	}
	return BSPColRange (ax,ay,bx,by,&c1,&c2) && Covered (c1,c2);
}

//
// front to back from node n
//
static void Walk (int n, int inside)
{
	bspnode	far *node;
	long	cam;
	int		nearc, farc, k;				// (near and far are Borland's keywords)
	bsprun	far *r;

	while (n >= 0 && bspleft > 0)
	{
		node = &bb.nodes[n];
		st_nodes++;
		if (!inside)						// (a box wholly in view: all below it too)
		{
			k = BSPClassify (node->x1,node->y1,node->x2,node->y2);
			if (k == 1)
			{
				st_culled++;
				return;						// nothing below it is in view
			}
			inside = k == 2;
		}
		if (BoxHidden (node->x1,node->y1,node->x2,node->y2))
		{
			st_boxhid++;
			return;							// nor anything that can be seen
		}
		cam = node->axis ? viewy : viewx;
		if (cam < ((long)node->coord << TILESHIFT))
		{
			nearc = node->lo;
			farc = node->hi;
		}
		else
		{
			nearc = node->hi;
			farc = node->lo;
		}
		Walk (nearc,inside);
		if (bspleft <= 0)
			return;
		for (k = 0, r = &bb.runs[node->first]; k < node->count; k++, r++)
			if ((r->of & 2) ? cam > ((long)node->coord << TILESHIFT)
				: cam < ((long)node->coord << TILESHIFT))
			{
				if (inside)
					;
				else if (r->of & 1)
				{
					if (BSPOutside (r->a1,r->line,r->a2,r->line))
						continue;
				}
				else if (BSPOutside (r->line,r->a1,r->line,r->a2))
					continue;
				st_runs++;
				DrawRun (r);
			}
		n = farc;							// the far side: a loop, not a call
	}
}

//
// the doors, over the walls wherever they are nearer -- projected the same
// way, one tile long, the open part (doorposition) left out
//
static void DrawDoors (void)
{
	doorobj_t	*d;
	bspend		e1, e2, t;
	int			col, cs, ce, c1, c2, page;
	long		line, base;
	bspstep		H, UH;
	bspword		hw1, hw2;
	unsigned	h, u, frac, dp, texture;

	for (d = doorobjlist; d < lastdoorobj; d++)
	{
		if (doorposition[d-doorobjlist] > 0xfc00
			|| BSPOutside (d->tilex,d->tiley,d->tilex+1,d->tiley+1))
			continue;					// open, or out of the view
		if (d->vertical)
		{
			line = ((long)d->tilex << TILESHIFT) + TILEGLOBAL/2;
			base = (long)d->tiley << TILESHIFT;
			if (!Ends (line-viewx,base-viewy,line-viewx,base+TILEGLOBAL-viewy,0,64,&e1,&e2))
				continue;
		}
		else
		{
			line = ((long)d->tiley << TILESHIFT) + TILEGLOBAL/2;
			base = (long)d->tilex << TILESHIFT;
			if (!Ends (base-viewx,line-viewy,base+TILEGLOBAL-viewx,line-viewy,0,64,&e1,&e2))
				continue;
		}
		if (e1.col > e2.col)
		{
			t = e1;
			e1 = e2;
			e2 = t;
		}
		c1 = (int)e1.col;
		c2 = (int)e2.col;
		cs = c1 < 0 ? 0 : (c1 + 63) >> 6;
		ce = c2 > viewwidth << 6 ? viewwidth : (c2 + 63) >> 6;
		if (cs >= ce)
			continue;
		switch (d->lock)
		{
		case dr_normal:		page = DOORWALL;	break;
		case dr_elevator:	page = DOORWALL+4;	break;
		default:			page = DOORWALL+6;	break;
		}
		if (d->vertical)
			page++;
		page = (unsigned)PM_GetPage (page);
		dp = doorposition[d-doorobjlist];
		hw1.w[0] = hw2.w[0] = 0;
		hw1.w[1] = (unsigned)e1.h;
		hw2.w[1] = (unsigned)e2.h;
		StepInit (&H,(long)hw1.l,(long)hw2.l,(cs << 6) - c1,c2 - c1);
		StepInit (&UH,e1.uh,e2.uh,(cs << 6) - c1,c2 - c1);
		for (col = cs; col < ce; col++, STEP(H), STEP(UH))
		{
			h = H.v.w[1];
			if (!h)
				h = 1;
			if ((!bspleft || bspclaim[col]) && h <= wallheight[col])
				continue;					// a wall in front of it
			if ((int)UH.v.w[1] < 0)
				u = 0;
			else if (UH.v.w[1] >= h)
				u = 63;
			else
			{
				unsigned	uhlo = UH.v.w[0], uhhi = UH.v.w[1];
asm				mov	ax,[uhlo]
asm				mov	dx,[uhhi]
asm				div	[h]
asm				mov	[u],ax
			}
			if (u > 63)
				u = 63;
			frac = u << 10;
			if (frac < dp)
				continue;					// the open part: what is behind shows
			texture = ((frac - dp) >> 4) & 0xfc0;
			wallheight[col] = h;
			if (bspleft && !bspclaim[col])
			{
				bspclaim[col] = 1;
				bspleft--;
			}
			postsource = ((long)page << 16) | texture;
			postx = col;
			postwidth = 1;
			ScalePostF ();
		}
	}
}

//
// one face of a block, from (gx1,gy1) to (gx2,gy2) (view-relative, the
// lower end first), drawn wherever it is nearer than what is there
//
static void BlockFace (long gx1, long gy1, long gx2, long gy2, unsigned page,
	int flip)
{
	bspend		e1, e2, t;
	int			col, cs, ce, c1, c2;
	bspstep		H, UH;
	bspword		hw1, hw2;
	unsigned	h, u, texture;

	if (!Ends (gx1,gy1,gx2,gy2,0,64,&e1,&e2))
		return;
	if (e1.col > e2.col)
	{
		t = e1;
		e1 = e2;
		e2 = t;
	}
	c1 = (int)e1.col;
	c2 = (int)e2.col;
	cs = c1 < 0 ? 0 : (c1 + 63) >> 6;
	ce = c2 > viewwidth << 6 ? viewwidth : (c2 + 63) >> 6;
	if (cs >= ce)
		return;
	hw1.w[0] = hw2.w[0] = 0;
	hw1.w[1] = (unsigned)e1.h;
	hw2.w[1] = (unsigned)e2.h;
	StepInit (&H,(long)hw1.l,(long)hw2.l,(cs << 6) - c1,c2 - c1);
	StepInit (&UH,e1.uh,e2.uh,(cs << 6) - c1,c2 - c1);
	for (col = cs; col < ce; col++, STEP(H), STEP(UH))
	{
		h = H.v.w[1];
		if (!h)
			h = 1;
		if ((!bspleft || bspclaim[col]) && h <= wallheight[col])
			continue;						// a wall in front of it
		if ((int)UH.v.w[1] < 0)
			u = 0;
		else if (UH.v.w[1] >= h)
			u = 63;
		else
		{
			unsigned	uhlo = UH.v.w[0], uhhi = UH.v.w[1];
asm			mov	ax,[uhlo]
asm			mov	dx,[uhhi]
asm			div	[h]
asm			mov	[u],ax
		}
		if (u > 63)
			u = 63;
		texture = u << 6;
		if (flip)
			texture = 0xfc0 - texture;
		wallheight[col] = h;
		if (bspleft && !bspclaim[col])
		{
			bspclaim[col] = 1;
			bspleft--;
		}
		((unsigned *)&postsource)[0] = texture;
		((unsigned *)&postsource)[1] = page;
		postx = col;
		postwidth = 1;
		ScalePostF ();
	}
}

//
// the block on the move, at pwallpos along its way: its faces that look at
// the camera, each over the walls wherever it is nearer
//
static void DrawPushwalls (void)
{
	int			x, y, pic;
	long		x0, y0, off;
	unsigned	vpage, hpage;

	if (!pwallstate)
		return;
	x = pwallx;
	y = pwally;
	if ((tilemap[x][y] & 0xc0) != 0xc0
		|| BSPOutside (x-1,y-1,x+2,y+2))
		return;
	pic = tilemap[x][y] & 63;
	x0 = ((long)x << TILESHIFT) - viewx;
	y0 = ((long)y << TILESHIFT) - viewy;
	off = (long)pwallpos << 10;
	switch (pwalldir)
	{
	case di_north:	y0 -= off;	break;
	case di_east:	x0 += off;	break;
	case di_south:	y0 += off;	break;
	case di_west:	x0 -= off;	break;
	}
	vpage = (unsigned)PM_GetPage (vertwall[pic]);
	hpage = (unsigned)PM_GetPage (horizwall[pic]);
	if (x0 > 0)
		BlockFace (x0,y0,x0,y0+TILEGLOBAL,vpage,0);			// west
	if (x0+TILEGLOBAL < 0)
		BlockFace (x0+TILEGLOBAL,y0,x0+TILEGLOBAL,y0+TILEGLOBAL,vpage,1);	// east
	if (y0 > 0)
		BlockFace (x0,y0,x0+TILEGLOBAL,y0,hpage,1);			// north
	if (y0+TILEGLOBAL < 0)
		BlockFace (x0,y0+TILEGLOBAL,x0+TILEGLOBAL,y0+TILEGLOBAL,hpage,0);	// south
}

//
// Everything visible is inside the triangle of the view cut off at the
// farthest wall drawn (the least post, postmin, is its height), so its
// bounding box, a tile wider, rejects most of a level's statics with four
// compares and no multiply.  When some column drew no wall there is no
// such bound, and every object is tested.
//
static void ViewBox (int *bx1, int *by1, int *bx2, int *by2)
{
	long	d;
	int		k, a, hf, px, py;

	*bx1 = *bx2 = cam8x;
	*by1 = *by2 = cam8y;
	if (bspleft > 0 || postmin < 4 || postmin >= 0x7fff)
	{
		*bx1 = *by1 = -0x7fff;
		*bx2 = *by2 = 0x7fff;
		return;
	}
	d = heightnumerator / (postmin << 1);	// the farthest depth, in 8.8 tiles
	d += d >> 1;							// along the edges: past 1/cos(40)
	if (d > 0x5c00)
		d = 0x5c00;							// the map's diagonal
	hf = pixelangle[0]/10 + 2;
	for (k = -1; k <= 1; k += 2)
	{
		a = viewangle + k*hf;
		while (a < 0)
			a += ANGLES;
		while (a >= ANGLES)
			a -= ANGLES;
		px = cam8x + (int)((d * SignMag (sintable[a+ANGLES/4])) >> 8);
		py = cam8y - (int)((d * SignMag (sintable[a])) >> 8);
		if (px < *bx1) *bx1 = px;
		if (px > *bx2) *bx2 = px;
		if (py < *by1) *by1 = py;
		if (py > *by2) *by2 = py;
	}
	*bx1 -= 256;
	*by1 -= 256;
	*bx2 += 256;
	*by2 += 256;
}

static void BSPVisibility (void)
{
	int		bx1, by1, bx2, by2;

	ViewBox (&bx1,&by1,&bx2,&by2);
	BSPSetBox (bx1,by1,bx2,by2);
	BSPMarkVis ();
}

/*
=====================
=
= BSPRefresh
=
= WallRefresh's AsmRefresh, from the tree
=
=====================
*/

void BSPRefresh (void)
{
	int	col;

	bspleft = viewwidth;
	ClaimInit ();
	postmin = 0x7fff;					// step 62's least wall, this frame
	SetPlanes ();
	st_frames++;
	BSPWalk (bb.nodes,bb.runs,solid,&bspleft);	// the tree, in WL_DR_A.ASM
	st_nodes += BSPWalkStat (0);
	st_culled += BSPWalkStat (1);
	st_boxhid += BSPWalkStat (2);
	st_runs += BSPWalkStat (3);
	if (bspleft > 0)					// columns no wall reached: the claims
	{									// as a byte a column, for the doors
		int	k;
		_fmemset (bspclaim,1,sizeof(bspclaim));
		for (k = 0; k < nsolid-1; k++)
			_fmemset (&bspclaim[solid[k].b < 0 ? 0 : solid[k].b],0,
				solid[k+1].a - (solid[k].b < 0 ? 0 : solid[k].b));
	}
	if (pwallstate)
		st_pwframes++;
	DrawPushwalls ();
	DrawDoors ();
	st_left += bspleft;
	if (bspleft == viewwidth)
		st_lnone++;
	else if (bspleft > st_lmax)
	{
		int c;
		st_lmax = bspleft;
		st_lframe = (int)st_frames;
		for (c = 0; c < viewwidth && !bspclaim[c]; c++)
			;
		st_lfirst = c;
		for (c = viewwidth-1; c >= 0 && !bspclaim[c]; c--)
			;
		st_llast = c;
	}
	if (bspleft > 0)
	for (col = 0; col < viewwidth; col++)
		if (!bspclaim[col])				// nothing there: the band, not an
		{								// old frame (as step 92)
			wallheight[col] = 0;
			postx = col;
			postwidth = 1;
			DropFillF ();
		}
	BSPVisibility ();
}

int BSPReady (void)
{
	return bb.numnodes != 0;
}
