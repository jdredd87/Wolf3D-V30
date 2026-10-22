/*
 * w32dos.c -- Borland's findfirst and findnext (DIR.H) on Win32, from
 * FindFirstFile: id's menus list the saved games with them (SAVEGAM?.WL6).
 * The search's handle is kept in the ffblk's reserved bytes, as DOS keeps its
 * own there; a search that finds nothing more closes it.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <windows.h>
#include <string.h>
#include "DIR.H"

static int Fill (struct ffblk *f, WIN32_FIND_DATA *d)
{
	char	*n = d->cAlternateFileName[0] ? d->cAlternateFileName : d->cFileName;

	f->ff_attrib = (char)(d->dwFileAttributes & 0x3f);
	f->ff_fsize = (long)d->nFileSizeLow;
	f->ff_ftime = f->ff_fdate = 0;
	strncpy (f->ff_name,n,12);
	f->ff_name[12] = 0;
	return 0;
}

static HANDLE *Handle (struct ffblk *f)
{
	return (HANDLE *)f->ff_reserved;
}

int w32_findfirst (const char *path, struct ffblk *f, int attrib)
{
	WIN32_FIND_DATA	d;
	HANDLE			h = FindFirstFile (path,&d);

	attrib = attrib;
	*Handle (f) = h;
	if (h == INVALID_HANDLE_VALUE)
		return -1;
	return Fill (f,&d);
}

int w32_findnext (struct ffblk *f)
{
	WIN32_FIND_DATA	d;
	HANDLE			h = *Handle (f);

	if (h == INVALID_HANDLE_VALUE)
		return -1;
	if (!FindNextFile (h,&d))
	{
		FindClose (h);
		*Handle (f) = INVALID_HANDLE_VALUE;
		return -1;
	}
	return Fill (f,&d);
}
