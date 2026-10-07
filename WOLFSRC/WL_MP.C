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
#include <io.h>
#include <fcntl.h>

#define MAXPLAYERS	4

extern	boolean		buttonstate[NUMBUTTONS];
extern	int			gotgatgun;
extern	objtype		*LastAttacker;
extern	long		playerxmove,playerymove;
extern	memptr		demobuffer;
extern	statetype	s_player,s_attack;

void	T_Player (objtype *ob);
void	T_Attack (objtype *ob);
void	LatchNumber (int x, int y, int width, long number);
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
	int			absent;						// nobody in this slot (the steps say)
	int			rejoined;					// came in during a tally: fresh stats
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
int		far	mprules;			// the server's rules (MULTIPLAYER.md):
#define RULE_DM			1		//   deathmatch, not co-op
#define RULE_NOFF		2		//   co-op: no friendly fire
#define RULE_NOENEMIES	4		//   no enemies spawned
long	far	mptook[MAXPLAYERS];	// damage each player has been dealt (the
								// report: god mode hides it from health)

void	T_MPPlayer (objtype *ob);
void	T_MPAttack (objtype *ob);
void	T_MPDead (objtype *ob);

// shapenum -1: the shape is ob->temp1 (PlaceActors), set from the walk below
statetype s_mpplayer = {true,-1,0,T_MPPlayer,NULL,NULL};
statetype s_mpattack = {false,-1,0,T_MPAttack,NULL,NULL};
statetype s_mpdead = {false,-1,0,T_MPDead,NULL,NULL};
statetype s_mpgone = {false,0,0,NULL,NULL,NULL};	// an empty slot: no shape, no think

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

						BJ -- the players' sprites

mp/mkbj.py writes VSWAPM.WL6: the player's own VSWAP.WL6 with BJ added at
the end of the sprite range, 49 frames in each player's colour (P1 grey,
P2 green, P3 red, P4 brown), each block in the SS's own frame order.  When
it is there WOLF3DM opens it instead (MPPageFile, before the page manager
starts), and a player's frame is the BJ sprite at the SS frame's place.

=============================================================================
*/

int		far	mpbjfile;			// VSWAPM.WL6 is the page file
int		far	mpbjbase = -1;		// its first BJ sprite, or -1: the SS

void MPPageFile (void)
{
	static char far stem[] = "VSWAPM.";
	char	name[13];
	int		h;

	_fstrcpy ((char far *)name,stem);
	strcat (name,extension);
	h = open (name,O_RDONLY | O_BINARY);
	if (h == -1)
		return;
	close (h);
	strcpy (PageFileName,name);
	mpbjfile = 1;
}

static int Spr (int i, int ss)
{
	if (mpbjbase < 0 && mpbjfile)
		mpbjbase = PMSoundStart - PMSpriteStart - 4*49;
	if (mpbjbase < 0)
		return ss;
	return mpbjbase + (i & 3)*49 + (ss - SPR_SS_S_1);
}

/*
=============================================================================

						THE PLAYERS' THINKING

=============================================================================
*/

//
// After id's code has run: its states back to ours, and the sprite's frame.
// the frames: BJ, in the player's colour, from VSWAPM.WL6 (Spr, below);
// the SS's own when it is not there
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
		ob->temp1 = Spr (i,SPR_SS_SHOOT1 + (gamestate.attackframe ? 1 : 0));
	else
	{
		moved = labs (playerxmove) + labs (playerymove);
		if (!moved)
			ob->temp1 = Spr (i,SPR_SS_S_1);
		else
		{
			c->walkdist += moved;
			if (c->walkdist >= TILEGLOBAL/2)
			{
				c->walkdist -= TILEGLOBAL/2;
				c->walkframe = (c->walkframe+1)&3;
			}
			ob->temp1 = Spr (i,SPR_SS_W1_1 + 8*c->walkframe);
		}
	}
}

objtype	*mpsrc;						// whose thinking is running, or NULL (HEARING)

//
// Where a bonus may lie, a bit a tile: set wherever a bonus static is made
// (SpawnStatic, PlaceItemType), cleared with the list -- never on a pickup,
// so a superset.  The players' pickups (AutomapPickup, a scan of the whole
// static list) look only there: that scan, for every player every step, was
// 16% of the V30's time in a four-player game on E1M2
//
byte	far	mpbonus[64*64/8];

void MPBonusClear (void)
{
	_fmemset (mpbonus,0,sizeof(mpbonus));
}

void MPBonusAt (int x, int y)
{
	mpbonus[(x<<3) | (y>>3)] |= 1 << (y&7);
}

static void Think (objtype *ob, void (*think) (objtype *))
{
	int	i = Index (ob);

	MPUse (i);
	mpsrc = ob;						// its sounds come from where it stands
	playerxmove = playerymove = 0;
	think (ob);
	if (mpbonus[(player->tilex<<3) | (player->tiley>>3)] & (1 << (player->tiley&7)))
		AutomapPickup ();			// items: picked up where the player stands,
	After (ob,i);					// not where a screen saw them
	mpsrc = NULL;
	MPUse (0);
}

