/*
 * w32null.c -- the headless replay's picture and input: nothing.  (The game
 * has w32gfx.c, w32draw.c and w32win.c instead.)  A font for the text the
 * game measures -- WL_MP.C's Text1 reads widths before it draws -- every
 * letter 8 wide, 8 high, blank.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop

word	PMSpriteStart,PMSoundStart;

static struct
{
	int		height;
	int		location[256];
	char	width[256];
	byte	data[64];
} w32font;

void W32FontInit (void)
{
	int	i;

	w32font.height = 8;
	for (i=0;i<256;i++)
	{
		w32font.location[i] = (byte *)w32font.data - (byte *)&w32font;
		w32font.width[i] = 8;
	}
	grsegs[STARTFONT] = grsegs[STARTFONT+1] = &w32font;
}

void W32Plot (int x, int y, int color) { x = y = color; }
void VL_Bar (int x, int y, int width, int height, int color) {}
void VL_FadeIn (int start, int end, byte far *palette, int steps) {}
void VL_FadeOut (int start, int end, int red, int green, int blue, int steps) {}
void VL_Hlin (unsigned x, unsigned y, unsigned width, unsigned color) {}
void VL_LowVert (int on) {}
void VL_Plot (int x, int y, int color) {}
void VL_ScreenToScreen (unsigned source, unsigned dest,int width, int height) {}
void VL_SetPalette (byte far *palette) {}
void VL_Vlin (int x, int y, int height, int color) {}
void VL_WaitVBL (int vbls) {}
void VWB_Bar (int x, int y, int width, int height, int color) {}
void VWB_DrawPic (int x, int y, int chunknum) {}
void VWB_Hlin (int x1, int x2, int y, int color) {}
void VWB_Plot (int x, int y, int color) {}
void VWB_Vlin (int y1, int y2, int x, int color) {}
void VW_UpdateScreen (void) {}
void LatchDrawPic (unsigned x, unsigned y, unsigned picnum) {}
boolean FizzleFade (unsigned source, unsigned dest, unsigned width,unsigned height,
	unsigned frames,boolean abortable) { return false; }
void ThreeDRefresh (void) {}
void FixOfs (void) {}
void ClearSplitVWB (void) {}
void US_DrawWindow (word x,word y,word w,word h) {}
void US_CPrint (char far *s) {}
void US_Print (char far *s) {}
boolean US_LineInput (int x,int y,char *buf,char *def,boolean escok,int maxchars,int maxwidth)
	{ return false; }
void Message (char far *string) {}
void Write (int x,int y,char *string) {}
void CacheLump (int lumpstart,int lumpend) {}
void PreloadGraphics (void) {}
void W32MouseDelta (int *dx, int *dy) { *dx = *dy = 0; }
unsigned short	w32ax,w32bx,w32cx,w32dx,w32si,w32di;	// (w32comp.h: no mouse
void W32Int (int n) { w32cx = w32dx = w32bx = 0; }		// here, nothing moved)
void CA_CacheGrChunk (int chunk) {}

//
// input: nobody at the keyboard
//
void IN_Ack (void) {}
boolean IN_CheckAck (void) { return true; }
void IN_ClearKeysDown (void) {}
void IN_StartAck (void) {}
boolean IN_UserInput (longword delay) { return false; }
byte IN_JoyButtons (void) { return 0; }
byte IN_MouseButtons (void) { return 0; }
void IN_SetKeyHook (void (*hook)()) {}
void INL_GetJoyDelta (word joy,int *dx,int *dy) { *dx = *dy = 0; }

SDMode		SoundMode;
SMMode		MusicMode;

//
// sound: nothing plays.  No game state waits on a sound in a network game
// (WL_MP.C's MPFace replaced id's face, which skipped random numbers while
// a sound played)
//
boolean SD_PlaySound (soundnames sound) { return false; }
word SD_SoundPlaying (void) { return 0; }
void SD_PositionSound (int leftvol,int rightvol) {}
void SD_SetPosition (int leftvol,int rightvol) {}
void SD_WaitSoundDone (void) {}
void SD_StartMusic (MusicGroup far *music) {}
void SD_MusicOn (void) {}
void SD_MusicOff (void) {}
boolean SD_SetSoundMode (SDMode mode) { return true; }
boolean SD_SetMusicMode (SMMode mode) { return true; }
void SD_SetDigiDevice (SDSMode mode) {}
void SD_StopDigitized (void) {}
void SD_Poll (void) {}
void CA_CacheAudioChunk (int chunk) {}
void CA_LoadAllSounds (void) {}

void W32Events (void) {}				// no window
void W32Present (byte *screen, byte *palette) {}
void W32Message (char *s) {}

//
// the headless replay's start: the blank font; and its main
//
void W32Startup (void)
{
	W32FontInit ();
}

int W32Run (void);

int main (void)
{
	return W32Run ();
}
void IN_ReadControl (int player,ControlInfo *info) { memset (info,0,sizeof(*info)); }
