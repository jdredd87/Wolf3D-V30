// WL_NET.C -- multiplayer: the network.  The packet driver, ARP, IPv4 and
// UDP, just enough to talk to one server.  Written by StevenC and Claude
// (Anthropic), 2026.  WL_NETA.ASM is the driver's receive callback; WL_MP.C
// speaks the protocol on top (MULTIPLAYER.md, "Protocol, version 1").
//
// Learned on the DOS Bridge (C:\dosbridgeDEV\docs\network.md), and kept here:
//   * answer ARP for our own address, always -- a peer that cannot ARP us
//     stalls (the bridge's transport stall, weeks of it, was exactly that);
//   * release both handles on EVERY way out (NetStop, from ShutdownId):
//     a receive callback left pointing into a program that has exited takes
//     the machine off the network;
//   * a peer that is not up yet does not answer ARP: keep asking.
//
// The addresses come from the same files the bridge and mTCP use -- the
// file named by %MTCPCFG%, then C:\AI\NET.CFG -- lines IPADDR, NETMASK,
// GATEWAY and PACKETINT.  Everything here is far data: DGROUP is full.

// The far variables here in ONE segment, not one each rounded up to 16
// bytes.  Only initialized ones join it (an uninitialized one would need
// -Fc-, and a second -Fc- module defines id's menuitems twice: BUILD86.BAT),
// so every one below is given its 0 -- 227 bytes back, for the 486
#pragma option -zEWL_NET_FAR
#include "WL_DEF.H"
#pragma hdrstop
#include <dos.h>
#include <io.h>
#include <fcntl.h>
#include <stdlib.h>

#define NSLOTS		8
#define SLOTSZ		1024		// the biggest packet, STEPS of 64 four-player steps,
								// is an 820-byte frame (mpproto.py's STEPS_MAX)

typedef struct
{
	volatile byte		head,tail;
	volatile unsigned	drops;
	volatile unsigned	len[NSLOTS];
	byte				ring[NSLOTS][SLOTSZ];
} netshare_t;

memptr		netmem;			// the ring: 8 KB, only when a network game starts
							// (WL_NETA.ASM knows the layout).  NEAR, in DGROUP: the
							// memory manager keeps a near pointer to its owner, and
							// a far one gave it only the offset -- the ring was 0:0,
							// and the first frame in overwrote the vector table
netshare_t	far * far ns = 0;
byte	far	nettx[1514] = {0};
byte	far	netmyip[4] = {0}, far netmask[4] = {0}, far netgw[4] = {0}, far netsrv[4] = {0};
byte	far	netmymac[6] = {0}, far nettomac[6] = {0};
int		far	netvec = 0;				// the driver's interrupt, 0 = none
int		far	nethip = 0, far nethar = 0;	// the IP and ARP handles
int		far	netopen = 0;			// both handles held
int		far	nethavemac = 0;			// nettomac is the server's, or the gateway's
unsigned far netport = 0;			// ours and the server's
unsigned far netident = 0;
long	far	netsentn = 0, far netrecvn = 0, far netframes = 0;

void	NetSetShare (void far *share);	// WL_NETA.ASM
#ifdef HANGDUMP
static void HangStart (void), HangStop (void);	// the hang watchdog, below
#endif
void	far NetRecv (void);

static byte far ethip[2] = {0x08,0x00}, far etharp[2] = {0x08,0x06};

/*
=============================================================================

						THE CONFIGURATION

=============================================================================
*/

static int ParseIP (char far *s, byte far *ip)
{
	int	n = 0, v = 0, digits = 0;

	for (;;s++)
	{
		if (*s >= '0' && *s <= '9')
		{
			v = v*10 + *s - '0';
			if (++digits > 3 || v > 255)
				return 0;
		}
		else if (*s == '.' || *s == 0 || *s == ' ' || *s == '\t' || *s == '\r' || *s == '\n')
		{
			if (!digits || n > 3)
				return 0;
			ip[n++] = v;
			v = digits = 0;
			if (*s != '.')
				break;
		}
		else
			return 0;
	}
	return n == 4;
}

