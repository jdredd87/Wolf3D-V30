/*
 * w32draw.c -- the 3-D view on Win32: ThreeDRefresh, in C, into w32gfx.c's
 * screen.  The DOS game's renderer is assembly for the V30 (WL_DR_A.ASM);
 * this is a new one, drawn as id's draws: id's projection (FOCALLENGTH, the
 * eye 0x5700 behind the player, 0xAF00 to the screen), id's texture columns
 * and flips (HitVertWall, HitHorizWall), doors at the tile's middle opened by
 * doorposition, a jamb beside a door (0x40), a moving pushwall (0xC0) moved
 * pwallpos/64 of a tile, the sprites' posts, their eight rotations
 * (CalcRotate), the weapon in hand.  The picture is not the game: nothing
 * here touches its state, and two machines' pictures may differ.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop
#include <math.h>

#define DOORWALL	(PMSpriteStart-8)

extern	byte	w32screen[320*200];
void	W32Present (byte *screen, byte *palette);
extern	byte	w32palette[768];

static unsigned vgaCeiling[]=		// WL_DRAW.C's, by episode and floor
{
#ifndef SPEAR
 0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0xbfbf,
 0x4e4e,0x4e4e,0x4e4e,0x1d1d,0x8d8d,0x4e4e,0x1d1d,0x2d2d,0x1d1d,0x8d8d,
 0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x1d1d,0x2d2d,0xdddd,0x1d1d,0x1d1d,0x9898,
 0x1d1d,0x9d9d,0x2d2d,0xdddd,0xdddd,0x9d9d,0x2d2d,0x4d4d,0x1d1d,0xdddd,
 0x7d7d,0x1d1d,0x2d2d,0x2d2d,0xdddd,0xd7d7,0x1d1d,0x1d1d,0x1d1d,0x2d2d,
 0x1d1d,0x1d1d,0x1d1d,0x1d1d,0xdddd,0xdddd,0x7d7d,0xdddd,0xdddd,0xdddd
#else
 0x6f6f,0x4f4f,0x1d1d,0xdede,0xdfdf,0x2e2e,0x7f7f,0x9e9e,0xaeae,0x7f7f,
 0x1d1d,0xdede,0xdfdf,0xdede,0xdfdf,0xdede,0xe1e1,0xdcdc,0x2e2e,0x1d1d,0xdcdc
#endif
};

static int	weaponscale[NUMWEAPONS] = {SPR_KNIFEREADY,SPR_PISTOLREADY,
				SPR_MACHINEGUNREADY,SPR_CHAINREADY};
static int	wdirangle[9] = {0,ANGLES/8,2*ANGLES/8,3*ANGLES/8,4*ANGLES/8,
				5*ANGLES/8,6*ANGLES/8,7*ANGLES/8,ANGLES};

static double	zbuf[320];			// each column's wall distance
static double	eyex,eyey,dirx,diry,rightx,righty,wscale;
static int		vx0,vy0;			// the view's corner on the screen

static void Put (int x, int y, int c)	// within the view
{
	if ((unsigned)x < (unsigned)viewwidth && (unsigned)y < (unsigned)viewheight)
		w32screen[(vy0+y)*320 + vx0+x] = (byte)c;
}

//
// a wall's column: texel column col of page, scaled to the distance
//
static void Column (int x, double perp, int page, int col)
{
	byte	*src = (byte *)PM_GetPage (page) + (col & 63)*64;
	double	h = wscale / perp;
	int		top = (int)floor (viewheight/2.0 - h/2), bot = (int)floor (viewheight/2.0 + h/2), y, t;

	for (y = top < 0 ? 0 : top;y < bot && y < viewheight;y++)
	{
		t = (int)((y - (viewheight/2.0 - h/2)) * 64 / h);
		Put (x,y,src[t < 0 ? 0 : t > 63 ? 63 : t]);
	}
}

//
// one ray: the grid stepped tile by tile until a wall, a door or the
// pushwall; its distance along the view (perp), for the sprites after
//
static void Ray (int x)
{
	double	cam = ((x + 0.5) - viewwidth/2.0) / viewwidth * 65536.0 / 44800.0;
	double	rx = dirx + rightx*cam, ry = diry + righty*cam;
	int		tx = (int)floor (eyex), ty = (int)floor (eyey);
	int		stepx = rx < 0 ? -1 : 1, stepy = ry < 0 ? -1 : 1;
	double	ddx = rx ? fabs (1/rx) : 1e30, ddy = ry ? fabs (1/ry) : 1e30;
	double	sx = rx < 0 ? (eyex - tx)*ddx : (tx + 1 - eyex)*ddx;
	double	sy = ry < 0 ? (eyey - ty)*ddy : (ty + 1 - eyey)*ddy;
	double	t = 0, hx, hy;
	int		side, tile, n, page, col;

	for (n=0;n<128;n++)
	{
		double	texit;					// where it leaves the tile it steps into

		if (sx < sy)
		{
			t = sx;
			sx += ddx;
			tx += stepx;
			side = 0;				// crossed a vertical line
		}
		else
		{
			t = sy;
			sy += ddy;
			ty += stepy;
			side = 1;
		}
		if ((unsigned)tx > 63 || (unsigned)ty > 63)
			break;
		texit = sx < sy ? sx : sy;
		tile = tilemap[tx][ty];
		if (!tile)
			continue;
		if ((tile & 0xc0) == 0xc0)		// the pushwall, on the move
		{
			double	off = pwallpos/64.0, bx0 = tx, by0 = ty, bx1, by1, tnear, tfar;
			double	t1,t2,t3,t4;

			switch (pwalldir)
			{
			case di_north:	by0 -= off; break;
			case di_south:	by0 += off; break;
			case di_east:	bx0 += off; break;
			case di_west:	bx0 -= off; break;
			}
			bx1 = bx0 + 1;
			by1 = by0 + 1;
			t1 = rx ? (bx0 - eyex)/rx : -1e30;	t2 = rx ? (bx1 - eyex)/rx : 1e30;
			t3 = ry ? (by0 - eyey)/ry : -1e30;	t4 = ry ? (by1 - eyey)/ry : 1e30;
			if (t1 > t2) { double k = t1; t1 = t2; t2 = k; }
			if (t3 > t4) { double k = t3; t3 = t4; t4 = k; }
			tnear = t1 > t3 ? t1 : t3;
			tfar = t2 < t4 ? t2 : t4;
			if (tnear > tfar || tnear < t - 1e-9 || tnear > texit)
				continue;				// through the gap it left
			hx = eyex + rx*tnear;
			hy = eyey + ry*tnear;
			if (t1 > t3)				// its x face
			{
				col = (int)((hy - by0)*64);
				if (stepx < 0)
					col = 63 - col;
				page = (tile & 63)*2 - 1;
			}
			else
			{
				col = (int)((hx - bx0)*64);
				if (stepy > 0)
					col = 63 - col;
				page = (tile & 63)*2 - 2;
			}
			zbuf[x] = tnear;
			Column (x,tnear,page,col);
			return;
		}
		if (tile & 0x80)				// a door: at the tile's middle
		{
			int		d = tile & 0x7f, lock = doorobjlist[d].lock;
			double	tm, frac;

			if (doorobjlist[d].vertical)
			{
				if (!rx)
					continue;
				tm = (tx + 0.5 - eyex)/rx;
				frac = eyey + ry*tm - ty;
			}
			else
			{
				if (!ry)
					continue;
				tm = (ty + 0.5 - eyey)/ry;
				frac = eyex + rx*tm - tx;
			}
			if (frac < 0 || frac >= 1 || tm < t || tm > texit)
				continue;				// out of the tile before the middle
			if (frac*65536.0 < doorposition[d])
				continue;				// the open part
			col = (int)((frac*65536.0 - doorposition[d]) / 1024);
			page = lock == dr_normal ? DOORWALL : lock == dr_elevator ? DOORWALL+4 : DOORWALL+6;
			if (doorobjlist[d].vertical)
				page++;
			zbuf[x] = tm;
			Column (x,tm,page,col);
			return;
		}
		hx = eyex + rx*t;
		hy = eyey + ry*t;
		if (!side)						// HitVertWall
		{
			col = (int)((hy - floor (hy))*64);
			if (stepx < 0)
				col = 63 - col;
			if ((tile & 0x40) && (tilemap[tx-stepx][ty] & 0x80))
				page = DOORWALL+3;		// beside a door: its jamb
			else
				page = (tile & 63)*2 - 1;
		}
		else							// HitHorizWall
		{
			col = (int)((hx - floor (hx))*64);
			if (stepy > 0)
				col = 63 - col;
			if ((tile & 0x40) && (tilemap[tx][ty-stepy] & 0x80))
				page = DOORWALL+2;
			else
				page = (tile & 63)*2 - 2;
		}
		zbuf[x] = t;
		Column (x,t,page,col);
		return;
	}
	zbuf[x] = 1e30;
}

/*
=============================================================================

						SPRITES

=============================================================================
*/

