/* OPLTIME.C -- how long does one IN from the AdLib port take on this box?
   StevenC & Claude, 2026

   id's alOut waits for the OPL2 by reading its status port: 6 reads after
   the address write (the chip needs 3.3 us) and 35 after the data write
   (23 us) -- counts chosen for a 1990 AT.  This times reads of port 388h,
   and of port 61h for comparison, over three BIOS ticks with 16 reads per
   loop pass, and says what the two waits come to here.
*/

#include <stdio.h>
#include <dos.h>

static unsigned long ticks (void)
{
	unsigned long t;
	disable ();
	t = *(unsigned long far *)MK_FP(0x40,0x6c);
	enable ();
	return t;
}

/* passes of 16 INs from port p in n BIOS ticks, after syncing to a tick edge */
static unsigned long passes (unsigned port, unsigned n)
{
	unsigned long start, count = 0;
	unsigned lo;

	start = ticks ();
	while (ticks () == start)
		;
	start = ticks ();
	while (ticks () - start < n)
	{
		_DX = port;
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		asm	in	al,dx
		count++;
	}
	lo = 0;
	(void)lo;
	return count;
}

static void report (char *what, unsigned port)
{
	unsigned long p = passes (port, 3);
	/* 3 ticks = 164,775 us; ns per pass then per read (loop overhead included) */
	unsigned long nsread = (164775000UL / p) / 16;
	printf ("%-24s %6lu passes of 16 in 3 ticks = %lu ns per read (loop included)\n",
		what, p, nsread);
	if (port == 0x388)
	{
		printf ("  id's waits here: 6 reads = %lu ns (chip needs 3,300)  35 reads = %lu ns (chip needs 23,000)\n",
			6 * nsread, 35 * nsread);
	}
}

int main (void)
{
	printf ("OPLTIME -- the cost of an AdLib status read -- StevenC & Claude\n");
	report ("port 388h (AdLib)", 0x388);
	report ("port 61h (motherboard)", 0x61);
	report ("port 388h again", 0x388);
	return 0;
}
