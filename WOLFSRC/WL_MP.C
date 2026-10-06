// WL_MP.C -- multiplayer, phase 1: up to four players in one game.
// Written by StevenC and Claude (Anthropic), 2026.  MULTIPLAYER.md has the plan.
//
// The game keeps one player in globals -- `player`, `gamestate`, the controls,
// the weapon timing.  Rather than rewrite every use, each extra player keeps a
// copy of those globals here (a context), and MPUse swaps one in: id's own
// T_Player and T_Attack then run unchanged for whichever player is in.  The
// home context, P1 (objlist[0], the head of the actor list), is in the globals
// between turns; the camera swaps in the local player only to draw.
//
// Nothing here runs unless mpplayers is set (TIMEDEMO MGEN n, so far): the
// single-player game is untouched, and the exact build's checksums prove it.
//
// Everything here is in far data: DGROUP is full.

#include "WL_DEF.H"
#pragma hdrstop
#include <stdarg.h>

#define MAXPLAYERS	4

extern	boolean		buttonstate[NUMBUTTONS];
extern	int			gotgatgun;
extern	objtype		*LastAttacker;
extern	long		playerxmove,playerymove;
extern	memptr		demobuffer;
extern	statetype	s_player,s_attack;

void	T_Player (objtype *ob);
void	T_Attack (objtype *ob);
void	MPAsm (int on, objtype *first);		// WL_DR_A.ASM: the renderer's MP hooks
void	AutomapPickup (void);				// WL_DR_A.ASM: GetBonus where the player stands

typedef struct
{
	objtype		*ob;
	gametype	gs;
	int			controlx,controly;
	boolean		buttonstate[NUMBUTTONS],buttonheld[NUMBUTTONS];
	boolean		running;
	long		thrustspeed;
	unsigned	plux,pluy;
	int			anglefrac,gotgatgun;
	objtype		*LastAttacker;
	long		playerxmove,playerymove;
	int			walkframe;					// the sprite's walk, by distance
	long		walkdist;
} mpctx_t;

mpctx_t	far	mpctx[MAXPLAYERS];
int		far	mpplayers;			// 0: single player
int		far	mplocal;			// whose eyes the screen shows (0-based)
int		far	mpcur;				// whose context is in the globals
int		far	tdmgen;				// TIMEDEMO MGEN n: n+1, else 0
unsigned long far mpsum;		// the game state's checksum, every step
long	far	mpsteps;
#define MAXCHECKS	64
unsigned long far mpcheck[MAXCHECKS];	// the sum at every 50th step
unsigned far mprnd;				// the face's own random numbers (see MPFace)

void	T_MPPlayer (objtype *ob);
void	T_MPAttack (objtype *ob);

// shapenum -1: the shape is ob->temp1 (PlaceActors), set from the walk below
statetype s_mpplayer = {true,-1,0,T_MPPlayer,NULL,NULL};
statetype s_mpattack = {false,-1,0,T_MPAttack,NULL,NULL};

/*
=============================================================================

						PRINTING (far strings)

=============================================================================
*/

static void mprintf (char far *fmt, ...)
{
	char	s[100];
	va_list	ap;

	_fstrcpy ((char far *)s,fmt);
	va_start (ap,fmt);
	vprintf (s,ap);
	va_end (ap);
}

/*
=============================================================================

						CONTEXTS

=============================================================================
*/

static void Save (int i)
{
	mpctx_t	far *c = &mpctx[i];
	int		j;

	c->ob = player;
	_fmemcpy (&c->gs,(gametype far *)&gamestate,sizeof(gametype));
	c->controlx = controlx;
	c->controly = controly;
	_fmemcpy (c->buttonstate,(boolean far *)buttonstate,sizeof(buttonstate));
	_fmemcpy (c->buttonheld,(boolean far *)buttonheld,sizeof(buttonheld));
	c->running = running;
	c->thrustspeed = thrustspeed;
	c->plux = plux;
	c->pluy = pluy;
	c->anglefrac = anglefrac;
	c->gotgatgun = gotgatgun;
	c->LastAttacker = LastAttacker;
	c->playerxmove = playerxmove;
	c->playerymove = playerymove;
	for (j=0;j<mpplayers;j++)		// keys: one player picks one up, every
		mpctx[j].gs.keys |= gamestate.keys;	// player has it (StevenC)
}

static void Load (int i)
{
	mpctx_t	far *c = &mpctx[i];

	player = c->ob;
	_fmemcpy ((gametype far *)&gamestate,&c->gs,sizeof(gametype));
	controlx = c->controlx;
	controly = c->controly;
	_fmemcpy ((boolean far *)buttonstate,c->buttonstate,sizeof(buttonstate));
	_fmemcpy ((boolean far *)buttonheld,c->buttonheld,sizeof(buttonheld));
	running = c->running;
	thrustspeed = c->thrustspeed;
	plux = c->plux;
	pluy = c->pluy;
	anglefrac = c->anglefrac;
	gotgatgun = c->gotgatgun;
	LastAttacker = c->LastAttacker;
	playerxmove = c->playerxmove;
	playerymove = c->playerymove;
}

