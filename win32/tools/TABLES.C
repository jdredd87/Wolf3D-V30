/* TABLES.C -- id's BuildTables (WL_MAIN.C), as Borland C++ 3.1 computes it on
   DOS, printed: the Win32 build takes the numbers from here rather than its
   own floating point.  StevenC & Claude (Anthropic), 2026-10-21. */
#include <stdio.h>
#include <math.h>
#define PI          3.141592657
#define ANGLES      360
#define ANGLEQUAD   (ANGLES/4)
#define FINEANGLES  3600
#define GLOBAL1     (1l<<16)
#define TILEGLOBAL  GLOBAL1
typedef long fixed;
const float radtoint = (float)FINEANGLES/2/PI;   /* WL_MAIN.C: a float */
fixed sintable[ANGLES+ANGLES/4+1];
fixed finetangent[FINEANGLES/4];
int main (void)
{
  int i;
  float angle,anglestep;
  double tang;
  fixed value;
  for (i=0;i<FINEANGLES/8;i++)
  {
    tang = tan( (i+0.5)/radtoint);
    finetangent[i] = tang*TILEGLOBAL;
    finetangent[FINEANGLES/4-1-i] = 1/tang*TILEGLOBAL;
  }
  angle = 0;
  anglestep = PI/2/ANGLEQUAD;
  for (i=0;i<=ANGLEQUAD;i++)
  {
    value=GLOBAL1*sin(angle);
    sintable[i]= sintable[i+ANGLES]= sintable[ANGLES/2-i] = value;
    sintable[ANGLES-i]= sintable[ANGLES/2+i] = value | 0x80000000l;
    angle += anglestep;
  }
  for (i=0;i<ANGLES+ANGLES/4+1;i++) printf ("S %d %08lX\n",i,sintable[i]);
  for (i=0;i<FINEANGLES/4;i++) printf ("T %d %08lX\n",i,finetangent[i]);
  return 0;
}
