// WL_DRAW.C

#include "WL_DEF.H"
#include <DOS.H>
#pragma hdrstop

//#define DEBUGWALLS
//#define DEBUGTICS

/*
=============================================================================

						 LOCAL CONSTANTS

=============================================================================
*/

// the door is the last picture before the sprites
#define DOORWALL	(PMSpriteStart-8)

#define ACTORSIZE	0x4000

/*
=============================================================================

						 GLOBAL VARIABLES

=============================================================================
*/


#ifdef DEBUGWALLS
unsigned screenloc[3]= {0,0,0};
#else
unsigned screenloc[3]= {PAGE1START,PAGE2START,PAGE3START};
#endif
unsigned freelatch = FREESTART;

long 	lasttimecount;
long 	frameon;

unsigned	wallheight[MAXVIEWWIDTH];
int			pixstep = 1;				// NEC V30 build (step 79): 2 with LOWWALLS
int			lowsprites;					// NEC V30 build (step 80): 1 with LOWSPRITES
int			flatwalls;					// NEC V30 build (step 81): 1 with FLATWALLS, 2 once set up
int			solidart;					// NEC V30 build (step 84): 1 with FLATART
memptr		flatbuf;					// NEC V30 build (step 84): FLATWALLS' buffer, locked
int			farblobs;					// NEC V30 build (step 93): FARBLOBS' scale, 0 off
memptr		blobfill;					// ... and its compiled fill (WL_MAIN.C makes it)
int			lowvert;					// NEC V30 build (step 82): 1 with LOWVERT, 2 while displayed
#define	WALLPAGE(p)	(flatwalls ? FlatPage (p) : (unsigned)PM_GetPage (p))	// step 81

fixed	tileglobal	= TILEGLOBAL;
fixed	mindist		= MINDIST;


//
// math tables
//
int			pixelangle[MAXVIEWWIDTH];
long		far finetangent[FINEANGLES/4];
fixed 		far sintable[ANGLES+ANGLES/4],far *costable = sintable+(ANGLES/4);

//
// refresh variables
//
fixed	viewx,viewy;			// the focal point
int		viewangle;
fixed	viewsin,viewcos;



fixed	FixedByFrac (fixed a, fixed b);
void	BuildTables (void);
void	ClearScreen (void);
int		CalcRotate (objtype *ob);
void	DrawScaleds (void);
void	CalcTics (void);
void	FixOfs (void);
void	ThreeDRefresh (void);



//
// wall optimization variables
//
int		lastside;		// true for vertical
long	lastintercept;
extern	unsigned lastkey;	// WL_DR_A.ASM (step 51): invalidated wherever
							// lastside or lasttilehit change here
int		lasttilehit;


//
// ray tracing variables
//
int			focaltx,focalty,viewtx,viewty;

int			midangle,angle;
unsigned	xpartial,ypartial;
unsigned	xpartialup,xpartialdown,ypartialup,ypartialdown;
unsigned	xinttile,yinttile;

unsigned	tilehit;
unsigned	pixx;

int		xtile,ytile;
int		xtilestep,ytilestep;
long	xintercept,yintercept;
long	xstep,ystep;

int		horizwall[MAXWALLTILES],vertwall[MAXWALLTILES];


/*
=============================================================================

						 LOCAL VARIABLES

=============================================================================
*/


void AsmRefresh (void);			// in WL_DR_A.ASM
void DrawVisList (void);		// in WL_DR_A.ASM: DrawScaleds' drawing loop
void PlaceStatics (void);		// in WL_DR_A.ASM: DrawScaleds' static objects
void PlaceActors (void);		// in WL_DR_A.ASM: DrawScaleds' actors

/*
============================================================================

			   3 - D  DEFINITIONS

============================================================================
*/


//==========================================================================


/*
========================
=
= FixedByFrac
=
= multiply a 16/16 bit, 2's complement fixed point number by a 16 bit
= fraction, passed as a signed magnitude 32 bit number
=
========================
*/

#pragma warn -rvl			// I stick the return value in with ASMs

