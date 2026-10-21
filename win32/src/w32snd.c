/*
 * w32snd.c -- id's sound calls on Win32 (ID_SD.C's SD_ ones), over
 * w32wave.c's OPL2 and mixer: the sounds from AUDIOT (AdLib effects and
 * music) and the page file (the digitized ones), id's priorities, a sound's
 * place left and right, NOAL / NOSB / NOMUSIC as on DOS.
 *
 * A sound's header is read byte by byte -- a word is 32 bits here, and id's
 * structs would put every field in the wrong place.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include "WL_DEF.H"
#pragma hdrstop
#include <math.h>

int		W32SndStart (void);			// w32wave.c
void	W32SndDigi (byte *data, long len, int hz, int lvol, int rvol);
void	W32SndDigiStop (void);
int		W32SndDigiPlaying (void);
void	W32SndFx (byte *inst, int block, byte *data, long len);
void	W32SndFxStop (void);
int		W32SndFxPlaying (void);
void	W32SndMusic (byte *data, long len);
void	W32SndMusicOff (void);
void	W32SndMusicOn (void);
void	W32Wait (int ms);
extern	word	ChunksInFile;		// w32gfx.c's page file
memptr	PM_GetPage (int pagenum);

SDMode		SoundMode;
SMMode		MusicMode;
int			DigiMap[LASTSOUND];
static	int		LeftPosition, RightPosition, nextsoundpos;
static	int		SoundNumber, SoundPriority;
static	int		started;
static	byte	**digis;
static	long	*digilens;
static	int		numdigi;

static int	wolfdigimap[] =		// WL_MAIN.C's: a sound, its digitized one
{
#ifndef SPEAR
	HALTSND,0, DOGBARKSND,1, CLOSEDOORSND,2, OPENDOORSND,3, ATKMACHINEGUNSND,4,
	ATKPISTOLSND,5, ATKGATLINGSND,6, SCHUTZADSND,7, GUTENTAGSND,8, MUTTISND,9,
	BOSSFIRESND,10, SSFIRESND,11, DEATHSCREAM1SND,12, DEATHSCREAM2SND,13,
	DEATHSCREAM3SND,13, TAKEDAMAGESND,14, PUSHWALLSND,15, LEBENSND,20,
	NAZIFIRESND,21, SLURPIESND,22, YEAHSND,32,
#ifndef UPLOAD
	DOGDEATHSND,16, AHHHGSND,17, DIESND,18, EVASND,19, TOT_HUNDSND,23,
	MEINGOTTSND,24, SCHABBSHASND,25, HITLERHASND,26, SPIONSND,27, NEINSOVASSND,28,
	DOGATTACKSND,29, LEVELDONESND,30, MECHSTEPSND,31, SCHEISTSND,33,
	DEATHSCREAM4SND,34, DEATHSCREAM5SND,35, DONNERSND,36, EINESND,37,
	ERLAUBENSND,38, DEATHSCREAM6SND,39, DEATHSCREAM7SND,40, DEATHSCREAM8SND,41,
	DEATHSCREAM9SND,42, KEINSND,43, MEINSND,44, ROSESND,45,
#endif
#else
	HALTSND,0, CLOSEDOORSND,2, OPENDOORSND,3, ATKMACHINEGUNSND,4, ATKPISTOLSND,5,
	ATKGATLINGSND,6, SCHUTZADSND,7, BOSSFIRESND,8, SSFIRESND,9, DEATHSCREAM1SND,10,
	DEATHSCREAM2SND,11, TAKEDAMAGESND,12, PUSHWALLSND,13, AHHHGSND,15, LEBENSND,16,
	NAZIFIRESND,17, SLURPIESND,18, LEVELDONESND,22, DEATHSCREAM4SND,23,
	DEATHSCREAM3SND,23, DEATHSCREAM5SND,24, DEATHSCREAM6SND,25, DEATHSCREAM7SND,26,
	DEATHSCREAM8SND,27, DEATHSCREAM9SND,28, DOGBARKSND,29, DOGDEATHSND,30,
	DOGATTACKSND,31, ANGELTIREDSND,32, ANGELDEATHSND,33, ANGELFIRESND,34,
	GETGATLINGSND,35, SHOOTDOORSND,36, ANGELSIGHTSND,37, SPIONSND,38, NEINSOVASSND,39,
	DOGBARKSND,40, YEAHSND,41, KNIGHTSIGHTSND,42, KNIGHTDEATHSND,43,
	KNIGHTMISSILESND,44, TRANSSIGHTSND,45, TRANSDEATHSND,46, WILHELMSIGHTSND,47,
	WILHELMDEATHSND,48, UBERDEATHSND,49, ENDBONUS1SND,50, ENDBONUS2SND,51,
	GETSPEARSND,52,
#endif
	LASTSOUND
};

static long Get32 (byte *p) { return p[0] | (p[1] << 8) | ((long)p[2] << 16) | ((long)p[3] << 24); }
static int Get16 (byte *p) { return p[0] | (p[1] << 8); }

static int Has (char *w)
{
	int	i;

	for (i=1;i<_argc;i++)
		if (!stricmp (_argv[i],w))
			return 1;
	return 0;
}

//
// the start: AUDIOHED's offsets and every chunk of AUDIOT in memory; the
// digitized sounds out of the page file's pages, each in one piece (its
// last page lists them: a start page and a length each)
//
void W32SndStartup (void)
{
	char	name[16];
	byte	*list;
	long	*ofs;
	int		f,i,n;

	for (i=0;i<LASTSOUND;i++)
		DigiMap[i] = -1;
	for (i=0;wolfdigimap[i] != LASTSOUND;i += 2)
		DigiMap[wolfdigimap[i]] = wolfdigimap[i+1];
	strcpy (name,"AUDIOHED.");
	strcat (name,extension);
	if ((f = open (name,O_RDONLY|O_BINARY)) < 0)
		return;
	ofs = malloc ((NUMSNDCHUNKS+1)*4);
	for (i=0;i<=NUMSNDCHUNKS;i++)
	{
		byte	b[4];

		read (f,b,4);
		ofs[i] = Get32 (b);
	}
	close (f);
	strcpy (name,"AUDIOT.");
	strcat (name,extension);
	if ((f = open (name,O_RDONLY|O_BINARY)) >= 0)
	{
		for (i=0;i<NUMSNDCHUNKS;i++)
		{
			long	len = ofs[i+1] - ofs[i];

			if (len <= 0)
				continue;
			audiosegs[i] = malloc (len + 4);
			lseek (f,ofs[i],SEEK_SET);
			read (f,audiosegs[i],len);
		}
		close (f);
	}
	free (ofs);
	list = PM_GetPage (ChunksInFile-1);
	numdigi = 0;
	for (n=0;n<256;n++)				// to the first that does not fit
	{
		int	page = Get16 (list+n*4);
		long	len = Get16 (list+n*4+2);

		if (!len || PMSoundStart + page >= ChunksInFile-1)
			break;
		numdigi = n+1;
	}
	digis = calloc (numdigi+1,sizeof(byte *));
	digilens = calloc (numdigi+1,sizeof(long));
	for (n=0;n<numdigi;n++)
	{
		int		page = PMSoundStart + Get16 (list+n*4);
		long	len = Get16 (list+n*4+2), done;

		digis[n] = malloc (len);
		digilens[n] = len;
		for (done=0;done<len;done += 4096,page++)
			memcpy (digis[n] + done,PM_GetPage (page),len - done < 4096 ? len - done : 4096);
	}
	SoundMode = Has ("noal") ? sdm_Off : sdm_AdLib;
	MusicMode = Has ("noal") || Has ("nomusic") ? smm_Off : smm_AdLib;
	DigiMode = Has ("nosb") ? sds_Off : sds_SoundBlaster;
	AdLibPresent = SoundMode == sdm_AdLib;
	SoundBlasterPresent = DigiMode == sds_SoundBlaster;
	started = W32SndStart ();
	if (!started)
	{
		SoundMode = sdm_Off;
		MusicMode = smm_Off;
		DigiMode = sds_Off;
	}
}

void CA_CacheAudioChunk (int chunk) {}	// all of them, at the start
void CA_LoadAllSounds (void) {}

static int Gain (int pos)				// an attenuation 0-15, 0 loud: 2 dB a step
{
	if (pos < 0)
		pos = 0;
	if (pos > 15)
		pos = 15;
	return (int)(256 * pow (10.0,-pos*2.0/20));
}

static boolean Playing (void)
{
	return W32SndDigiPlaying () || W32SndFxPlaying ();
}

//
// SD_PlaySound, as id's: digitized if there is one for it, else the AdLib
// effect; either only if its priority is not under what is playing
//
boolean SD_PlaySound (soundnames sound)
{
	byte	*s;
	int		lp = LeftPosition, rp = RightPosition, ispos = nextsoundpos, pri;

	LeftPosition = RightPosition = 0;
	nextsoundpos = false;
	if ((int)sound < 0 || sound >= LASTSOUND || !started)
		return false;
	s = audiosegs[STARTADLIBSOUNDS + sound];
	if (!s)
		return false;
	pri = Get16 (s+4);
	if (!Playing ())
		SoundPriority = 0;
	if (DigiMode != sds_Off && DigiMap[sound] != -1 && DigiMap[sound] < numdigi)
	{
		if (pri < SoundPriority)
			return false;
		W32SndFxStop ();
		W32SndDigi (digis[DigiMap[sound]],digilens[DigiMap[sound]],7042,Gain (lp),Gain (rp));
		SoundPositioned = ispos;
		SoundNumber = sound;
		SoundPriority = pri;
		return true;
	}
	if (SoundMode == sdm_Off || pri < SoundPriority)
		return false;
	W32SndDigiStop ();
	W32SndFx (s+6,s[22],s+23,Get32 (s));
	SoundNumber = sound;
	SoundPriority = pri;
	return false;
}

word SD_SoundPlaying (void)
{
	return Playing () ? SoundNumber : 0;
}

void SD_PositionSound (int leftvol,int rightvol)
{
	LeftPosition = leftvol;
	RightPosition = rightvol;
	nextsoundpos = true;
}

void SD_SetPosition (int leftvol,int rightvol) {}	// (a playing sound stays where it began)

void SD_StopSound (void)
{
	W32SndDigiStop ();
	W32SndFxStop ();
	SoundNumber = SoundPriority = 0;
}

void SD_WaitSoundDone (void)
{
	while (Playing ())
		W32Wait (10);
}

//
// music: id's MusicGroup -- its length in bytes, then register, value and a
// delay at 700 Hz, round and round
//
void SD_StartMusic (MusicGroup far *music)
{
	byte	*m = (byte *)music;

	if (!started || MusicMode != smm_AdLib || !m)
		return;
	W32SndMusic (m+2,Get16 (m));
}

void SD_MusicOn (void) { if (started && MusicMode == smm_AdLib) W32SndMusicOn (); }
void SD_MusicOff (void) { if (started) W32SndMusicOff (); }
void SD_FadeOutMusic (void) { SD_MusicOff (); }

boolean SD_SetSoundMode (SDMode mode)
{
	if (!started || Has ("noal"))
		mode = sdm_Off;
	SoundMode = mode;
	return true;
}

boolean SD_SetMusicMode (SMMode mode)
{
	if (!started || Has ("noal") || Has ("nomusic"))
		mode = smm_Off;
	MusicMode = mode;
	if (mode == smm_Off)
		SD_MusicOff ();
	return true;
}

void SD_SetDigiDevice (SDSMode mode)
{
	DigiMode = started && !Has ("nosb") ? mode : sds_Off;
}

void SD_StopDigitized (void) { W32SndDigiStop (); }
void SD_Poll (void) {}
