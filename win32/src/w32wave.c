/*
 * w32wave.c -- sound on Win32: an OPL2 (the AdLib's YM3812) in C, the
 * digitized sounds, mixed at 22,050 Hz stereo into waveOut's buffers by a
 * thread -- waveOut, threads and critical sections all there since Windows
 * 95.  w32snd.c is id's side of it (SD_PlaySound and the rest); the calls
 * between the two are plain C.  (Not with id's headers: both define boolean.)
 *
 * The OPL2 is written from what the chip is documented to do, not from any
 * other emulator: 9 channels of 2 operators -- a modulator and a carrier,
 * FM or added -- each a phase (fnum and block, the multiplier) through one
 * of four waveforms, an envelope (attack, decay, sustain, release at the
 * chip's rates, key scaling) and an attenuation (total level), the
 * modulator's feedback.  No rhythm mode, vibrato or tremolo: Wolfenstein's
 * music and effects do not lean on them.  It sounds like an AdLib, not
 * exactly like one.
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <windows.h>
#include <mmsystem.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>

#define RATE		22050
#define FRAMES		512					// a buffer: 23 ms
#define NBUF		6

/*
=============================================================================

						THE OPL2

=============================================================================
*/

typedef struct
{
	unsigned long	phase, inc;			// a cycle is 1 << 20
	int		mult, ksr, egt, tl, ksl, ar, dr, sl, rr, ws;
	int		state;						// 0 off, 1 attack, 2 decay, 3 sustain, 4 release
	double	env;						// attenuation, dB: 0 loud, 96 silent
	double	da, dd, dr2;				// dB a sample: attack, decay, release
	int		out1, out2;					// the last two outputs (feedback)
} op_t;

typedef struct
{
	op_t	op[2];
	int		fnum, block, key, fb, cnt;
} chan_t;

static chan_t	chans[9];
static int		wse;					// waveform select enabled (register 1)
static short	sintab[1024];			// a cycle, 4095 at the top
static unsigned short	dbtab[1024];	// 0 .. 96 dB in 1024 steps, as a gain of 4096

static const double multtab[16] = {0.5,1,2,3,4,5,6,7,8,9,10,10,12,12,15,15};
// the chip's attack times, 0 to full, and decay/release times, 0 to 96 dB,
// in ms, by rate (key scaling 0); each step of the four within a rate a
// quarter of an octave faster
static const double attackms[16] = {0,2826.24,1413.12,706.56,353.28,176.64,88.32,44.16,
	22.08,11.04,5.52,2.76,1.38,0.69,0.35,0.01};
static const double decayms[16] = {0,39280.64,19640.32,9820.16,4910.08,2455.04,1227.52,
	613.76,306.88,153.44,76.72,38.36,19.20,9.60,4.80,2.40};
// the operators' register offsets, by channel: modulator, carrier
static const int opoffs[9][2] = {{0,3},{1,4},{2,5},{8,11},{9,12},{10,13},{16,19},{17,20},{18,21}};

static void OplTables (void)
{
	int	i;

	for (i=0;i<1024;i++)
	{
		sintab[i] = (short)floor (sin (i * 2 * 3.14159265358979 / 1024) * 4095 + 0.5);
		dbtab[i] = (unsigned short)floor (pow (10.0,-(i * 96.0 / 1024) / 20) * 4096 + 0.5);
	}
}

static double Time (const double *tab, int rate, int ksroff)
{
	double	t;

	if (!rate)
		return 0;						// never
	t = tab[rate] / pow (2.0,ksroff/4.0);
	return t < 0.01 ? 0.01 : t;
}

static void OpRates (chan_t *c, op_t *o)
{
	int		rof = (c->block << 1) | (c->fnum >> 9);	// key scaling: block and its top bit

	if (!o->ksr)
		rof >>= 2;
	o->da = o->ar ? 96.0 / (Time (attackms,o->ar,rof) * RATE / 1000) : 0;
	o->dd = o->dr ? 96.0 / (Time (decayms,o->dr,rof) * RATE / 1000) : 0;
	o->dr2 = o->rr ? 96.0 / (Time (decayms,o->rr,rof) * RATE / 1000) : 0;
	o->inc = (unsigned long)(c->fnum * 49716.0 / pow (2.0,20 - c->block) * multtab[o->mult]
		/ RATE * (1 << 20));
}