// does the line start with key (case blind) followed by a space?
static char far *Key (char far *line, char far *key)
{
	while (*key)
		if ((*line++ | 32) != (*key++ | 32))
			return NULL;
	if (*line != ' ' && *line != '\t')
		return NULL;
	while (*line == ' ' || *line == '\t')
		line++;
	return line;
}

static int ReadConfig (char far *path)
{
	static char far kip[] = "IPADDR", far kmask[] = "NETMASK", far kgw[] = "GATEWAY",
		far kint[] = "PACKETINT";
	char	line[100];
	char	far *v;
	int		handle, n, got = 0;
	char	c;

	_fstrcpy ((char far *)line,path);
	handle = open (line,O_RDONLY | O_BINARY);
	if (handle == -1)
		return 0;
	for (;;)
	{
		n = 0;
		while (read (handle,&c,1) == 1 && c != '\n')
			if (n < sizeof(line)-1)
				line[n++] = c;
		if (!n && eof (handle))
			break;
		line[n] = 0;
		if ((v = Key (line,kip)) != NULL && ParseIP (v,netmyip))
			got = 1;
		else if ((v = Key (line,kmask)) != NULL)
			ParseIP (v,netmask);
		else if ((v = Key (line,kgw)) != NULL)
			ParseIP (v,netgw);
		else if ((v = Key (line,kint)) != NULL)
		{
			if (v[0] == '0' && (v[1]|32) == 'x')
				v += 2;
			for (netvec = 0;;v++)
				if (*v >= '0' && *v <= '9')
					netvec = netvec*16 + *v - '0';
				else if ((*v|32) >= 'a' && (*v|32) <= 'f')
					netvec = netvec*16 + (*v|32) - 'a' + 10;
				else
					break;
		}
	}
	close (handle);
	return got;
}

/*
=============================================================================

						THE PACKET DRIVER

=============================================================================
*/

static int Driver (int vec)
{
	static char far sig[] = "PKT DRVR";
	char	far *p = (char far *)getvect (vec);

	return p && !_fmemcmp (p+3,sig,8);
}

static int Access (byte far *type, int far *handle)
{
	union REGS	r;
	struct SREGS	s;

	r.h.ah = 2;					// access_type
	r.h.al = 1;					// class: Ethernet
	r.x.bx = 0xffff;			// any type of interface
	r.h.dl = 0;
	r.x.cx = 2;
	s.ds = FP_SEG(type);
	r.x.si = FP_OFF(type);
	s.es = FP_SEG(NetRecv);
	r.x.di = FP_OFF(NetRecv);
	int86x (netvec,&r,&r,&s);
	if (r.x.cflag)
		return 0;
	*handle = r.x.ax;
	return 1;
}

static void Release (int handle)
{
	union REGS	r;

	r.h.ah = 3;
	r.x.bx = handle;
	int86 (netvec,&r,&r);
}

static void SendFrame (unsigned len)
{
	union REGS	r;
	struct SREGS	s;

	if (len < 60)
	{
		_fmemset (nettx+len,0,60-len);
		len = 60;
	}
	r.h.ah = 4;					// send_pkt
	s.ds = FP_SEG(nettx);
	r.x.si = FP_OFF(nettx);
	r.x.cx = len;
	int86x (netvec,&r,&r,&s);
	netsentn++;
}

/*
=============================================================================

						STARTING AND STOPPING

=============================================================================
*/