typedef struct
{
	double	depth,lateral;
	int		page;
} vissprite;

static vissprite	vis[MAXSTATS+MAXACTORS];
static int			nvis;

//
// a sprite's page (id's t_compshape): leftpix, rightpix, a word per column
// giving its posts -- each the end*2, the pixels' place less the start, and
// the start*2 -- ending at 0
//
static void Sprite (vissprite *v)
{
	byte	*shape = PM_GetPage (v->page);
	word	left = shape[0] | (shape[1] << 8), right = shape[2] | (shape[3] << 8);
	double	h = wscale / v->depth, cx = viewwidth/2.0 + v->lateral*wscale/v->depth;
	double	x0 = cx - h/2, top = viewheight/2.0 - h/2;
	int		x, xa = (int)floor (x0 + left*h/64), xb = (int)ceil (x0 + (right+1)*h/64);

	if (xa < 0)
		xa = 0;
	if (xb > viewwidth)
		xb = viewwidth;
	for (x=xa;x<xb;x++)
	{
		int		c = (int)((x + 0.5 - x0)*64/h), y;
		word	ofs, end, start;
		short	corr;
		byte	*post;

		if (c < (int)left || c > (int)right || v->depth >= zbuf[x])
			continue;
		ofs = shape[4+(c-left)*2] | (shape[5+(c-left)*2] << 8);
		post = shape + ofs;
		for (;;)
		{
			end = post[0] | (post[1] << 8);
			if (!end)
				break;
			corr = (short)(post[2] | (post[3] << 8));
			start = post[4] | (post[5] << 8);
			post += 6;
			end /= 2;
			start /= 2;
			{
				int	ya = (int)ceil (top + start*h/64 - 0.5), yb = (int)ceil (top + end*h/64 - 0.5);

				for (y = ya < 0 ? 0 : ya;y < yb && y < viewheight;y++)
				{
					int	ty = (int)((y + 0.5 - top)*64/h);

					if (ty < (int)start)
						ty = start;
					if (ty >= (int)end)
						ty = end - 1;
					Put (x,y,shape[(unsigned short)(corr + ty)]);
				}
			}
		}
	}
}

