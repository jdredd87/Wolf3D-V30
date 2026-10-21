/*
 * w32net.c -- the network on Win32: WL_NET.C's calls on Winsock 1.1 UDP,
 * which Windows has had since 95 (wsock32.dll).  The DOS game speaks to a
 * packet driver and does its own ARP, IPv4 and UDP; here Windows does all of
 * that, and these only send and take datagrams.
 *
 *   * the game's port, 31992, when it is free -- and any port when it is not
 *     (a server on this PC holds it): the server answers whatever port a
 *     datagram came from;
 *   * from the server only, unless netany (FIND): then anyone's, broadcast;
 *   * never blocking: NetPump takes what has come and returns.
 *
 * (Not with id's headers: windows.h and WL_DEF.H both define boolean.)
 *
 * StevenC & Claude (Anthropic), 2026-10-21.
 */
#include <winsock.h>
#include <stdio.h>
#include <string.h>

typedef unsigned char	byte;

int		netany, netearly;			// WL_NET.C's: FIND takes anyone's datagram
byte	netfrom[4];					// who sent the last one
byte	nettx[1514];				// WL_MP.C builds some packets in place here
long	netsentn, netrecvn;

static SOCKET	sock = INVALID_SOCKET;
static struct sockaddr_in	srv;
static int		started;
static long		dropped;

int NetStart (byte *server, unsigned port, char **why)
{
	static char	nows[] = "Windows has no network (Winsock 1.1)";
	static char	nosock[] = "no UDP socket";
	WSADATA		w;
	struct sockaddr_in	me;
	u_long		on = 1;
	int			yes = 1;

	if (sock != INVALID_SOCKET)
		return 1;
	if (!started)
	{
		if (WSAStartup (MAKEWORD (1,1),&w))
		{
			*why = nows;
			return 0;
		}
		started = 1;
	}
	sock = socket (AF_INET,SOCK_DGRAM,0);
	if (sock == INVALID_SOCKET)
	{
		*why = nosock;
		return 0;
	}
	memset (&me,0,sizeof(me));
	me.sin_family = AF_INET;
	me.sin_port = htons ((u_short)port);
	if (bind (sock,(struct sockaddr *)&me,sizeof(me)))
	{
		me.sin_port = 0;			// taken (a server here?): any port
		bind (sock,(struct sockaddr *)&me,sizeof(me));
	}
	ioctlsocket (sock,FIONBIO,&on);
	setsockopt (sock,SOL_SOCKET,SO_BROADCAST,(char *)&yes,sizeof(yes));
	memset (&srv,0,sizeof(srv));
	srv.sin_family = AF_INET;
	srv.sin_port = htons ((u_short)port);
	memcpy (&srv.sin_addr,server,4);
	return 1;
}

void NetStop (void)
{
	if (sock != INVALID_SOCKET)
		closesocket (sock);
	sock = INVALID_SOCKET;
}

void NetAsk (void) {}				// ARP: Windows' own
int NetReady (void) { return sock != INVALID_SOCKET; }

void NetSend (byte *data, unsigned len)
{
	struct sockaddr_in	to = srv;

	if (sock == INVALID_SOCKET)
		return;
	if (netany)
		to.sin_addr.s_addr = INADDR_BROADCAST;
	if (sendto (sock,(char *)data,len,0,(struct sockaddr *)&to,sizeof(to)) != SOCKET_ERROR)
		netsentn++;
}

void NetPump (void (*take) (byte *data, unsigned len))
{
	static byte	buf[2048];
	struct sockaddr_in	from;
	int			n, fl;

	if (sock == INVALID_SOCKET)
		return;
	for (;;)
	{
		fl = sizeof(from);
		n = recvfrom (sock,(char *)buf,sizeof(buf),0,(struct sockaddr *)&from,&fl);
		if (n == SOCKET_ERROR)
		{
			if (WSAGetLastError () == WSAEWOULDBLOCK)
				return;
			continue;				// (a port unreachable, from an ICMP: next)
		}
		if (!netany && (from.sin_addr.s_addr != srv.sin_addr.s_addr
		|| from.sin_port != srv.sin_port))
		{
			dropped++;
			continue;
		}
		memcpy (netfrom,&from.sin_addr,4);
		netrecvn++;
		take (buf,n);
	}
}

void NetStatus (char *s)
{
	sprintf (s,"sent %ld  in %ld  drop %ld\nWinsock UDP",netsentn,netrecvn,dropped);
}
