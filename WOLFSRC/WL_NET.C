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
	return 1;
}

void NetStop (void)
{
	if (!netopen)
		return;
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

//
// Every frame that has come in: ARP answered and learnt, and each UDP
// datagram from the server to our port handed to take()
//
void NetPump (void (*take) (byte far *data, unsigned len))
{
	byte		far *f;
	unsigned	len;
	int			ihl;

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
