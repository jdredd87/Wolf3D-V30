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
void	ConnectAreas (void);
void	ClearPaletteShifts (void);
void	UpdatePaletteShifts (void);

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
int		far	tdsound, far tdrealtime;	// TIMEDEMO SOUND, REALTIME

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

		// SOUND: AdLib effects and music and Sound Blaster digitized sound for
		// this run, whatever CONFIG.WL6 says (TIMEDEMO never saves it).
		// REALTIME: demo steps at the game's own pace, to be listened to
		if ((a[0]|32) == 's' && (a[1]|32) == 'o' && (a[2]|32) == 'u'
		&& (a[3]|32) == 'n' && (a[4]|32) == 'd' && !a[5])
			tdsound = 1;
		if ((a[0]|32) == 'r' && (a[1]|32) == 'e' && (a[2]|32) == 'a' && (a[3]|32) == 'l'
		&& (a[4]|32) == 't' && (a[5]|32) == 'i' && (a[6]|32) == 'm' && (a[7]|32) == 'e' && !a[8])
			tdrealtime = 1;

		if ((a[0]|32) == 'm' && (a[1]|32) == 'o' && (a[2]|32) == 'r'
		&& (a[3]|32) == 't' && (a[4]|32) == 'a' && (a[5]|32) == 'l' && !a[6])
			mortal = 1;
	}
	if (tdmgen)
		godmode = !mortal;
}

static void Init (int players)
{
	mpplayers = players < 1 ? 1 : players > MAXPLAYERS ? MAXPLAYERS : players;
	_fmemset (mpctx,0,sizeof(mpctx));
	_fmemset (mptook,0,sizeof(mptook));
	if (mplocal >= mpplayers)
		mplocal = 0;
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
	Init (b[1]);
	return (char far *)b + 2 + 4*mpplayers;
}

//
// A start for player i "beside P1": the nearest open floor tile in P1's
// area -- no wall, no actor, no player already put there -- searching rings
// outward, each row by row.  The same search on every machine, so a server
// needs to know nothing of maps
//
static void Beside (int i, byte *x, byte *y)
{
	int	r,dx,dy,tx,ty,k,taken;
	int	px = objlist[0].tilex, py = objlist[0].tiley;
	int	area = objlist[0].areanumber;

	for (r=1;r<8;r++)
		for (dy=-r;dy<=r;dy++)
			for (dx=-r;dx<=r;dx++)
			{
				if (abs (dx) != r && abs (dy) != r)
					continue;
				tx = px+dx;
				ty = py+dy;
				if (tx < 1 || ty < 1 || tx > 62 || ty > 62 || tilemap[tx][ty] || actorat[tx][ty]
				|| *(mapsegs[0] + farmapylookup[ty]+tx) - AREATILE != area)
					continue;
				for (taken = 0,k=1;k<i;k++)
					if (mpctx[k].sx == tx && mpctx[k].sy == ty)
						taken = 1;
				if (!taken)
				{
					*x = tx;
					*y = ty;
					return;
				}
			}
	*x = px;						// nowhere: on P1
	*y = py;
}