//
// The configuration, the driver, both handles and our address.  0 and a
// reason in *why on failure; nothing is left held
//
int NetStart (byte far *server, unsigned port, char far * far *why)
{
	static char far noconf[] = "no IPADDR in %MTCPCFG% or C:\\AI\\NET.CFG";
	static char far nodrv[] = "no packet driver";
	static char far noacc[] = "the packet driver refused a handle";
	static char far ainet[] = "C:\\AI\\NET.CFG", far mtcp[] = "MTCPCFG";
	char	name[12];
	char	*env;
	union REGS	r;
	struct SREGS	s;

	if (netopen)
		return 1;
	_fmemset (netmask,255,4);
	_fmemset (netgw,0,4);
	_fstrcpy ((char far *)name,mtcp);
	env = getenv (name);
	if (!(env && ReadConfig ((char far *)env)) && !ReadConfig (ainet))
	{
		*why = noconf;
		return 0;
	}
	if (netvec && !Driver (netvec))
		netvec = 0;
	if (!netvec)
		for (netvec = 0x60;netvec <= 0x80;netvec++)
			if (Driver (netvec))
				break;
	if (netvec > 0x80)
	{
		netvec = 0;
		*why = nodrv;
		return 0;
	}
	_fmemcpy (netsrv,server,4);
	netport = port;
	if (!ns)
	{
		MM_GetPtr (&netmem,sizeof(netshare_t));
		MM_SetLock (&netmem,true);	// the driver writes into it: it must not move
		ns = (netshare_t far *)netmem;
	}
	_fmemset (ns,0,sizeof(netshare_t) - sizeof(ns->ring));
	NetSetShare (ns);
	if (!Access (ethip,&nethip))
	{
		*why = noacc;
		return 0;
	}
	if (!Access (etharp,&nethar))
	{
		Release (nethip);
		*why = noacc;
		return 0;
	}
	r.h.ah = 6;					// get_address
	r.x.bx = nethip;
	s.es = FP_SEG(netmymac);
	r.x.di = FP_OFF(netmymac);
	r.x.cx = 6;
	int86x (netvec,&r,&r,&s);
	nethavemac = 0;
	netopen = 1;
#ifdef HANGDUMP
	HangStart ();
#endif
	return 1;
}

void NetStop (void)
{
	if (!netopen)
		return;
#ifdef HANGDUMP
	HangStop ();
#endif
	netopen = 0;
	Release (nethip);
	Release (nethar);
}

/*
=============================================================================

						ARP, IPv4, UDP

=============================================================================
*/

static void PutW (byte far *p, unsigned v)
{
	p[0] = v >> 8;
	p[1] = v;
}

static unsigned GetW (byte far *p)
{
	return (p[0] << 8) | p[1];
}

// the address on our own wire to send to: the server, or the gateway
static byte far *NextHop (void)
{
	int	i;

	for (i=0;i<4;i++)
		if ((netsrv[i] & netmask[i]) != (netmyip[i] & netmask[i]))
			return netgw;
	return netsrv;
}

static void Arp (int op, byte far *tomac, byte far *toip)
{
	byte	far *p = nettx;

	if (op == 1)
		_fmemset (p,0xff,6);
	else
		_fmemcpy (p,tomac,6);
	_fmemcpy (p+6,netmymac,6);
	p[12] = 0x08;	p[13] = 0x06;
	PutW (p+14,1);				// Ethernet
	PutW (p+16,0x0800);			// IPv4
	p[18] = 6;	p[19] = 4;
	PutW (p+20,op);
	_fmemcpy (p+22,netmymac,6);
	_fmemcpy (p+28,netmyip,4);
	if (op == 1)
		_fmemset (p+32,0,6);
	else
		_fmemcpy (p+32,tomac,6);
	_fmemcpy (p+38,toip,4);
	SendFrame (42);
}

// ask who has the server's (or the gateway's) address
void NetAsk (void)
{
	Arp (1,NULL,NextHop ());
}

int NetReady (void)
{
	return nethavemac;
}

