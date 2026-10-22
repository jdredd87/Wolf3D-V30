/*
 * w32sp.c -- the whole game on Windows (WOLF3DW.EXE): what id's single-player
 * files -- WL_MAIN.C, WL_MENU.C, WL_INTER.C, WL_TEXT.C, ID_US_1.C, built as
 * they are with W32SP -- need from the managers the DOS game has and Windows
 * does not: the start and end of each (the window's start-up has done the
 * work: w32main.c), the memory figures the signon screen and the menus print,
 * the control reading id's menus walk with (ID_IN.C's IN_ReadControl), the
 * signon picture and the way out.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

void	W32Message (char *s);			// w32win.c: a box
void	W32Wait (int ms);

//
// the managers' starts and ends: the window's start (w32main.c's W32Run)
// opened the files, the picture, the sound and the input before id's
// InitGame was called; at the end the process goes, and its memory with it
//
void MM_Startup (void) {}
void MM_Shutdown (void) {}
void PM_Startup (void) {}
void PM_Shutdown (void) {}
void SD_Startup (void) {}
void SD_Shutdown (void) {}
//
// IN_Startup: a mouse (a Windows machine has one), and its buttons before the
// config is read -- left fires, right opens doors, middle strafes, as the
// network game has them (StevenC, 2026-10-21; RIGHTSTRAFE for id's own).  A
// config, and id's Control menu, have the last word
//
void IN_Startup (void)
{
	extern int	buttonmouse[4];

	MousePresent = true;
	buttonmouse[0] = bt_attack;
	buttonmouse[1] = MS_CheckParm ("rightstrafe") ? bt_strafe : bt_use;
	buttonmouse[2] = MS_CheckParm ("rightstrafe") ? bt_use : bt_strafe;
}
void IN_Shutdown (void) {}
void CA_Startup (void) {}
void CA_Shutdown (void) {}
void VL_Startup (void) {}
void VL_Shutdown (void) {}
void VL_SetVGAPlaneMode (void) {}
void VL_TestPaletteSet (void) {}
void VL_SetScreen (int crtc, int pelpan) {}
void LoadLatchMem (void) {}			// (w32gfx.c draws latched pictures from their chunks)
void alOut (byte n,byte b) {}
void VL_ColorBorder (int color) {}	// (a debugging key: the VGA's overscan colour)
long MM_UnusedMemory (void) { return 4096l*1024; }	// (the debugging key's memory report)
long MM_TotalFree (void) { return 4096l*1024; }		// (the menu's "shut up the AdLib" at the end)

//
// what the DOS game's memory managers report: a Windows machine has enough
// of everything, so these are DOS's largest figures
//
mminfotype	mminfo = {64l*1024,576l*1024,0,4096l*1024,640l*1024};	// near, far, EMS, XMS, main
boolean		EMSPresent = false, XMSPresent = true, SoundSourcePresent = false;
word		EMSPagesAvail = 0, XMSPagesAvail = 1024;
int			MainPagesAvail = 64;
boolean		JoysPresent[MaxJoys];
char		audioname[13] = "AUDIO.";

//
// CA_CacheMarks (ID_CA.C): every chunk marked needed, in memory -- here
// each is read when it is first drawn, so a mark is a read now
//
void CA_CacheMarks (void)
{
	int	i;

	for (i=0;i<NUMCHUNKS;i++)
		if (grneeded[i])
			CA_CacheGrChunk (i);
}

//
// ID_IN.C's controls: everyone on the keyboard, id's keys -- Ctrl and Alt
// the buttons, the arrows and the keypad's corners
//
ControlType	Controls[MaxPlayers];
KeyboardDef	KbdDefs = {0x1d,0x38,0x47,0x48,0x49,0x4b,0x4d,0x4f,0x50,0x51};

//
// what WL_MAIN.C's DOS-only code names, never run here: the 386 patch, the
// wall and ray tables (w32draw.c keeps its own)
//
int far CheckIs386 (void) { return 1; }
void far jabhack2 (void) {}
int		horizwall[MAXWALLTILES],vertwall[MAXWALLTILES];
int		pixelangle[MAXVIEWWIDTH];

//
// the joystick: none
//
void IN_GetJoyAbs (word joy,word *xp,word *yp) { *xp = *yp = 0; }
void IN_SetupJoy (word joy,word minx,word maxx,word miny,word maxy) {}

//
// IN_ReadControl, ID_IN.C's: the keyboard, mouse or joystick read into id's
// ControlInfo -- the way every menu walks.  As id's, but for its old demo
// recorder, which Wolfenstein never uses (its demos are WL_PLAY.C's)
//
static Direction	DirTable[] =
{
	dir_NorthWest,	dir_North,	dir_NorthEast,
	dir_West,		dir_None,	dir_East,
	dir_SouthWest,	dir_South,	dir_SouthEast
};

void IN_ReadControl (int player,ControlInfo *info)
{
	word		buttons = 0;
	int			dx = 0,dy = 0;
	Motion		mx = motion_None,my = motion_None;
	boolean		realdelta = false;
	KeyboardDef	*def;

	switch (Controls[player])
	{
	case ctrl_Keyboard:
		def = &KbdDefs;
		if (Keyboard[def->upleft])
			mx = motion_Left,my = motion_Up;
		else if (Keyboard[def->upright])
			mx = motion_Right,my = motion_Up;
		else if (Keyboard[def->downleft])
			mx = motion_Left,my = motion_Down;
		else if (Keyboard[def->downright])
			mx = motion_Right,my = motion_Down;
		if (Keyboard[def->up])
			my = motion_Up;
		else if (Keyboard[def->down])
			my = motion_Down;
		if (Keyboard[def->left])
			mx = motion_Left;
		else if (Keyboard[def->right])
			mx = motion_Right;
		if (Keyboard[def->button0])
			buttons += 1 << 0;
		if (Keyboard[def->button1])
			buttons += 1 << 1;
		break;
	case ctrl_Mouse:
		_AX = 11;					// MDelta (w32in.c's INT 33h)
		geninterrupt (0x33);
		dx = (short)_CX;
		dy = (short)_DX;
		buttons = IN_MouseButtons ();
		realdelta = true;
		break;
	default:
		break;
	}
	if (realdelta)
	{
		mx = (dx < 0) ? motion_Left : ((dx > 0) ? motion_Right : motion_None);
		my = (dy < 0) ? motion_Up : ((dy > 0) ? motion_Down : motion_None);
	}
	else
	{
		dx = mx * 127;
		dy = my * 127;
	}
	info->x = dx;
	info->xaxis = mx;
	info->y = dy;
	info->yaxis = my;
	info->button0 = buttons & (1 << 0);
	info->button1 = buttons & (1 << 1);
	info->button2 = buttons & (1 << 2);
	info->button3 = buttons & (1 << 3);
	info->dir = DirTable[((my + 1) * 3) + (mx + 1)];
	W32Wait (0);					// (a menu's loop reads this and nothing else:
}									// let the machine breathe)

//
// the signon screen: the picture DOS links into the program (SIGNON.OBJ,
// introscn) -- here built in by build.py -- while the managers start, and
// FinishSignon's "Press a key" below it
//
extern unsigned char	w32signon[64000];	// (obj/sp/w32sign.c, made by build.py)
extern byte				w32screen[];

void W32Signon (void)
{
	VL_SetPalette (&gamepal);			// (id's headers: one byte, the palette at its address)
	memcpy (w32screen,w32signon,64000);
	VW_UpdateScreen ();
}

//
// the boss key (WL_MENU.C's BossKey, F1 with GOODTIMES): DOS goes to a text
// screen with a prompt on it until Escape -- here the same, drawn: black, and
// "C>" at the top in grey
//
void W32BossPrompt (void)
{
	unsigned	was = bufferofs;

	bufferofs = 0;
	VL_SetPalette (&gamepal);			// (the text mode's own colours on DOS: the
	VWB_Bar (0,0,320,200,0);			// game had faded its palette out)
	fontnumber = 0;
	fontcolor = 7;
	px = 2;
	py = 2;
	VWB_DrawPropString ("C>");
	VW_UpdateScreen ();
	bufferofs = was;
}

//
// Quit (WL_MAIN.C's, on Windows): the DOS game ends on a text screen -- the
// order screen, or the error; here the config is kept (as id's Quit does on
// a plain quit) and an error is said in a box
//
void W32Quit (char *error)
{
	static int	quitting;

	if (!quitting++ && (!error || !*error))
		WriteConfig ();
	ShutdownId ();
	if (error && *error)
	{
		printf ("%s\n",error);
		W32Message (error);
		exit (1);
	}
	exit (0);
}
