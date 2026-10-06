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
	int			dead,deaths,frags;			// dead: waiting to respawn
	long		deadtime;
	byte		sx,sy,sdir;					// where the player (re)spawns
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
int		far	mpnoise;			// who made this step's noise (madenoise)
long	far	mptook[MAXPLAYERS];	// damage each player has been dealt (the
								// report: god mode hides it from health)

void	T_MPPlayer (objtype *ob);
void	T_MPAttack (objtype *ob);
void	T_MPDead (objtype *ob);

// shapenum -1: the shape is ob->temp1 (PlaceActors), set from the walk below
statetype s_mpplayer = {true,-1,0,T_MPPlayer,NULL,NULL};
statetype s_mpattack = {false,-1,0,T_MPAttack,NULL,NULL};
statetype s_mpdead = {false,-1,0,T_MPDead,NULL,NULL};

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

						AIMING -- from geometry, not from a screen

id's GunAttack and KnifeAttack took their targets from the last frame drawn:
FL_VISABLE, and viewx within shootdelta of the screen's centre.  Each machine
draws only its own player, so in multiplayer the same shot would hit on one
and miss on another.  Here the shooter's own view is worked out instead, with
the same transform as id's TransformActor, and the screen-centre test turned
into the cone it is: |viewx-centerx| < shootdelta = viewwidth/10 is
|ny|*scale/nx < halfview/5, and scale = halfview*facedist/0x8000 with
facedist = FOCALLENGTH+MINDIST = 0xAF00 -- so |ny|*5*0xAF00 < nx*0x8000,
about 8 degrees either side, the same for every window size.  T_Shoot's
"the player can see to dodge" is the whole screen: |ny|*0xAF00 < nx*0x8000.

=============================================================================
*/

#define MPFOCAL		0x5700l			// FOCALLENGTH (WL_MAIN.C)
#define MPACTOR		0x4000l			// ACTORSIZE (WL_DRAW.C)

static long Transform (objtype *from, objtype *to, long *ny)
{
	fixed	vc = costable[from->angle], vs = sintable[from->angle];
	fixed	vx = from->x - FixedByFrac (MPFOCAL,vc);
	fixed	vy = from->y + FixedByFrac (MPFOCAL,vs);
	fixed	gx = to->x - vx, gy = to->y - vy;

	*ny = FixedByFrac (gy,vc) + FixedByFrac (gx,vs);
	return FixedByFrac (gx,vc) - FixedByFrac (gy,vs) - MPACTOR;
}

// to is in from's aim (the cone a shot can hit in); its distance in *dist
static boolean InAim (objtype *from, objtype *to, long *dist)
{
	long	ny, nx = Transform (from,to,&ny);

	*dist = nx;
	return nx >= MINDIST && (labs (ny) >> 3) * 875 < (nx >> 3) * 128;	// 5*0xAF00/0x8000
}

// A shot or a stab that found its target: an enemy takes it as id's code
// gives it; a player -- friendly fire, as DOOM's co-op -- takes it in its
// own context, from `by`
static void Hit (objtype *target, unsigned damage, objtype *by)
{
	int	a = mpcur;

	if (target->obclass != playerobj)
	{
		DamageActor (target,damage);
		return;
	}
	MPUse (Index (target));
	TakeDamage (damage,by);
	MPUse (a);
	madenoise = true;
	mpnoise = a;
}

// T_Shoot: can the player (the context) see ob, to dodge?
boolean MPSees (objtype *ob)
{
	long	ny, nx = Transform (player,ob,&ny);

	return nx >= MINDIST && (labs (ny) >> 3) * 175 < (nx >> 3) * 128;	// 0xAF00/0x8000
}