//
// A line saying how the network is doing, for the joining screen
//
static char *Dec (char *s, long v)
{
	char	t[12];
	int		n = 0;

	if (v < 0)
	{
		*s++ = '-';
		v = -v;
	}
	do
		t[n++] = '0' + v % 10;
	while (v /= 10);
	while (n)
		*s++ = t[--n];
	return s;
}

static char *Hex2 (char *s, int v)
{
	static char far h[] = "0123456789ABCDEF";

	*s++ = h[(v >> 4) & 15];
	*s++ = h[v & 15];
	return s;
}

static char *Str (char *s, char far *t)
{
	while (*t)
		*s++ = *t++;
	return s;
}

void NetStatus (char *s)
{
	static char far a[] = "sent ", far b[] = "  in ", far c[] = "  drop ", far d[] = "\nARP ",
		far yes[] = "yes", far no[] = "no", far e[] = "  MAC ";
	int		i;

	s = Str (s,a);
	s = Dec (s,netsentn);
	s = Str (s,b);
	s = Dec (s,netframes);
	s = Str (s,c);
	s = Dec (s,ns ? ns->drops : 0);
	s = Str (s,d);
	s = Str (s,nethavemac ? yes : no);
	s = Str (s,e);
	for (i=0;i<6;i++)
		s = Hex2 (s,netmymac[i]);
	*s = 0;
}

void NetSend (byte far *data, unsigned len)
{
	byte		far *p = nettx;
	unsigned	sum,i;
	unsigned long s;

	if (!netopen || len > 1472)
		return;
	if (!nethavemac)
	{
		NetAsk ();				// not yet: ask, and this one is lost --
		return;					// the protocol sends again
	}
	_fmemcpy (p,nettomac,6);
	_fmemcpy (p+6,netmymac,6);
	p[12] = 0x08;	p[13] = 0x00;
	p += 14;
	p[0] = 0x45;	p[1] = 0;
	PutW (p+2,20+8+len);
	PutW (p+4,netident++);
	PutW (p+6,0);
	p[8] = 64;	p[9] = 17;		// TTL, UDP
	PutW (p+10,0);
	_fmemcpy (p+12,netmyip,4);
	_fmemcpy (p+16,netsrv,4);
	for (s = 0,i = 0;i < 20;i += 2)
		s += GetW (p+i);
	while (s >> 16)
		s = (s & 0xffff) + (s >> 16);
	sum = ~(unsigned)s;
	PutW (p+10,sum);
	p += 20;
	PutW (p,netport);
	PutW (p+2,netport);
	PutW (p+4,8+len);
	PutW (p+6,0);				// no UDP checksum: optional in IPv4
	_fmemcpy (p+8,data,len);
	SendFrame (14+20+8+len);
}

#ifdef HANGDUMP
/*
=============================================================================

					THE HANG WATCHDOG (test builds only)

=============================================================================
*/
//
// mp/huntbot.py defines HANGDUMP; the real game has none of this.
//
// NetPump runs in every loop the game has while the network is up, so the
// BIOS tick (INT 1Ch, 18.2 a second: whichever of id's three timer services
// is in, it chains to the BIOS at that rate) counts how long it has not run.
// 20 s of that is a game stuck -- or a floor that took 20 s to load: the
// next NetPump says so.  Then, from the tick, on a stack of its own:
//   * 384 bytes of the stack as it was -- every frame from here down to the
//     stuck code; mp/hangtrace.py names them from the build's map;
//   * the step, the floor, the counters, and where the packet driver, DOS
//     and the disk BIOS live, to tell "stuck in them" from "stuck in us";
// to the server as a HANG packet (three times, 5 s apart) and once into
// HANG.LOG, if DOS was not in the middle of something.  And from NetPump:
// the server going quiet while the game runs, and coming back.
//
// The stack reported is not the tick's own: DOS (STACKS=) moves the BIOS
// tick onto a stack of its own before INT 1Ch, so Hang8 (WL_NETA.ASM), in
// front of id's timer service on INT 8, notes the game's SS:SP every tick.
//
// The tick's work runs with SS on its own stack and DS on DGROUP, so it
// never takes the address of a local: the packet driver and DOS are called
// from inline asm, not int86x (whose REGS are near pointers, DS-relative).
// StevenC & Claude (Anthropic), 2026-10-09.
//
#define HANGTICKS	(20*18)				// 20 s
#define HANGWORDS	192					// the stack words reported (one datagram)