fixed FixedByFrac (fixed a, fixed b)
{
//
// setup
//
asm	mov	si,[WORD PTR b+2]	// sign of result = sign of fraction

asm	mov	ax,[WORD PTR a]
asm	mov	cx,[WORD PTR a+2]

asm	or	cx,cx
asm	jns	aok:				// negative?
asm	neg	cx
asm	neg	ax
asm	sbb	cx,0
asm	xor	si,0x8000			// toggle sign of result
aok:

//
// multiply  cx:ax by bx
//
asm	mov	bx,[WORD PTR b]
asm	mul	bx					// fraction*fraction
asm	mov	di,dx				// di is low word of result
asm	mov	ax,cx				//
asm	mul	bx					// units*fraction
asm add	ax,di
asm	adc	dx,0

//
// put result dx:ax in 2's complement
//
asm	test	si,0x8000		// is the result negative?
asm	jz	ansok:
asm	neg	dx
asm	neg	ax
asm	sbb	dx,0

ansok:;

}

#pragma warn +rvl

//==========================================================================

/*
========================
=
= TransformActor
=
= Takes paramaters:
=   gx,gy		: globalx/globaly of point
=
= globals:
=   viewx,viewy		: point of view
=   viewcos,viewsin	: sin/cos of viewangle
=   scale		: conversion from global value to screen value
=
= sets:
=   screenx,transx,transy,screenheight: projected edge location and size
=
========================
*/


//
// transform actor
//
// NEC V30 build (StevenC & Claude): TransformActor is TransformActorA in
// WL_DR_A.ASM, called NEAR from PlaceActors -- the same arithmetic, inline.

//==========================================================================

/*
========================
=
= TransformTile
=
= Takes paramaters:
=   tx,ty		: tile the object is centered in
=
= globals:
=   viewx,viewy		: point of view
=   viewcos,viewsin	: sin/cos of viewangle
=   scale		: conversion from global value to screen value
=
= sets:
=   screenx,transx,transy,screenheight: projected edge location and size
=
= Returns true if the tile is withing getting distance
=
========================
*/

// TransformTile is in WL_DR_A.ASM since the NEC V30 build (StevenC & Claude):
// the same arithmetic without the six far calls.
boolean TransformTile (int tx, int ty, int *dispx, int *dispheight);

//==========================================================================

/*
====================
=
= CalcHeight
=
= Calculates the height of xintercept,yintercept from viewx,viewy
=
====================
*/

#pragma warn -rvl			// I stick the return value in with ASMs

// CalcHeight is in WL_DR_A.ASM since the NEC V30 build (StevenC & Claude):
// the same arithmetic without the stack frame and the two calls per ray.
int	CalcHeight (void);


//==========================================================================

/*
===================
=
= ScalePost
=
===================
*/

long		postsource;
unsigned	postx;
unsigned	postwidth;

void	near ScalePostNow (void)		// VGA version (NEC V30 build: FarScalePost's,
{									// which draws outside a frame, for WL_DEBUG)
	// NEC V30 build (StevenC & Claude): the scalers load from ES and store to
	// DS, so the texture goes in ES and the screen in DS -- see BuildCompScale.
	asm	mov	bx,[postx]
	asm	shl	bx,1
	asm	mov	bp,WORD PTR [wallheight+bx]		// fractional height (low 3 bits frac)
	asm	and	bp,0xfff8				// bp = heightscaler*4
	asm	shr	bp,1
	asm	cmp	bp,[maxscaleshl2]
	asm	jle	heightok
	asm	mov	bp,[maxscaleshl2]
heightok:
	asm	add	bp,OFFSET fullscalefarcall
	//
	// scale a byte wide strip of wall
	//
	asm	mov	bx,[postx]
	asm	mov	di,bx
	asm	shr	di,2						// X in bytes
	asm	add	di,[bufferofs]

	asm	and	bx,3
	asm	shl	bx,3						// bx = pixel*8+pixwidth
	asm	add	bx,[postwidth]

	asm	mov	al,BYTE PTR [mapmasks1-1+bx]	// -1 because no widths of 0
	asm	mov	dx,SC_INDEX+1
	asm	out	dx,al						// set bit mask register
	asm	les	si,DWORD PTR [postsource]	// ES:SI = the texture column
	asm	mov	ax,SCREENSEG
	asm	mov	ds,ax						// DS = the screen
	asm	call DWORD PTR [bp]				// scale the line of pixels

	asm	mov	al,BYTE PTR [ss:mapmasks2-1+bx]   // -1 because no widths of 0
	asm	or	al,al
	asm	jz	nomore

	//
	// draw a second byte for vertical strips that cross two bytes
	//
	asm	inc	di
	asm	out	dx,al						// set bit mask register
	asm	call DWORD PTR [bp]				// scale the line of pixels

	asm	mov	al,BYTE PTR [ss:mapmasks3-1+bx]	// -1 because no widths of 0
	asm	or	al,al
	asm	jz	nomore
	//
	// draw a third byte for vertical strips that cross three bytes
	//
	asm	inc	di
	asm	out	dx,al						// set bit mask register
	asm	call DWORD PTR [bp]				// scale the line of pixels


nomore:
	asm	mov	ax,ss
	asm	mov	ds,ax
}

