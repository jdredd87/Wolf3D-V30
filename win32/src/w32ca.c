/*
 * w32ca.c -- id's cache and memory managers (ID_CA.C, ID_MM.C), as far as
 * the game logic needs them on Win32: the maps, read as id reads them
 * (MAPHEAD's offsets, each map's header, two planes Carmack- then
 * RLEW-compressed), memory from malloc, and the DOS file calls on Windows'.
 *
 * The map's header and planes are read from the file field by field, 16
 * bits each, whatever size an unsigned is here.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

maptype		*mapheaderseg[NUMMAPS];
unsigned	*mapsegs[MAPPLANES];
int			mapon;
byte		ca_levelbit,ca_levelnum;

static unsigned short	rlewtag;
static long				headeroffsets[100];
static char				gamemaps[16];

static unsigned short Get16 (byte *p) { return (unsigned short)(p[0] | (p[1] << 8)); }
static long Get32 (byte *p) { return (long)((unsigned long)p[0] | ((unsigned long)p[1] << 8)
	| ((unsigned long)p[2] << 16) | ((unsigned long)p[3] << 24)); }

//
// the maps' header (MAPHEAD) and every map's own (GAMEMAPS): CAL_SetupMapFile
//
void W32CAStartup (void)
{
	char	name[16];
	byte	b[402],h[38];
	int		f,i,j;

	strcpy (name,"MAPHEAD.");
	strcat (name,extension);
	if ((f = open (name,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open MAPHEAD");
	if (read (f,b,402) != 402)
		Quit ("MAPHEAD is short");
	close (f);
	rlewtag = Get16 (b);
	for (i=0;i<100;i++)
		headeroffsets[i] = Get32 (b+2+4*i);
	strcpy (gamemaps,"GAMEMAPS.");
	strcat (gamemaps,extension);
	if ((f = open (gamemaps,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open GAMEMAPS");
	for (i=0;i<NUMMAPS;i++)
	{
		if (headeroffsets[i] <= 0)
			continue;					// none (id's: -1, or 0 in some data)
		mapheaderseg[i] = calloc (1,sizeof(maptype));
		lseek (f,headeroffsets[i],SEEK_SET);
		if (read (f,h,38) != 38)
			Quit ("GAMEMAPS is short");
		for (j=0;j<3;j++)
		{
			mapheaderseg[i]->planestart[j] = Get32 (h+4*j);
			mapheaderseg[i]->planelength[j] = Get16 (h+12+2*j);
		}
		mapheaderseg[i]->width = Get16 (h+18);
		mapheaderseg[i]->height = Get16 (h+20);
		memcpy (mapheaderseg[i]->name,h+22,16);
	}
	close (f);
	for (i=0;i<MAPPLANES;i++)
		mapsegs[i] = calloc (64*64,sizeof(unsigned));
}

//
// Carmack's expansion: near and far copies of words already written
//
static void CarmackExpand (byte *src, unsigned short *dest, unsigned length)
{
	unsigned	n = length/2, done = 0, count, k;
	unsigned short	ch, ofs;

	while (done < n)
	{
		ch = Get16 (src);
		src += 2;
		if ((ch >> 8) == 0xa7 || (ch >> 8) == 0xa8)
		{
			count = ch & 0xff;
			if (!count)
			{
				dest[done++] = (unsigned short)((ch & 0xff00) | *src++);
			}
			else if ((ch >> 8) == 0xa7)
			{
				ofs = *src++;			// back that many words
				for (k=0;k<count && done < n;k++,done++)
					dest[done] = dest[done-ofs];
			}
			else
			{
				ofs = Get16 (src);		// from that word of the plane
				src += 2;
				for (k=0;k<count && done < n;k++,done++)
					dest[done] = dest[ofs+k];
			}
		}
		else
			dest[done++] = ch;
	}
}

//
// CA_CacheMap: both planes of a map, each Carmack- then RLEW-expanded
//
void CA_CacheMap (int mapnum)
{
	static unsigned short	carm[64*64+64];
	byte	*src;
	int		f,plane;
	unsigned	i,o,n,len,explen;

	mapon = mapnum;
	if (!mapheaderseg[mapnum])
		Quit ("CA_CacheMap: no such map");
	if ((f = open (gamemaps,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open GAMEMAPS");
	for (plane=0;plane<MAPPLANES;plane++)
	{
		len = mapheaderseg[mapnum]->planelength[plane];
		src = malloc (len);
		lseek (f,mapheaderseg[mapnum]->planestart[plane],SEEK_SET);
		if ((unsigned)read (f,src,len) != len)
			Quit ("GAMEMAPS is short");
		explen = Get16 (src);			// Carmack's expanded size, in bytes
		if (explen > sizeof(carm))
			Quit ("CA_CacheMap: a plane too big");
		CarmackExpand (src+2,carm,explen);
		free (src);
		// RLEW: the first word is the expanded size; tag, count, value repeats
		n = 64*64;
		for (i=1,o=0;o<n;)
		{
			if (carm[i] != rlewtag)
				mapsegs[plane][o++] = carm[i++];
			else
			{
				unsigned	count = carm[i+1], v = carm[i+2];

				i += 3;
				while (count-- && o < n)
					mapsegs[plane][o++] = v;
			}
		}
	}
	close (f);
}

void CA_UpLevel (void) {}
void CA_DownLevel (void) {}

//
// files: id's read and write in any size
//
boolean CA_FarRead (int handle, byte far *dest, long length)
{
	return read (handle,dest,length) == length;
}

boolean CA_FarWrite (int handle, byte far *source, long length)
{
	return write (handle,source,length) == length;
}

boolean CA_LoadFile (char *filename, memptr *ptr)
{
	int		f;
	long	size;

	if ((f = open (filename,O_RDONLY|O_BINARY)) < 0)
		return false;
	size = filelength (f);
	*ptr = malloc (size ? size : 1);
	if (!CA_FarRead (f,*ptr,size))
	{
		close (f);
		return false;
	}
	close (f);
	return true;
}

boolean CA_WriteFile (char *filename, void far *ptr, long length)
{
	int		f;

	if ((f = open (filename,O_CREAT|O_TRUNC|O_WRONLY|O_BINARY,S_IREAD|S_IWRITE)) < 0)
		return false;
	if (!CA_FarWrite (f,ptr,length))
	{
		close (f);
		return false;
	}
	close (f);
	return true;
}

//
// memory: id's manager purges and moves blocks to fit 640 KB; here there is
// room for everything, and nothing moves
//
void MM_GetPtr (memptr *baseptr,unsigned long size)
{
	*baseptr = calloc (1,size ? size : 1);
	if (!*baseptr)
		Quit ("MM_GetPtr: out of memory");
}

void MM_FreePtr (memptr *baseptr)
{
	free (*baseptr);
	*baseptr = NULL;
}

void MM_SetPurge (memptr *baseptr, int purge) {}
void MM_SetLock (memptr *baseptr, boolean locked) {}
void MM_SortMem (void) {}
void MM_BombOnError (boolean bomb) {}

//
// the DOS file calls (dos.h), on Windows' own: w32comp.h sends them here
//
unsigned w32_dos_open (const char *path, unsigned mode, int *handle)
{
	int	m = (mode & 3) == 0 ? O_RDONLY : (mode & 3) == 1 ? O_WRONLY : O_RDWR;

	*handle = open (path,m|O_BINARY);
	return *handle < 0 ? 2 : 0;
}

unsigned w32_dos_creat (const char *path, unsigned attr, int *handle)
{
	*handle = open (path,O_CREAT|O_TRUNC|O_RDWR|O_BINARY,S_IREAD|S_IWRITE);
	attr = attr;
	return *handle < 0 ? 5 : 0;
}

unsigned w32_dos_read (int handle, void *buf, unsigned count, unsigned *bytes)
{
	int	n = read (handle,buf,count);

	*bytes = n < 0 ? 0 : n;
	return n < 0 ? 5 : 0;
}

unsigned w32_dos_write (int handle, const void *buf, unsigned count, unsigned *bytes)
{
	int	n = write (handle,buf,count);

	*bytes = n < 0 ? 0 : n;
	return n < 0 ? 5 : 0;
}

unsigned w32_dos_close (int handle)
{
	return close (handle) ? 6 : 0;
}

int w32_creat (const char *path, int attr)
{
	attr = attr;
	return open (path,O_CREAT|O_TRUNC|O_RDWR|O_BINARY,S_IREAD|S_IWRITE);
}