extern	char	far	mpname[17];
extern	long	far	mpplayed;
extern	unsigned	hang8ss, hang8sp;	// WL_NETA.ASM: the game's stack at the tick
void	interrupt	Hang8 (void);		// WL_NETA.ASM: INT 8, in front of id's
void	HangNext8 (void interrupt (*isr)(void));

unsigned	hangdss = 0, hangdsp = 0;	// the stack reported: Hang8's, at this tick
unsigned	hangss = 0, hangsp = 0;		// NEAR: the tick's inline asm reads them
unsigned	hangstkseg = 0, hangstktop = 0;	// with DS = DGROUP
int			hangbusy = 0;
static	void interrupt	(*hangold)(void);
static	void interrupt	(*hangnext8)(void);	// id's service, behind Hang8
static	byte	far	hangstack[1024];
static	char	far	hangtxt[1440];		// the tick's report
static	char	far	hangmsg[200];		// NetPump's (the tick's may be mid-way)
static	char	far	hangwhat[48];
static	byte	far	hangtx[1514];
static	char	far	hanglog[] = "HANG.LOG";
static	byte	far	* far hangindos;	// DOS's InDOS flag; the critical error flag before it
static	unsigned far	hangtime;		// BIOS ticks since the network started
static	unsigned far	hangpumps, far hangseen;	// NetPump runs, and the count last tick
static	unsigned far	hangstill;		// ticks with no NetPump
static	unsigned far	hangback;		// a stall ended: how long it was
static	unsigned far	hangrecvat;		// when a datagram last came
static	long	far	hangrecv;
static	int		far	hangquiet;

static char far *HStr (char far *s, char far *t)
{
	while (*t)
		*s++ = *t++;
	return s;
}

static char far *HHex (char far *s, unsigned v)
{
	static char far h[] = "0123456789ABCDEF";
	int		i;

	for (i=12;i>=0;i-=4)
		*s++ = h[(v >> i) & 15];
	return s;
}

static char far *HDec (char far *s, unsigned long v)
{
	do
	{
		*s++ = '0' + (int)(v % 10);
		v /= 10;
	} while (v);
	return s;
}

//
// A number, the right way round: HDec writes it backwards, this turns it
//
static char far *HNum (char far *s, unsigned long v)
{
	char	far *e = HDec (s,v), far *a = s, far *b = e-1;
	char	c;

	while (a < b)
	{
		c = *a;
		*a++ = *b;
		*b-- = c;
	}
	return e;
}

static char far *HVec (char far *s, int vec)
{
	unsigned far *v = (unsigned far *)MK_FP (0,vec*4);

	s = HHex (s,v[1]);
	*s++ = ':';
	return HHex (s,v[0]);
}

//
// Into HANG.LOG, appended; DOS from inline asm (see above)
//
static void HangFile (char far *buf, unsigned len)
{
	unsigned	no = FP_OFF (hanglog), ng = FP_SEG (hanglog);
	unsigned	bo = FP_OFF (buf), bg = FP_SEG (buf);
	unsigned	h = 0;

asm	push	ds
asm	mov	ax,ng
asm	mov	ds,ax
asm	mov	dx,no
asm	mov	ax,3d01h
asm	int	21h
asm	jnc	hopened
asm	xor	cx,cx
asm	mov	ah,3ch
asm	int	21h
asm	jc	hfailed
hopened:
asm	mov	h,ax
asm	mov	bx,ax
asm	mov	ax,4202h
asm	xor	cx,cx
asm	xor	dx,dx
asm	int	21h
asm	mov	ax,bg
asm	mov	ds,ax
asm	mov	dx,bo
asm	mov	cx,len
asm	mov	bx,h
asm	mov	ah,40h
asm	int	21h
asm	mov	bx,h
asm	mov	ah,3eh
asm	int	21h
hfailed:
asm	pop	ds
}

