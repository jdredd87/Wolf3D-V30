/*
 * w32stub.c -- what the game logic links against, for the headless Win32
 * replay: id's variables, and the picture, sound, input, menus and network
 * as nothing at all.  The game's state never depends on any of them -- the
 * DOS machines stay in step with different windows, detail and sound -- so a
 * replay with none of them must reach the same sums.  The parts that matter
 * are elsewhere: w32logic.c (id's C for what the V30 keeps in assembly),
 * w32ca.c (the maps), w32tab.c (the DOS game's sine table), w32main.c.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

//
// variables: the picture, the input, the sound, the network
//
boolean		AdLibPresent,SoundBlasterPresent,SoundPositioned,MousePresent;
SDSMode		DigiMode;
boolean		Keyboard[NumCodes];
char		LastASCII;
ScanCode	LastScan;
boolean		Paused;
word		PrintX,PrintY,WindowX,WindowY;
byte		fontcolor,backcolor;
int			fontnumber;
long		frameon;
byte		gamepal;				// (id's is an .OBJ's label: only its address is used)
byte		grneeded[NUMCHUNKS];
void		*grsegs[NUMCHUNKS];
byte		*audiosegs[NUMSNDCHUNKS];
long		lasttimecount;
unsigned	bufferofs,displayofs,linewidth,screenofs,screenloc[3];
unsigned	ylookup[MAXSCANLINES];
int			centerx,shootdelta,viewwidth,viewheight;
fixed		viewx,viewy,viewsin,viewcos,tileglobal = TILEGLOBAL;
int			pixstep = 1,lowsprites,lowvert;
int			px,py;
boolean		screenfaded,startgame,loadedgame,virtualreality,tedlevel,profiling,mmerror;
int			mouseadjustment;
char		str[80],str2[20];
char		extension[6] = "WL6";
char		PageFileName[13] = "VSWAP.";
word		PMSpriteStart,PMSoundStart;
unsigned long pmcount[5];
LRstruct	LevelRatios[8];
int			netany,netearly;
byte		netfrom[4];
long		netsentn,netrecvn;
byte		nettx[1514];

// the menu's items: the game only renames one (WL_GAME.C, after a high score)
CP_itemtype	MainMenu[16],NewEMenu[16];

//
// TimeCount: the DOS game's 70 Hz timer tick, here kept by a thread
// (w32main.c)
//
longword	TimeCount;

//
// the picture: nothing.  A font for the text the game measures (WL_MP.C's
// Text1 reads widths before it draws): every letter 8 wide, 8 high, blank
//
static struct
{
	int		height;
	int		location[256];
	char	width[256];
	byte	data[64];
} w32font;

void W32FontInit (void)
{
	int	i;

	w32font.height = 8;
	for (i=0;i<256;i++)
	{
		w32font.location[i] = (byte *)w32font.data - (byte *)&w32font;
		w32font.width[i] = 8;
	}
	grsegs[STARTFONT] = grsegs[STARTFONT+1] = &w32font;
}

void W32Plot (int x, int y, int color) { x = y = color; }
void VL_Bar (int x, int y, int width, int height, int color) {}
void VL_FadeIn (int start, int end, byte far *palette, int steps) {}
void VL_FadeOut (int start, int end, int red, int green, int blue, int steps) {}
void VL_Hlin (unsigned x, unsigned y, unsigned width, unsigned color) {}
void VL_LowVert (int on) {}
void VL_Plot (int x, int y, int color) {}
void VL_ScreenToScreen (unsigned source, unsigned dest,int width, int height) {}
void VL_SetPalette (byte far *palette) {}
void VL_Vlin (int x, int y, int height, int color) {}
void VL_WaitVBL (int vbls) {}
void VWB_Bar (int x, int y, int width, int height, int color) {}
void VWB_DrawPic (int x, int y, int chunknum) {}
void VWB_Hlin (int x1, int x2, int y, int color) {}
void VWB_Plot (int x, int y, int color) {}
void VWB_Vlin (int y1, int y2, int x, int color) {}
void VW_UpdateScreen (void) {}
void LatchDrawPic (unsigned x, unsigned y, unsigned picnum) {}
boolean FizzleFade (unsigned source, unsigned dest, unsigned width,unsigned height,
	unsigned frames,boolean abortable) { return false; }
void ThreeDRefresh (void) {}
void FixOfs (void) {}
void ClearSplitVWB (void) {}
void NewViewSize (int width) { viewwidth = width*16; viewheight = width*16*HEIGHTRATIO; }
void US_DrawWindow (word x,word y,word w,word h) {}
void US_CPrint (char far *s) {}
void US_Print (char far *s) {}
boolean US_LineInput (int x,int y,char *buf,char *def,boolean escok,int maxchars,int maxwidth)
	{ return false; }
void Message (char far *string) {}
void Write (int x,int y,char *string) {}
void CacheLump (int lumpstart,int lumpend) {}
void PreloadGraphics (void) {}
void W32MouseDelta (int *dx, int *dy) { *dx = *dy = 0; }
void CA_CacheGrChunk (int chunk) {}

//
// the automap (WL_DR_A.ASM's): drawing, but for AutomapPickup
//
void AutomapReset (byte far *seen) {}
int AutomapKey (int down) { return 0; }
int AutomapOn (int demo) { return 0; }

//
// AutomapPickup: game logic, despite its name -- GetBonus for every item the
// player stands on, as DrawScaleds would on a frame drawn.  The network game
// calls it for every player every step (WL_MP.C's Think).  As WL_DR_A.ASM's:
// the list walked to laststatobj, read afresh each time
//
void AutomapPickup (void)
{
	statobj_t	*st;
	byte		x = (byte)player->tilex, y = (byte)player->tiley;

	for (st = &statobjlist[0];st < laststatobj;st++)
		if (st->shapenum != -1 && (st->flags & FL_BONUS)
		&& st->tilex == x && st->tiley == y)
			GetBonus (st);
}

//
// sound: nothing plays.  No game state waits on a sound in a network game
// (WL_MP.C's MPFace replaced id's face, which skipped random numbers while
// a sound played)
//
boolean SD_PlaySound (soundnames sound) { return false; }
word SD_SoundPlaying (void) { return 0; }
void SD_PositionSound (int leftvol,int rightvol) {}
void SD_SetPosition (int leftvol,int rightvol) {}
void SD_WaitSoundDone (void) {}
void SD_StartMusic (MusicGroup far *music) {}
void SD_MusicOn (void) {}
void SD_MusicOff (void) {}
boolean SD_SetSoundMode (SDMode mode) { return true; }
boolean SD_SetMusicMode (SMMode mode) { return true; }
void SD_SetDigiDevice (SDSMode mode) {}
void SD_StopDigitized (void) {}
void SD_Poll (void) {}
void CA_CacheAudioChunk (int chunk) {}
void CA_LoadAllSounds (void) {}

//
// input: nobody at the keyboard
//
void IN_Ack (void) {}
boolean IN_CheckAck (void) { return true; }
void IN_ClearKeysDown (void) {}
void IN_StartAck (void) {}
boolean IN_UserInput (longword delay) { return false; }
byte IN_JoyButtons (void) { return 0; }
byte IN_MouseButtons (void) { return 0; }
void IN_SetKeyHook (void (*hook)()) {}
void INL_GetJoyDelta (word joy,int *dx,int *dy) { *dx = *dy = 0; }

//
// the network: a replay reads a file, and sends nothing
//
void NetAsk (void) {}
void NetPump (void (*take) (byte far *data, unsigned len)) {}
int NetReady (void) { return 1; }
void NetSend (byte far *data, unsigned len) {}
int NetStart (byte far *server, unsigned port, char far * far *why) { return 1; }
void NetStatus (char *s) { *s = 0; }
void NetStop (void) {}

//
// the page manager: nothing is drawn, so no page is needed
//
void PM_CheckMainMem (void) {}
void PM_Preload (boolean (*update)(word current,word total)) {}
void PM_SetMainMemPurge (int level) {}

//
// the rest of the game: menus, screens, the single-player intermission
//
void CP_ViewScores (void) {}
void CheckHighScore (long score,word other) {}
int DebugKeys (void) { return 0; }
void LevelCompleted (void) {}
void Victory (void) {}
void US_ControlPanel (byte scancode) {}
void ShutdownId (void) {}
void ProfInit (void) {}
void ProfStart (void) {}
void ProfStop (void) {}
unsigned long ProfWrite (void) { return 0; }
void MPAsm (int on, objtype *first) {}		// the renderer's multiplayer switch

//
// CalcTics, id's (WL_DRAW.C): the picture's pacing, not the game's -- a
// network game plays every step at DEMOTICS
//
void CalcTics (void)
{
	long	newtime;

	if (lasttimecount > (long)TimeCount)
		TimeCount = lasttimecount;
	do
	{
		newtime = TimeCount;
		tics = newtime-lasttimecount;
	} while (!tics);
	lasttimecount = newtime;
	if (tics>MAXTICS)
	{
		TimeCount -= (tics-MAXTICS);
		tics = MAXTICS;
	}
}

//
// FixedByFrac, exactly as WL_DRAW.C's assembly: |a| times the low word of b,
// shifted down 16 with the low word of the low product dropped, negative if
// exactly one of a and b has bit 31 set (b is sign and magnitude)
//
fixed FixedByFrac (fixed a, fixed b)
{
	unsigned long	ua = (unsigned long)a, r;
	unsigned short	si = (unsigned short)((unsigned long)b >> 16);
	unsigned short	bx = (unsigned short)b;

	if ((long)a < 0)
	{
		ua = 0 - ua;
		si ^= 0x8000;
	}
	r = (((unsigned long)(unsigned short)ua * bx) >> 16)	// fraction*fraction: its high word
		+ (ua >> 16) * bx;								// units*fraction
	if (si & 0x8000)
		r = 0 - r;
	return (fixed)r;
}

//
// id's table-driven random numbers (ID_US_A.ASM)
//
byte	rndtable[256] = {
	  0,   8, 109, 220, 222, 241, 149, 107,  75, 248, 254, 140,  16,  66,
	 74,  21, 211,  47,  80, 242, 154,  27, 205, 128, 161,  89,  77,  36,
	 95, 110,  85,  48, 212, 140, 211, 249,  22,  79, 200,  50,  28, 188,
	 52, 140, 202, 120,  68, 145,  62,  70, 184, 190,  91, 197, 152, 224,
	149, 104,  25, 178, 252, 182, 202, 182, 141, 197,   4,  81, 181, 242,
	145,  42,  39, 227, 156, 198, 225, 193, 219,  93, 122, 175, 249,   0,
	175, 143,  70, 239,  46, 246, 163,  53, 163, 109, 168, 135,   2, 235,
	 25,  92,  20, 145, 138,  77,  69, 166,  78, 176, 173, 212, 166, 113,
	 94, 161,  41,  50, 239,  49, 111, 164,  70,  60,   2,  37, 171,  75,
	136, 156,  11,  56,  42, 146, 138, 229,  73, 146,  77,  61,  98, 196,
	135, 106,  63, 197, 195,  86,  96, 203, 113, 101, 170, 247, 181, 113,
	 80, 250, 108,   7, 255, 237, 129, 226,  79, 107, 112, 166, 103, 241,
	 24, 223, 239, 120, 198,  58,  60,  82, 128,   3, 184,  66, 143, 224,
	145, 224,  81, 206, 163,  45,  63,  90, 168, 114,  59,  33, 159,  95,
	 28, 139, 123,  98, 125, 196,  15,  70, 194, 253,  54,  14, 109, 226,
	 71,  17, 161,  93, 186,  87, 244, 138,  20,  52, 123, 251,  26,  36,
	 17,  46,  52, 231, 232,  76,  31, 221,  84,  37, 216, 165, 212, 106,
	197, 242,  98,  43,  39, 175, 254, 145, 190,  84, 118, 222, 187, 136,
	120, 163, 236, 249 };
static unsigned short rndindex;

void US_InitRndT (boolean randomize)
{
	rndindex = randomize ? (unsigned short)(W32Ms () & 0xff) : 0;
}

int US_RndT (void)
{
	rndindex = (rndindex + 1) & 0xff;
	return rndtable[rndindex];
}

//
// MPSwapOut and MPSwapIn (WL_NETA.ASM): a player's globals out to its
// context and in again -- the same fields, by name
//
extern	boolean	running;
extern	long	thrustspeed;
extern	unsigned plux,pluy;
extern	int		anglefrac,gotgatgun;
extern	objtype	*LastAttacker;
extern	long	playerxmove,playerymove;

typedef struct					// the head of WL_MP.C's mpctx_t
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
} w32ctx;

void MPSwapOut (void far *ctx, unsigned gswords)
{
	w32ctx	*c = ctx;

	c->ob = player;
	c->gs = gamestate;
	c->controlx = controlx;
	c->controly = controly;
	memcpy (c->buttonstate,buttonstate,sizeof(buttonstate));
	memcpy (c->buttonheld,buttonheld,sizeof(buttonheld));
	c->running = running;
	c->thrustspeed = thrustspeed;
	c->plux = plux;
	c->pluy = pluy;
	c->anglefrac = anglefrac;
	c->gotgatgun = gotgatgun;
	c->LastAttacker = LastAttacker;
	c->playerxmove = playerxmove;
	c->playerymove = playerymove;
	gswords = gswords;
}

void MPSwapIn (void far *ctx, unsigned gswords)
{
	w32ctx	*c = ctx;

	player = c->ob;
	gamestate = c->gs;
	controlx = c->controlx;
	controly = c->controly;
	memcpy (buttonstate,c->buttonstate,sizeof(buttonstate));
	memcpy (buttonheld,c->buttonheld,sizeof(buttonheld));
	running = c->running;
	thrustspeed = c->thrustspeed;
	plux = c->plux;
	pluy = c->pluy;
	anglefrac = c->anglefrac;
	gotgatgun = c->gotgatgun;
	LastAttacker = c->LastAttacker;
	playerxmove = c->playerxmove;
	playerymove = c->playerymove;
	gswords = gswords;
}

//
// DoActors: id's actor loop (WL_PLAY.C), which the V30 keeps in assembly.
// A network game uses MPDoActors instead
//
void DoActors (void)
{
	objtype	*obj;

	for (obj = player;obj;obj = obj->next)
		DoActor (obj);
}

//
// NewGame (WL_MAIN.C), as id's
//
void NewGame (int difficulty,int episode)
{
	memset (&gamestate,0,sizeof(gamestate));
	gamestate.difficulty = difficulty;
	gamestate.weapon = gamestate.bestweapon
		= gamestate.chosenweapon = wp_pistol;
	gamestate.health = 100;
	gamestate.ammo = STARTAMMO;
	gamestate.lives = 3;
	gamestate.nextextra = EXTRAPOINTS;
	gamestate.episode=episode;

	startgame = true;
}

//
// MS_CheckParm (WL_MAIN.C), as id's: a word on the command line, whatever
// - or / comes before it
//
boolean MS_CheckParm (char far *check)
{
	int		i;
	char	*parm;

	for (i = 1;i<_argc;i++)
	{
		parm = _argv[i];
		while (!isalpha(*parm))
			if (!*parm++)
				break;
		if (!stricmp(check,parm))
			return true;
	}
	return false;
}

//
// Quit: say why, and leave
//
void Quit (char *error)
{
	if (error && *error)
	{
		printf ("%s\n",error);
		exit (1);
	}
	exit (0);
}

//
// each 50th step's sum as it is made (WL_MP.C's MPStep), with W3DSUMS set:
// a replay that stops part way still shows how far it agreed
//
void W32Check (long step, unsigned long sum)
{
	if (getenv ("W3DSUMS"))
		printf ("w32 step %ld: %08lX\n",step,sum);
}

//
// InitGame's tables (WL_MAIN.C, "build some tables") that the game logic
// reads: each map row's offset, in the planes and in tilemap
//
void W32Tables (void)
{
	int	i;

	for (i=0;i<MAPSIZE;i++)
	{
		nearmapylookup[i] = &tilemap[0][0]+MAPSIZE*i;
		farmapylookup[i] = i*64;
	}
}
