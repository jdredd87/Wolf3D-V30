/* Open Watcom toolchain check: a Win32 console program -- StevenC & Claude (Anthropic) */
#include <stdio.h>
#include <windows.h>
int main (void)
{
	OSVERSIONINFO v;
	short s = 32767;
	v.dwOSVersionInfoSize = sizeof(v);
	GetVersionEx (&v);
	s++;							/* 16-bit wrap, as Borland's int does */
	printf ("hello from Open Watcom on Windows %lu.%lu build %lu; short 32767+1 = %d, sizeof(int) %u\n",
		v.dwMajorVersion, v.dwMinorVersion, v.dwBuildNumber, s, (unsigned)sizeof(int));
	return 3;
}
