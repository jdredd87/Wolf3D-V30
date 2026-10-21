/*
 * w32comp.h -- forced into every WOLFSRC file built for Win32 (wcc386 -fi).
 * id's code is Borland C++ 3.1 for real mode: far, near and huge pointers,
 * _seg, interrupt functions.  In a flat 32-bit program every pointer is
 * the same, so they mean nothing.  StevenC & Claude (Anthropic), 2026-10-21.
 */
#ifndef W32COMP_H
#define W32COMP_H
/* the compiler's own headers first: they declare _fmemcpy and the rest, and
   the macros below must not reach those declarations */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <fcntl.h>
#include <io.h>
#include <dos.h>
#include <errno.h>
#include <process.h>
#include <sys/stat.h>
#define W32			1
#define far
#define near
#define huge
#define _seg
#define interrupt
#define _fmemcpy	memcpy
#define _fmemset	memset
#define _fmemcmp	memcmp
#define _fmemmove	memmove
#define _fstrcpy	strcpy
#define _fstrlen	strlen
#define _fstrcmp	strcmp
#define _fstrncpy	strncpy
#define _fstricmp	stricmp
#define _fstrcat	strcat
/* the DOS file calls: Open Watcom declares them with 48-bit far pointers and
   has none on Win32 -- w32ca.c has them, flat */
#define _dos_open	w32_dos_open
#define _dos_creat	w32_dos_creat
#define _dos_read	w32_dos_read
#define _dos_write	w32_dos_write
#define _dos_close	w32_dos_close
#define _creat		w32_creat
unsigned w32_dos_open (const char *path, unsigned mode, int *handle);
unsigned w32_dos_creat (const char *path, unsigned attr, int *handle);
unsigned w32_dos_read (int handle, void *buf, unsigned count, unsigned *bytes);
unsigned w32_dos_write (int handle, const void *buf, unsigned count, unsigned *bytes);
unsigned w32_dos_close (int handle);
int w32_creat (const char *path, int attr);
#define peek(s,o)		((void)(s),(void)(o),0)
#define bioskey(c)		((void)(c),0)
#define farmalloc	malloc
#define farfree		free
#define farcoreleft()	(16L*1024*1024)
#define coreleft()		(16L*1024*1024)
#define MAXINT		0x7fff
/* Borland's _argc and _argv: Open Watcom's runtime keeps them as __argc and
   __argv (stdlib.h).  (Defining an _argc here replaced the runtime's own --
   Watcom puts an underscore before data names -- and main got 0.) */
#define _argc		__argc
#define _argv		__argv
extern long		w32biosticks;	/* the BIOS tick, 18.2 a second (w32main.c) */
unsigned long	W32Ms (void);	/* milliseconds since start (w32main.c) */
void			W32MouseDelta (int *dx, int *dy);
void			W32Plot (int x, int y, int color);
void			W32Check (long step, unsigned long sum);	/* each 50th step's sum */	/* a pixel of the page drawn on */
/* the VGA's ports: written to the emulated card (w32vga.c, later); read as 0 */
#define outport(p,v)	((void)(p),(void)(v))
#define outportb(p,v)	((void)(p),(void)(v))
#define inport(p)		((void)(p),0)
#define inportb(p)		((void)(p),0)
#define disable()		((void)0)
#define enable()		((void)0)
/* printf and friends: id's formats say %Fs for a far string (w32fmt.c) */
#include <stdarg.h>
int w32_printf (const char *fmt, ...);
int w32_sprintf (char *out, const char *fmt, ...);
int w32_vprintf (const char *fmt, va_list ap);
int w32_vsprintf (char *out, const char *fmt, va_list ap);
#define printf		w32_printf
#define sprintf		w32_sprintf
#define vprintf		w32_vprintf
#define vsprintf	w32_vsprintf
#ifndef M_PI
#define M_PI		3.14159265358979323846	/* Borland's math.h has it */
#endif
#endif
