/* DIR.H -- Borland's findfirst and findnext on Win32 (w32dos.c, from
   FindFirstFile): id's menus look for SAVEGAM?.WL6 with them.
   StevenC & Claude (Anthropic), 2026-10-21. */
#ifndef W32DIR_H
#define W32DIR_H
#include <stdlib.h>
#include <string.h>
struct ffblk
{
	char			ff_reserved[21];	/* (w32dos.c keeps its search here) */
	char			ff_attrib;
	unsigned short	ff_ftime;
	unsigned short	ff_fdate;
	long			ff_fsize;
	char			ff_name[13];
};
#ifndef FA_ARCH
#define FA_ARCH		0x20
#endif
#define findfirst	w32_findfirst
#define findnext	w32_findnext
int w32_findfirst (const char *path, struct ffblk *f, int attrib);
int w32_findnext (struct ffblk *f);
#endif