// GunAttack after its sound: id's targeting, statement for statement, with
// InAim for the screen
void MPGunHit (objtype *ob)
{
	objtype	*check,*closest,*oldclosest;
	int		damage,dx,dy,dist;
	long	viewdist,d;

	mpnoise = mpcur;				// GunAttack set madenoise: this player's

	viewdist = 0x7fffffffl;
	closest = NULL;
	while (1)
	{
		oldclosest = closest;
		for (check=&objlist[0] ; check ; check=check->next)
			if (check != ob && (check->flags & FL_SHOOTABLE)
			&& InAim (ob,check,&d) && d < viewdist)
			{
				viewdist = d;
				closest = check;
			}
		if (closest == oldclosest)
			return;						// no more targets, all missed
		if (CheckLine (closest))
			break;
	}
	dx = abs (closest->tilex - player->tilex);
	dy = abs (closest->tiley - player->tiley);
	dist = dx>dy ? dx:dy;
	if (dist<2)
		damage = US_RndT() / 4;
	else if (dist<4)
		damage = US_RndT() / 6;
	else
	{
		if ( (US_RndT() / 12) < dist)	// missed
			return;
		damage = US_RndT() / 6;
	}
	Hit (closest,damage,ob);
}

// KnifeAttack after its sound, the same way
void MPKnifeHit (objtype *ob)
{
	objtype	*check,*closest;
	long	dist,d;

	dist = 0x7fffffff;
	closest = NULL;
	for (check=&objlist[0] ; check ; check=check->next)
		if (check != ob && (check->flags & FL_SHOOTABLE)
		&& InAim (ob,check,&d) && d < dist)
		{
			dist = d;
			closest = check;
		}
	if (!closest || dist> 0x18000l)
		return;							// missed
	Hit (closest,US_RndT() >> 4,ob);
}

/*
=============================================================================

						ENEMIES -- every player is a target

An enemy keeps its target in flagspad, the pad byte after flags (the NEC V30
build's, there to keep the words after it even): no new memory, and
GetNewActor clears it.  As DOOM's monsters do: one that is not yet fighting
looks at each player in turn, and goes for whoever made a noise; one that is
fighting keeps its target -- and one that is hurt turns on whoever hurt it.
Its think and action then run with that player's context in the globals, so
id's sighting, chasing and shooting -- all of which read `player` and
`gamestate` -- see the target.

=============================================================================
*/

static int Target (objtype *ob)
{
	int	t = ob->flagspad;

	if (t >= mpplayers)
		t = 0;
	if (!(ob->flags & FL_ATTACKMODE))
	{
		if (madenoise)
			t = mpnoise;			// heard someone
		else if (++t == mpplayers)	// look at each player in turn
			t = 0;
		ob->flagspad = t;
	}
	if (mpctx[t].dead)				// dead: on to the next one alive
	{
		int	k;

		for (k=1;k<mpplayers;k++)
			if (!mpctx[(t+k)%mpplayers].dead)
			{
				t = (t+k)%mpplayers;
				ob->flagspad = t;
				break;
			}
	}
	return t;
}

// TakeDamage: the player in the globals is hit
void MPTook (int points)
{
	mptook[mpcur] += points;
}

// DamageActor: the player in the globals hurt ob
void MPHurt (objtype *ob)
{
	ob->flagspad = mpcur;
	mpnoise = mpcur;
}

/*
=============================================================================

						DYING AND RESPAWNING -- as DOOM

No lives.  A player at 0 health falls (the death frames, then a body on the
floor) and enemies leave them for someone alive; after a second, "use"
brings them back at their own start with 100 health, a pistol and 50 bullets
(StevenC: DOOM's 50).  Keys stay: one player's keys are everyone's.

=============================================================================
*/

// TakeDamage, health gone: the player in the globals
void MPDie (objtype *attacker)
{
	mpctx_t	far *c = &mpctx[mpcur];

	c->dead = 1;
	c->deadtime = 0;
	c->deaths++;
	if (attacker && attacker->obclass == playerobj)
	{
		int	k = Index (attacker);

		if (k == mpcur)
			mpctx[k].frags--;		// by one's own hand
		else
			mpctx[k].frags++;
	}
	player->state = &s_mpdead;
	player->temp1 = SPR_SS_DIE_1;
	if (actorat[player->tilex][player->tiley] == player)
		actorat[player->tilex][player->tiley] = NULL;
	player->flags = FL_NEVERMARK;	// a body: not solid, not shootable
}

// TakeDamage: already dead, nothing more to take
boolean MPDead (void)
{
	return mpctx[mpcur].dead;
}