/*
=============================================================================

						HEARING

Every machine plays every player's game, so without this each one hears
every gun fired and every item taken anywhere on the map, at full volume.
As DOOM: a sound is heard only near the local player's eyes.  A located
sound (PlaySoundLocGlobal) is where it says; any other comes from the actor
whose thinking made it (mpsrc) -- another player's pistol from that player,
panned there on a Sound Blaster.  Only what is played changes, never the
game: SD_PlaySound's answer decides nothing but the sound location.

=============================================================================
*/

#define HEARTILES	16				// DOOM's clipping distance is ~19 tiles


int		far	mplocated;				// PlaySoundLocGlobal: mpsndx,y are set
int		far	mpcatching;				// joining late: playing every step, fast
long	far	mpcaught, far mpcaughtticks;	// steps so played, and in how long
fixed	far	mpsndx, far mpsndy;

boolean MPHear (void)
{
	fixed	x,y;

	if (!mpplayers)
		return true;
	if (mpcatching)
		return false;				// a game played fast to catch up: silent
	if (mplocated)
	{
		x = mpsndx;
		y = mpsndy;
	}
	else
	{
		if (!mpsrc || mpsrc == mpctx[mplocal].ob)
			return true;			// our own, or from nowhere in particular
		x = mpsrc->x;
		y = mpsrc->y;
		SetSoundLoc (x,y);			// panned where it was made
		SD_PositionSound (leftchannel,rightchannel);
		globalsoundx = x;
		globalsoundy = y;
	}
	return labs (x - viewx) < (long)HEARTILES*TILEGLOBAL
		&& labs (y - viewy) < (long)HEARTILES*TILEGLOBAL;
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

// co-op with friendly fire off: another player is no target -- a shot
// passes through to what is behind
static boolean Friend (objtype *ob)
{
	return ob->obclass == playerobj && (mprules & (RULE_DM|RULE_NOFF)) == RULE_NOFF;
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
			if (check != ob && (check->flags & FL_SHOOTABLE) && !Friend (check)
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
		if (check != ob && (check->flags & FL_SHOOTABLE) && !Friend (check)
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
	if (mpctx[t].dead || mpctx[t].absent)	// dead or gone: on to the next one
	{
		int	k;

		for (k=1;k<mpplayers;k++)
			if (!mpctx[(t+k)%mpplayers].dead && !mpctx[(t+k)%mpplayers].absent)
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
	player->temp1 = Spr (mpcur,SPR_SS_DIE_1);
	if (actorat[player->tilex][player->tiley] == player)
		actorat[player->tilex][player->tiley] = NULL;
	player->flags = FL_NEVERMARK;	// a body: not solid, not shootable
}

// Cmd_Use: may the elevator end the level?  Not in deathmatch
boolean MPExitOK (void)
{
	return !(mprules & RULE_DM);
}

// TakeDamage: already dead, nothing more to take
boolean MPDead (void)
{
	return mpctx[mpcur].dead;
}

//
// Deathmatch: a start somewhere on the map -- open floor, no actor, no
// player within four tiles -- picked the same way on every machine (from
// the step count and the player), as DOOM picks a deathmatch start
//
static void DMStart (int i, byte *x, byte *y)
{
	unsigned	n,k,tries;
	int			tx,ty,j;
	objtype		*o;

	n = (unsigned)(mpsteps*7919 + i*104729);
	for (tries = 0;tries < 400;tries++)
	{
		n = n*25173 + 13849;
		tx = 1 + (n >> 4) % 62;
		n = n*25173 + 13849;
		ty = 1 + (n >> 4) % 62;
		if (tilemap[tx][ty] || actorat[tx][ty]
		|| *(mapsegs[0] + farmapylookup[ty]+tx) < AREATILE)
			continue;
		for (k = 1,j=0;j<mpplayers;j++)
		{
			o = mpctx[j].ob;
			if (j != i && o && abs (o->tilex - tx) < 4 && abs (o->tiley - ty) < 4)
				k = 0;
		}
		if (k)
		{
			*x = tx;
			*y = ty;
			return;
		}
	}
	*x = mpctx[i].sx;
	*y = mpctx[i].sy;
}

static void Respawn (objtype *ob, int i)
{
	mpctx_t	far *c = &mpctx[i];
	byte	x,y;

	c->dead = 0;
	gamestate.health = 100;
	gamestate.ammo = 50;
	gamestate.weapon = gamestate.bestweapon = gamestate.chosenweapon = wp_pistol;
	gamestate.attackframe = gamestate.attackcount = gamestate.weaponframe = 0;
	gamestate.faceframe = 0;
	if (mprules & RULE_DM)
	{
		DMStart (i,&x,&y);
		gamestate.keys = 3;			// deathmatch: every door, as DOOM
		SpawnPlayer (x,y,c->sdir);
	}
	else
		SpawnPlayer (c->sx,c->sy,c->sdir);
	ConnectAreas ();				// SpawnPlayer's InitAreas left only the
	ob->state = &s_mpplayer;		// players' own areas
	ob->temp1 = Spr (i,SPR_SS_S_1);
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

/*
=============================================================================

						JOINING AND LEAVING -- a running game

The server keeps a game going while people come and go.  A slot's presence
is in every step: an empty slot's 3 bytes are 0, -128, -128 -- a turn and a
move id's PollControls clamps to 100 a tic never are -- so every machine
sees a player arrive or go at the same step, and does the same.  One who
goes vanishes: no body, nothing to hit, nobody's target.  One who comes is
a new player, as DOOM's: in as from a respawn, score and frags at 0.  A slot
nobody has taken is empty from the first step.  In a tally only the slot's
state changes; the next floor puts the world right.

=============================================================================
*/

int		far	mpintally;			// the tally: presence noted, the world waits
int		far	mplocalin;			// this machine's player has been in the game
int		far	mpdropped;			// ... and the server has let it go

static void Leave (int i)
{
	mpctx_t	far *c = &mpctx[i];
	objtype	*ob = c->ob;

	c->absent = 1;
	c->dead = 0;
	if (actorat[ob->tilex][ob->tiley] == ob)
		actorat[ob->tilex][ob->tiley] = NULL;
	ob->flags = FL_NEVERMARK;		// not solid, not shootable
	ob->state = &s_mpgone;			// no shape: not drawn
	ob->ticcount = 0;
}

static void Join (int i)
{
	mpctx_t	far *c = &mpctx[i];

	MPUse (i);
	c->absent = 0;
	c->deaths = c->frags = 0;
	c->deadtime = 0;
	gamestate.score = gamestate.oldscore = 0;
	gamestate.nextextra = EXTRAPOINTS;
	Respawn (player,i);				// 100 health, a pistol, 50 bullets, a start
	MPUse (0);
}

static void Presence (int i, int present)
{
	mpctx_t	far *c = &mpctx[i];

	if (present == !c->absent)
		return;
	if (i == mplocal)
	{
		if (present)
			mplocalin = 1;
		else if (mplocalin)
			mpdropped = 1;			// the server stopped hearing this machine
	}
	if (mpintally)
	{
		c->absent = !present;
		if (present)
			c->rejoined = 1;
		return;
	}
	if (present)
		Join (i);
	else
		Leave (i);
}

static int Gone (byte far *s)
{
	return s[1] == 0x80 && s[2] == 0x80;
}

void T_MPDead (objtype *ob)
{
	int		i = Index (ob);
	mpctx_t	far *c = &mpctx[i];

	MPUse (i);
	mpsrc = ob;
	c->deadtime += tics;
	ob->temp1 = Spr (i,c->deadtime < 15 ? SPR_SS_DIE_1 : c->deadtime < 30 ? SPR_SS_DIE_2
		: c->deadtime < 45 ? SPR_SS_DIE_3 : SPR_SS_DEAD);
	if (c->deadtime > 70 && buttonstate[bt_use] && !buttonheld[bt_use])
		Respawn (ob,i);
	mpsrc = NULL;
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
		mpsrc = ob;					// an enemy's sounds come from the enemy
		DoActor (ob);
	}
	mpsrc = NULL;
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
	mprules = mpplayers > 1 ? b[2+4+3] : 0;	// P2's start's 4th byte
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
		else if (mprules & RULE_DM)
		{
			DMStart (i,&sx,&sy);		// deathmatch: scattered, as DOOM
			sd = mpctx[0].sdir;
		}
		else
		{
			Beside (i,&sx,&sy);
			sd = mpctx[0].sdir;
		}
		mpctx[i].sx = sx;
		mpctx[i].sy = sy;
		mpctx[i].sdir = sd;
		mpctx[i].dead = mpctx[i].deaths = mpctx[i].frags = 0;
		mpctx[i].deadtime = 0;
		SpawnPlayer (sx,sy,sd);		// sets player's place and Thrust's globals
		player->state = &s_mpplayer;
		player->temp1 = Spr (i,SPR_SS_S_1);
		player->flags = FL_SHOOTABLE;	// solid (DoActor marks it) and shootable
		Save (i);
		Load (0);
		mpcur = 0;
	}
	player->state = &s_mpplayer;
	player->temp1 = Spr (0,SPR_SS_S_1);
	player->flags = FL_SHOOTABLE;
	MPAsm (1,&objlist[0]);			// the renderer: no pickups or waking, and
									// PlaceActors from the list's head
	InitAreas ();					// every player's area, now they all exist
	if (mprules & RULE_DM)
		for (i=0;i<mpplayers;i++)
			mpctx[i].gs.keys = 3;	// deathmatch: every door
	if (mprules & RULE_DM)
		gamestate.keys = 3;
	if (mprules & RULE_NOENEMIES)
	{
		objtype	*ob,*next;

		for (ob = &objlist[0];ob;ob = next)
		{
			next = ob->next;
			if (ob->obclass == playerobj)
				continue;
			if (actorat[ob->tilex][ob->tiley] == ob)
				actorat[ob->tilex][ob->tiley] = NULL;
			RemoveObj (ob);
		}
		gamestate.killtotal = 0;
	}
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
	static byte far none[3];
	mpctx_t	far *c = &mpctx[i];
	boolean	far *now, far *held;
	int		b;
	byte	bits;

	Presence (i,!Gone (s));			// (first: Join swaps contexts)
	if (Gone (s))
		s = none;
	bits = s[0];

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

	if (Gone ((byte far *)demoptr - 3))	// P1's, which id's code has just read
	{
		controlx = controly = 0;
		memset (buttonstate,0,sizeof(buttonstate));
		Presence (0,0);
	}
	else
		Presence (0,1);

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

		if (!ob || mpctx[i].absent)
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
unsigned far mpfraglimit;		// WELCOME: deathmatch ends a level at these
unsigned far mptimelimit;		//   frags, or minutes (0: none)
long	far	mpheard;			// TimeCount when the server was last heard
long	far	mpframes, far mpticks;	// pictures drawn, and in how long
int		far	mpend;				// why it ended: 0 the game, 1 ESC Y, 2 BYE, 3 silence,
									// 4 dropped by the server
int		far	mpbye;				// BYE's reason: 0 the end, 1 full, 2 another build,
									// 3 this machine dropped
#define DEAF	(15*70)			// silent this long: the server is gone
int		far	mpwhy;				// why the level ended: 0 elevator, 1 frags, 2 time
extern	int	ElevatorBackTo[];	// WL_GAME.C
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
	mpheard = TimeCount;
	switch (d[3])
	{
	case 2:							// WELCOME
		if (mpstate == 0 && len >= 6)
		{
			mplocal = d[4];
			mpstate = 1;
			if (len >= 14)
			{
				mpfraglimit = d[10] | (d[11] << 8);
				mptimelimit = d[12] | (d[13] << 8);
			}
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
		mpbye = len >= 6 ? d[5] : 0;
		if (!mpend)
			mpend = mpbye == 3 ? 4 : 2;
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
	// in int, as id's PollControls does (max = 100*tics; min = -max): tics is
	// UNSIGNED, and "controlx < -100*tics" compared 0 with 65136 -- every
	// player turned and ran flat out with no key down (StevenC saw it spin)
	{
		int	t = DEMOTICS, max = 100*t, min = -max;

		if (controlx > max)
			controlx = max;
		if (controlx < min)
			controlx = min;
		if (controly > max)
			controly = max;
		if (controly < min)
			controly = min;
		*x = controlx/t;
		*y = controly/t;
	}
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
	PutL (mppkt+14,mpplayed < 0 ? 0xffffffffl : mpplayed);	// the server lets a
	NetSend (mppkt,18);				// joiner in once it has caught up
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
// The command line: NET [a.b.c.d] [PORT n] [NAME x] [NETBOT].  The server,
// the port and the name are remembered in WOLF3DM.CFG, a text file beside
// the game that the PLAY menu writes too:
//
//	SERVER 192.168.1.10
//	PORT 31992
//	NAME StevenC
//
// so NET alone joins the last server, and whatever the command line gives
// is saved for next time (not by NETBOT, a test, which leaves it alone).
// The picture switches are not in it: the menu remembers those (W3MENU.CFG)
//
static char far netcfg[] = "WOLF3DM.CFG";
static char far noword[1];
static int far mpcfg;			// a server is known

// the word at a is w (lower case), whole -- the command line's or the file's
static int Is (char far *a, char far *w)
{
	while (*w)
		if ((*a++|32) != *w++)
			return 0;
	return (byte)*a <= ' ';
}

// a dotted address at p into d[4]: 1 if it was one
static int Addr (char far *p, byte *d)
{
	int	v = 0, part = 0, digits = 0;

	for (;;p++)
		if (*p >= '0' && *p <= '9')
		{
			if (++digits > 3)
				return 0;
			v = v*10 + *p - '0';
		}
		else
		{
			if (!digits || part > 3 || v > 255)
				return 0;
			d[part++] = v;
			v = digits = 0;
			if (*p != '.')
				return part == 4 && (byte)*p <= ' ';
		}
}

static unsigned Num (char far *p)
{
	unsigned n = 0;

	for (;*p >= '0' && *p <= '9';p++)
		n = n*10 + *p - '0';
	return n;
}

static void Name (char far *p)
{
	int	k;

	for (k=0;k<16 && (byte)p[k] > ' ';k++)
		mpname[k] = p[k];
	mpname[k] = 0;
}

static void LoadNet (void)
{
	static char far wserver[] = "server", far wport[] = "port", far wname[] = "name";
	char	buf[256], fn[12];
	char	far *p, far *v;
	byte	d[4];
	int		h,n;

	_fstrcpy ((char far *)fn,netcfg);
	h = open (fn,O_RDONLY|O_BINARY);
	if (h == -1)
		return;
	n = read (h,buf,sizeof(buf)-1);
	close (h);
	if (n <= 0)
		return;
	buf[n] = 0;
	for (p = (char far *)buf;*p;)
	{
		for (v = p;(byte)*v > ' ';v++)		// the word, then its value
			;
		while (*v == ' ' || *v == '\t')
			v++;
		if (Is (p,wserver) && Addr (v,d))
		{
			_fmemcpy (mpserver,d,4);
			mpcfg = 1;
		}
		if (Is (p,wport) && Num (v))
			mpport = Num (v);
		if (Is (p,wname))
			Name (v);
		while (*p && *p != '\n')
			p++;
		if (*p)
			p++;
	}
}

static void SaveNet (void)
{
	static char far f[] = "SERVER %d.%d.%d.%d\r\nPORT %u\r\nNAME %s\r\n";
	char	buf[80], fmt[40], fn[12], name[17];
	int		h;

	_fstrcpy ((char far *)fn,netcfg);
	_fstrcpy ((char far *)fmt,f);
	_fstrcpy ((char far *)name,mpname);
	sprintf (buf,fmt,mpserver[0],mpserver[1],mpserver[2],mpserver[3],mpport,name);
	h = _creat (fn,0);
	if (h == -1)
		return;
	write (h,buf,strlen (buf));
	close (h);
}

int MPNetArgs (void)
{
	static int far done;
	static char far wnet[] = "net", far wport[] = "port", far wname[] = "name", far wbot[] = "netbot";
	static char far none[] = "WOLF3DM NET: which server?  WOLF3DM NET a.b.c.d -- remembered after that\n";
	int		i,net = 0,given = 0;
	byte	d[4];

	if (done)						// asked twice: before InitGame, and after
		return mpnet;
	done = 1;
	for (i = 1;i < _argc;i++)
		if (Is (_argv[i],wnet))
			net = 1;
	if (!net)
		return 0;
	LoadNet ();
	for (i = 1;i < _argc;i++)
	{
		char	far *a = _argv[i];
		char	far *p = i+1 < _argc ? _argv[i+1] : noword;

		if (Is (a,wnet) && Addr (p,d))
		{
			_fmemcpy (mpserver,d,4);
			mpcfg = given = 1;
		}
		if (Is (a,wport) && Num (p))
		{
			mpport = Num (p);
			given = 1;
		}
		if (Is (a,wname) && *p)
		{
			Name (p);
			given = 1;
		}
		if (Is (a,wbot))
			mpbot = 1;
	}
	if (!mpcfg)
	{
		char	s[80];

		_fstrcpy ((char far *)s,none);
		printf (s);
		exit (1);
	}
	if (given && !mpbot)
		SaveNet ();
	return mpnet = 1;
}

//
// The status bar, from the local player's own numbers: anything that changed
// since it was drawn is drawn again (the game draws it only when the local
// player's context happens to be in -- this catches every other way)
//
static int far shown[7] = {-1,-1,-1,-1,-1,-1,-1};

static void Status (void)
{
	MPUse (mplocal);
	if (shown[0] != gamestate.health)
	{
		shown[0] = gamestate.health;
		DrawHealth ();
		DrawFace ();
	}
	if (shown[1] != gamestate.ammo)
	{
		shown[1] = gamestate.ammo;
		DrawAmmo ();
	}
	if (shown[2] != gamestate.keys)
	{
		shown[2] = gamestate.keys;
		DrawKeys ();
	}
	if (shown[3] != gamestate.weapon)
	{
		shown[3] = gamestate.weapon;
		DrawWeapon ();
	}
	if (shown[4] != (int)gamestate.score)
	{
		shown[4] = (int)gamestate.score;
		DrawScore ();
	}
	if (shown[5] != gamestate.mapon)
	{
		shown[5] = gamestate.mapon;
		DrawLevel ();
	}
	{								// LIVES: no lives here -- frags in a
		int	n = mprules & RULE_DM ? mpctx[mplocal].frags : mpctx[mplocal].deaths;

		if (shown[6] != n)			// deathmatch, deaths in co-op, as DOOM
		{
			shown[6] = n;
			LatchNumber (13,16,2,n);
		}
	}
	MPUse (0);
}

//
// DOOM's keys for a slow machine: - and = make the window smaller and bigger
// (id's sizes 4-19, as its Change View menu), F5 the walls' detail -- a ray
// for every column, every 2nd, every 4th (LOWWALLS, LOWWALLS4).  Only this
// machine's picture changes: aiming is worked out from geometry (above), so
// every machine still plays the same game.  Nothing is saved: the game ends
// without WriteConfig.  LOWSPRITES' sprite code is set up at its first call
// for walls in pairs at least, so with it F5 keeps to 2 and 4.  A new size
// rebuilds id's compiled scalers -- 2.1 s on the V30 -- so the presses are
// counted first and the window changes once, half a second after the last
//
#define sc_Less		0x0c			// - _
#define sc_More		0x0d			// = +

static void Picture (void)
{
	static int far size;
	static long far pressed;

	if (!size)
		size = viewsize;
	if (pressed > TimeCount)
		pressed = TimeCount;			// NetLoop starts TimeCount again each floor
	if (Keyboard[sc_Less] || Keyboard[sc_More])
	{
		if (Keyboard[sc_Less] && size > 4)
			size--;
		if (Keyboard[sc_More] && size < 19)
			size++;
		Keyboard[sc_Less] = Keyboard[sc_More] = false;
		pressed = TimeCount;
	}
	if (size != viewsize && TimeCount - pressed > 35)
	{
		ClearMemory ();				// as id's Change View: the page manager's
		NewViewSize (size);			// memory let go for the new scalers (and
		PM_CheckMainMem ();			// their 20 KB to build in), then taken back
		DrawAllPlayBorder ();
	}
	if (Keyboard[sc_F5])
	{
		Keyboard[sc_F5] = false;
		pixstep = pixstep == 1 ? 2 : pixstep == 2 ? 4 : lowsprites ? 2 : 1;
	}
}

//
// Joining a running game: every step since the first, played as fast as the
// machine can -- no picture, no sound -- with a line to say how far it is
//
static void Behind (long n)
{
	static char far f[] = "Catching up: %ld steps to go";
	char	s[40], fmt[32];

	_fstrcpy ((char far *)fmt,f);
	sprintf (s,fmt,n);
	CenterWindow (28,3);
	US_CPrint ((char far *)s);
	VW_UpdateScreen ();
}

static void NetLoop (void)
{
	static char far leave[] = "Leave the game?  Y or N";
	long	lastsend = -100, lastsay = -100, catchfrom = 0;
	int		n,i,asking = 0,limit;

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
	mpheard = 0;
	MPCamera (true);				// the first picture BEFORE "loaded": it reads
	ThreeDRefresh ();				// the level's walls and sprites into the page
	MPCamera (false);				// cache, and with FLATWALLS averages every wall
	mpframes++;						// -- 8 s on the V30, which the server's clock
	lasttimecount = TimeCount = 0;	// must not be running for
	SendInput ();					// "loaded": the server starts its clock
	do
	{
		NetPump (Take);
		if (TimeCount - lastsend >= 2)
		{
			lastsend = TimeCount;
			SendInput ();
		}
		if (mphave - mpplayed > 35)		// two seconds behind: catch up
			mpcatching = 1;
		else if (mpcatching && mphave - mpplayed < 8)
		{
			mpcatching = 0;
			DrawAllPlayBorder ();
			for (i=0;i<7;i++)
				shown[i] = -1;
		}
		limit = mpcatching ? 64 : 16;
		if (mpcatching)
			catchfrom = TimeCount;
		for (n=0;n < limit && mpplayed < mphave && !playstate;n++)
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
			if (mpcatching)
			{
				mpcaught++;
				if (!((n+1) & 7))		// catching up, the network too, every 8 steps:
				{						// its 8 packet slots fill in a fraction of a
					NetPump (Take);		// second, and the server sends from the step
					if (TimeCount - lastsend >= 2)	// this machine last said it had
					{
						lastsend = TimeCount;
						SendInput ();
					}
				}
			}
			if (!playstate && (mprules & RULE_DM))
			{
				for (i=0;i<mpplayers;i++)
					if (mpfraglimit && mpctx[i].frags >= mpfraglimit)
					{
						playstate = ex_completed;
						mpwhy = 1;
					}
				if (!playstate && mptimelimit
				&& gamestate.TimeCount >= (long)mptimelimit*60*70)
				{
					playstate = ex_completed;
					mpwhy = 2;
				}
			}
		}
		if (mpcatching)
		{
			if (TimeCount >= catchfrom)
				mpcaughtticks += TimeCount - catchfrom;
			if (TimeCount - lastsay >= 70 || TimeCount < lastsay)
			{
				lastsay = TimeCount;
				Behind (mphave - mpplayed);
			}
		}
		else
		{
			if (n)
				Status ();
			if ((n || !frameon) && !asking)
			{
				MPCamera (true);
				ThreeDRefresh ();
				MPCamera (false);
				mpframes++;
			}
			if (!asking)
				Picture ();
		}
		UpdateSoundLoc ();
		if (screenfaded)
			VW_FadeIn ();
		// ESC asks first, with the game going on underneath (it cannot
		// stop for one player); the picture holds still while it asks
		if (Keyboard[sc_Escape] && !asking)
		{
			asking = 1;
			IN_ClearKeysDown ();
			Message (leave);			// WL_MENU.C's box, as god mode's
		}
		if (asking && Keyboard[sc_Y])
		{
			playstate = ex_abort;
			mpend = 1;
		}
		if (asking && (Keyboard[sc_N] || Keyboard[sc_Escape]))
		{
			asking = 0;
			IN_ClearKeysDown ();
			DrawAllPlayBorderSides ();
		}
		if ((long)(TimeCount - mpheard) > DEAF)	// signed: id's first frame
		{							// sets TimeCount back to 0 after a fade-in, and
			mpstate = 3;			// unsigned, a packet a tick before it looked
			if (!mpend)				// like 4 billion ticks of silence.  Its BYE
				mpend = 3;			// lost, or the server gone: nobody
		}
		if (mpdropped && !mpend)
			mpend = 4;
		if (mpstate == 3 || mpdropped)	// sends steps again
			playstate = ex_abort;
	} while (!playstate);
	mpcatching = 0;
	mpticks += TimeCount;
}

/*
=============================================================================

						THE END OF A LEVEL

DOOM's way: everyone sees the same tally -- each player's kills, items and
secrets, frags and deaths -- and then everyone goes to the next floor
together.  The steps go on arriving all through it, so it ends on a step
every machine agrees on: after 6 seconds, the first step in which anyone
presses fire or use, and after 20 seconds regardless.  Co-op keeps each
player's health, weapons, ammo and score from floor to floor (a player who
was dead comes back as from a respawn); keys go, as in id's game.

=============================================================================
*/

#define TALLYMIN	105				// steps: 6 seconds
#define TALLYMAX	350				// 20

static gametype far *Gs (int i)
{
	return i == mpcur ? (gametype far *)&gamestate : &mpctx[i].gs;
}

static void Col (int x, int y, char far *s)
{
	PrintX = WindowX + x;
	PrintY = WindowY + y;
	US_Print (s);
}

static void ColN (int x, int y, long n, int pct)
{
	char	s[12];
	int		k;

	ltoa (n,s,10);
	if (pct)
	{
		k = strlen (s);
		s[k] = '%';
		s[k+1] = 0;
	}
	Col (x,y,(char far *)s);
}

static int Pct (int n, int total)
{
	return total ? (int)((long)n*100/total) : 0;
}

static void TallyDraw (int over)
{
	static char far t0[] = "FLOOR COMPLETE", far t1[] = "FRAG LIMIT", far t2[] = "TIME LIMIT";
	static char far h1[] = "KILLS", far h2[] = "ITEMS", far h3[] = "SECRET";
	static char far h4[] = "FRAGS", far h5[] = "DIED";
	static char far nm[4][9] = {"P1 GREY","P2 GREEN","P3 RED","P4 BROWN"};
	static char far you[] = ">";
	static char far next[] = "fire or use: the next floor";
	static char far end[] = "fire or use: the end";
	static char far empty[] = "(nobody)";
	gametype	far *g, far *g0 = Gs (0);
	int			i,y,oldfont = fontnumber;

	fontnumber = 0;
	CenterWindow (38,12);			// the small font: about 7 pixels a letter
	SETFONTCOLOR (0,15);
	PrintY = WindowY + 4;
	US_CPrint (mpwhy == 1 ? t1 : mpwhy == 2 ? t2 : t0);
	SETFONTCOLOR (0,15);
	Col (78,20,h1);
	Col (122,20,h2);
	Col (166,20,h3);
	Col (218,20,h4);
	Col (262,20,h5);
	for (i=0;i<mpplayers;i++)
	{
		g = Gs (i);
		y = 34 + i*12;
		if (i == mplocal)
			Col (2,y,you);
		Col (10,y,nm[i]);
		if (mpctx[i].absent)
		{
			Col (78,y,empty);
			continue;
		}
		ColN (78,y,Pct (g->killcount,g0->killtotal),1);
		ColN (122,y,Pct (g->treasurecount,g0->treasuretotal),1);
		ColN (166,y,Pct (g->secretcount,g0->secrettotal),1);
		ColN (218,y,mpctx[i].frags,0);
		ColN (262,y,mpctx[i].deaths,0);
	}
	PrintY = WindowY + 34 + 4*12 + 4;
	US_CPrint (over ? end : next);
	VW_UpdateScreen ();
	fontnumber = oldfont;
}

//
// The tally, playing the steps as they come.  Returns 0 if this player
// left (ESC) or the server ended the game
//
static int Tally (int over)
{
	long	lastsend = -100;
	int		steps = 0,i,done = 0;

	TallyDraw (over);
	mpheard = TimeCount;
	while (!done)
	{
		NetPump (Take);
		if (TimeCount - lastsend >= 2)
		{
			lastsend = TimeCount;
			SendInput ();
		}
		while (mpplayed < mphave && !done)
		{
			byte	far *row = mpring[++mpplayed % RING];

			mpintally = 1;
			for (i=0;i<mpplayers;i++)
				Presence (i,!Gone (row+3*i));
			mpintally = 0;
			if (++steps >= TALLYMAX)
				done = 1;
			if (steps >= TALLYMIN)
				for (i=0;i<mpplayers;i++)
					if (row[3*i] & ((1<<bt_attack) | (1<<bt_use)))
						done = 1;
		}
		if (Keyboard[sc_Escape] || mpstate == 3 || mpdropped
		|| (long)(TimeCount - mpheard) > DEAF)
			return 0;
	}
	return 1;
}

//
// Everyone to the next floor, the way id's GameLoop picks it
//
static void NextLevel (void)
{
	static gametype far keep[MAXPLAYERS];
	static int far wasdead[MAXPLAYERS];
	static byte far nostarts[4*MAXPLAYERS];
	static int far gone[MAXPLAYERS], far fresh[MAXPLAYERS];
	gametype	far *g;
	int			i;

	MPUse (0);
	Save (0);
	for (i=0;i<mpplayers;i++)
	{
		_fmemcpy (&keep[i],&mpctx[i].gs,sizeof(gametype));
		wasdead[i] = mpctx[i].dead;
		gone[i] = mpctx[i].absent;	// MPSpawn spawns every slot: these
		fresh[i] = mpctx[i].rejoined;	// go again, and these start new
	}
	gamestate.keys = 0;
	gamestate.oldscore = gamestate.score;
	if (gamestate.mapon == 9)
		gamestate.mapon = ElevatorBackTo[gamestate.episode];	// back from the secret floor
	else if (playstate == ex_secretlevel)
		gamestate.mapon = 9;
	else
		gamestate.mapon++;
	if ((mprules & RULE_DM) && gamestate.mapon > 8)
		gamestate.mapon = 0;		// deathmatch: round the episode again

	SendInput ();					// heard from, through the load: the server lets
	VW_FadeOut ();					// a machine go after 30 s of nothing, and a V30
	ClearMemory ();					// loading a floor is quiet for 15
	SETFONTCOLOR (0,15);
	DrawPlayScreen ();
	VW_FadeIn ();
	SendInput ();
	SetupGameLevel ();
	SendInput ();
	{								// the steps count on through every floor:
		long			s = mpsteps;	// the server compares SYNCs by step
		unsigned long	m = mpsum;

		MPSpawn (nostarts);
		mpsteps = s;
		mpsum = m;
	}
	for (i=0;i<mpplayers;i++)
	{
		g = Gs (i);
		g->oldscore = keep[i].oldscore;
		g->score = keep[i].score;
		g->nextextra = keep[i].nextextra;
		g->lives = keep[i].lives;
		g->health = keep[i].health;
		g->ammo = keep[i].ammo;
		g->bestweapon = keep[i].bestweapon;
		g->weapon = keep[i].weapon;
		g->chosenweapon = keep[i].chosenweapon;
		g->attackframe = g->attackcount = g->weaponframe = 0;
		if (fresh[i])				// came in during the tally: a new player
		{
			g->score = g->oldscore = 0;
			g->nextextra = EXTRAPOINTS;
		}
		if (wasdead[i] || g->health <= 0 || fresh[i] || (mprules & RULE_DM))
		{							// back as from a respawn (deathmatch: always)
			g->health = 100;
			g->ammo = 50;
			g->weapon = g->bestweapon = g->chosenweapon = wp_pistol;
		}
		mpctx[i].dead = mpctx[i].deaths = mpctx[i].frags = 0;
		mpctx[i].deadtime = 0;
		mpctx[i].absent = mpctx[i].rejoined = 0;
	}
	for (i=0;i<mpplayers;i++)
		if (gone[i])
			Leave (i);
	mpwhy = 0;
	for (i=0;i<7;i++)
		shown[i] = -1;				// the status bar, all of it, next frame
	StartMusic ();
	PM_CheckMainMem ();
	fizzlein = true;
	DrawLevel ();
}

void MPNetGame (void)
{
	static char far joining[] = "Joining the server...";
	static char far waiting[] = "Waiting for the others...";
	static char far defname[] = "Player";
	static char far noanswer[] = "No answer from the server in 90 seconds";
	static char far full[] = "The server is full -- try again when someone leaves";
	static char far other[] = "The server is playing a different WOLF3DM";
	static char far ended[] = "The server ended the game";
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
	if (mpstate == 3)				// a BYE, not a START
		NetQuit (mpbye == 1 ? full : mpbye == 2 ? other : ended);
	for (i=0;i<RING;i++)
		mpringstep[i] = -1;

	mprules = mpstart[3];
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

	for (;;)
	{
		int	over;

		NetLoop ();
		if (playstate == ex_abort)
			break;
		over = playstate != ex_completed && playstate != ex_secretlevel;
		if (!Tally (over) || over)
			break;
		NextLevel ();
	}

	Head (8);						// BYE
	mppkt[4] = mplocal;
	NetSend (mppkt,5);
	NetStop ();
	ShutdownId ();
	MPReport ();
	{
		static char far r[] = "net: %ld steps played, %ld held; packets sent %ld, received %ld; %Fs\n";
		static char far ok[] = "no desync", far bad[] = "DESYNC reported";
		static char far f[] = "net: %ld pictures in %ld s, %ld.%ld a second (view %d, walls 1 ray in %d)\n";
		char	s[90];
		long	t = mpticks ? mpticks : 1, r10 = mpframes*700/t;

		_fstrcpy ((char far *)s,r);
		printf (s,mpplayed+1,mphave+1,netsentn,netrecvn,mpdesync < 0 ? (char far *)ok : (char far *)bad);
		_fstrcpy ((char far *)s,f);
		printf (s,mpframes,mpticks/70,r10/10,r10%10,viewsize,pixstep);
		{
			static char far e[] = "net: ended by %Fs\n";
			static char far e0[] = "the game", far e1[] = "this player (ESC, Y)",
				far e2[] = "the server (BYE)", far e3[] = "15 s with nothing from the server",
				far e4[] = "the server, which stopped hearing this machine";
			static char far *far why[5] = {e0,e1,e2,e3,e4};

			_fstrcpy ((char far *)s,e);
			printf (s,why[mpend >= 0 && mpend <= 4 ? mpend : 0]);
			if (mpcaught)
			{
				static char far c[] = "net: caught up %ld steps in %ld s, %ld a second\n";
				long	t = mpcaughtticks ? mpcaughtticks : 1;

				_fstrcpy ((char far *)s,c);
				printf (s,mpcaught,mpcaughtticks/70,mpcaught*70/t);
			}
		}
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