static void Add (double wx, double wy, int page)
{
	double	rx = wx - eyex, ry = wy - eyey;
	vissprite	*v;

	if (nvis >= MAXSTATS+MAXACTORS)
		return;
	v = &vis[nvis];
	v->depth = rx*dirx + ry*diry;
	if (v->depth < 0.25)				// behind, or at the eye
		return;
	v->lateral = rx*rightx + ry*righty;
	v->page = page;
	nvis++;
}

//
// id's CalcRotate: which of the eight views, from where the camera stands
//
static int Rotate (objtype *ob, double lateral, double depth)
{
	int	viewxs = (int)(viewwidth/2.0 + lateral*wscale/depth), angle, viewangle;

	viewangle = player->angle + (centerx - viewxs)/8;
	if (ob->obclass == rocketobj || ob->obclass == hrocketobj)
		angle = (viewangle-180) - ob->angle;
	else
		angle = (viewangle-180) - wdirangle[ob->dir];
	angle += ANGLES/16;
	while (angle >= ANGLES)
		angle -= ANGLES;
	while (angle < 0)
		angle += ANGLES;
	if (ob->state->rotate == 2)
		return 4*(angle/(ANGLES/2));
	return angle/(ANGLES/8);
}

static int Far (const void *a, const void *b)
{
	double	d = ((vissprite *)b)->depth - ((vissprite *)a)->depth;

	return d > 0 ? 1 : d < 0 ? -1 : 0;
}

