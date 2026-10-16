{ WINNET -- the network for the Wolf3D server on Windows.  Written by StevenC
  and Claude (Anthropic), 2026-10-15.

  The same procedures as SrvNet (mp/srvnet.pas, the DOS one: a packet
  driver), over WinSock UDP sockets, so mp/mpsrv.pas is one source for both
  machines.  Two sockets: the game's on every address (UDP 31992 by default),
  and the console's on 127.0.0.1 only (31999), as mp/mpserver.py's is --
  nothing off this PC can reach it.  Windows checks UDP checksums itself and
  sends a frame at a time, so the DOS unit's checksum test and its pause
  after each frame have nothing to do here. }

unit WinNet;

{$MODE OBJFPC}{$H-}

interface

const
  SN_MAXUDP = 1472;

type
  TIP  = packed array[0..3] of Byte;
  TMac = packed array[0..5] of Byte;

var
  SnMyIP, SnMask, SnGw: TIP;
  SnMyMac    : TMac;
  SnVec      : Byte;
  SnErr      : ShortString;
  SnCfgUsed  : ShortString;
  SnFromIP   : TIP;
  SnFromMac  : TMac;             { unused here: Windows finds the MAC }
  SnFromPort : Word;
  SnToPort   : Word;             { which of our ports the datagram came to }
  SnRxFrames, SnRxWrong, SnTxFrames, SnTxFail, SnArpReplied: LongInt;
  SnTxRetried, SnRxBadSum: LongInt;
  SnLastDst  : Word;
  SnGapLoops : Word;

function  SnReadConfig: Boolean;
procedure SnSetPorts(Game, Ctl: Word);
function  SnOpen: Boolean;
procedure SnClose;
function  SnPoll(var Data; MaxLen: Word; var GotLen: Word): Boolean;
function  SnSendTo(const IP: TIP; const Mac: TMac; SrcPort, DstPort: Word;
                   var Data; Len: Word): Boolean;
function  SnWait(Ms: Integer): Boolean;
function  SnDropped: Word;
procedure SnSpin(Loops: Word);
function  IPStr(const A: TIP): ShortString;
function  ParseIP(S: ShortString; var A: TIP): Boolean;
function  SameIP(const A, B: TIP): Boolean;

implementation

uses WinSock2;

var
  Wsa: TWSAData;
  Started: Boolean;
  GameSock, CtlSock: TSocket;
  GamePortN, CtlPortN: Word;

function Num(L: LongInt): ShortString;
var S: ShortString;
begin
  Str(L, S);
  Num := S;
end;

function IPStr(const A: TIP): ShortString;
begin
  IPStr := Num(A[0]) + '.' + Num(A[1]) + '.' + Num(A[2]) + '.' + Num(A[3]);
end;

function SameIP(const A, B: TIP): Boolean;
begin
  SameIP := (A[0] = B[0]) and (A[1] = B[1]) and (A[2] = B[2]) and (A[3] = B[3]);
end;

function ParseIP(S: ShortString; var A: TIP): Boolean;
var
  I, N, V, Digits: Integer;
  Ch: Char;
begin
  ParseIP := False;
  N := 0; V := 0; Digits := 0;
  for I := 1 to Length(S) + 1 do
  begin
    if I <= Length(S) then Ch := S[I] else Ch := '.';
    if (Ch >= '0') and (Ch <= '9') then
    begin
      V := V * 10 + (Ord(Ch) - Ord('0'));
      Inc(Digits);
      if (V > 255) or (Digits > 3) then Exit;
    end
    else if Ch = '.' then
    begin
      if (Digits = 0) or (N > 3) then Exit;
      A[N] := Byte(V);
      Inc(N); V := 0; Digits := 0;
    end
    else
      Exit;
  end;
  ParseIP := (N = 4);
end;

procedure SnSetPorts(Game, Ctl: Word);
begin
  GamePortN := Game;
  CtlPortN := Ctl;
end;

function WsaUp: Boolean;
begin
  if not Started then
    Started := WSAStartup($0202, Wsa) = 0;
  WsaUp := Started;
end;

{ This PC's address on its network, for the log: the one Windows would send
  from to reach a LAN host -- a UDP socket "connected" sends nothing }
function SnReadConfig: Boolean;
var
  S: TSocket;
  A: TSockAddrIn;
  L: LongInt;
begin
  SnReadConfig := False;
  FillChar(SnMyIP, SizeOf(SnMyIP), 0);
  SnMask[0] := 255; SnMask[1] := 255; SnMask[2] := 255; SnMask[3] := 0;
  SnCfgUsed := 'Windows';
  if not WsaUp then
  begin
    SnErr := 'WinSock did not start';
    Exit;
  end;
  S := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if S <> INVALID_SOCKET then
  begin
    FillChar(A, SizeOf(A), 0);
    A.sin_family := AF_INET;
    A.sin_port := htons(9);
    A.sin_addr.S_addr := htonl($C0A80001);      { 192.168.0.1: any private address will do }
    if connect(S, @A, SizeOf(A)) = 0 then
    begin
      L := SizeOf(A);
      if getsockname(S, A, L) = 0 then
        Move(A.sin_addr, SnMyIP, 4);
    end;
    closesocket(S);
  end;
  SnReadConfig := True;
