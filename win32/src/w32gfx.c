/*
 * w32gfx.c -- the picture's data and its 2-D drawing on Win32: the page
 * file (VSWAP: walls, sprites, digitized sounds), the graphics file
 * (VGAHEAD, VGADICT, VGAGRAPH: Huffman-compressed pictures and fonts), and
 * id's VL_, VWB_ and US_ drawing calls -- into one 320x200 byte-per-pixel
 * screen, which w32win.c shows in a window.
 *
 * id draws in the VGA's unchained mode: an address is a byte of 4 pixels,
 * 80 a row, three 16,640-byte pages.  Every call here takes its place from
 * bufferofs as id's do, and turns it into the screen's x and y: one screen
 * for all three pages, as nothing here waits on the beam.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

void	W32Present (byte *screen, byte *palette);	// w32win.c

byte	w32screen[320*200];
byte	w32palette[768];
static	int	w32ready;							// the window is up

// id's picture table, from the graphics file (16-bit ints there)
pictabletype	*pictable;

//
// a place from bufferofs: the page's row and the x of its first byte
//
static void Base (int *bx, int *by)
{
	unsigned	r = bufferofs % SCREENSIZE;

	*by = r / SCREENBWIDE;
	*bx = (r % SCREENBWIDE) * 4;
}

static void Put (int x, int y, int color)
{
	if ((unsigned)x < 320 && (unsigned)y < 200)
		w32screen[y*320+x] = (byte)color;
}

void W32Plot (int x, int y, int color)
{
	int	bx,by;

	Base (&bx,&by);
	Put (bx+x,by+y,color);
}

/*
=============================================================================

						THE PAGE FILE -- walls, sprites, sounds

=============================================================================
*/

word	ChunksInFile,PMSpriteStart,PMSoundStart;
static	byte	**pmpages;
static	word	*pmlengths;

