/*
 * w32main.c -- the headless Win32 replay: id's startup, as much of it as the
 * game logic needs, then the network game's own code (WL_MP.C) with the
 * command line it is given -- REPLAY file FAST [SNAPTEST n] -- printing the
 * same sums the DOS game prints.
 *
 *     W3DREP REPLAY T1.MPR FAST        in a folder with the game's *.WL6
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <windows.h>		/* (not with id's headers: both define boolean) */
#include <stdio.h>

extern unsigned long	TimeCount;
void	US_InitRndT (int randomize);
void	Quit (char *error);

static DWORD	w32start;
long		w32biosticks;

void	W32CAStartup (void);
void	W32FontInit (void);
void	W32Tables (void);
int		MPNetArgs (void);
void	MPNetGame (void);

unsigned long W32Ms (void)
{
	return GetTickCount () - w32start;
}

//
// TimeCount: the DOS game's timer interrupt counts it at 70 Hz; here a
// thread does, from the clock
//
static DWORD WINAPI Ticker (LPVOID arg)
{
	arg = arg;
	for (;;)
	{
		TimeCount = W32Ms () * 7 / 100;
		w32biosticks = (long)(W32Ms () * 91 / 5000);
		Sleep (2);
	}
}

//
// A crash: where, and the chain of callers (the frames' saved EBPs) --
// addresses to look up in obj/w3drep.map
//
static LONG WINAPI Crashed (EXCEPTION_POINTERS *e)
{
	DWORD	*bp = (DWORD *)e->ContextRecord->Ebp;
	int		i;

	printf ("CRASH: exception %08lX at %08lX (address %08lX)\n",
		e->ExceptionRecord->ExceptionCode,e->ContextRecord->Eip,
		e->ExceptionRecord->NumberParameters > 1 ? e->ExceptionRecord->ExceptionInformation[1] : 0);
	printf ("  EAX %08lX EBX %08lX ECX %08lX EDX %08lX ESI %08lX EDI %08lX\n",
		e->ContextRecord->Eax,e->ContextRecord->Ebx,e->ContextRecord->Ecx,
		e->ContextRecord->Edx,e->ContextRecord->Esi,e->ContextRecord->Edi);
	for (i=0;i<24 && bp && !IsBadReadPtr (bp,8);i++,bp = (DWORD *)bp[0])
		printf ("  called from %08lX\n",bp[1]);
	fflush (stdout);
	ExitProcess (99);
	return EXCEPTION_EXECUTE_HANDLER;
}

int main (void)
{
	DWORD	id;

	if (getenv ("W3DCRASH"))			// debugging: a crash's place, before the
	{									// runtime's own handler sees it (XP and later)
		typedef PVOID (WINAPI *addveh) (ULONG,PVECTORED_EXCEPTION_HANDLER);
		addveh	a = (addveh)GetProcAddress (GetModuleHandle ("kernel32.dll"),
			"AddVectoredExceptionHandler");

		if (a)
			a (1,(PVECTORED_EXCEPTION_HANDLER)Crashed);
	}
	w32start = GetTickCount ();
	CreateThread (NULL,0,Ticker,NULL,0,&id);
	setvbuf (stdout,NULL,_IONBF,0);
	W32CAStartup ();
	W32FontInit ();
	W32Tables ();
	US_InitRndT (0);
	if (!MPNetArgs ())
		Quit ("W3DREP REPLAY file FAST -- in a folder with the game's data");
	MPNetGame ();
	Quit (NULL);
	return 0;
}