void MPUse (int i)
{
	if (i == mpcur)
		return;
	Save (mpcur);
	Load (i);
	mpcur = i;
}

// is the player in the globals the one on this screen?  The status bar, the
// palette flashes and the face are only ever the local player's
boolean MPLocal (void)
{
	return !mpplayers || mpcur == mplocal;
}

static int Index (objtype *ob)
{
	int	i;

	for (i=0;i<mpplayers;i++)
		if (mpctx[i].ob == ob)
			return i;
	return 0;
}

/*
=============================================================================

						THE PLAYERS' THINKING

=============================================================================
*/

//
// After id's code has run: its states back to ours, and the sprite's frame.
// SPR_SS_* stand in until mp/mkbj.py's BJ is loaded
//
static void After (objtype *ob, int i)
{
	mpctx_t	far *c = &mpctx[i];
	long	moved;

	ob->dir = (dirtype)(((ob->angle + 22) / 45) & 7);	// for CalcRotate's 8 views
	if (ob->state == &s_attack)
		ob->state = &s_mpattack;
	else if (ob->state == &s_player)
		ob->state = &s_mpplayer;

	if (ob->state == &s_mpattack)
		ob->temp1 = SPR_SS_SHOOT1 + (gamestate.attackframe ? 1 : 0);
	else
	{
		moved = labs (playerxmove) + labs (playerymove);
		if (!moved)
			ob->temp1 = SPR_SS_S_1;
		else
		{
			c->walkdist += moved;
			if (c->walkdist >= TILEGLOBAL/2)
			{
				c->walkdist -= TILEGLOBAL/2;
				c->walkframe = (c->walkframe+1)&3;
			}
			ob->temp1 = SPR_SS_W1_1 + 8*c->walkframe;
		}
	}
}

static void Think (objtype *ob, void (*think) (objtype *))
{
	int	i = Index (ob);

	MPUse (i);
	playerxmove = playerymove = 0;
	think (ob);
	AutomapPickup ();				// items: picked up where the player stands,
	After (ob,i);					// not where a screen saw them
	MPUse (0);
}

void T_MPPlayer (objtype *ob)
{
	Think (ob,T_Player);
}

void T_MPAttack (objtype *ob)
{
	Think (ob,T_Attack);
}

/*
=============================================================================

						SETTING UP

=============================================================================
*/

//
// The command line: MGEN n (Mn.DEM, a multiplayer demo) and LOCAL n (whose
// eyes, 1-4).  Called from WL_MAIN.C's TIMEDEMO setup
//
void MPArgs (void)
{
	int		i;

	for (i = 1;i < _argc-1;i++)
	{
		char	far *a = _argv[i];
		char	far *p = _argv[i+1];
		int		n = 0;

		while (*p >= '0' && *p <= '9')
			n = n*10 + *p++ - '0';
		if ((a[0]|32) == 'm' && (a[1]|32) == 'g' && (a[2]|32) == 'e'
		&& (a[3]|32) == 'n' && !a[4])
			tdmgen = n+1;
		if ((a[0]|32) == 'l' && (a[1]|32) == 'o' && (a[2]|32) == 'c'
		&& (a[3]|32) == 'a' && (a[4]|32) == 'l' && !a[5] && n)
			mplocal = n-1;
	}
}

//
// Mn.DEM: 'M', the number of players, then a start for each (tile x, y,
// direction, 0; x 0 for P1 = the map's own), then id's demo format -- map,
// length, pad -- with every player's 3 bytes in each step, P1 first.
// Returns where id's format starts
//
char far *MPDemoLoad (int n)
{
	char	name[10];
	int		k = 0;
	byte	far *b;

	name[k++] = 'M';
	if (n >= 100)
		name[k++] = '0'+n/100;
	if (n >= 10)
		name[k++] = '0'+n/10%10;
	name[k++] = '0'+n%10;
	name[k++] = '.';
	name[k++] = 'D';
	name[k++] = 'E';
	name[k++] = 'M';
	name[k] = 0;
	CA_LoadFile (name,&demobuffer);
	MM_SetLock (&demobuffer,true);
	b = (byte far *)demobuffer;
	mpplayers = b[1] < 2 ? 2 : b[1] > MAXPLAYERS ? MAXPLAYERS : b[1];
	_fmemset (mpctx,0,sizeof(mpctx));
	if (mplocal >= mpplayers)
		mplocal = 0;
	return (char far *)b + 2 + 4*mpplayers;
}

//
// After SetupGameLevel: the other players, each at its start, and every
// player on the MP states.  P1 is objlist[0], the head of the actor list
//
void MPSpawn (void)
{
	byte	far *b = (byte far *)demobuffer + 2;
	int		i;

	if (b[0])
		SpawnPlayer (b[0],b[1],b[2]);
	mpcur = 0;
	Save (0);
	for (i=1;i<mpplayers;i++)
	{
		_fmemcpy (&mpctx[i],&mpctx[0],sizeof(mpctx_t));
		b += 4;
		GetNewActor ();
		player = new;
		mpctx[i].ob = new;
		Load (i);
		mpcur = i;
		SpawnPlayer (b[0],b[1],b[2]);	// sets player's place and Thrust's globals
		player->state = &s_mpplayer;
		player->temp1 = SPR_SS_S_1;
		player->flags = FL_NEVERMARK;
		Save (i);
		Load (0);
		mpcur = 0;
	}
	player->state = &s_mpplayer;
	player->temp1 = SPR_SS_S_1;
	MPAsm (1,&objlist[0]);			// the renderer: no pickups or waking, and
									// PlaceActors from the list's head
	InitAreas ();					// every player's area, now they all exist
	mpsum = 0;
	mpsteps = 0;
}

