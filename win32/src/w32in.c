/*
 * w32in.c -- id's input calls on Win32, from the window's messages
 * (w32win.c): Keyboard[], LastScan and LastASCII as id's keyboard interrupt
 * kept them, the mouse's movement and buttons, IN_Ack and friends.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

void	W32Events (void);
void	W32Wait (int ms);

static int	mousedx, mousedy, mousebtn;
static void	(*keyhook) (void);

void W32Key (int scan, int down)
{
	if (scan <= 0 || scan >= NumCodes)
		return;
	Keyboard[scan] = down ? true : false;
	if (down)
	{
		LastScan = scan;
		if (keyhook)
			keyhook ();
	}
}

void W32Char (int ascii)
{
	if (ascii >= 32 && ascii < 127)
		LastASCII = (char)ascii;
	else if (ascii == 8 || ascii == 13 || ascii == 27)
		LastASCII = (char)ascii;
}

void W32Mouse (int dx, int dy, int buttons)
{
	mousedx += dx;
	mousedy += dy;
	mousebtn = buttons;
}

static int Has (char *w)
{
	int	i;

	for (i=1;i<_argc;i++)
		if (!stricmp (_argv[i],w))
			return 1;
	return 0;
}

//
// the mouse's move since the last: NOMOUSEY (StevenC, 2026-10-21) for turning
// only -- id's game walks forward and back with it too, as without
//
void W32MouseDelta (int *dx, int *dy)
{
	static int	noy = -1;

	if (noy < 0)
		noy = Has ("nomousey");
	*dx = mousedx;
	*dy = noy ? 0 : mousedy;
	mousedx = mousedy = 0;
}

byte IN_MouseButtons (void) { return (byte)mousebtn; }

//
// the window took the mouse (a click) or gave it back (F12, away): id's
// mouseenabled, which the game reads every step
//
void W32MouseOn (int on)
{
	extern boolean	mouseenabled;

	extern int		buttonmouse[4];

	mouseenabled = on ? true : false;
	MousePresent = mouseenabled;
	// the buttons: left fires, right opens (a two-button mouse has no middle
	// to open doors with), middle strafes -- RIGHTSTRAFE for id's: right
	// strafes, middle opens (StevenC, 2026-10-21)
	buttonmouse[0] = bt_attack;
	buttonmouse[1] = Has ("rightstrafe") ? bt_strafe : bt_use;
	buttonmouse[2] = Has ("rightstrafe") ? bt_use : bt_strafe;
	if (!mouseadjustment)
		mouseadjustment = 5;			// id's default sensitivity
	mousedx = mousedy = 0;
	mousebtn = 0;
}
byte IN_JoyButtons (void) { return 0; }
void INL_GetJoyDelta (word joy,int *dx,int *dy) { *dx = *dy = 0; }
void IN_SetKeyHook (void (*hook)()) { keyhook = hook; }

void IN_ClearKeysDown (void)
{
	LastScan = sc_None;
	LastASCII = key_None;
	memset (Keyboard,0,NumCodes*sizeof(Keyboard[0]));
}

static boolean Any (void)
{
	return LastScan != sc_None || (mousebtn != 0);
}

void IN_StartAck (void)
{
	IN_ClearKeysDown ();
}

boolean IN_CheckAck (void)
{
	W32Events ();
	return Any ();
}

void IN_Ack (void)
{
	IN_StartAck ();
	while (!IN_CheckAck ())
		W32Wait (10);
}

boolean IN_UserInput (longword delay)
{
	longword	end = TimeCount + delay;

	IN_StartAck ();
	while (TimeCount < end)
	{
		if (IN_CheckAck ())
			return true;
		W32Wait (10);
	}
	return false;
}
