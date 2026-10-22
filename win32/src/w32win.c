/*
 * w32win.c -- the game's window on Win32: GDI and window messages, all of
 * which Windows 95 has.  The picture is w32gfx.c's 320x200 screen and its
 * palette, stretched into the window (4:3, as a CRT showed it) with
 * StretchDIBits; the keys are id's scan codes, which a key's message carries
 * in bits 16-23.  (Not with id's headers: both define boolean.)
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <windows.h>
#include <stdio.h>

void	W32Key (int scan, int down);	// w32in.c: id's Keyboard[], LastScan
void	W32Char (int ascii);
void	W32Mouse (int dx, int dy, int buttons);
void	W32MouseOn (int on);				// w32in.c: id's mouseenabled
void	Quit (char *error);
int		W32Run (void);					// w32main.c: the game

static HWND		win;
static struct
{
	BITMAPINFOHEADER	h;
	RGBQUAD				pal[256];
} bmi;
static int		mousebuttons;
static unsigned char	*shown;			// the last frame, for WM_PAINT
static int		captured;				// the mouse is the game's
static int		remote;					// in a Remote Desktop session (below)
static POINT	lastp;

//
// the mouse: a click in the window gives it to the game -- the cursor hidden
// and kept in the window, every move a turn (or a step, up and down), as
// the DOS mouse driver gave id's game; F12 or leaving the window gives it
// back
//
static void Center (POINT *c)
{
	RECT	r;

	GetClientRect (win,&r);
	c->x = r.right/2;
	c->y = r.bottom/2;
	ClientToScreen (win,c);
}

static void Capture (int on)
{
	POINT	c;
	RECT	r;

	if (on == captured)
		return;
	captured = on;
	if (on)
	{
		GetClientRect (win,&r);
		ClientToScreen (win,(POINT *)&r.left);
		ClientToScreen (win,(POINT *)&r.right);
		ClipCursor (&r);
		ShowCursor (FALSE);
		// Remote Desktop sends where the far mouse IS: a cursor put back in
		// the middle here moves nothing there, and the next place is as far
		// out as before -- the view spun (StevenC, 2026-10-21).  There each
		// move is from the last place, and the window's edge is the end of a
		// turn; at the machine, back to the middle every move
		remote = GetSystemMetrics (0x1000) != 0;	// SM_REMOTESESSION
		Center (&c);
		if (!remote)
			SetCursorPos (c.x,c.y);
		GetCursorPos (&lastp);
	}
	else
	{
		ClipCursor (NULL);
		ShowCursor (TRUE);
	}
	W32MouseOn (on);
}

//
// 4:3 or widescreen (StevenC, 2026-10-21): the picture the game was made for
// is 320x200 on a 4:3 screen; WIDE (or F11, remembered in W32VIEW.CFG) shows
// it 16:9 -- a full-width view cast further each side (w32draw.c), the rest
// of the 320 columns between bars.  Either way the window keeps its shape:
// a picture never stretched, black bars round it when the window is not
//
#define WIDEW	426						// (w32draw.c's)
#define WSIDE	((WIDEW-320)/2)
int				w32widemode;			// the picture is 16:9
int				w32wideview, w32viewtop, w32viewrows;	// (w32draw.c: the view's sides)
unsigned char	w32wide[WIDEW*200];
static int		shownw = 320;			// the width of the frame shown

static void Blit (HDC dc)
{
	RECT	r;
	int		w, h, x, y;

	GetClientRect (win,&r);
	w = r.right;
	h = r.bottom;
	if (w*(w32widemode ? 9 : 3) > h*(w32widemode ? 16 : 4))
		w = h*(w32widemode ? 16 : 4)/(w32widemode ? 9 : 3);		// bars left and right
	else
		h = w*(w32widemode ? 9 : 3)/(w32widemode ? 16 : 4);		// bars above and below
	x = (r.right - w)/2;
	y = (r.bottom - h)/2;
	if (x > 0)
	{
		PatBlt (dc,0,0,x,r.bottom,BLACKNESS);
		PatBlt (dc,x+w,0,r.right-x-w,r.bottom,BLACKNESS);
	}
	if (y > 0)
	{
		PatBlt (dc,0,0,r.right,y,BLACKNESS);
		PatBlt (dc,0,y+h,r.right,r.bottom-y-h,BLACKNESS);
	}
	bmi.h.biWidth = shownw;
	StretchDIBits (dc,x,y,w,h,0,0,shownw,200,shown,(BITMAPINFO *)&bmi,
		DIB_RGB_COLORS,SRCCOPY);
}

//
// the window's size for the shape, its height kept
//
static void Shape (void)
{
	RECT	r, c;

	GetClientRect (win,&c);
	if (c.bottom < 200)
		c.bottom = 720;
	r.left = r.top = 0;
	r.right = c.bottom*(w32widemode ? 16 : 4)/(w32widemode ? 9 : 3);
	r.bottom = c.bottom;
	AdjustWindowRect (&r,WS_OVERLAPPEDWINDOW,FALSE);
	SetWindowPos (win,NULL,0,0,r.right-r.left,r.bottom-r.top,SWP_NOMOVE|SWP_NOZORDER);
}

static void ViewChoice (int save)
{
	FILE	*f;
	char	s[8];

	if (save)
	{
		if ((f = fopen ("W32VIEW.CFG","w")) != NULL)
		{
			fputs (w32widemode ? "WIDE" : "4:3",f);
			fclose (f);
		}
		return;
	}
	if ((f = fopen ("W32VIEW.CFG","r")) != NULL)
	{
		if (fgets (s,sizeof(s),f))
			w32widemode = !strncmp (s,"WIDE",4);
		fclose (f);
	}
	{
		int	i;

		for (i=1;i<__argc;i++)
			if (!stricmp (__argv[i],"wide") || !stricmp (__argv[i],"widescreen"))
				w32widemode = 1;
			else if (!stricmp (__argv[i],"4:3") || !stricmp (__argv[i],"narrow"))
				w32widemode = 0;
	}
}

static LRESULT CALLBACK Proc (HWND w, UINT m, WPARAM wp, LPARAM lp)
{
	switch (m)
	{
	case WM_KEYDOWN:
	case WM_SYSKEYDOWN:
		if (wp == VK_F12)
		{
			Capture (0);				// the mouse back to Windows
			return 0;
		}
		if (wp == VK_F11)
		{
			w32widemode = !w32widemode;	// 4:3 or widescreen, kept for next time
			ViewChoice (1);
			Shape ();
			InvalidateRect (win,NULL,FALSE);
			return 0;
		}
		W32Key ((lp >> 16) & 0xff,1);
		return 0;						// (Alt alone does not open a menu)
	case WM_KEYUP:
	case WM_SYSKEYUP:
		W32Key ((lp >> 16) & 0xff,0);
		return 0;
	case WM_CHAR:
		W32Char ((int)wp);
		return 0;
	case WM_SYSCOMMAND:
		if ((wp & 0xfff0) == SC_KEYMENU)
			return 0;
		break;
	case WM_LBUTTONDOWN:
		if (!captured)
		{
			Capture (1);				// the first click takes the mouse, fires nothing
			return 0;
		}
		mousebuttons |= 1;
		W32Mouse (0,0,mousebuttons);
		return 0;
	case WM_LBUTTONUP: mousebuttons &= ~1; W32Mouse (0,0,mousebuttons); return 0;
	case WM_RBUTTONDOWN: mousebuttons |= 2; W32Mouse (0,0,mousebuttons); return 0;
	case WM_RBUTTONUP: mousebuttons &= ~2; W32Mouse (0,0,mousebuttons); return 0;
	case WM_MOUSEMOVE:
		if (captured)
		{
			POINT	c, p;

			GetCursorPos (&p);
			if (remote)					// from the last place (Capture, above)
			{
				W32Mouse (p.x - lastp.x,p.y - lastp.y,mousebuttons);
				lastp = p;
			}
			else
			{
				Center (&c);
				if (p.x != c.x || p.y != c.y)
				{
					W32Mouse (p.x - c.x,p.y - c.y,mousebuttons);
					SetCursorPos (c.x,c.y);	// back to the middle: moves, not places
				}
			}
		}
		return 0;
	case WM_KILLFOCUS:
		Capture (0);
		{
			int	i;

			for (i=0;i<128;i++)		// no key held while away
				W32Key (i,0);
		}
		break;
	case WM_CLOSE:
		Quit (NULL);
		return 0;
	case WM_PRINTCLIENT:				// a window's picture taken (PrintWindow)
		if (shown)
			Blit ((HDC)wp);
		return 0;
	case WM_PAINT:
		{
			PAINTSTRUCT	ps;

			BeginPaint (w,&ps);
			if (shown)
				Blit (ps.hdc);			// uncovered: the last frame again
			EndPaint (w,&ps);
		}
		return 0;
	}
	return DefWindowProc (w,m,wp,lp);
}

//
// Quit's message, in a box: the game has no console
//
void W32Message (char *s)
{
	MessageBox (win,s,"Wolfenstein 3-D",MB_OK);
}

#ifdef W32SP
//
// the whole game (WOLF3DW): the window has a thread of its own, which takes
// its messages as they come -- so Keyboard[] and LastScan change under a
// waiting loop as id's keyboard interrupt changed them, and id's menus and
// screens wait in loops of their own (IN_WaitForKey: "while (!LastScan);").
// Here there is nothing to take; a wait is a sleep
//
void W32Events (void) {}

unsigned long	w32waited, w32waits;
void	W32Show (void);					// w32gfx.c: the screen as it is

void W32Wait (int ms)
{
	DWORD	t0 = GetTickCount ();

	W32Show ();						// a wait is when id's code shows what it drew
	Sleep (ms > 0 ? ms : 0);
	w32waited += GetTickCount () - t0;
	w32waits++;
}
#else
void W32Events (void)
{
	MSG	msg;

	while (PeekMessage (&msg,NULL,0,0,PM_REMOVE))
	{
		TranslateMessage (&msg);
		DispatchMessage (&msg);
	}
}

unsigned long	w32waited, w32waits;		// (W3DFPS: how long the game waits)

void W32Wait (int ms)
{
	DWORD	until = GetTickCount () + ms, t0 = GetTickCount ();

	do
	{
		W32Events ();
		Sleep (1);
	} while ((long)(until - GetTickCount ()) > 0);
	w32waited += GetTickCount () - t0;
	w32waits++;
}

#endif

//
// the frame the window shows: a copy, kept -- id's FizzleFade (w32gfx.c)
// dissolves the new picture into the one on show
//
static unsigned char	frame[WIDEW*200];	// as shown: 320, or 426 wide
static unsigned char	last320[64000];		// the game's own 320x200 of it

unsigned char *W32Shown (void)
{
	return last320;
}

void W32Present (unsigned char *screen, unsigned char *palette)
{
	HDC		dc;
	int		i;

	if (!win)
		return;
	memcpy (last320,screen,sizeof(last320));
	if (!w32widemode)
	{
		memcpy (frame,screen,64000);
		shownw = 320;
	}
	else
	{
		int	y;

		for (y=0;y<200;y++)			// the 320 in the middle, and beside them
		{							// the view's sides, or the row's own edge
			unsigned char	*o = frame + y*WIDEW, *sr = screen + y*320;

			memcpy (o + WSIDE,sr,320);
			if (w32wideview && y >= w32viewtop && y < w32viewtop + w32viewrows)
			{
				memcpy (o,w32wide + y*WIDEW,WSIDE);
				memcpy (o + WSIDE + 320,w32wide + y*WIDEW + WSIDE + 320,WIDEW - WSIDE - 320);
			}
			else
			{
				memset (o,w32wideview ? sr[0] : 0,WSIDE);
				memset (o + WSIDE + 320,w32wideview ? sr[319] : 0,WIDEW - WSIDE - 320);
			}
		}
		shownw = WIDEW;
	}
	screen = frame;
	for (i=0;i<256;i++)
	{
		bmi.pal[i].rgbRed = (BYTE)(palette[i*3] * 255 / 63);
		bmi.pal[i].rgbGreen = (BYTE)(palette[i*3+1] * 255 / 63);
		bmi.pal[i].rgbBlue = (BYTE)(palette[i*3+2] * 255 / 63);
		bmi.pal[i].rgbReserved = 0;
	}
	shown = screen;
	dc = GetDC (win);
	Blit (dc);
	ReleaseDC (win,dc);
	W32Events ();
}

#ifdef W32SP
#define CLASSNAME	"WOLF3DW"
#define TITLE		"Wolfenstein 3-D (StevenC & Claude)"
#define LOGNAME		"WOLF3DW.LOG"
#else
#define CLASSNAME	"WOLF3DMW"
#define TITLE		"Wolfenstein 3-D -- the network game (StevenC & Claude)"
#define LOGNAME		"WOLF3DMW.LOG"
#endif

static HINSTANCE	instance;
static int			showhow;

static void Open (void)
{
	WNDCLASS	wc;
	RECT		r = {0,0,960,720};

	ViewChoice (0);
	if (w32widemode)
		r.right = 1280;

	memset (&wc,0,sizeof(wc));
	wc.lpfnWndProc = Proc;
	wc.hInstance = instance;
	wc.hCursor = LoadCursor (NULL,IDC_ARROW);
	wc.hbrBackground = (HBRUSH)GetStockObject (BLACK_BRUSH);
	wc.lpszClassName = CLASSNAME;
	RegisterClass (&wc);
	AdjustWindowRect (&r,WS_OVERLAPPEDWINDOW,FALSE);
	win = CreateWindow (CLASSNAME,TITLE,
		WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,r.right-r.left,r.bottom-r.top,
		NULL,NULL,instance,NULL);
	ShowWindow (win,showhow);
	UpdateWindow (win);
}

#ifdef W32SP
static HANDLE	opened;

//
// the window's thread: opens it, then takes its messages until the end
//
static DWORD WINAPI Window (LPVOID arg)
{
	MSG	msg;

	arg = arg;
	Open ();
	SetEvent (opened);
	while (GetMessage (&msg,NULL,0,0) > 0)
	{
		TranslateMessage (&msg);
		DispatchMessage (&msg);
	}
	return 0;
}
#endif

int PASCAL WinMain (HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
	instance = inst;
	showhow = show;
	memset (&bmi,0,sizeof(bmi.h));
	bmi.h.biSize = sizeof(BITMAPINFOHEADER);
	bmi.h.biWidth = 320;
	bmi.h.biHeight = -200;				// top row first
	bmi.h.biPlanes = 1;
	bmi.h.biBitCount = 8;
	bmi.h.biCompression = BI_RGB;
	bmi.h.biClrUsed = 256;
#ifdef W32SP
	{
		DWORD	id;

		opened = CreateEvent (NULL,TRUE,FALSE,NULL);
		CreateThread (NULL,0,Window,NULL,0,&id);
		WaitForSingleObject (opened,INFINITE);
	}
#else
	Open ();
	W32Events ();
#endif
	freopen (LOGNAME,"w",stdout);		// no console: the report and any
	setvbuf (stdout,NULL,_IONBF,0);		// trouble go here, beside the game
	prev = prev; cmd = cmd;
	return W32Run ();
}