void  FarScalePost (void)				// just so other files can call
{
	ScalePostNow ();
}

//
// NEC V30 build (step 62), StevenC & Claude: the frame's posts are drawn by
// ScalePostA (WL_DR_A.ASM), which also fills the rows VGAClearScreen left to
// a wall when the wall turns out shorter.
//
void	ScalePostF (void);
void	DropFillF (void);		// step 92: the band for a post id drops

void	near ScalePost (void)
{
	ScalePostF ();
}


/*
====================
=
= HitVertWall
=
= tilehit bit 7 is 0, because it's not a door tile
= if bit 6 is 1 and the adjacent tile is a door tile, use door side pic
=
====================
*/

// HitVertWall is HitVertWallA in WL_DR_A.ASM since the NEC V30 build (StevenC & Claude):
// the same routine, called NEAR from AsmRefresh's ray loop.


/*
====================
=
= HitHorizWall
=
= tilehit bit 7 is 0, because it's not a door tile
= if bit 6 is 1 and the adjacent tile is a door tile, use door side pic
=
====================
*/

// HitHorizWall is HitHorizWallA in WL_DR_A.ASM since the NEC V30 build (StevenC & Claude):
// the same routine, called NEAR from AsmRefresh's ray loop.

//==========================================================================

/*
====================
=
= HitHorizDoor
=
====================
*/

void HitHorizDoor (void)
{
	unsigned	texture,doorpage,doornum;

	doornum = tilehit&0x7f;
	texture = ( ((unsigned)xintercept-doorposition[doornum]) >> 4) &0xfc0;	// low word only

	// NEC V30 build (StevenC & Claude): CalcHeight is not called for a wide-scale
	// column, whose height id computed and then overwrote with the one before;
	// the two branches that keep it compute it first thing.

	if (lasttilehit == tilehit)
	{
	// in the same door as last time, so check for optimized draw
		if (texture == (unsigned)postsource && pixstep < 4)	// (step 97)
		{
		// wide scale
			postwidth += pixstep;		// step 79: LOWDETAIL's two columns
			wallheight[pixx] = wallheight[pixx-pixstep];
			return;
		}
		else
		{
			wallheight[pixx] = CalcHeight();
			ScalePost ();
			(unsigned)postsource = texture;
			postwidth = pixstep;
			postx = pixx;
		}
	}
	else
	{
		wallheight[pixx] = CalcHeight();
		if (lastside != -1)				// if not the first scaled post
			ScalePost ();			// draw last post
		else if (pixx)					// step 92: id drops the pending post here
			DropFillF ();			// (a pushwall's): its band, not an old frame
	// first pixel in this door
		lastside = 2;
		lastkey = 0xFFFF;
		lasttilehit = tilehit;
		postx = pixx;
		postwidth = pixstep;

		switch (doorobjlist[doornum].lock)
		{
		case dr_normal:
			doorpage = DOORWALL;
			break;
		case dr_lock1:
		case dr_lock2:
		case dr_lock3:
		case dr_lock4:
			doorpage = DOORWALL+6;
			break;
		case dr_elevator:
			doorpage = DOORWALL+4;
			break;
		}

		*( ((unsigned *)&postsource)+1) = WALLPAGE(doorpage);
		(unsigned)postsource = texture;
	}
}

//==========================================================================

/*
====================
=
= HitVertDoor
=
====================
*/