static void OplWrite (int reg, int val)
{
	int	ch, o, i;

	reg &= 0xff;
	val &= 0xff;
	if (reg == 1)
	{
		wse = val & 0x20;
		return;
	}
	if (reg >= 0x20 && reg < 0xa0 || reg >= 0xe0)
	{
		int	off = reg & 0x1f, base = reg & 0xe0;

		for (ch=0;ch<9;ch++)
			for (o=0;o<2;o++)
				if (opoffs[ch][o] == off)
				{
					op_t	*op = &chans[ch].op[o];

					switch (base)
					{
					case 0x20: op->mult = val & 15; op->ksr = (val >> 4) & 1; op->egt = (val >> 5) & 1; break;
					case 0x40: op->tl = val & 63; op->ksl = val >> 6; break;
					case 0x60: op->ar = val >> 4; op->dr = val & 15; break;
					case 0x80: op->sl = val >> 4; op->rr = val & 15; break;
					case 0xe0: op->ws = wse ? val & 3 : 0; break;
					}
					OpRates (&chans[ch],op);
				}
		return;
	}
	ch = reg & 0x0f;
	if (ch > 8)
		return;
	switch (reg & 0xf0)
	{
	case 0xa0:
		chans[ch].fnum = (chans[ch].fnum & 0x300) | val;
		break;
	case 0xb0:
		{
			int	key = (val >> 5) & 1;

			chans[ch].fnum = (chans[ch].fnum & 0xff) | ((val & 3) << 8);
			chans[ch].block = (val >> 2) & 7;
			if (key && !chans[ch].key)
				for (i=0;i<2;i++)		// key on: from the start of the attack
				{
					chans[ch].op[i].state = 1;
					chans[ch].op[i].phase = 0;
				}
			if (!key && chans[ch].key)
				for (i=0;i<2;i++)
					if (chans[ch].op[i].state)
						chans[ch].op[i].state = 4;
			chans[ch].key = key;
		}
		break;
	case 0xc0:
		chans[ch].fb = (val >> 1) & 7;
		chans[ch].cnt = val & 1;
		return;
	default:
		return;
	}
	OpRates (&chans[ch],&chans[ch].op[0]);
	OpRates (&chans[ch],&chans[ch].op[1]);
}

//
// an operator's sample: the phase (with what modulates it, a cycle being
// 1 << 20) through its waveform, at its envelope's and total level's gain
//
static int OpOut (op_t *o, long pm)
{
	unsigned long	p;
	int				s, idx;
	double			att;

	switch (o->state)
	{
	case 0:
		return 0;
	case 1:
		o->env -= o->da ? o->da : 0;
		if (!o->ar)
			break;						// rate 0: never
		if (o->env <= 0)
		{
			o->env = 0;
			o->state = 2;
		}
		break;
	case 2:
		o->env += o->dd;
		if (o->env >= o->sl*3.0)
		{
			o->env = o->sl*3.0;
			o->state = o->egt ? 3 : 4;	// held while keyed, or let go
		}
		break;
	case 4:
		o->env += o->dr2;
		if (o->env >= 96)
		{
			o->env = 96;
			o->state = 0;
			return 0;
		}
		break;
	}
	o->phase += o->inc;
	p = (o->phase + (unsigned long)pm) >> 10;	// 1024 a cycle
	idx = p & 1023;
	switch (o->ws)
	{
	case 0: s = sintab[idx]; break;
	case 1: s = idx < 512 ? sintab[idx] : 0; break;
	case 2: s = sintab[idx & 511]; break;
	default: s = (idx & 256) ? 0 : sintab[idx & 255]; break;
	}
	att = o->env + o->tl * 0.75;
	if (att >= 96)
		return 0;
	return (int)((long)s * dbtab[(int)(att * 1024 / 96)] >> 12);
}

static int OplSample (void)
{
	int		ch, sum = 0;

	for (ch=0;ch<9;ch++)
	{
		chan_t	*c = &chans[ch];
		long	fbm = 0;
		int		m, k;

		if (!c->op[0].state && !c->op[1].state)
			continue;
		if (c->fb)						// the modulator's own last two, back in:
			fbm = ((long)(c->op[0].out1 + c->op[0].out2) << (c->fb + 2)) >> 1;
										// full scale moves it pi/16 (1) .. 4 pi (7)
		m = OpOut (&c->op[0],fbm);
		c->op[0].out2 = c->op[0].out1;
		c->op[0].out1 = m;
		if (c->cnt)						// added
			k = m + OpOut (&c->op[1],0);
		else							// FM: full scale moves the carrier two cycles
			k = OpOut (&c->op[1],(long)m << 9);
		sum += k;
	}
	return sum;
}