//
// To the server: NetSend's frame, built in a buffer of its own (the main
// loop may have stopped half way through nettx), sent from inline asm
//
static void HangDriver (unsigned len)
{
	void		far *v = *(void far * far *)MK_FP (0,netvec*4);
	unsigned	o = FP_OFF (hangtx), g = FP_SEG (hangtx);

asm	push	si
asm	push	di
asm	push	ds
asm	push	bp
asm	mov	cx,len
asm	mov	si,o
asm	mov	ax,g
asm	mov	ds,ax
asm	mov	ah,4
asm	pushf
asm	call	dword ptr v
asm	pop	bp
asm	pop	ds
asm	pop	di
asm	pop	si
}

static void HangSend (char far *data, unsigned len)
{
	byte		far *p = hangtx;
	unsigned	i;
	unsigned long s;

	if (!netopen || !nethavemac || len > 1440)
		return;
	_fmemcpy (p,nettomac,6);
	_fmemcpy (p+6,netmymac,6);
	p[12] = 0x08;	p[13] = 0x00;
	p += 14;
	p[0] = 0x45;	p[1] = 0;
	PutW (p+2,20+8+4+len);
	PutW (p+4,netident++);
	PutW (p+6,0);
	p[8] = 64;	p[9] = 17;
	PutW (p+10,0);
	_fmemcpy (p+12,netmyip,4);
	_fmemcpy (p+16,netsrv,4);
	for (s = 0,i = 0;i < 20;i += 2)
		s += GetW (p+i);
	while (s >> 16)
		s = (s & 0xffff) + (s >> 16);
	PutW (p+10,~(unsigned)s);
	p += 20;
	PutW (p,netport);
	PutW (p+2,netport);
	PutW (p+4,8+4+len);
	PutW (p+6,0);
	p[8] = 'W';	p[9] = 'M';	p[10] = 1;	p[11] = 12;	// mpproto.HANG
	_fmemcpy (p+12,data,len);
	len += 14+20+8+4;
	if (len < 60)
	{
		_fmemset (hangtx+len,0,60-len);
		len = 60;
	}
	HangDriver (len);
	netsentn++;
}

//
// The first line of every report: who, when, and the counters
//
static char far *HangHead (char far *s, char far *what)
{
	static char far a[] = ": ", far b[] = "  step ", far c[] = "  floor ",
		far d[] = "  sent ", far e[] = "  in ", far f[] = "  frames ",
		far g[] = "  ring ", far h[] = "  drops ", far i[] = "  t ";

	s = HStr (s,mpname);
	s = HStr (s,a);
	s = HStr (s,what);
	s = HStr (s,b);
	s = HNum (s,mpplayed);
	s = HStr (s,c);
	s = HNum (s,gamestate.mapon+1);
	s = HStr (s,d);
	s = HNum (s,netsentn);
	s = HStr (s,e);
	s = HNum (s,netrecvn);
	s = HStr (s,f);
	s = HNum (s,netframes);
	s = HStr (s,g);
	s = HNum (s,ns->head);
	*s++ = '/';
	s = HNum (s,ns->tail);
	s = HStr (s,h);
	s = HNum (s,ns->drops);
	s = HStr (s,i);
	s = HNum (s,hangtime);
	*s++ = '\r';
	*s++ = '\n';
	return s;
}