void HitVertDoor (void)
{
	unsigned	texture,doorpage,doornum;

	doornum = tilehit&0x7f;
	texture = ( ((unsigned)yintercept-doorposition[doornum]) >> 4) &0xfc0;	// low word only

	// NEC V30 build (StevenC & Claude): CalcHeight is not called for a wide-scale
	// column, whose height id computed and then overwrote with the one before;
	// the two branches that keep it compute it first thing.

	if (lasttilehit == tilehit)
	{
	// in the same door as last time, so check for optimized draw
		if (texture == (unsigned)postsource && pixstep < 4)	// (step 97)
		{
		// wide scale
			postwidth += pixstep;		// step 79: LOWDETAIL's two columns
			wallheight[pixx] = wallheight[pixx-pixstep];
			return;
		}
		else
		{
			wallheight[pixx] = CalcHeight();
			ScalePost ();
			(unsigned)postsource = texture;
			postwidth = pixstep;
			postx = pixx;
		}
	}
	else
	{
		wallheight[pixx] = CalcHeight();
		if (lastside != -1)				// if not the first scaled post
			ScalePost ();			// draw last post
		else if (pixx)					// step 92: id drops the pending post here
			DropFillF ();			// (a pushwall's): its band, not an old frame
	// first pixel in this door
		lastside = 2;
		lastkey = 0xFFFF;
		lasttilehit = tilehit;
		postx = pixx;
		postwidth = pixstep;

		switch (doorobjlist[doornum].lock)
		{
		case dr_normal:
			doorpage = DOORWALL;
			break;
		case dr_lock1:
		case dr_lock2:
		case dr_lock3:
		case dr_lock4:
			doorpage = DOORWALL+6;
			break;
		case dr_elevator:
			doorpage = DOORWALL+4;
			break;
		}

		*( ((unsigned *)&postsource)+1) = WALLPAGE(doorpage+1);
		(unsigned)postsource = texture;
	}
}

//==========================================================================


/*
====================
=
= HitHorizPWall
=
= A pushable wall in action has been hit
=
====================
*/

void HitHorizPWall (void)
{
	int			wallpic;
	unsigned	texture,offset;

	texture = ((unsigned)xintercept>>4)&0xfc0;	// low word only: no long shift
	offset = pwallpos<<10;
	if (ytilestep == -1)
		yintercept += TILEGLOBAL-offset;
	else
	{
		texture = 0xfc0-texture;
		yintercept += offset;
	}

	// NEC V30 build (StevenC & Claude): CalcHeight is not called for a wide-scale
	// column, whose height id computed and then overwrote with the one before;
	// the two branches that keep it compute it first thing.

	if (lasttilehit == tilehit)
	{
		// in the same wall type as last time, so check for optimized draw
		if (texture == (unsigned)postsource && pixstep < 4)	// (step 97)
		{
		// wide scale
			postwidth += pixstep;		// step 79: LOWDETAIL's two columns
			wallheight[pixx] = wallheight[pixx-pixstep];
			return;
		}
		else
		{
			wallheight[pixx] = CalcHeight();
			ScalePost ();
			(unsigned)postsource = texture;
			postwidth = pixstep;
			postx = pixx;
		}
	}
	else
	{
		wallheight[pixx] = CalcHeight();
	// new wall
		if (lastside != -1)				// if not the first scaled post
			ScalePost ();
		else if (pixx)					// step 92: id drops the pending post here
			DropFillF ();			// (a pushwall's): its band, not an old frame

		lastkey = 0xFFFF;
		lasttilehit = tilehit;
		postx = pixx;
		postwidth = pixstep;

		wallpic = horizwall[tilehit&63];

		*( ((unsigned *)&postsource)+1) = WALLPAGE(wallpic);
		(unsigned)postsource = texture;
	}

}


/*
====================
=
= HitVertPWall
=
= A pushable wall in action has been hit
=
====================
*/

void HitVertPWall (void)
{
	int			wallpic;
	unsigned	texture,offset;

	texture = ((unsigned)yintercept>>4)&0xfc0;	// low word only: no long shift
	offset = pwallpos<<10;
	if (xtilestep == -1)
	{
		xintercept += TILEGLOBAL-offset;
		texture = 0xfc0-texture;
	}
	else
		xintercept += offset;

	// NEC V30 build (StevenC & Claude): CalcHeight is not called for a wide-scale
	// column, whose height id computed and then overwrote with the one before;
	// the two branches that keep it compute it first thing.

	if (lasttilehit == tilehit)
	{
		// in the same wall type as last time, so check for optimized draw
		if (texture == (unsigned)postsource && pixstep < 4)	// (step 97)
		{
		// wide scale
			postwidth += pixstep;		// step 79: LOWDETAIL's two columns
			wallheight[pixx] = wallheight[pixx-pixstep];
			return;
		}
		else
		{
			wallheight[pixx] = CalcHeight();
			ScalePost ();
			(unsigned)postsource = texture;
			postwidth = pixstep;
			postx = pixx;
		}
	}
	else
	{
		wallheight[pixx] = CalcHeight();
	// new wall
		if (lastside != -1)				// if not the first scaled post
			ScalePost ();
		else if (pixx)					// step 92: id drops the pending post here
			DropFillF ();			// (a pushwall's): its band, not an old frame

		lastkey = 0xFFFF;
		lasttilehit = tilehit;
		postx = pixx;
		postwidth = pixstep;

		wallpic = vertwall[tilehit&63];

		*( ((unsigned *)&postsource)+1) = WALLPAGE(wallpic);
		(unsigned)postsource = texture;
	}

}