static void Sprites (void)
{
	statobj_t	*st;
	objtype		*ob;
	int			i, shapenum;

	nvis = 0;
	for (st = &statobjlist[0];st != laststatobj;st++)
		if (st->shapenum != -1)
			Add (st->tilex + 0.5,st->tiley + 0.5,PMSpriteStart + st->shapenum);
	for (ob = &objlist[0];ob;ob = ob->next)
	{
		if (ob == player || !ob->state)
			continue;					// the camera's own (and none)
		shapenum = ob->state->shapenum;
		if (shapenum == -1)
			shapenum = ob->temp1;		// a player's (WL_MP.C's Spr), or such
		if (!shapenum)
			continue;
		{
			double	wx = ob->x/65536.0, wy = ob->y/65536.0;
			double	rx = wx - eyex, ry = wy - eyey;
			double	depth = rx*dirx + ry*diry, lateral = rx*rightx + ry*righty;

			if (depth < 0.25)
				continue;
			if (ob->state->rotate)
				shapenum += Rotate (ob,lateral,depth);
			Add (wx,wy,PMSpriteStart + shapenum);
		}
	}
	qsort (vis,nvis,sizeof(vissprite),Far);
	for (i=0;i<nvis;i++)
		Sprite (&vis[i]);
}

//
// the weapon in hand: id's SimpleScaleShape, the view's height, its middle
//
static void Weapon (void)
{
	vissprite	v;
	int			x;

	if (gamestate.weapon == -1)
		return;
	if (mpplayers && (MPDead () || MPDeadLook () >= 0))
		return;							// dead: no gun in hand
	for (x=0;x<viewwidth;x++)
		zbuf[x] = 1e30;
	v.page = PMSpriteStart + weaponscale[gamestate.weapon] + gamestate.weaponframe;
	v.lateral = 0;
	v.depth = wscale / (viewheight + 1);
	Sprite (&v);
}

/*
=============================================================================

						THE FRAME

=============================================================================
*/

void ThreeDRefresh (void)
{
	double	a = player->angle * M_PI / 180, fl = 0x5700/65536.0;
	int		x, y, ceiling = vgaCeiling[gamestate.episode*10+mapon] & 0xff;

	vx0 = (320 - viewwidth)/2;
	vy0 = (200 - STATUSLINES - viewheight)/2;
	dirx = cos (a);
	diry = -sin (a);					// y grows to the south
	rightx = -diry;
	righty = dirx;
	eyex = player->x/65536.0 - fl*dirx;	// the eye: FOCALLENGTH behind the player
	eyey = player->y/65536.0 - fl*diry;
	wscale = (viewwidth/2.0) / (32768.0/44800.0);
	for (y=0;y<viewheight;y++)			// VGAClearScreen: the ceiling, the floor
		memset (&w32screen[(vy0+y)*320 + vx0],y < viewheight/2 ? ceiling : 0x19,viewwidth);
	{
		static unsigned long	tw,ts,tp,nf,last,gap;
		extern unsigned long	w32waited, w32waits;
		unsigned long			t0 = W32Ms (), t1, t2;

		if (last)
			gap += t0 - last;
		last = t0;

		for (x=0;x<viewwidth;x++)
			Ray (x);
		t1 = W32Ms ();
		Sprites ();
		Weapon ();
		t2 = W32Ms ();
		tw += t1-t0;
		ts += t2-t1;
		if (getenv ("W3DFPS") && ++nf % 50 == 0)
			printf ("frame %lu: walls %lu ms, sprites %lu ms, present %lu ms (each, 50 frames)\n",
				nf,tw/50,ts/50,tp/50), printf ("  %lu ms a frame; W32Wait %lu times, %lu ms\n",gap/50,w32waits,w32waited),
				tw = ts = tp = gap = w32waits = w32waited = 0;
		t0 = W32Ms ();
		if (mpnet)
		{
			bufferofs += screenofs;
			MPOverlay ();
			bufferofs -= screenofs;
		}
		frameon++;
		W32Present (w32screen,w32palette);
		tp += W32Ms () - t0;
		return;
	}
	if (mpnet)
	{
		bufferofs += screenofs;			// as id's: the overlay is the view's
		MPOverlay ();
		bufferofs -= screenofs;
	}
	frameon++;
	W32Present (w32screen,w32palette);
}