//
// From the tick, on hangstack: the report
//
static void far HangWork (void)
{
	static char far stuck[] = "STUCK, no NetPump for ", far secs[] = " s",
		far l2[] = "netsend ", far l3[] = "  ss:sp ", far l4[] = "  pktdrv ",
		far l5[] = "  int21 ", far l6[] = "  int13 ", far l7[] = "  indos ",
		far l8[] = "stack:\r\n";
	char	far *s;
	unsigned far *st = (unsigned far *)MK_FP (hangdss,hangdsp);
	void	(*ns_) (byte far *, unsigned) = NetSend;
	int		i, dosfree = hangindos[0] == 0 && hangindos[-1] == 0;

asm	mov	al,20h			// the BIOS has not acked IRQ 0 yet, and a
asm	out	20h,al			// packet driver may want its own interrupt
asm	sti
	s = HStr (HNum (HStr (hangwhat,stuck),hangstill/18),secs);
	*s = 0;
	s = HangHead (hangtxt,hangwhat);
	s = HStr (s,l2);
	s = HHex (s,FP_SEG ((void far *)ns_));
	*s++ = ':';
	s = HHex (s,FP_OFF ((void far *)ns_));
	s = HStr (s,l3);
	s = HHex (s,hangdss);
	*s++ = ':';
	s = HHex (s,hangdsp);
	s = HStr (s,l4);
	s = HVec (s,netvec);
	s = HStr (s,l5);
	s = HVec (s,0x21);
	s = HStr (s,l6);
	s = HVec (s,0x13);
	s = HStr (s,l7);
	s = HHex (s,hangindos[-1]*256+hangindos[0]);
	*s++ = '\r';
	*s++ = '\n';
	s = HStr (s,l8);
	for (i=0;i<HANGWORDS;i++)
	{
		s = HHex (s,st[i]);
		*s++ = (i & 15) == 15 ? '\r' : ' ';
		if ((i & 15) == 15)
			*s++ = '\n';
	}
	HangSend (hangtxt,s-hangtxt);
	if (hangstill == HANGTICKS && dosfree)
		HangFile (hangtxt,s-hangtxt);
asm	cli
}

//
// INT 1Ch
//
static void interrupt HangTick (void)
{
	hangold ();
	hangtime++;
	if (hangpumps != hangseen)
	{
		if (hangstill >= HANGTICKS)
			hangback = hangstill;
		hangseen = hangpumps;
		hangstill = 0;
		return;
	}
	if (hangstill < 0xffff)
		hangstill++;
	if (hangbusy || (hangstill != HANGTICKS && hangstill != HANGTICKS+5*18
	&& hangstill != HANGTICKS+10*18))
		return;
	hangbusy = 1;
	hangdss = hang8ss;			// IRQ 0 is not acked yet: no tick can change them
	hangdsp = hang8sp;
asm	mov	hangss,ss
asm	mov	hangsp,sp
asm	mov	ax,hangstkseg
asm	cli
asm	mov	ss,ax
asm	mov	sp,hangstktop
	HangWork ();
asm	cli
asm	mov	ss,hangss
asm	mov	sp,hangsp
	hangbusy = 0;
}

//
// From NetPump, in the main loop: alive; a stall that ended; the server
// gone quiet, and back
//
static void HangPump (void)
{
	static char far back[] = "BACK after a stall of ", far quiet[] = "NET QUIET for 20 s",
		far loud[] = "NET BACK after ", far secs[] = " s";
	char	far *s;
	unsigned	t;

	hangpumps++;
	t = hangback;
	if (t)
	{
		hangback = 0;
		s = HStr (HNum (HStr (hangwhat,back),t/18),secs);
		*s = 0;
		s = HangHead (hangmsg,hangwhat);
		HangSend (hangmsg,s-hangmsg);
		HangFile (hangmsg,s-hangmsg);
		hangrecvat = hangtime;		// nothing came in a stall: that was not the network
	}
	if (netrecvn != hangrecv)
	{
		if (hangquiet)
		{
			s = HStr (HNum (HStr (hangwhat,loud),(unsigned)(hangtime-hangrecvat)/18),secs);
			*s = 0;
			s = HangHead (hangmsg,hangwhat);
			HangFile (hangmsg,s-hangmsg);
			hangquiet = 0;
		}
		hangrecv = netrecvn;
		hangrecvat = hangtime;
	}
	else if (netrecvn && !hangquiet && (unsigned)(hangtime-hangrecvat) >= HANGTICKS)
	{
		hangquiet = 1;
		s = HangHead (hangmsg,quiet);
		HangFile (hangmsg,s-hangmsg);
	}
}