//==========================================================================

//==========================================================================

#if 0
/*
=====================
=
= ClearScreen
=
=====================
*/

void ClearScreen (void)
{
 unsigned floor=egaFloor[gamestate.episode*10+mapon],
	  ceiling=egaCeiling[gamestate.episode*10+mapon];

  //
  // clear the screen
  //
asm	mov	dx,GC_INDEX
asm	mov	ax,GC_MODE + 256*2		// read mode 0, write mode 2
asm	out	dx,ax
asm	mov	ax,GC_BITMASK + 255*256
asm	out	dx,ax

asm	mov	dx,40
asm	mov	ax,[viewwidth]
asm	shr	ax,3
asm	sub	dx,ax					// dx = 40-viewwidth/8

asm	mov	bx,[viewwidth]
asm	shr	bx,4					// bl = viewwidth/16
asm	mov	bh,BYTE PTR [viewheight]
asm	shr	bh,1					// half height

asm	mov	ax,[ceiling]
asm	mov	es,[screenseg]
asm	mov	di,[bufferofs]

toploop:
asm	mov	cl,bl
asm	rep	stosw
asm	add	di,dx
asm	dec	bh
asm	jnz	toploop

asm	mov	bh,BYTE PTR [viewheight]
asm	shr	bh,1					// half height
asm	mov	ax,[floor]

bottomloop:
asm	mov	cl,bl
asm	rep	stosw
asm	add	di,dx
asm	dec	bh
asm	jnz	bottomloop


asm	mov	dx,GC_INDEX
asm	mov	ax,GC_MODE + 256*10		// read mode 1, write mode 2
asm	out	dx,ax
asm	mov	al,GC_BITMASK
asm	out	dx,al

}
#endif
//==========================================================================

unsigned vgaCeiling[]=
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

/*
=====================
=
= VGAClearScreen
=
=====================
*/

void VGAClearScreen (void)
{
 unsigned ceiling=vgaCeiling[gamestate.episode*10+mapon];
 unsigned half;
 unsigned rowadd = 0,floorn;		// NEC V30 build (step 82): LOWVERT's even rows
 static unsigned fill,skip;			// static: named in the asm below
 extern unsigned postmin,bandlim,bandhalf,bandtop,ceilcolor;

  //
  // NEC V30 build (step 62), StevenC & Claude: the scaler for scale i covers
  // rows half-i .. half+i-1 of every column it draws (scaler 0 is scaler 1),
  // and a wall post draws its whole column.  So the band the last frame's
  // least wall covered -- 32 of 120 rows on average -- is left out here, and
  // a post whose wall is shorter this frame fills its own part of it
  // (ScalePostA).  The walls always come next: only ThreeDRefresh calls this.
  //
 half = viewheight/2;
 skip = postmin>>2;					// the last frame's least scale
 if (!skip)
	skip = 1;
 if (skip > half)
	skip = half;
 fill = half-skip;					// rows of ceiling, and of floor
 bandhalf = skip;
 bandlim = skip >= 2 ? skip<<2 : 0;	// a coverage of 1 is every wall's
 bandtop = fill*SCREENBWIDE;
 ceilcolor = ceiling;
 skip *= 2*SCREENBWIDE;				// the band, in bytes
 floorn = fill;
 if (lowvert)						// NEC V30 build (step 82): the even rows only
 {
	unsigned fr = half+bandhalf;	// the floor's first row, made even
	fr += fr&1;
	floorn = (viewheight-fr)/2;
	fill = (fill+1)/2;				// the ceiling's even rows
	skip = (fr-2*fill)*SCREENBWIDE;
	rowadd = SCREENBWIDE;
 }

  //
  // clear the screen
  //
asm	mov	dx,SC_INDEX
asm	mov	ax,SC_MAPMASK+15*256	// write through all planes
asm	out	dx,ax

asm	mov	dx,80
asm	mov	ax,[viewwidth]
asm	shr	ax,2
asm	sub	dx,ax					// dx = 40-viewwidth/2
asm	add	dx,[rowadd]				// LOWVERT: and over the odd row

asm	mov	bx,[viewwidth]
asm	shr	bx,3					// bl = viewwidth/8
asm	mov	bh,BYTE PTR [fill]

asm	mov	es,[screenseg]
asm	mov	di,[bufferofs]
asm	mov	ax,[ceiling]
asm	xor	ch,ch					// NEC V30 build (StevenC & Claude): the loops
									// below load only CL.  id's ThreeDRefresh
									// cleared spotvis with a rep stosw every
									// frame just before, which left CX = 0; since
									// step 19 it does not, and a stray CH ran the
									// ceiling fill across the whole page, status
									// bar and all.  The view itself was redrawn
									// over it, so the view checksums never saw it.

asm	or	bh,bh
asm	jz	noceiling
toploop:
asm	mov	cl,bl
asm	rep	stosw
asm	add	di,dx
asm	dec	bh
asm	jnz	toploop
noceiling:

asm	add	di,[skip]				// over the band the walls cover
asm	mov	bh,BYTE PTR [floorn]
asm	or	bh,bh
asm	jz	nofloor
asm	mov	ax,0x1919

bottomloop:
asm	mov	cl,bl
asm	rep	stosw
asm	add	di,dx
asm	dec	bh
asm	jnz	bottomloop
nofloor:
	;
}