/*
=============================================================================

						THE MIXER

=============================================================================
*/

static CRITICAL_SECTION	sndlock;
static HWAVEOUT		wo;
static WAVEHDR		hdr[NBUF];
static short		bufs[NBUF][FRAMES*2];

// the digitized sound: one at a time, as the Sound Blaster plays them
static unsigned char	*digi;
static long		digilen, digipos;			// in 1/65536 samples
static unsigned long	digistep;
static int		digil, digir;				// 0-256 a side

// the AdLib effect: channel 0, a byte at 140 Hz
static unsigned char	*fx;
static long		fxlen, fxpos;
static int		fxblock;
static double	fxclock;

// the music: register, value and a delay at 700 Hz, round and round
static unsigned char	*music;
static long		musiclen, musicpos;
static double	musicclock, musicdue;
static int		musicon;

void W32SndDigi (unsigned char *data, long len, int hz, int lvol, int rvol)
{
	EnterCriticalSection (&sndlock);
	digi = data;
	digilen = len;
	digipos = 0;
	digistep = (unsigned long)((double)hz / RATE * 65536);
	digil = lvol;
	digir = rvol;
	LeaveCriticalSection (&sndlock);
}

void W32SndDigiStop (void)
{
	EnterCriticalSection (&sndlock);
	digi = NULL;
	LeaveCriticalSection (&sndlock);
}

int W32SndDigiPlaying (void)
{
	return digi != NULL;
}

//
// an AdLib effect: id's SDL_ALPlaySound -- the instrument on channel 0's two
// operators (feedback and connection 0, as id's), then its bytes at 140 Hz
//
void W32SndFx (unsigned char *inst, int block, unsigned char *data, long len)
{
	EnterCriticalSection (&sndlock);
	OplWrite (0xb0,0);
	OplWrite (0x20,inst[0]);	OplWrite (0x23,inst[1]);
	OplWrite (0x40,inst[2]);	OplWrite (0x43,inst[3]);
	OplWrite (0x60,inst[4]);	OplWrite (0x63,inst[5]);
	OplWrite (0x80,inst[6]);	OplWrite (0x83,inst[7]);
	OplWrite (0xe0,inst[8]);	OplWrite (0xe3,inst[9]);
	OplWrite (0xc0,0);
	fx = data;
	fxlen = len;
	fxpos = 0;
	fxblock = ((block & 7) << 2) | 0x20;
	fxclock = 0;
	LeaveCriticalSection (&sndlock);
}

void W32SndFxStop (void)
{
	EnterCriticalSection (&sndlock);
	fx = NULL;
	OplWrite (0xb0,0);
	LeaveCriticalSection (&sndlock);
}

int W32SndFxPlaying (void)
{
	return fx != NULL;
}

void W32SndMusic (unsigned char *data, long len)
{
	int	ch;

	EnterCriticalSection (&sndlock);
	for (ch=1;ch<9;ch++)
		OplWrite (0xb0+ch,0);
	music = data;
	musiclen = len & ~3;
	musicpos = 0;
	musicclock = musicdue = 0;
	musicon = 1;
	LeaveCriticalSection (&sndlock);
}

void W32SndMusicOff (void)
{
	int	ch;

	EnterCriticalSection (&sndlock);
	musicon = 0;
	for (ch=1;ch<9;ch++)
		OplWrite (0xb0+ch,0);
	LeaveCriticalSection (&sndlock);
}

void W32SndMusicOn (void)
{
	EnterCriticalSection (&sndlock);
	if (music)
		musicon = 1;
	LeaveCriticalSection (&sndlock);
}

