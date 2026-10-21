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
void	Quit (char *error);
int		W32Run (void);					// w32main.c: the game

static HWND		win;
static struct
{
	BITMAPINFOHEADER	h;
	RGBQUAD				pal[256];
} bmi;
static int		lastmx = -1, lastmy = -1, mousebuttons;
static unsigned char	*shown;			// the last frame, for WM_PAINT

static void Blit (HDC dc)
{
	RECT	r;

	GetClientRect (win,&r);
	StretchDIBits (dc,0,0,r.right,r.bottom,0,0,320,200,shown,(BITMAPINFO *)&bmi,
		DIB_RGB_COLORS,SRCCOPY);
}

static LRESULT CALLBACK Proc (HWND w, UINT m, WPARAM wp, LPARAM lp)
{
	switch (m)
	{
	case WM_KEYDOWN:
	case WM_SYSKEYDOWN:
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
	case WM_LBUTTONDOWN: mousebuttons |= 1; W32Mouse (0,0,mousebuttons); return 0;
	case WM_LBUTTONUP: mousebuttons &= ~1; W32Mouse (0,0,mousebuttons); return 0;
	case WM_RBUTTONDOWN: mousebuttons |= 2; W32Mouse (0,0,mousebuttons); return 0;
	case WM_RBUTTONUP: mousebuttons &= ~2; W32Mouse (0,0,mousebuttons); return 0;
	case WM_MOUSEMOVE:
		{
			int	x = (short)LOWORD (lp), y = (short)HIWORD (lp);

			if (lastmx >= 0)
				W32Mouse (x - lastmx,y - lastmy,mousebuttons);
			lastmx = x;
			lastmy = y;
		}
		return 0;
	case WM_KILLFOCUS:
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

void W32Present (unsigned char *screen, unsigned char *palette)
{
	HDC		dc;
	int		i;

	if (!win)
		return;
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

int PASCAL WinMain (HINSTANCE inst, HINSTANCE prev, LPSTR cmd, int show)
{
	WNDCLASS	wc;
	RECT		r = {0,0,960,720};

	memset (&wc,0,sizeof(wc));
	wc.lpfnWndProc = Proc;
	wc.hInstance = inst;
	wc.hCursor = LoadCursor (NULL,IDC_ARROW);
	wc.hbrBackground = (HBRUSH)GetStockObject (BLACK_BRUSH);
	wc.lpszClassName = "WOLF3DMW";
	RegisterClass (&wc);
	AdjustWindowRect (&r,WS_OVERLAPPEDWINDOW,FALSE);
	win = CreateWindow ("WOLF3DMW","Wolfenstein 3-D -- the network game (StevenC & Claude)",
		WS_OVERLAPPEDWINDOW,CW_USEDEFAULT,CW_USEDEFAULT,r.right-r.left,r.bottom-r.top,
		NULL,NULL,inst,NULL);
	ShowWindow (win,show);
	UpdateWindow (win);
	memset (&bmi,0,sizeof(bmi.h));
	bmi.h.biSize = sizeof(BITMAPINFOHEADER);
	bmi.h.biWidth = 320;
	bmi.h.biHeight = -200;				// top row first
	bmi.h.biPlanes = 1;
	bmi.h.biBitCount = 8;
	bmi.h.biCompression = BI_RGB;
	bmi.h.biClrUsed = 256;
	W32Events ();
	freopen ("WOLF3DMW.LOG","w",stdout);	// no console: the report and any
	setvbuf (stdout,NULL,_IONBF,0);			// trouble go here, beside the game
	prev = prev; cmd = cmd;
	return W32Run ();
}