//==========================================================================

/*
=====================
=
= CalcRotate
=
=====================
*/

int	CalcRotate (objtype *ob)
{
	int	angle,viewangle;

	// this isn't exactly correct, as it should vary by a trig value,
	// but it is close enough with only eight rotations

	viewangle = player->angle + (centerx - ob->viewx)/8;

	if (ob->obclass == rocketobj || ob->obclass == hrocketobj)
		angle =  (viewangle-180)- ob->angle;
	else
		angle =  (viewangle-180)- dirangle[ob->dir];

	angle+=ANGLES/16;
	while (angle>=ANGLES)
		angle-=ANGLES;
	while (angle<0)
		angle+=ANGLES;

	if (ob->state->rotate == 2)             // 2 rotation pain frame
		return 4*(angle/(ANGLES/2));        // seperated by 3 (art layout...)

	return angle/(ANGLES/8);
}


/*
=====================
=
= DrawScaleds
=
= Draws all objects that are visable
=
=====================
*/

#define MAXVISABLE	50

typedef struct
{
	int	viewx,
		viewheight,
		shapenum;
} visobj_t;

visobj_t	vislist[MAXVISABLE],*visptr,*visstep,*farthest;

void DrawScaleds (void)
{
	int 		i,j,least,numvisable,height;
	memptr		shape;
	byte		*tilespot,*visspot;
	int			shapenum;
	unsigned	spotloc;

	statobj_t	*statptr;
	objtype		*obj;

//
// place static objects
//
	// NEC V30 build (StevenC & Claude): PlaceStatics in WL_DR_A.ASM -- the
	// same scan, TransformTile and GetBonus in the same order, in registers.
	// It sets visptr.
	PlaceStatics ();

//
// place active objects
//
	// NEC V30 build (StevenC & Claude): PlaceActors in WL_DR_A.ASM -- the same
	// loop, the same nine-spot test, the same stores and calls in the same order.
	PlaceActors ();

//
// draw from back to front
//
	numvisable = visptr-&vislist[0];

	if (!numvisable)
		return;									// no visable objects

	// NEC V30 build (StevenC & Claude): the back-to-front selection loop is
	// DrawVisList in WL_DR_A.ASM -- same order, first smallest viewheight
	// each pass, with its state in registers instead of memory.
	DrawVisList ();

}

//==========================================================================

/*
==============
=
= DrawPlayerWeapon
=
= Draw the player's hands
=
==============
*/

int	weaponscale[NUMWEAPONS] = {SPR_KNIFEREADY,SPR_PISTOLREADY
	,SPR_MACHINEGUNREADY,SPR_CHAINREADY};

void DrawPlayerWeapon (void)
{
	int	shapenum;

#ifndef SPEAR
	if (gamestate.victoryflag)
	{
		if (player->state == &s_deathcam && (TimeCount&32) )
			SimpleScaleShape(viewwidth/2,SPR_DEATHCAM,viewheight+1);
		return;
	}
#endif

	if (gamestate.weapon != -1)
	{
		shapenum = weaponscale[gamestate.weapon]+gamestate.weaponframe;
		SimpleScaleShape(viewwidth/2,shapenum,viewheight+1);
	}

	if (demorecord || demoplayback)
		SimpleScaleShape(viewwidth/2,SPR_DEMO,viewheight+1);
}


//==========================================================================