void W32PMStartup (void)
{
	int		f,i;
	long	*ofs;
	byte	h[6];

	if ((f = open (PageFileName,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open the page file (VSWAP)");
	read (f,h,6);
	ChunksInFile = h[0] | (h[1] << 8);
	PMSpriteStart = h[2] | (h[3] << 8);
	PMSoundStart = h[4] | (h[5] << 8);
	ofs = malloc (ChunksInFile*4);
	pmlengths = malloc (ChunksInFile*sizeof(word));
	pmpages = calloc (ChunksInFile,sizeof(byte *));
	for (i=0;i<ChunksInFile;i++)
	{
		byte	b[4];

		read (f,b,4);
		ofs[i] = b[0] | (b[1] << 8) | ((long)b[2] << 16) | ((long)b[3] << 24);
	}
	for (i=0;i<ChunksInFile;i++)
	{
		byte	b[2];

		read (f,b,2);
		pmlengths[i] = b[0] | (b[1] << 8);
	}
	for (i=0;i<ChunksInFile;i++)		// every page, once: 1.5 MB is nothing here
	{
		if (!ofs[i] || !pmlengths[i])
			continue;
		pmpages[i] = malloc (pmlengths[i] < 4096 ? 4096 : pmlengths[i]);
		memset (pmpages[i],0,4096);
		lseek (f,ofs[i],SEEK_SET);
		read (f,pmpages[i],pmlengths[i]);
	}
	free (ofs);
	close (f);
}

memptr PM_GetPage (int pagenum)
{
	static byte	blank[4096];

	if (pagenum < 0 || pagenum >= ChunksInFile || !pmpages[pagenum])
		return blank;
	return pmpages[pagenum];
}

word W32PageLength (int pagenum)
{
	return pagenum >= 0 && pagenum < ChunksInFile ? pmlengths[pagenum] : 0;
}

/*
=============================================================================

						THE GRAPHICS FILE -- pictures and fonts

=============================================================================
*/

typedef struct { unsigned short bit0,bit1; } w32huff;
static	w32huff	grhuff[255];
static	long	*w32grstarts;
static	int		grfile = -1;

static long GrPos (int chunk)
{
	return w32grstarts[chunk];
}

//
// id's Huffman (CAL_HuffExpand): a byte's bits, low first, from the head
// node (254); a value under 256 is a byte out
//
static void HuffExpand (byte *src, byte *dest, long length)
{
	w32huff	*head = &grhuff[254], *node = head;
	byte	val = *src++, mask = 1;
	unsigned short	v;

	while (length > 0)
	{
		v = (val & mask) ? node->bit1 : node->bit0;
		if (mask == 0x80)
		{
			val = *src++;
			mask = 1;
		}
		else
			mask <<= 1;
		if (v < 256)
		{
			*dest++ = (byte)v;
			node = head;
			length--;
		}
		else
			node = &grhuff[v-256];
	}
}

void W32GrStartup (void)
{
	char	name[16];
	int		f,i;
	byte	*b;
	long	n;

	strcpy (name,"VGADICT.");
	strcat (name,extension);
	if ((f = open (name,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open VGADICT");
	b = malloc (255*4);
	read (f,b,255*4);
	close (f);
	for (i=0;i<255;i++)
	{
		grhuff[i].bit0 = b[i*4] | (b[i*4+1] << 8);
		grhuff[i].bit1 = b[i*4+2] | (b[i*4+3] << 8);
	}
	free (b);
	strcpy (name,"VGAHEAD.");
	strcat (name,extension);
	if ((f = open (name,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open VGAHEAD");
	b = malloc ((NUMCHUNKS+1)*3);
	read (f,b,(NUMCHUNKS+1)*3);
	close (f);
	w32grstarts = malloc ((NUMCHUNKS+1)*sizeof(long));
	for (i=0;i<=NUMCHUNKS;i++)
	{
		n = b[i*3] | (b[i*3+1] << 8) | ((long)b[i*3+2] << 16);
		w32grstarts[i] = n == 0xffffffl ? -1 : n;
	}
	free (b);
	strcpy (name,"VGAGRAPH.");
	strcat (name,extension);
	if ((grfile = open (name,O_RDONLY|O_BINARY)) < 0)
		Quit ("Can't open VGAGRAPH");
	//
	// the picture table: NUMPICS widths and heights, 16 bits each
	//
	{
		long	pos = GrPos (STRUCTPIC), next = GrPos (STRUCTPIC+1);
		byte	*comp = malloc (next-pos), *raw = malloc (NUMPICS*4);

		lseek (grfile,pos,SEEK_SET);
		read (grfile,comp,next-pos);
		HuffExpand (comp+4,raw,NUMPICS*4);
		pictable = malloc (NUMPICS*sizeof(pictabletype));
		for (i=0;i<NUMPICS;i++)
		{
			pictable[i].width = (short)(raw[i*4] | (raw[i*4+1] << 8));
			pictable[i].height = (short)(raw[i*4+2] | (raw[i*4+3] << 8));
		}
		free (comp);
		free (raw);
	}
}

//
// a font, from the file's layout (16-bit ints: height, 256 locations, 256
// widths, then the letters a byte a pixel) to this build's fontstruct
//
static void *Font (byte *raw, long size)
{
	fontstruct	*f;
	long		head = 2 + 256*2 + 256, delta;
	int			i;

	delta = (long)sizeof(fontstruct) - head;
	f = calloc (1,sizeof(fontstruct) + size - head + 64);
	f->height = (short)(raw[0] | (raw[1] << 8));
	for (i=0;i<256;i++)
	{
		f->location[i] = (short)(raw[2+i*2] | (raw[3+i*2] << 8)) + delta;
		f->width[i] = raw[2+512+i];
	}
	memcpy ((byte *)f + sizeof(fontstruct),raw + head,size - head);
	return f;
}

void CA_CacheGrChunk (int chunk)
{
	long	pos,next,expanded;
	byte	*comp,*raw;
	int		n;

	if (chunk < 0 || chunk >= NUMCHUNKS || grsegs[chunk] || grfile < 0)
		return;
	pos = GrPos (chunk);
	if (pos < 0)
		return;
	n = chunk + 1;
	while (GrPos (n) == -1)
		n++;
	next = GrPos (n);
	comp = malloc (next-pos+8);
	lseek (grfile,pos,SEEK_SET);
	read (grfile,comp,next-pos);
	if (chunk >= STARTTILE8 && chunk < STARTEXTERNS)
	{
		expanded = chunk < STARTTILE8M ? 64l*NUMTILE8 : 64l*4;
		raw = malloc (expanded);
		HuffExpand (comp,raw,expanded);
	}
	else
	{
		expanded = comp[0] | (comp[1] << 8) | ((long)comp[2] << 16) | ((long)comp[3] << 24);
		raw = malloc (expanded+16);
		HuffExpand (comp+4,raw,expanded);
	}
	free (comp);
	if (chunk >= STARTFONT && chunk < STARTFONT+NUMFONT)
	{
		grsegs[chunk] = Font (raw,expanded);
		free (raw);
	}
	else
		grsegs[chunk] = raw;
}

void W32FontInit (void)
{
	int	i;

	for (i=0;i<NUMFONT;i++)
		CA_CacheGrChunk (STARTFONT+i);
}

void CacheLump (int lumpstart,int lumpend)
{
	int	i;

	for (i=lumpstart;i<=lumpend;i++)
		CA_CacheGrChunk (i);
}

void PreloadGraphics (void) {}

/*
=============================================================================

						DRAWING

=============================================================================
*/

//
// a picture: planar in the file -- plane 0's pixels (x = 0, 4, 8 ...) for
// every row, then plane 1's ...
//
static void Pic (int x, int y, int chunk)
{
	int		p = chunk - STARTPICS, w,h,plane,row,col;
	byte	*src;

	if (p < 0 || p >= NUMPICS)
		return;
	CA_CacheGrChunk (chunk);
	src = grsegs[chunk];
	if (!src)
		return;
	w = pictable[p].width;
	h = pictable[p].height;
	for (plane=0;plane<4;plane++)
		for (row=0;row<h;row++)
			for (col=0;col<w/4;col++)
				Put (x + col*4 + plane,y + row,*src++);
}

void VWB_DrawPic (int x, int y, int chunknum)
{
	int	bx,by;

	Base (&bx,&by);
	Pic (bx + (x & ~7),by + y,chunknum);
}

void LatchDrawPic (unsigned x, unsigned y, unsigned picnum)
{
	int	bx,by;

	Base (&bx,&by);
	Pic (bx + x*8,by + y,picnum);
}

static void Bar (int x, int y, int width, int height, int color)
{
	int	i,j;

	for (j=0;j<height;j++)
		for (i=0;i<width;i++)
			Put (x+i,y+j,color);
}

void VL_Bar (int x, int y, int width, int height, int color)
{
	int	bx,by;

	Base (&bx,&by);
	Bar (bx+x,by+y,width,height,color);
}

void VWB_Bar (int x, int y, int width, int height, int color) { VL_Bar (x,y,width,height,color); }
void VL_Hlin (unsigned x, unsigned y, unsigned width, unsigned color) { VL_Bar (x,y,width,1,color); }
void VL_Vlin (int x, int y, int height, int color) { VL_Bar (x,y,1,height,color); }
void VWB_Hlin (int x1, int x2, int y, int color) { VL_Bar (x1,y,x2-x1+1,1,color); }
void VWB_Vlin (int y1, int y2, int x, int color) { VL_Bar (x,y1,1,y2-y1+1,color); }
void VL_Plot (int x, int y, int color) { W32Plot (x,y,color); }
void VWB_Plot (int x, int y, int color) { W32Plot (x,y,color); }

//
// one address's rectangle to another's: on one screen, the same place --
// a copy only when the two are different places within a page
//
void VL_ScreenToScreen (unsigned source, unsigned dest,int width, int height)
{
	unsigned	rs = source % SCREENSIZE, rd = dest % SCREENSIZE;
	int			sx = (rs % SCREENBWIDE)*4, sy = rs / SCREENBWIDE;
	int			dx = (rd % SCREENBWIDE)*4, dy = rd / SCREENBWIDE;
	int			i,j;

	if (sx == dx && sy == dy)
		return;
	for (j=0;j<height;j++)
		for (i=0;i<width*4;i++)
			if ((unsigned)(sx+i) < 320 && (unsigned)(sy+j) < 200)
				Put (dx+i,dy+j,w32screen[(sy+j)*320+sx+i]);
}

//
// text: id's proportional fonts (fontnumber), in fontcolor
//
static int Letters (char far *s, int draw, int x, int y)
{
	fontstruct	*f = grsegs[STARTFONT+fontnumber];
	byte		*src;
	int			w = 0, cw, r, c;

	if (!f)
		return 0;
	for (;*s;s++)
	{
		cw = f->width[(byte)*s];
		if (draw)
		{
			src = (byte *)f + f->location[(byte)*s];
			for (r=0;r<f->height;r++)
				for (c=0;c<cw;c++)
					if (src[r*cw+c])
						Put (x+w+c,y+r,fontcolor);
		}
		w += cw;
	}
	return w;
}

void VWB_DrawPropString (char far *string)
{
	int	bx,by;

	Base (&bx,&by);
	px += Letters (string,1,bx+px,by+py);
}

void VW_MeasurePropString (char far *string, word *width, word *height)
{
	fontstruct	*f = grsegs[STARTFONT+fontnumber];

	*width = Letters (string,0,0,0);
	*height = f ? f->height : 0;
}

void US_Print (char far *s)
{
	char	line[256];
	int		i;

	while (*s)
	{
		for (i=0;*s && *s != '\n' && i < 255;)
			line[i++] = *s++;
		line[i] = 0;
		px = PrintX;
		py = PrintY;
		VWB_DrawPropString (line);
		PrintX = px;
		if (*s == '\n')
		{
			fontstruct	*f = grsegs[STARTFONT+fontnumber];

			s++;
			PrintX = WindowX;
			PrintY += f ? f->height : 10;
		}
	}
}

void US_CPrint (char far *s)
{
	char	line[256];
	int		i;
	word	w,h;

	while (*s)
	{
		for (i=0;*s && *s != '\n' && i < 255;)
			line[i++] = *s++;
		line[i] = 0;
		VW_MeasurePropString (line,&w,&h);
		px = WindowX + (WindowW - w)/2;
		py = PrintY;
		VWB_DrawPropString (line);
		PrintY += h;
		if (*s == '\n')
			s++;
	}
}

void US_DrawWindow (word x,word y,word w,word h)
{
	WindowX = x*8;
	WindowY = y*8;
	WindowW = w*8;
	WindowH = h*8;
	PrintX = WindowX;
	PrintY = WindowY;
	VWB_Bar (WindowX,WindowY,WindowW,WindowH,WHITE);
}

void Message (char far *string)
{
	CA_CacheGrChunk (STARTFONT);
	fontnumber = 0;
	fontcolor = 0;
	PrintY = 100 - 10;
	WindowX = 0;
	WindowW = 320;
	US_CPrint (string);
	VW_UpdateScreen ();
}

void Write (int x,int y,char *string)
{
	px = x*8;
	py = y*8;
	VWB_DrawPropString (string);
}

boolean US_LineInput (int x,int y,char *buf,char *def,boolean escok,int maxchars,int maxwidth)
{
	return false;
}

/*
=============================================================================

						THE SCREEN

=============================================================================
*/

void VL_SetPalette (byte far *palette)
{
	memcpy (w32palette,palette,768);
	VW_UpdateScreen ();
}

void VL_GetPalette (byte far *palette)
{
	memcpy (palette,w32palette,768);
}

void VL_FadeOut (int start, int end, int red, int green, int blue, int steps)
{
	int	i;

	for (i=start;i<=end;i++)
	{
		w32palette[i*3] = (byte)red;
		w32palette[i*3+1] = (byte)green;
		w32palette[i*3+2] = (byte)blue;
	}
	screenfaded = true;
	VW_UpdateScreen ();
}

void VL_FadeIn (int start, int end, byte far *palette, int steps)
{
	memcpy (w32palette+start*3,palette+start*3,(end-start+1)*3);
	screenfaded = false;
	VW_UpdateScreen ();
}

void VW_UpdateScreen (void)
{
	W32Present (w32screen,w32palette);
}

void VL_WaitVBL (int vbls) { W32Wait (vbls*1000/70); }
void VL_LowVert (int on) {}
void FixOfs (void) {}
void ClearSplitVWB (void) {}

boolean FizzleFade (unsigned source, unsigned dest, unsigned width,unsigned height,
	unsigned frames,boolean abortable)
{
	VW_UpdateScreen ();
	return false;
}

void	MPPageFile (void);
void	InitRedShifts (void);
void	W32Wait (int ms);
extern	int	viewsize;

//
// the game's start (w32main.c's W32Run): the graphics, the palette, the page
// file -- VSWAPM with the players' BJ when it is there (WL_MP.C's MPPageFile),
// as on DOS -- the palette's red and white shifts, the view (VIEW n: 4-20)
//
void W32Startup (void)
{
	int	i, v = 20;

	memcpy (w32palette,(byte *)&gamepal,768);	// (w32pal.c: id's palette)
	W32GrStartup ();
	W32FontInit ();
	strcpy (PageFileName,"VSWAP.");
	strcat (PageFileName,extension);
	MPPageFile ();
	W32PMStartup ();
	InitRedShifts ();
	for (i=1;i+1<_argc;i++)
		if (!stricmp (_argv[i],"view"))
			v = atoi (_argv[i+1]);
	viewsize = v;
	NewViewSize (v);
}