static void Respawn (objtype *ob, int i)
{
	mpctx_t	far *c = &mpctx[i];

	c->dead = 0;
	gamestate.health = 100;
	gamestate.ammo = 50;
	gamestate.weapon = gamestate.bestweapon = gamestate.chosenweapon = wp_pistol;
	gamestate.attackframe = gamestate.attackcount = gamestate.weaponframe = 0;
	gamestate.faceframe = 0;
	SpawnPlayer (c->sx,c->sy,c->sdir);
	ConnectAreas ();				// SpawnPlayer's InitAreas left only the
	ob->state = &s_mpplayer;		// players' own areas
	ob->temp1 = SPR_SS_S_1;
	ob->flags = FL_SHOOTABLE;		// solid (DoActor marks it) and shootable
	if (MPLocal ())
	{
		DrawHealth ();
		DrawAmmo ();
		DrawWeapon ();
		DrawFace ();
		DrawKeys ();
	}
}

void T_MPDead (objtype *ob)
{
	int		i = Index (ob);
	mpctx_t	far *c = &mpctx[i];

	MPUse (i);
	c->deadtime += tics;
	ob->temp1 = c->deadtime < 15 ? SPR_SS_DIE_1 : c->deadtime < 30 ? SPR_SS_DIE_2
		: c->deadtime < 45 ? SPR_SS_DIE_3 : SPR_SS_DEAD;
	if (c->deadtime > 70 && buttonstate[bt_use] && !buttonheld[bt_use])
		Respawn (ob,i);
	MPUse (0);
}

// PlayLoop's actor loop in multiplayer: id's DoActor (WL_PLAY.C) for each,
// with its target's context in -- the players' own thinking swaps theirs
void MPDoActors (void)
{
	objtype	*ob;

	for (ob = &objlist[0];ob;ob = ob->next)
	{
		if (!ob->active && !areabyplayer[ob->areanumber])
			continue;
		if (ob->obclass != playerobj)
			MPUse (Target (ob));
		DoActor (ob);
	}
	MPUse (0);
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
	int		i,mortal = 0;

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
	for (i = 1;i < _argc;i++)		// MORTAL: no god mode -- players die
	{
		char	far *a = _argv[i];

		if ((a[0]|32) == 'm' && (a[1]|32) == 'o' && (a[2]|32) == 'r'
		&& (a[3]|32) == 't' && (a[4]|32) == 'a' && (a[5]|32) == 'l' && !a[6])
			mortal = 1;
	}
	if (tdmgen)
		godmode = !mortal;
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
	_fmemset (mptook,0,sizeof(mptook));
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
	mpctx[0].sx = player->tilex;	// P1: the map's own start, or the demo's
	mpctx[0].sy = player->tiley;
	mpctx[0].sdir = (1 - player->angle/90) & 3;	// SpawnPlayer: angle = (1-dir)*90
	for (i=1;i<mpplayers;i++)
	{
		_fmemcpy (&mpctx[i],&mpctx[0],sizeof(mpctx_t));
		b += 4;
		GetNewActor ();
		player = new;
		mpctx[i].ob = new;
		if (mpctx[i-1].ob->next != new)	// move it from the list's end to just
		{								// after the players before it
			objtype	*after = mpctx[i-1].ob;

			lastobj = new->prev;
			lastobj->next = NULL;
			new->prev = after;
			new->next = after->next;
			after->next->prev = new;
			after->next = new;
		}
		Load (i);
		mpcur = i;
		mpctx[i].sx = b[0];
		mpctx[i].sy = b[1];
		mpctx[i].sdir = b[2];
		mpctx[i].dead = mpctx[i].deaths = 0;
		SpawnPlayer (b[0],b[1],b[2]);	// sets player's place and Thrust's globals
		player->state = &s_mpplayer;
		player->temp1 = SPR_SS_S_1;
		player->flags = FL_SHOOTABLE;	// solid (DoActor marks it) and shootable
		Save (i);
		Load (0);
		mpcur = 0;
	}
	player->state = &s_mpplayer;
	player->temp1 = SPR_SS_S_1;
	player->flags = FL_SHOOTABLE;
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
		Sum (mpctx[i].deaths);
		Sum (mpctx[i].frags);
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
	static char far r3[] = "  P%d at %d,%d  health %d  ammo %d  keys %d  score %ld  took %ld  died %d  frags %d\n";
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
			mpctx[i].gs.keys,mpctx[i].gs.score,mptook[i],mpctx[i].deaths,mpctx[i].frags);
	}
}