/*
=============================================================================

						EVERY STEP

=============================================================================
*/

//
// PollControls, playing a demo: the other players' 3 bytes each, after P1's
//
void MPReadDemo (void)
{
	int		i,b;
	byte	bits;

	for (i=1;i<mpplayers;i++)
	{
		mpctx_t	far *c = &mpctx[i];

		_fmemcpy (c->buttonheld,c->buttonstate,sizeof(c->buttonstate));
		bits = *demoptr++;
		for (b=0;b<NUMBUTTONS;b++)
		{
			c->buttonstate[b] = bits&1;
			bits >>= 1;
		}
		c->controlx = *demoptr++ * (int)tics;
		c->controly = *demoptr++ * (int)tics;
	}
}

//
// The areas: every player's, and all connected to any
//
void MPConnectAreas (boolean connect)
{
	int	i,a;

	memset (areabyplayer,0,sizeof(areabyplayer));
	for (i=0;i<mpplayers;i++)
	{
		objtype	*ob = i == mpcur ? player : mpctx[i].ob;

		if (!ob)
			continue;
		a = ob->areanumber;
		areabyplayer[a] = true;
		if (connect)
			RecursiveConnect (a);
	}
}

//
// The camera: the local player's context in, its own sprite out of the
// picture (s_player has no shape), and PlaceActors from the list's head
//
static statetype *camstate;

void MPCamera (boolean on)
{
	objtype	*ob;

	if (on)
	{
		MPUse (mplocal);
		ob = player;
		camstate = ob->state;
		ob->state = &s_player;
	}
	else
	{
		player->state = camstate;
		MPUse (0);
	}
}

//
// The game state's checksum, once a step: every actor, door, item and
// player.  Two machines -- or two cameras -- playing the same demo must agree
// on every step
//
static void Sum (unsigned long v)
{
	mpsum = (mpsum << 5) + (mpsum >> 27) + v;
}

void MPStep (void)
{
	objtype		*ob;
	statobj_t	*st;
	int			i;

	MPUse (0);
	Save (0);
	for (ob = &objlist[0];ob;ob = ob->next)
	{
		Sum (ob->x);
		Sum (ob->y);
		Sum (ob->angle);
		Sum (ob->hitpoints);
		Sum ((unsigned)ob->state);
		Sum (ob->ticcount);
		Sum (ob->flags & ~FL_VISABLE);
		Sum (ob->active);
		Sum (ob->dir);
	}
	for (st = &statobjlist[0];st != laststatobj;st++)
		Sum (st->shapenum);
	for (i=0;i<doornum;i++)
		Sum (doorposition[i]);
	for (i=0;i<mpplayers;i++)
	{
		Sum (mpctx[i].gs.health);
		Sum (mpctx[i].gs.ammo);
		Sum (mpctx[i].gs.keys);
		Sum (mpctx[i].gs.weapon);
		Sum (mpctx[i].gs.score);
	}
	mpsteps++;
	if (!(mpsteps % 50) && mpsteps/50 <= MAXCHECKS)
		mpcheck[mpsteps/50-1] = mpsum;
}

//
// The face in the status bar: only the local player's, with random numbers of
// its own -- id's skipped US_RndT while a sound played, and sound timing is
// not the same on two machines
//
void MPFace (void)
{
	if (!MPLocal ())
		return;
	facecount += tics;
	mprnd = mprnd*25173 + 13849;
	if (facecount > (mprnd >> 8))
	{
		mprnd = mprnd*25173 + 13849;
		gamestate.faceframe = (mprnd >> 14);
		if (gamestate.faceframe==3)
			gamestate.faceframe = 1;
		facecount = 0;
		DrawFace ();
	}
}

void MPReport (void)
{
	static char far r1[] = "mp: %d players, camera P%d, %ld steps, state sum %08lX\n";
	static char far r2[] = "mp step %4d: %08lX\n";
	static char far r3[] = "  P%d at %d,%d  health %d  ammo %d  keys %d  score %ld\n";
	int	i;

	MPUse (0);
	Save (0);
	mprintf (r1,mpplayers,mplocal+1,mpsteps,mpsum);
	for (i=0;i<MAXCHECKS && i < mpsteps/50;i++)
		mprintf (r2,(i+1)*50,mpcheck[i]);
	for (i=0;i<mpplayers;i++)
	{
		objtype	*ob = mpctx[i].ob;

		mprintf (r3,i+1,ob->tilex,ob->tiley,mpctx[i].gs.health,mpctx[i].gs.ammo,
			mpctx[i].gs.keys,mpctx[i].gs.score);
	}
}