end;

function OpenOne(Port: Word; Loopback: Boolean; var S: TSocket): Boolean;
var
  A: TSockAddrIn;
  On_: u_long;
begin
  OpenOne := False;
  S := socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
  if S = INVALID_SOCKET then
  begin
    SnErr := 'no socket: ' + Num(WSAGetLastError);
    Exit;
  end;
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := htons(Port);
  if Loopback then A.sin_addr.S_addr := htonl($7F000001) else A.sin_addr.S_addr := INADDR_ANY;
  if bind(S, @A, SizeOf(A)) <> 0 then
  begin
    SnErr := 'UDP ' + Num(Port) + ' is in use (another server?): ' + Num(WSAGetLastError);
    closesocket(S);
    S := INVALID_SOCKET;
    Exit;
  end;
  On_ := 1;
  ioctlsocket(S, LongInt(FIONBIO), On_);
  OpenOne := True;
end;

function SnOpen: Boolean;
begin
  SnOpen := False;
  if not WsaUp then
  begin
    SnErr := 'WinSock did not start';
    Exit;
  end;
  if not OpenOne(GamePortN, False, GameSock) then Exit;
  CtlSock := INVALID_SOCKET;
  if CtlPortN <> 0 then
    if not OpenOne(CtlPortN, True, CtlSock) then
    begin
      SnErr := 'the console port: ' + SnErr;
      closesocket(GameSock);
      GameSock := INVALID_SOCKET;
      Exit;
    end;
  SnOpen := True;
end;

procedure SnClose;
begin
  if GameSock <> INVALID_SOCKET then closesocket(GameSock);
  if CtlSock <> INVALID_SOCKET then closesocket(CtlSock);
  GameSock := INVALID_SOCKET;
  CtlSock := INVALID_SOCKET;
end;

function RecvOne(S: TSocket; Port: Word; var Data; MaxLen: Word; var GotLen: Word): Boolean;
var
  A: TSockAddrIn;
  L, N: LongInt;
begin
  RecvOne := False;
  if S = INVALID_SOCKET then Exit;
  repeat
    L := SizeOf(A);
    N := recvfrom(S, Data, MaxLen, 0, A, L);
    { WSAECONNRESET: an ICMP port-unreachable from an earlier send -- not a
      datagram; try again }
  until (N >= 0) or (WSAGetLastError <> WSAECONNRESET);
  if N < 0 then Exit;
  Inc(SnRxFrames);
  GotLen := N;
  Move(A.sin_addr, SnFromIP, 4);
  SnFromPort := ntohs(A.sin_port);
  SnToPort := Port;
  RecvOne := True;
end;

function SnPoll(var Data; MaxLen: Word; var GotLen: Word): Boolean;
begin
  GotLen := 0;
  SnPoll := RecvOne(GameSock, GamePortN, Data, MaxLen, GotLen)
            or RecvOne(CtlSock, CtlPortN, Data, MaxLen, GotLen);
end;

{ Nothing to do: wait up to Ms for a datagram on either socket, rather than
  spin the CPU }
function SnWait(Ms: Integer): Boolean;
var
  R: TFDSet;
  T: TTimeVal;
begin
  FD_ZERO(R);
  FD_SET(GameSock, R);
  if CtlSock <> INVALID_SOCKET then FD_SET(CtlSock, R);
  T.tv_sec := 0;
  T.tv_usec := Ms * 1000;
  SnWait := select(0, @R, nil, nil, @T) > 0;
end;

function SnSendTo(const IP: TIP; const Mac: TMac; SrcPort, DstPort: Word;
                  var Data; Len: Word): Boolean;
var
  A: TSockAddrIn;
  S: TSocket;
begin
  if (SrcPort = CtlPortN) and (CtlSock <> INVALID_SOCKET) then S := CtlSock else S := GameSock;
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := htons(DstPort);
  Move(IP, A.sin_addr, 4);
  SnLastDst := DstPort;
  SnSendTo := sendto(S, @Data, Len, 0, @A, SizeOf(A)) = Len;
  if SnSendTo then Inc(SnTxFrames) else Inc(SnTxFail);
end;

function SnDropped: Word;
begin
  SnDropped := 0;
end;

procedure SnSpin(Loops: Word);
var I: Word;
begin
  for I := 1 to Loops do ;
end;

begin
  Started := False;
  GameSock := INVALID_SOCKET;
  CtlSock := INVALID_SOCKET;
  GamePortN := 31992;
  CtlPortN := 31999;
  SnVec := 0;
  SnErr := '';
  SnRxFrames := 0; SnRxWrong := 0; SnTxFrames := 0; SnTxFail := 0; SnArpReplied := 0;
  SnTxRetried := 0; SnRxBadSum := 0; SnLastDst := 0; SnGapLoops := 0;
  FillChar(SnFromMac, SizeOf(SnFromMac), 0);
end.