//
// After SetupGameLevel: the other players, each at its start, and every
// player on the MP states.  P1 is objlist[0], the head of the actor list.
// starts: a start per player (x, y, direction, 0); x 0 is the map's own for
// P1, beside P1 (facing the same way) for the others
//
void MPSpawn (byte far *b)
{
	int		i;
	byte	sx,sy,sd;

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
		if (b[0])
		{
			sx = b[0];
			sy = b[1];
			sd = b[2];
		}
		else
		{
			Beside (i,&sx,&sy);
			sd = mpctx[0].sdir;
		}
		mpctx[i].sx = sx;
		mpctx[i].sy = sy;
		mpctx[i].sdir = sd;
		mpctx[i].dead = mpctx[i].deaths = 0;
		SpawnPlayer (sx,sy,sd);		// sets player's place and Thrust's globals
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
// Player i's controls for this step, from its 3 bytes (a demo's): button
// bits, turn, move.  P1's go in the globals (its context is home), the
// others' in their contexts
//
static void SetControls (int i, byte far *s)
{
	mpctx_t	far *c = &mpctx[i];
	boolean	far *now, far *held;
	int		b;
	byte	bits = s[0];

	if (i)
	{
		now = c->buttonstate;
		held = c->buttonheld;
	}
	else
	{
		now = (boolean far *)buttonstate;
		held = (boolean far *)buttonheld;
	}
	_fmemcpy (held,now,sizeof(buttonstate));
	for (b=0;b<NUMBUTTONS;b++)
	{
		now[b] = bits&1;
		bits >>= 1;
	}
	if (i)
	{
		c->controlx = (signed char)s[1] * (int)tics;
		c->controly = (signed char)s[2] * (int)tics;
	}
	else
	{
		controlx = (signed char)s[1] * (int)tics;
		controly = (signed char)s[2] * (int)tics;
	}
}

//
// PollControls, playing a demo: the other players' 3 bytes each, after P1's
//
void MPReadDemo (void)
{
	int		i;

	for (i=1;i<mpplayers;i++)
	{
		SetControls (i,(byte far *)demoptr);
		demoptr += 3;
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

	// the whole state is summed only every 50th step -- when it is compared
	// -- each sum chained to the one before: summed every step it cost the
	// V30 most of a frame (32-bit shifts are software on an 8086)
	if (++mpsteps % 50)
		return;
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
	if (mpsteps/50 <= MAXCHECKS)
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

/*
=============================================================================

						THE NETWORK GAME

WOLF3DM NET server [PORT n] [NAME x] [NETBOT]: join the server, and play the
map it names, every step from it.  MULTIPLAYER.md's "Protocol, version 1".
Each frame: this player's controls (or NETBOT's random ones, for testing
with nobody at the keyboard) to the server as INPUT; every packet in; every
step that has arrived played, in order, exactly as a demo's -- a SYNC every
50; then one picture, if anything was played.  ESC leaves.

=============================================================================
*/

int		NetStart (byte far *server, unsigned port, char far * far *why);
void	NetStop (void);
void	NetAsk (void);
int		NetReady (void);
void	NetSend (byte far *data, unsigned len);
void	NetPump (void (*take) (byte far *data, unsigned len));
void	NetStatus (char *s);
void	PollKeyboardButtons (void);
void	PollMouseButtons (void);
void	PollJoystickButtons (void);
void	PollKeyboardMove (void);
void	PollMouseMove (void);
void	PollJoystickMove (void);
extern	long	far netsentn, far netrecvn;

#define RING	128					// steps held, played or not

int		far	mpnet;				// NET given: 1
byte	far	mpserver[4];
unsigned far mpport = 31992;
int		far	mpbot;				// NETBOT: random controls of its own
char	far	mpname[17];
int		far	mpstate;			// 0 hello, 1 welcomed, 2 started, 3 over
byte	far	mpstart[4+4*MAXPLAYERS];	// START's players, map, skill, rules, starts
byte	far	mpring[RING][3*MAXPLAYERS];
long	far	mpringstep[RING];
long	far	mphave = -1;		// the highest step held with none missing
long	far	mpplayed = -1;		// the highest step played
unsigned far mpseq;
long	far	mpdesync = -1;		// the first step a DESYNC named
byte	far	mppkt[64+3*MAXPLAYERS*8];
unsigned far mpbotrnd = 1;
int		far	mpbotleft, far mpbotx, far mpboty, far mpbotb;

static void PutL (byte far *p, unsigned long v)
{
	p[0] = v;
	p[1] = v >> 8;
	p[2] = v >> 16;
	p[3] = v >> 24;
}

static unsigned long GetL (byte far *p)
{
	return p[0] | ((unsigned long)p[1] << 8) | ((unsigned long)p[2] << 16)
		| ((unsigned long)p[3] << 24);
}

static void Head (int kind)
{
	mppkt[0] = 'W';
	mppkt[1] = 'M';
	mppkt[2] = 1;
	mppkt[3] = kind;
}

//
// Everything from the server
//
static void Take (byte far *d, unsigned len)
{
	unsigned long first;
	int			count,players,i,n;
	long		s;

	if (len < 4 || d[0] != 'W' || d[1] != 'M' || d[2] != 1)
		return;
	switch (d[3])
	{
	case 2:							// WELCOME
		if (mpstate == 0 && len >= 6)
		{
			mplocal = d[4];
			mpstate = 1;
		}
		break;
	case 3:							// START
		if (mpstate == 1 && len >= 8)
		{
			n = d[4] > MAXPLAYERS ? MAXPLAYERS : d[4];
			_fmemset (mpstart,0,sizeof(mpstart));
			_fmemcpy (mpstart,d+4,4+4*n);
			mpstart[0] = n;
			mpstate = 2;
		}
		break;
	case 5:							// STEPS
		if (len < 10)
			break;
		first = GetL (d+4);
		count = d[8];
		players = d[9];
		if (players != mpplayers || len < 10 + count*3*players)
			break;
		for (i=0;i<count;i++)
		{
			s = first+i;
			if (s <= mphave || s > mpplayed + RING)
				continue;			// had it, or no room yet: it comes again
			_fmemcpy (mpring[s % RING],d+10+i*3*players,3*players);
			mpringstep[s % RING] = s;
		}
		while (mpringstep[(mphave+1) % RING] == mphave+1)
			mphave++;
		break;
	case 7:							// DESYNC
		if (mpdesync < 0 && len >= 9)
			mpdesync = GetL (d+4);
		break;
	case 8:							// BYE
		mpstate = 3;
		break;
	}
}

//
// This player's controls, as a demo would record them: button bits, turn,
// move -- PollControls' polling at DEMOTICS, without touching what the
// game is playing (the home context's globals are put back)
//
static void LocalInput (byte *bits, int *x, int *y)
{
	boolean	save[NUMBUTTONS],held[NUMBUTTONS];
	int		sx = controlx, sy = controly, st = tics, i;

	if (mpbot)
	{
		if (--mpbotleft <= 0)		// NETBOT: runs, turns and strafes, a few
		{							// frames each; fire now and then
			mpbotrnd = mpbotrnd*25173 + 13849;
			mpbotleft = 4 + (mpbotrnd >> 12);
			mpbotx = (int)((mpbotrnd >> 4) & 127) - 64;
			mpboty = (mpbotrnd & 0x100) ? -60 : (int)((mpbotrnd >> 2) & 63) - 32;
			mpbotb = ((mpbotrnd & 0x600) == 0x600) | ((mpbotrnd & 0x800) ? 4 : 0);
		}
		mpbotrnd = mpbotrnd*25173 + 13849;
		*bits = mpbotb | ((mpbotrnd & 0x700) == 0x700 ? 8 : 0);	// use, now and then
		*x = mpbotx;
		*y = mpboty;
		return;
	}
	memcpy (save,buttonstate,sizeof(save));
	memcpy (held,buttonheld,sizeof(held));
	tics = DEMOTICS;
	controlx = controly = 0;
	memset (buttonstate,0,sizeof(buttonstate));
	PollKeyboardButtons ();
	if (mouseenabled)
		PollMouseButtons ();
	if (joystickenabled)
		PollJoystickButtons ();
	PollKeyboardMove ();
	if (mouseenabled)
		PollMouseMove ();
	if (joystickenabled)
		PollJoystickMove ();
	if (controlx > 100*tics)
		controlx = 100*tics;
	if (controlx < -100*tics)
		controlx = -100*tics;
	if (controly > 100*tics)
		controly = 100*tics;
	if (controly < -100*tics)
		controly = -100*tics;
	*x = controlx/tics;
	*y = controly/tics;
	for (*bits = 0,i=NUMBUTTONS-1;i>=0;i--)
		*bits = (*bits << 1) | (buttonstate[i] ? 1 : 0);
	memcpy (buttonstate,save,sizeof(save));
	memcpy (buttonheld,held,sizeof(held));
	controlx = sx;
	controly = sy;
	tics = st;
}

static void SendInput (void)
{
	byte	bits;
	int		x,y;

	LocalInput (&bits,&x,&y);
	Head (4);
	mppkt[4] = mplocal;
	mppkt[5] = bits;
	mppkt[6] = x;
	mppkt[7] = y;
	mpseq++;
	mppkt[8] = mpseq;
	mppkt[9] = mpseq >> 8;
	PutL (mppkt+10,mphave < 0 ? 0xffffffffl : mphave);
	NetSend (mppkt,14);
}

static void Say (char far *s)
{
	char	line[80];

	CenterWindow (28,5);
	US_CPrint (s);
	NetStatus (line);				// what the network is doing
	US_CPrint ((char far *)line);
	VW_UpdateScreen ();
}

static void NetQuit (char far *why)
{
	char	buf[80];

	NetStop ();
	_fstrcpy ((char far *)buf,why);
	Quit (buf);
}

//
// The command line: NET a.b.c.d [PORT n] [NAME x] [NETBOT]
//
int MPNetArgs (void)
{
	int		i,k;

	for (i = 1;i < _argc;i++)
	{
		char	far *a = _argv[i];
		char	far *p = i+1 < _argc ? _argv[i+1] : a;
		unsigned n = 0;

		if ((a[0]|32) == 'n' && (a[1]|32) == 'e' && (a[2]|32) == 't' && !a[3])
		{
			int	v = 0, part = 0, digits = 0;

			for (;;p++)
				if (*p >= '0' && *p <= '9')
				{
					v = v*10 + *p - '0';
					digits++;
				}
				else
				{
					if (!digits || part > 3 || v > 255)
						break;
					mpserver[part++] = v;
					v = digits = 0;
					if (*p != '.')
						break;
				}
			if (part == 4)
				mpnet = 1;
		}
		if ((a[0]|32) == 'p' && (a[1]|32) == 'o' && (a[2]|32) == 'r' && (a[3]|32) == 't' && !a[4])
		{
			for (;*p >= '0' && *p <= '9';p++)
				n = n*10 + *p - '0';
			if (n)
				mpport = n;
		}
		if ((a[0]|32) == 'n' && (a[1]|32) == 'a' && (a[2]|32) == 'm' && (a[3]|32) == 'e' && !a[4])
		{
			for (k=0;k<16 && p[k];k++)
				mpname[k] = p[k];
			mpname[k] = 0;
		}
		if ((a[0]|32) == 'n' && (a[1]|32) == 'e' && (a[2]|32) == 't' && (a[3]|32) == 'b'
		&& (a[4]|32) == 'o' && (a[5]|32) == 't' && !a[6])
			mpbot = 1;
	}
	return mpnet;
}

static void NetLoop (void)
{
	long	lastsend = -100;
	int		n,i;

	playstate = TimeCount = lasttimecount = 0;
	frameon = 0;
	running = false;
	anglefrac = 0;
	facecount = 0;
	memset (buttonstate,0,sizeof(buttonstate));
	ClearPaletteShifts ();
	if (MousePresent)
		Mouse(MDelta);
	tics = DEMOTICS;
	SendInput ();					// "loaded": the server starts its clock
	do
	{
		NetPump (Take);
		if (TimeCount - lastsend >= 2)
		{
			lastsend = TimeCount;
			SendInput ();
		}
		for (n=0;n < 16 && mpplayed < mphave && !playstate;n++)
		{
			byte	far *row = mpring[++mpplayed % RING];

			for (i=0;i<mpplayers;i++)
				SetControls (i,row+3*i);
			madenoise = false;
			MoveDoors ();
			MovePWalls ();
			MPDoActors ();
			MPStep ();
			if (!(mpsteps % 50))
			{
				Head (6);
				mppkt[4] = mplocal;
				mppkt[5] = 0;
				PutL (mppkt+6,mpsteps);
				PutL (mppkt+10,mpsum);
				NetSend (mppkt,14);
			}
			UpdatePaletteShifts ();
			gamestate.TimeCount += tics;
		}
		if (n || !frameon)
		{
			MPCamera (true);
			ThreeDRefresh ();
			MPCamera (false);
		}
		UpdateSoundLoc ();
		if (screenfaded)
			VW_FadeIn ();
		if (Keyboard[sc_Escape] || mpstate == 3)
			playstate = ex_abort;
	} while (!playstate);
}

void MPNetGame (void)
{
	static char far joining[] = "Joining the server...";
	static char far waiting[] = "Waiting for the others...";
	static char far defname[] = "Player";
	static char far noanswer[] = "No answer from the server in 90 seconds";
	char	far *why;
	long	last = -100, began;
	int		i;

	if (!mpname[0])
		_fstrcpy (mpname,defname);
	if (!NetStart (mpserver,mpport,&why))
		NetQuit (why);
	Say (joining);
	began = TimeCount;
	while (mpstate < 2)				// HELLO until WELCOME, then wait for START
	{
		NetPump (Take);
		if (mpstate == 0 && TimeCount - began > 90*70)
			NetQuit (noanswer);		// nobody may be at this keyboard
		if (TimeCount - last >= 35)
		{
			last = TimeCount;
			if (mpstate == 0)
				Say (joining);
			if (!NetReady ())
				NetAsk ();
			else if (mpstate == 0)
			{
				Head (1);
				_fmemset (mppkt+4,0,16);
				_fstrcpy ((char far *)mppkt+4,mpname);
				PutL (mppkt+20,0x12345678l);	// the build -- to be the EXE's CRC
				mppkt[24] = 0xff;
				NetSend (mppkt,25);
			}
			else
				Say (waiting);
		}
		if (Keyboard[sc_Escape])
		{
			Head (8);
			mppkt[4] = mplocal;
			NetSend (mppkt,5);
			NetStop ();
			Quit (NULL);
		}
	}
	for (i=0;i<RING;i++)
		mpringstep[i] = -1;

	NewGame (mpstart[2],mpstart[1]/10);
	gamestate.mapon = mpstart[1] % 10;
	godmode = false;
	demoplayback = false;
	Init (mpstart[0]);
	VW_FadeOut ();
	SETFONTCOLOR(0,15);
	DrawPlayScreen ();
	VW_FadeIn ();
	startgame = false;
	SetupGameLevel ();
	MPSpawn (mpstart+4);
	StartMusic ();
	PM_CheckMainMem ();
	fizzlein = true;
	DrawLevel ();

	NetLoop ();

	Head (8);						// BYE
	mppkt[4] = mplocal;
	NetSend (mppkt,5);
	NetStop ();
	ShutdownId ();
	MPReport ();
	{
		static char far r[] = "net: %ld steps played, %ld held; packets sent %ld, received %ld; %Fs\n";
		static char far ok[] = "no desync", far bad[] = "DESYNC reported";
		char	s[90];

		_fstrcpy ((char far *)s,r);
		printf (s,mpplayed+1,mphave+1,netsentn,netrecvn,mpdesync < 0 ? (char far *)ok : (char far *)bad);
	}
	exit (0);
}

//
// TIMEDEMO SOUND: every sound device there is, for this run only
//
void MPSoundOn (void)
{
	if (!tdsound)
		return;
	if (AdLibPresent)
	{
		SD_SetSoundMode (sdm_AdLib);
		SD_SetMusicMode (smm_AdLib);
	}
	if (SoundBlasterPresent)
		SD_SetDigiDevice (sds_SoundBlaster);
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