/*
=====================
=
= CalcTics
=
=====================
*/

void CalcTics (void)
{
	long	newtime,oldtimecount;

//
// calculate tics since last refresh for adaptive timing
//
	if (lasttimecount > TimeCount)
		TimeCount = lasttimecount;		// if the game was paused a LONG time

	do
	{
		newtime = TimeCount;
		tics = newtime-lasttimecount;
	} while (!tics);			// make sure at least one tic passes

	lasttimecount = newtime;

#ifdef FILEPROFILE
		strcpy (scratch,"\tTics:");
		itoa (tics,str,10);
		strcat (scratch,str);
		strcat (scratch,"\n");
		write (profilehandle,scratch,strlen(scratch));
#endif

	if (tics>MAXTICS)
	{
		TimeCount -= (tics-MAXTICS);
		tics = MAXTICS;
	}
}


//==========================================================================


/*
========================
=
= FixOfs
=
========================
*/

void	FixOfs (void)
{
	VW_ScreenToScreen (displayofs,bufferofs,viewwidth/8,viewheight);
}


//==========================================================================


/*
====================
=
= WallRefresh
=
====================
*/

/*
=====================
=
= FlatColours
=
= NEC V30 build (steps 81, 83), StevenC & Claude: FLATWALLS' colour for each
= wall page.  Its average -- of 255 of its pixels, a stride of 17 so no row
= or column dominates -- is taken once; then, at each new ceiling colour,
= the palette entry nearest it, or failing that nearest a darker or lighter
= average, that is at least 9 steps from the floor and the ceiling, and
= from the light twin's colour for a dark one: so no wall melts into what is
= above or below it, the two sides of a wall stay apart, and grey stays grey.
=
=====================
*/

#define FLATPAGES	128
#define FLATMIND	80			// 9 steps of 6-bit RGB, squared

#define FLATAVG(p,i)	(((byte far *)flatbuf)[640+(p)*3+(i)])	// step 84: in the buffer

static unsigned FlatNear (byte far *pal, int r, int g, int b)
{
	unsigned	i,d,bestd,best;
	int			dr,dg,db;

	bestd = 0xffff;
	best = 0;
	for (i = 0; i < 256; i++, pal += 3)
	{
		dr = pal[0]-r;
		dg = pal[1]-g;
		db = pal[2]-b;
		d = dr*dr+dg*dg+db*db;		// at most 3*63*63
		if (d < bestd)
		{
			bestd = d;
			best = i;
		}
	}
	return best;
}

static unsigned FlatDist (byte far *pal, unsigned a, unsigned b)
{
	int	dr,dg,db;

	dr = pal[a*3]-pal[b*3];
	dg = pal[a*3+1]-pal[b*3+1];
	db = pal[a*3+2]-pal[b*3+2];
	return dr*dr+dg*dg+db*db;
}

void FlatColours (unsigned ceiling)
{
	static char	ks[] = {20,17,23,14,26,11,29,8,32,5};	// in 20ths
	static int	averaged;
	unsigned	page,i,ofs,r,g,b,d,c,light;
	byte		far *src, far *pal;

	pal = &gamepal;
	light = 0;
	for (page = 0; page < PMSpriteStart && page < FLATPAGES; page++)
	{
		if (!averaged)
		{
			src = (byte far *)PM_GetPage (page);
			r = g = b = 0;					// at most 255*63: no overflow
			for (i = 0, ofs = 0; i < 255; i++, ofs = (ofs+17)&0xfff)
			{
				d = src[ofs]*3;
				r += pal[d];
				g += pal[d+1];
				b += pal[d+2];
			}
			FLATAVG(page,0) = r/255;
			FLATAVG(page,1) = g/255;
			FLATAVG(page,2) = b/255;
		}
		c = 0;
		for (i = 0; i < sizeof(ks); i++)
		{
			r = FLATAVG(page,0)*ks[i]/20;
			g = FLATAVG(page,1)*ks[i]/20;
			b = FLATAVG(page,2)*ks[i]/20;
			c = FlatNear (pal, r > 63 ? 63 : r, g > 63 ? 63 : g, b > 63 ? 63 : b);
			if (FlatDist (pal,c,0x19) >= FLATMIND && FlatDist (pal,c,ceiling) >= FLATMIND
			&& (!(page&1) || FlatDist (pal,c,light) >= FLATMIND))
				break;
		}
		if (i == sizeof(ks))				// nothing far enough: the nearest
			c = FlatNear (pal, FLATAVG(page,0), FLATAVG(page,1), FLATAVG(page,2));
		if (!(page&1))
			light = c;
		FlatColour (page,c);
	}
	averaged = 1;
}