static void Fill (short *out)
{
	int	i;

	EnterCriticalSection (&sndlock);
	for (i=0;i<FRAMES;i++)
	{
		int	l = 0, r = 0, s;

		if (musicon && music)			// music: every event now due
		{
			while (musicclock >= musicdue)
			{
				unsigned char	*e = music + musicpos;

				OplWrite (e[0],e[1]);
				musicdue = musicclock + (e[2] | (e[3] << 8));
				musicpos += 4;
				if (musicpos >= musiclen)	// round again
				{
					musicpos = 0;
					musicclock = musicdue = 0;
					break;
				}
			}
			musicclock += 700.0 / RATE;
		}
		if (fx)							// the effect: a byte at 140 Hz
		{
			fxclock += 140.0 / RATE;
			while (fx && fxclock >= 1)
			{
				fxclock -= 1;
				if (fxpos >= fxlen)
				{
					fx = NULL;
					OplWrite (0xb0,0);
					break;
				}
				if (!fx[fxpos])
					OplWrite (0xb0,0);
				else
				{
					OplWrite (0xa0,fx[fxpos]);
					OplWrite (0xb0,fxblock);
				}
				fxpos++;
			}
		}
		s = OplSample () * 2;
		l += s;
		r += s;
		if (digi)						// the digitized: 8 bits, unsigned
		{
			long	k = digipos >> 16;

			if (k >= digilen)
				digi = NULL;
			else
			{
				int	v = ((int)digi[k] - 128) << 7;

				l += v * digil >> 8;
				r += v * digir >> 8;
				digipos += digistep;
			}
		}
		out[i*2] = (short)(l > 32767 ? 32767 : l < -32768 ? -32768 : l);
		out[i*2+1] = (short)(r > 32767 ? 32767 : r < -32768 ? -32768 : r);
	}
	LeaveCriticalSection (&sndlock);
}

static DWORD WINAPI Mixer (LPVOID arg)
{
	int	b;

	arg = arg;
	for (;;)
	{
		for (b=0;b<NBUF;b++)
			if (hdr[b].dwFlags & WHDR_DONE)
			{
				Fill (bufs[b]);
				hdr[b].dwFlags &= ~WHDR_DONE;
				waveOutWrite (wo,&hdr[b],sizeof(WAVEHDR));
			}
		Sleep (5);
	}
}

//
// W3DRAW=file (a test): the mix into a file -- raw 22,050 Hz 16-bit stereo --
// at the same pace, and nothing out of the speakers
//
static FILE	*rawfile;

static DWORD WINAPI Recorder (LPVOID arg)
{
	short	buf[FRAMES*2];
	DWORD	start = GetTickCount ();
	long	done = 0;

	arg = arg;
	for (;;)
	{
		while ((long)((GetTickCount () - start) * (double)RATE / 1000) >= done + FRAMES)
		{
			Fill (buf);
			fwrite (buf,4,FRAMES,rawfile);
			fflush (rawfile);
			done += FRAMES;
		}
		Sleep (5);
	}
}

//
// the sound's start: waveOut at 22,050 Hz, 16 bits, stereo; 0 if there is
// no sound device (the game plays on, silent)
//
int W32SndStart (void)
{
	WAVEFORMATEX	f;
	DWORD			id;
	int				b;

	OplTables ();
	for (b=0;b<9*2;b++)
		chans[b/2].op[b&1].env = 96;	// every operator silent
	InitializeCriticalSection (&sndlock);
	if (getenv ("W3DRAW"))
	{
		rawfile = fopen (getenv ("W3DRAW"),"wb");
		if (rawfile)
		{
			CreateThread (NULL,0,Recorder,NULL,0,&id);
			return 1;
		}
	}
	memset (&f,0,sizeof(f));
	f.wFormatTag = WAVE_FORMAT_PCM;
	f.nChannels = 2;
	f.nSamplesPerSec = RATE;
	f.wBitsPerSample = 16;
	f.nBlockAlign = 4;
	f.nAvgBytesPerSec = RATE*4;
	if (waveOutOpen (&wo,WAVE_MAPPER,&f,0,0,CALLBACK_NULL) != MMSYSERR_NOERROR)
		return 0;
	for (b=0;b<NBUF;b++)
	{
		memset (&hdr[b],0,sizeof(WAVEHDR));
		hdr[b].lpData = (LPSTR)bufs[b];
		hdr[b].dwBufferLength = FRAMES*4;
		waveOutPrepareHeader (wo,&hdr[b],sizeof(WAVEHDR));
		hdr[b].dwFlags |= WHDR_DONE;	// all free: the mixer fills them
	}
	CreateThread (NULL,0,Mixer,NULL,0,&id);
	return 1;
}
