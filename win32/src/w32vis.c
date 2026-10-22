/*
 * w32vis.c -- what the DOS renderer decides, besides the picture, for the
 * whole game (WOLF3DW): which tiles the view reaches (spotvis), which actors
 * it sees -- woken (active), marked FL_VISABLE, given their place on the
 * screen (viewx) for the guns' aim (WL_AGENT.C's GunAttack) -- and which
 * items the player is close enough to take (GetBonus).  On DOS that is the
 * renderer's own work (AsmRefresh's ray walk, DrawScaleds), so w32draw.c,
 * which only draws, left all of it undone: no shot hit anyone (StevenC,
 * 2026-10-21), and nothing was picked up.
 *
 * Here it is id's own, in C: the ray walk of id's WL_DR_A.ASM (the master
 * branch) word for word -- the same fixed-point steps, the same door and
 * pushwall tests, the same 16-bit words -- and id's TransformActor,
 * TransformTile and DrawScaleds' tests (WL_DRAW.C), with id's projection
 * (WL_MAIN.C's CalcProjection: w32stub.c's NewViewSize calls it here).  The
 * network game does none of this here: its machines aim, pick up and wake
 * by WL_MP.C's own rules, as its DOS machines do.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

#define ACTORSIZE	0x4000		// (WL_DRAW.C's)
#define DEG90		900
#define DEG180		1800
#define DEG270		2700
#define DEG360		3600

typedef unsigned long	u32;
typedef unsigned short	u16;
typedef short			s16;

fixed			mindist = MINDIST;		// (WL_DRAW.C's, which is not built here)

static int		midangle, focaltx, focalty;
static u16		xpartialup, xpartialdown, ypartialup, ypartialdown;

//
// xpartialbyystep and ypartialbyxstep: a long step (either sign) by a 16-bit
// partial -- |step|'s fraction by it, high word, plus its units by it -- the
// sign put back
//
static long ByPartial (long step, u16 partial)
{
	u32	m = step < 0 ? (u32)0 - (u32)step : (u32)step;
	u32	r = (((m & 0xffff) * partial) >> 16) + (u32)(u16)(m >> 16) * partial;

	return step < 0 ? (long)((u32)0 - r) : (long)r;
}

#define TILE(i)		(((byte *)tilemap)[i])
#define MARK(i)		(((byte *)spotvis)[i] = 1)
#define INMAP(i)	((unsigned)(i) < MAPSIZE*MAPSIZE)

//
// AsmRefresh's ray through view column pixx: every tile it crosses marked in
// spotvis, until a wall, a door closed that far, or a pushwall stops it
//
static void Trace (int pixx)
{
	int		a = midangle + pixelangle[pixx];
	int		xtilestep, ytilestep, xtile, ytile, xspot, yspot, steps;
	long	xstep, ystep, xintercept, yintercept, sum;
	u16		xpartial, ypartial;
	s16		dx, cx;
	byte	t;

	if (a < 0)
		a += FINEANGLES;				// -90 is the same as 270
	else if (a >= DEG360)
		a -= FINEANGLES;				// 360-449 the same as 0-89
	if (a < DEG90)
	{
		xtilestep = 1;
		ytilestep = -1;
		xstep = finetangent[DEG90-1-a];
		ystep = -finetangent[a];
		xpartial = xpartialup;
		ypartial = ypartialdown;
	}
	else if (a < DEG180)
	{
		xtilestep = -1;
		ytilestep = -1;
		xstep = -finetangent[a-DEG90];
		ystep = -finetangent[DEG180-1-a];
		xpartial = xpartialdown;
		ypartial = ypartialdown;
	}
	else if (a < DEG270)
	{
		xtilestep = -1;
		ytilestep = 1;
		xstep = -finetangent[DEG270-1-a];
		ystep = finetangent[a-DEG180];
		xpartial = xpartialdown;
		ypartial = ypartialup;
	}
	else
	{
		xtilestep = 1;
		ytilestep = 1;
		xstep = finetangent[a-DEG270];
		ystep = finetangent[DEG360-1-a];
		xpartial = xpartialup;
		ypartial = ypartialup;
	}

	// initvars
	yintercept = viewy + ByPartial (ystep,xpartial);
	xtile = focaltx + xtilestep;
	dx = (s16)(yintercept >> 16);
	xspot = (s16)((xtile << 6) + dx);
	xintercept = viewx + ByPartial (xstep,ypartial);
	cx = (s16)(xintercept >> 16);
	ytile = focalty + ytilestep;
	yspot = (s16)((cx << 6) + ytile);

	steps = 0;							// (a bound: the maps are walled in)
	for (;;)
	{
		// vertcheck: a vertical line next, unless the ray's y has passed ytile
		if (ytilestep == -1 ? dx <= ytile : dx >= ytile)
			goto horizentry;
vertentry:
		if (!INMAP (xspot))
			return;
		t = TILE (xspot);
		if (t)
		{
			if (!(t & 0x80))
				return;					// a wall
			if (t & 0x40)				// a pushwall: moved pwallpos/64 of a step
			{
				sum = yintercept + ((long)((u32)ystep * (u16)pwallpos) >> 6);
				if ((s16)(sum >> 16) == dx)
					return;				// hit it
			}
			else						// a door: half a step to its plane
			{
				sum = yintercept + (ystep >> 1);
				if ((s16)(sum >> 16) == dx
				&& (u16)sum >= (u16)doorposition[t & 0x7f])
					return;				// closed that far: hit it
			}
		}
		// passvert
		if (++steps > 4096)
			return;
		MARK (xspot);
		xtile += xtilestep;
		yintercept += ystep;
		dx = (s16)(yintercept >> 16);
		xspot = (s16)((xtile << 6) + dx);
		continue;

horizentry:
		if (!INMAP (yspot))
			return;
		t = TILE (yspot);
		if (t)
		{
			if (!(t & 0x80))
				return;
			if (t & 0x40)
			{
				sum = xintercept + ((long)((u32)xstep * (u16)pwallpos) >> 6);
				if ((s16)(sum >> 16) == cx)
					return;
			}
			else
			{
				sum = xintercept + (xstep >> 1);
				if ((s16)(sum >> 16) == cx
				&& (u16)sum >= (u16)doorposition[t & 0x7f])
					return;
			}
		}
		// passhoriz
		if (++steps > 4096)
			return;
		MARK (yspot);
		ytile += ytilestep;
		xintercept += xstep;
		cx = (s16)(xintercept >> 16);
		yspot = (s16)((cx << 6) + ytile);
		// horizcheck: a horizontal line next, unless the ray's x has passed xtile
		if (xtilestep == -1 ? cx <= xtile : cx >= xtile)
			goto vertentry;
		goto horizentry;
	}
}

//
// id's TransformActor (WL_DRAW.C): the actor in the view's frame; its column
// on the screen and its height there (heightnumerator/(nx>>8), a 16-bit
// quotient, as the 8086's IDIV gives it)
//
void TransformActor (objtype *ob)
{
	fixed	gx,gy,gxt,gyt,nx,ny;

	gx = ob->x-viewx;
	gy = ob->y-viewy;
	gxt = FixedByFrac (gx,viewcos);
	gyt = FixedByFrac (gy,viewsin);
	nx = gxt-gyt-ACTORSIZE;
	gxt = FixedByFrac (gx,viewsin);
	gyt = FixedByFrac (gy,viewcos);
	ny = gyt+gxt;
	ob->transx = nx;
	ob->transy = ny;
	if (nx < mindist)
	{
		ob->viewheight = 0;
		return;
	}
	ob->viewx = (s16)(centerx + ny*scale/nx);
	ob->viewheight = (u16)(heightnumerator / (s16)(nx >> 8));
}

//
// id's TransformTile: the same for an item's tile -- and true when it is
// close enough to take
//
static boolean TransformTile (int tx, int ty, int *dispx, int *dispheight)
{
	fixed	gx,gy,gxt,gyt,nx,ny;

	gx = ((long)tx<<TILESHIFT)+0x8000-viewx;
	gy = ((long)ty<<TILESHIFT)+0x8000-viewy;
	gxt = FixedByFrac (gx,viewcos);
	gyt = FixedByFrac (gy,viewsin);
	nx = gxt-gyt-0x2000;
	gxt = FixedByFrac (gx,viewsin);
	gyt = FixedByFrac (gy,viewcos);
	ny = gyt+gxt;
	if (nx < mindist)
		*dispheight = 0;
	else
	{
		*dispx = (s16)(centerx + ny*scale/nx);
		*dispheight = (u16)(heightnumerator / (s16)(nx >> 8));
	}
	return nx < TILEGLOBAL && ny > -TILEGLOBAL/2 && ny < TILEGLOBAL/2;
}

//
// a frame's decisions, before it is drawn: WallRefresh's view, AsmRefresh's
// rays, then DrawScaleds' items and actors
//
void W32Visibility (void)
{
	statobj_t	*st;
	objtype		*obj;
	byte		*vs, *ts;
	int			x, dispx, disph, viewangle;

	if (mpplayers)
		return;							// the network game's are WL_MP.C's
	viewangle = player->angle;
	midangle = viewangle*(FINEANGLES/ANGLES);
	viewsin = sintable[viewangle];
	viewcos = costable[viewangle];
	viewx = player->x - FixedByFrac (focallength,viewcos);
	viewy = player->y + FixedByFrac (focallength,viewsin);
	focaltx = (int)(viewx >> TILESHIFT);
	focalty = (int)(viewy >> TILESHIFT);
	xpartialdown = (u16)(viewx & (TILEGLOBAL-1));
	xpartialup = (u16)(TILEGLOBAL - xpartialdown);
	ypartialdown = (u16)(viewy & (TILEGLOBAL-1));
	ypartialup = (u16)(TILEGLOBAL - ypartialdown);

	memset (spotvis,0,sizeof(spotvis));
	for (x=0;x<viewwidth;x++)
		Trace (x);

	// the items: one in view and in reach is taken
	for (st = &statobjlist[0];st != laststatobj;st++)
	{
		if (st->shapenum == -1)
			continue;
		if (!*st->visspot)
			continue;
		if (TransformTile (st->tilex,st->tiley,&dispx,&disph) && (st->flags & FL_BONUS))
			GetBonus (st);
	}

	// the actors: one in or beside a tile in view is woken, and seen
	for (obj = player->next;obj;obj = obj->next)
	{
		if (!obj->state || !obj->state->shapenum)
			continue;
		x = (obj->tilex<<6) + obj->tiley;
		if (x < 65 || x >= MAPSIZE*MAPSIZE-65)
			continue;
		vs = &spotvis[0][0] + x;
		ts = &tilemap[0][0] + x;
		if (*vs
		|| (vs[-1] && !ts[-1]) || (vs[1] && !ts[1])
		|| (vs[-65] && !ts[-65]) || (vs[-64] && !ts[-64]) || (vs[-63] && !ts[-63])
		|| (vs[65] && !ts[65]) || (vs[64] && !ts[64]) || (vs[63] && !ts[63]))
		{
			obj->active = true;
			TransformActor (obj);
			if (!obj->viewheight)
				continue;				// too close or too far: as it was
			obj->flags |= FL_VISABLE;
		}
		else
			obj->flags &= ~FL_VISABLE;
	}
}