static void HangStart (void)
{
	static char far armed[] = "watchdog armed";
	union REGS	r;
	struct SREGS	s;
	char	far *e;

	r.h.ah = 0x34;
	intdosx (&r,&r,&s);
	hangindos = (byte far *)MK_FP (s.es,r.x.bx);
	hangstkseg = FP_SEG (hangstack);
	hangstktop = FP_OFF (hangstack) + sizeof(hangstack);
	hangstill = hangback = hangquiet = 0;
	hangrecv = netrecvn;
	hangrecvat = hangtime;
	e = HangHead (hangmsg,armed);
	HangFile (hangmsg,e-hangmsg);
	hangold = getvect (0x1c);
	setvect (0x1c,HangTick);
	hangnext8 = getvect (8);
	HangNext8 (hangnext8);
	setvect (8,Hang8);
}

//
// id's SDL_SetTimerSpeed, in a test build, sets its timer service through
// here (huntbot.py): behind Hang8 when Hang8 is in
//
void HangSet8 (void interrupt (*isr)(void))
{
	if (getvect (8) == Hang8)
	{
		hangnext8 = isr;
		HangNext8 (isr);
	}
	else
		setvect (8,isr);
}

static void HangStop (void)
{
	if (getvect (8) == Hang8)
		setvect (8,hangnext8);
	if (hangold)
	{
		setvect (0x1c,hangold);
		hangold = 0;
	}
}
#endif

//
// Every frame that has come in: ARP answered and learnt, and each UDP
// datagram from the server to our port handed to take()
//
void NetPump (void (*take) (byte far *data, unsigned len))
{
	byte		far *f;
	unsigned	len;
	int			ihl;

#ifdef HANGDUMP
	HangPump ();
#endif
	while (ns->tail != ns->head)
	{
		netframes++;
		f = ns->ring[ns->tail & (NSLOTS-1)];
		len = ns->len[ns->tail & (NSLOTS-1)];
		if (len >= 42 && f[12] == 0x08 && f[13] == 0x06)
		{
			unsigned op = GetW (f+20);

			if (op == 1 && !_fmemcmp (f+38,netmyip,4))
				Arp (2,f+22,f+28);			// who has us?  We do
			else if (op == 2 && !_fmemcmp (f+28,NextHop (),4))
			{
				_fmemcpy (nettomac,f+22,6);	// the server's, or the gateway's
				nethavemac = 1;
			}
			if (!nethavemac && !_fmemcmp (f+28,NextHop (),4))
			{
				_fmemcpy (nettomac,f+22,6);	// it asked us: now we know it too
				nethavemac = 1;
			}
		}
		else if (len >= 42 && f[12] == 0x08 && f[13] == 0x00)
		{
			f += 14;
			ihl = (f[0] & 15) * 4;
			if ((f[0] >> 4) == 4 && f[9] == 17 && !(GetW (f+6) & 0x3fff)
			&& !_fmemcmp (f+12,netsrv,4) && !_fmemcmp (f+16,netmyip,4)
			&& GetW (f+ihl+2) == netport)
			{
				unsigned ulen = GetW (f+ihl+4);

				if (ulen >= 8 && ihl+ulen <= len-14)
				{
					netrecvn++;
					take (f+ihl+8,ulen-8);
				}
			}
		}
		ns->tail++;
	}
}