void WallRefresh (void)
{
//
// set up variables for this view
//
	viewangle = player->angle;
	midangle = viewangle*(FINEANGLES/ANGLES);
	viewsin = sintable[viewangle];
	viewcos = costable[viewangle];
	viewx = player->x - FixedByFrac(focallength,viewcos);
	viewy = player->y + FixedByFrac(focallength,viewsin);

	focaltx = viewx>>TILESHIFT;
	focalty = viewy>>TILESHIFT;

	viewtx = player->x >> TILESHIFT;
	viewty = player->y >> TILESHIFT;

	xpartialdown = viewx&(TILEGLOBAL-1);
	xpartialup = TILEGLOBAL-xpartialdown;
	ypartialdown = viewy&(TILEGLOBAL-1);
	ypartialup = TILEGLOBAL-ypartialdown;

	lastside = -1;			// the first pixel is on a new wall
	lastkey = 0xFFFF;
	if (flatwalls)				// NEC V30 build (step 81): every post to
	{							// FlatPost, which only notes its colour
		extern unsigned bandlim;
		static unsigned flatceil = 0xffff;
		unsigned ceiling = vgaCeiling[gamestate.episode*10+mapon]&0xff;
		if (flatwalls == 1)
		{
			FlatSetup ();
			flatwalls = 2;
		}
		if (ceiling != flatceil)	// step 83: the colours, against this ceiling
		{
			FlatColours (ceiling);
			flatceil = ceiling;
		}
		bandlim = 0xFFFF;
	}
	AsmRefresh ();
	ScalePost ();			// no more optimization on last post
	if (pixstep > 1)			// NEC V30 build (step 79): LOWDETAIL cast every
	{							// other column (LOWWALLS4, step 97: every fourth);
		int	i, k;				// the sprites clip against them all
		for (i = 0; i < viewwidth; i += pixstep)
			for (k = 1; k < pixstep; k++)
				wallheight[i+k] = wallheight[i];
	}
	if (flatwalls)
		FlatRender ();			// NEC V30 build (step 81): the walls, at last
}

//==========================================================================

/*
========================
=
= ThreeDRefresh
=
========================
*/

void	ThreeDRefresh (void)
{
	int tracedir;

// this wouldn't need to be done except for my debugger/video wierdness
	outportb (SC_INDEX,SC_MAPMASK);

//
// clear out the traced array
//
// NEC V30 build (StevenC & Claude): not every frame any more.  The ray loop
// marks a tile with this frame's vismark, and "seen this frame" is
// spotvis[x][y] == vismark; the array is cleared only when vismark passes
// 255, every 255 frames, so no stale mark can ever equal the current one.
//
	if (lowvert == 1)			// NEC V30 build (step 82): show the even rows
	{
		VL_LowVert (1);
		lowvert = 2;
	}
	if (++vismark > 255)
	{
asm	mov	ax,ds
asm	mov	es,ax
asm	mov	di,OFFSET spotvis
asm	xor	ax,ax
asm	mov	cx,2048							// 64*64 / 2
asm	rep stosw
		vismark = 1;
	}

	bufferofs += screenofs;

//
// follow the walls from there to the right, drawwing as we go
//
	VGAClearScreen ();

	WallRefresh ();

//
// draw all the scaled images
//
	DrawScaleds();			// draw scaled stuff
	DrawPlayerWeapon ();	// draw player's hands

//
// show screen and time last cycle
//
	if (fizzlein)
	{
		FizzleFade(bufferofs,displayofs+screenofs,viewwidth,viewheight,20,false);
		if (tdcrc)
			FizzleCheck (bufferofs,displayofs+screenofs);	// TIMEDEMO CRC
		fizzlein = false;

		lasttimecount = TimeCount = 0;		// don't make a big tic count

	}

	bufferofs -= screenofs;
	displayofs = bufferofs;

	asm	cli
	asm	mov	cx,[displayofs]
	asm	mov	dx,3d4h		// CRTC address register
	asm	mov	al,0ch		// start address high register
	asm	out	dx,al
	asm	inc	dx
	asm	mov	al,ch
	asm	out	dx,al   	// set the high byte
	asm	sti

	bufferofs += SCREENSIZE;
	if (bufferofs > PAGE3START)
		bufferofs = PAGE1START;

	frameon++;
	PM_NextFrame();
}


//===========================================================================

