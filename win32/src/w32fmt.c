/*
 * w32fmt.c -- printf and friends for id's format strings on Win32.
 * Borland's %Fs is a far string; to Open Watcom's 32-bit printf an F size
 * is a 48-bit far pointer, so it read two arguments for one and wrote what
 * it found (a kill's notice ran a string of zeros up the stack, 2026-10-21).
 * Every pointer is the same here: the F and N sizes are taken out of the
 * format, and the call goes on.  w32comp.h sends the calls here.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <stdio.h>
#include <stdarg.h>
#include <string.h>
#undef printf
#undef sprintf
#undef vprintf
#undef vsprintf

static const char *Plain (const char *fmt, char *buf, unsigned size)
{
	const char	*p;
	char		*o = buf, *end = buf + size - 1;
	int			inspec = 0;

	if (!strchr (fmt,'F') && !strchr (fmt,'N'))
		return fmt;
	for (p = fmt;*p && o < end;p++)
	{
		if (!inspec)
		{
			*o++ = *p;
			if (*p == '%')
				inspec = 1;
			continue;
		}
		if (*p == '%')					// %%
		{
			*o++ = *p;
			inspec = 0;
			continue;
		}
		if (*p == 'F' || *p == 'N')		// the size: dropped
			continue;
		*o++ = *p;
		if (strchr ("diouxXcspeEfgGn",*p))
			inspec = 0;
	}
	*o = 0;
	return buf;
}

int w32_vprintf (const char *fmt, va_list ap)
{
	char	buf[512];

	return vprintf (Plain (fmt,buf,sizeof(buf)),ap);
}

int w32_vsprintf (char *out, const char *fmt, va_list ap)
{
	char	buf[512];

	return vsprintf (out,Plain (fmt,buf,sizeof(buf)),ap);
}

int w32_printf (const char *fmt, ...)
{
	va_list	ap;
	int		n;

	va_start (ap,fmt);
	n = w32_vprintf (fmt,ap);
	va_end (ap);
	return n;
}

int w32_sprintf (char *out, const char *fmt, ...)
{
	va_list	ap;
	int		n;

	va_start (ap,fmt);
	n = w32_vsprintf (out,fmt,ap);
	va_end (ap);
	return n;
}
