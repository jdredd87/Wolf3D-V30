/* LDTEST.C -- check H_LDIV.ASM's V30 fast path on real hardware
   StevenC & Claude, 2026

   Every / and % on longs below goes through H_LDIV (it is linked ahead of
   the library), and is checked against a reference that uses no division
   at all -- shift, compare and subtract, the way Borland's loop did it --
   for signed and unsigned quotients and remainders.

	LDTEST [n]		n random cases per class (default 4000)
	exit 0 all exact, 1 a mismatch (the first few are printed)
*/

#include <stdio.h>
#include <stdlib.h>

static unsigned long seed = 1992;
static long failures, checked;

static unsigned long rnd32 (void)
{
	seed = seed * 1103515245UL + 12345UL;
	return (seed >> 16) | ((seed * 69069UL + 1) & 0xFFFF0000UL);
}

/* reference: unsigned restoring division, no divide instruction */
static unsigned long refu (unsigned long u, unsigned long v, unsigned long *rem)
{
	unsigned long q = 0, r = 0;
	int i;

	for (i = 31; i >= 0; i--)
	{
		r = (r << 1) | ((u >> i) & 1);
		if (r >= v)
		{
			r -= v;
			q |= 1UL << i;
		}
	}
	*rem = r;
	return q;
}

static void fail (char *what, unsigned long a, unsigned long b, unsigned long got, unsigned long want)
{
	failures++;
	if (failures <= 8)
		printf ("MISMATCH %s %08lX, %08lX: got %08lX want %08lX\n", what, a, b, got, want);
}

static void check (unsigned long a, unsigned long b)
{
	unsigned long q, r, ua, ub;
	long sa, sb, sq, sr;
	int nega, negb;

	if (!b)
		return;
	checked++;

	/* unsigned */
	q = refu (a, b, &r);
	if (a / b != q) fail ("u/", a, b, a / b, q);
	if (a % b != r) fail ("u%", a, b, a % b, r);

	/* signed: C truncates toward zero, the remainder takes the dividend's sign */
	sa = (long)a;
	sb = (long)b;
	nega = sa < 0;
	negb = sb < 0;
	ua = nega ? 0UL - a : a;
	ub = negb ? 0UL - b : b;
	q = refu (ua, ub, &r);
	sq = (nega != negb) ? -(long)q : (long)q;
	sr = nega ? -(long)r : (long)r;
	if (sa / sb != sq) fail ("s/", a, b, (unsigned long)(sa / sb), (unsigned long)sq);
	if (sa % sb != sr) fail ("s%", a, b, (unsigned long)(sa % sb), (unsigned long)sr);
}

int main (int argc, char **argv)
{
	static unsigned long edges[] = {
		1, 2, 3, 0x7FFFUL, 0x8000UL, 0x8001UL, 0xFFFFUL, 0x10000UL, 0x10001UL,
		0x1FFFFUL, 0x5800UL, 0x7FFFFFFFUL, 0x80000000UL, 0x80000001UL,
		0xFFFFFFFEUL, 0xFFFFFFFFUL, 0xFFFF0000UL, 0x12345678UL, 0xFFFF8000UL };
	int ne = sizeof (edges) / sizeof (edges[0]);
	long n, i;
	int x, y, k;
	unsigned long v;

	n = argc > 1 ? atol (argv[1]) : 4000;
	printf ("LDTEST -- H_LDIV's V30 fast path against a reference -- StevenC & Claude\n");

	for (x = 0; x < ne; x++)
		for (y = 0; y < ne; y++)
			check (edges[x], edges[y]);
	for (k = 16; k < 32; k++)			/* every normalisation shift */
	{
		v = 1UL << k;
		check (0xFFFFFFFFUL, v); check (0xFFFFFFFFUL, v + 1); check (0xFFFFFFFFUL, v * 2 - 1);
		check (v * 3 - 1, v); check (v * 3, v); check (v - 1, v); check (v, v - 1);
	}
	for (i = 0; i < n; i++)
	{
		check (rnd32 (), rnd32 () | 0x10000UL);				/* big divisor */
		check (rnd32 (), rnd32 () & 0xFFFFUL);				/* small divisor */
		check (rnd32 () >> (rnd32 () & 31), rnd32 ());		/* any sizes */
		check (rnd32 () & 0x7FFFFFFFUL, 0x5800UL + (rnd32 () & 0x7FFFFFFUL));	/* ny*scale/nx */
		check (rnd32 (), 0x10000UL + (rnd32 () & 0xFEFFFFUL));	/* high word 1-255: step 42's byte shift */
	}

	printf ("%ld operand pairs, 4 operations each: %ld mismatches\n", checked, failures);
	return failures ? 1 : 0;
}
