{ SRVNET -- the network for a SERVER on DOS: one packet driver, many peers.
  Written by StevenC and Claude (Anthropic), 2026-10-15.

  The DOS Bridge's Net unit (C:\dosbridgeDEV\starter\net.pas) talks to ONE
  peer: NetOpen resolves its MAC and every send goes there.  A Wolf3D server
  answers up to four machines, so this unit keeps that unit's proven parts
  -- the interrupt-time receiver byte for byte (its patched offsets are why
  it is copied and not rewritten), the packet driver calls, answering ARP
  for our own address (the bridge's "transport stall" was a peer that could
  not ARP us) -- and changes what a server needs changed:

    * SnOpen holds the ARP and the IPv4 handles and resolves nobody;
    * SnPoll takes any UDP datagram for our address without waiting, and
      says who sent it -- address, port AND the Ethernet source MAC, which
      is the MAC to answer it at (the gateway's, for one off the subnet);
    * SnSendTo sends to any address at a MAC the caller gives.

  Net is not used here, and not changed: UGET and UPUT are built from it,
  and they are how every box stays reachable. }

unit SrvNet;

{$MODE OBJFPC}{$H-}

interface

const
  SN_MAXPKT  = 1520;
  SN_SLOTS   = 16;               { the receive ring: a power of two (8 until 2026-10-16) }
  SN_SLOTSZ  = 2048;
  OFS_RHEAD  = 12 + SN_MAXPKT;
  OFS_RING   = OFS_RHEAD + 2;
  SN_HDRLEN  = 14 + 20 + 8;
  SN_MAXUDP  = SN_MAXPKT - SN_HDRLEN;

type
  TIP  = packed array[0..3] of Byte;
  TMac = packed array[0..5] of Byte;

var
  SnMyIP, SnMask, SnGw: TIP;
  SnMyMac    : TMac;
  SnVec      : Byte;             { the packet driver's vector }
  SnVecWant  : Byte;             { PACKETINT from the config; 0 = search 60h-80h }
  SnErr      : ShortString;
  SnCfgUsed  : ShortString;
  { who sent the datagram SnPoll returned }
  SnFromIP   : TIP;
  SnFromMac  : TMac;
  SnFromPort : Word;
  SnToPort   : Word;
  { counters, for the status line }
  SnRxFrames, SnRxWrong, SnTxFrames, SnTxFail, SnArpReplied: LongInt;
  SnTxRetried: LongInt;          { frames the driver refused at first (busy), then took }
  SnRxBadSum : LongInt;          { datagrams dropped for a wrong UDP checksum }
  SnLastDst  : Word;             { debug: the UDP port in the last frame built }
  { a pause after each frame (2026-10-15): a PicoMEM's WiFi garbles a frame
    sent hard on the heels of the last -- SnSpin's loops, set by the caller
    from SnSpin's calibration against its clock; 0 = none }
  SnGapLoops : Word;          { frames the driver refused at first (busy), then took }

function  SnReadConfig: Boolean;
function  SnOpen: Boolean;
procedure SnClose;
function  SnPoll(var Data; MaxLen: Word; var GotLen: Word): Boolean;
function  SnSendTo(const IP: TIP; const Mac: TMac; SrcPort, DstPort: Word;
                   var Data; Len: Word): Boolean;
function  SnDropped: Word;
procedure SnSpin(Loops: Word);
{ for the same calls as WinNet (mp/winnet.pas): here every port comes in
  through the one packet driver, and nothing waits }
procedure SnSetPorts(Game, Ctl: Word);
function  SnWait(Ms: Integer): Boolean;
function  IPStr(const A: TIP): ShortString;
function  ParseIP(S: ShortString; var A: TIP): Boolean;
function  SameIP(const A, B: TIP): Boolean;

implementation

uses Dos;

type
  TPkt = array[0 .. SN_MAXPKT - 1] of Byte;
  PPkt = ^TPkt;
  TSlot = packed record
    Len : Word;
    Buf : TPkt;
    Pad : array[0 .. SN_SLOTSZ - 2 - SN_MAXPKT - 1] of Byte;
  end;
  { the layout the receiver writes into: DO NOT reorder the fields ahead of
    the ring -- PktRecv reaches them by fixed offsets (net.pas's TShared) }
  TShared = packed record
    Busy     : Word;                                 { +0  }
    PktLen   : Word;                                 { +2  }
    PktCount : Word;                                 { +4  }
    Dropped  : Word;                                 { +6  }
    BytesLo  : Word;                                 { +8  }
    BytesHi  : Word;                                 { +10 }
    Buf      : TPkt;                                 { +12 }
    RHead    : Byte;                                 { OFS_RHEAD }
    RTail    : Byte;
    Ring     : array[0 .. SN_SLOTS - 1] of TSlot;    { OFS_RING }
  end;

const
  ETH_IP  = $0800;
  ETH_ARP = $0806;
  IPPROTO_UDP = 17;

var
  Shared  : TShared;
  Filt    : packed array[0..1] of Byte;   { the IP handle's ethertype }
  FiltA   : packed array[0..1] of Byte;   { the ARP handle's }
  Handler : packed record O, S: Word; end;
  TxBuf   : TPkt;
  { The frames go out from a ring, not from TxBuf (2026-10-15).  It was put
    in on the theory that the PicoMEM's driver returns from send_pkt before
    the card has read the frame, so the next frame built in the same buffer
    went out in its place -- slot 2's packets were reaching slot 3.  It did
    NOT cure that; a pause after each frame did (SnGapLoops), so the card's
    WiFi is what garbles frames sent back to back.  The ring stays, being
    harmless and cheap, at two. }
  TxRing  : array[0..1] of TPkt;   { 8 until 2026-10-16: two, for a 16-slot receive ring's room and MPSRV /? }
  TxCur   : Byte;
  Handle, IpHnd, ArpHnd: Word;
  HaveIp, HaveArp, HaveDrv: Boolean;
  CarryB, ErrDH: Byte;
  IPIdent : Word;

{ The interrupt-time receiver: net.pas's, byte for byte.  +7 is patched with
  our data segment, +12 with Ofs(Shared). }
procedure PktRecv; assembler; nostackframe;
asm
  db  01Eh              { push ds                       +0 }
  db  053h              { push bx                       +1 }
  db  051h              { push cx                       +2 }
  db  056h              { push si                       +3 }
  db  08Bh, 0F0h        { mov si, ax                 +4,+5 }
  db  0B8h              { mov ax, imm16                 +6 }
  dw  0                 {   patched: data segment       +7 }
  db  08Eh, 0D8h        { mov ds, ax                 +9,+10 }
  db  0BBh              { mov bx, imm16                +11 }
  dw  0                 {   patched: Ofs(Shared)       +12 }

  cmp  si, 0
  jne  @@second

  cmp  cx, SN_MAXPKT
  ja   @@refuse
  mov  al, [bx + OFS_RHEAD]
  sub  al, [bx + OFS_RHEAD + 1]
  cmp  al, SN_SLOTS
  jae  @@refuse
  mov  al, [bx + OFS_RHEAD]
  and  al, SN_SLOTS - 1
  mov  ah, al
  xor  al, al
  shl  ah, 1
  shl  ah, 1
  shl  ah, 1                     { AX = slot * 2048 }
  mov  di, bx
  add  di, OFS_RING + 2
  add  di, ax
  mov  ax, ds
  mov  es, ax
  jmp  @@out

@@refuse:
  inc  word ptr [bx + 6]
  xor  ax, ax
  mov  es, ax
  xor  di, di
  jmp  @@out

@@second:
  mov  al, [bx + OFS_RHEAD]
  and  al, SN_SLOTS - 1
  mov  ah, al
  xor  al, al
  shl  ah, 1
  shl  ah, 1
  shl  ah, 1
  mov  si, bx
  add  si, OFS_RING
  add  si, ax
  mov  [si], cx
  inc  byte ptr [bx + OFS_RHEAD]
  inc  word ptr [bx + 4]
  add  word ptr [bx + 8], cx
  adc  word ptr [bx + 10], 0

@@out:
  pop  si
  pop  cx
  pop  bx
  pop  ds
  retf
end;

procedure Pump;
var
  S: Byte;
  L: Word;
begin
  if (Shared.Busy = 0) and (Shared.RHead <> Shared.RTail) then
  begin
    S := Shared.RTail and (SN_SLOTS - 1);
    L := Shared.Ring[S].Len;
    Move(Shared.Ring[S].Buf, Shared.Buf, L);
    Shared.PktLen := L;
    Shared.Busy := 1;
    Inc(Shared.RTail);
  end;
end;

procedure SnSpin(Loops: Word); assembler;
asm
  mov  cx, Loops
  jcxz @@done
@@l:
  nop
  loop @@l
@@done:
end;

procedure SnSetPorts(Game, Ctl: Word);
begin
end;

function SnWait(Ms: Integer): Boolean;
begin
  SnWait := False;
end;

function SnDropped: Word;
begin
  SnDropped := Shared.Dropped;
end;

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

procedure PutW(var P: TPkt; Ofs, V: Word);
begin
  P[Ofs] := Hi(V);
  P[Ofs + 1] := Lo(V);
end;

function GetW(var P: TPkt; Ofs: Word): Word;
begin
  GetW := (Word(P[Ofs]) shl 8) or P[Ofs + 1];
end;

procedure AddW(var S: Word; W: Word);
begin
  S := S + W;
  if S < W then Inc(S);
end;

{$I sumbuf.inc}      { the bridge's fast one's-complement sum (starter/) }

{ ---- configuration: %MTCPCFG%, then C:\AI\NET.CFG, as the game reads them }

function HexOrDec(const S: ShortString): Integer;
var
  V, C, I: Integer;
begin
  HexOrDec := 0;
  if (Length(S) > 2) and (S[1] = '0') and (UpCase(S[2]) = 'X') then
  begin
    V := 0;
    for I := 3 to Length(S) do
      case UpCase(S[I]) of
        '0'..'9': V := V * 16 + Ord(S[I]) - Ord('0');
        'A'..'F': V := V * 16 + Ord(UpCase(S[I])) - Ord('A') + 10;
      else Exit;
      end;
    HexOrDec := V;
  end
  else
  begin
    Val(S, V, C);
    if C = 0 then HexOrDec := V;
  end;
end;

function ReadCfgFile(const Cfg: ShortString; var GotIP: Boolean): Boolean;
var
  F: Text;
  Line, Key, Rest: ShortString;
  I: Integer;
begin
  ReadCfgFile := False;
  if Cfg = '' then Exit;
  {$I-}
  Assign(F, Cfg);
  Reset(F);
  {$I+}
  if IOResult <> 0 then Exit;
  while not Eof(F) do
  begin
    {$I-}
    ReadLn(F, Line);
    {$I+}
    if IOResult <> 0 then Break;
    I := 1;
    while (I <= Length(Line)) and (Line[I] in [' ', #9]) do Inc(I);
    Key := '';
    while (I <= Length(Line)) and not (Line[I] in [' ', #9]) do
    begin
      Key := Key + UpCase(Line[I]);
      Inc(I);
    end;
    while (I <= Length(Line)) and (Line[I] in [' ', #9]) do Inc(I);
    Rest := '';
    while (I <= Length(Line)) and not (Line[I] in [' ', #9]) do
    begin
      Rest := Rest + Line[I];
      Inc(I);
    end;
    if Key = 'IPADDR' then GotIP := ParseIP(Rest, SnMyIP)
    else if Key = 'NETMASK' then ParseIP(Rest, SnMask)
    else if Key = 'GATEWAY' then ParseIP(Rest, SnGw)
    else if Key = 'PACKETINT' then SnVecWant := Byte(HexOrDec(Rest));
  end;
  Close(F);
  SnCfgUsed := Cfg;
  while (Length(SnCfgUsed) > 0) and (SnCfgUsed[Length(SnCfgUsed)] = ' ') do
    Delete(SnCfgUsed, Length(SnCfgUsed), 1);
  ReadCfgFile := True;
end;

function SnReadConfig: Boolean;
var
  GotIP: Boolean;
begin
  SnReadConfig := False;
  GotIP := False;
  SnCfgUsed := '';
  SnMask[0] := 255; SnMask[1] := 255; SnMask[2] := 255; SnMask[3] := 0;
  FillChar(SnGw, SizeOf(SnGw), 0);
  if not (ReadCfgFile(GetEnv('MTCPCFG'), GotIP) and GotIP) then
    if not ReadCfgFile('C:\AI\NET.CFG', GotIP) then
    begin
      SnErr := 'no network config: %MTCPCFG% or C:\AI\NET.CFG';
      Exit;
    end;
  if not GotIP then
  begin
    SnErr := 'no IPADDR in ' + SnCfgUsed;
    Exit;
  end;
  SnReadConfig := True;
end;

{ ---- the packet driver }

function FindDriver: Boolean;
const
  Sig = 'PKT DRVR';
var
  V, I: Integer;
  Sg, Of_: Word;
  Ok: Boolean;
begin
  FindDriver := False;
  for V := $60 to $80 do
  begin
    if (SnVecWant <> 0) and (V <> SnVecWant) then Continue;
    Of_ := MemW[0 : Word(V) * 4];
    Sg  := MemW[0 : Word(V) * 4 + 2];
    if Sg = 0 then Continue;
    Ok := True;
    for I := 1 to 8 do
      if Chr(Mem[Sg : Word(Of_ + 2 + I)]) <> Sig[I] then
      begin
        Ok := False; Break;
      end;
    if Ok then
    begin
      SnVec := Byte(V);
      Handler.O := Of_; Handler.S := Sg;
      FindDriver := True;
      Exit;
    end;
  end;
  SnErr := 'no packet driver on vectors 60h-80h';
end;

function Acquire(EtherType: Word; FOfs: Word): Boolean;
var
  RSeg, ROfs: Word;
begin
  MemW[Seg(Filt) : FOfs] := Swap(EtherType);
  RSeg := Seg(PktRecv);
  ROfs := Ofs(PktRecv);
  asm
    push ds
    push es
    push si
    push di
    mov  ax, RSeg
    mov  es, ax
    mov  di, ROfs
    mov  si, FOfs
    mov  cx, 2
    mov  bx, 0FFFFh
    mov  dl, 0
    mov  ah, 2
    mov  al, 1
    pushf
    call far [Handler]
    mov  cx, ax
    mov  ax, dx
    pop  di
    pop  si
    pop  es
    pop  ds
    jnc  @@ok
    mov  CarryB, 1
    jmp  @@fin
  @@ok:
    mov  CarryB, 0
  @@fin:
    mov  Handle, cx
    mov  ErrDH, ah
  end;
  Acquire := (CarryB = 0);
  if CarryB <> 0 then
    SnErr := 'the packet driver refused ethertype ' + Num(EtherType) + ', error ' + Num(ErrDH);
end;

procedure ReleaseOne(H: Word);
begin
  asm
    push ds
    mov  bx, H
    mov  ah, 3
    pushf
    call far [Handler]
    pop  ds
  end;
end;

procedure GetMyMac;
var
  MSeg, MOfs: Word;
begin
  MSeg := Seg(SnMyMac); MOfs := Ofs(SnMyMac);
  asm
    push ds
    push es
    push di
    mov  ax, MSeg
    mov  es, ax
    mov  di, MOfs
    mov  cx, 6
    mov  bx, Handle
    mov  ah, 6
    pushf
    call far [Handler]
    pop  di
    pop  es
    pop  ds
  end;
end;

function SendOnce(Len: Word): Boolean;
var
  FOfs: Word;
begin
  FOfs := Ofs(TxRing[TxCur]);
  asm
    push ds
    push si
    mov  si, FOfs
    mov  cx, Len
    mov  ah, 4
    pushf
    call far [Handler]
    pop  si
    pop  ds
    jnc  @@ok
    mov  CarryB, 1
    jmp  @@fin
  @@ok:
    mov  CarryB, 0
  @@fin:
  end;
  SendOnce := CarryB = 0;
end;

{ A driver whose transmit buffer is still full refuses the frame and sends
  nothing (carry set) -- the bridge's Net counts these as NetTxFail.  A
  server sends to every player back to back, every step, so it waits for
  the card instead: up to ~2 ms, then counts it lost. }
procedure SendFrame(Len: Word);
var
  T0, Tries: Word;
begin
  TxCur := (TxCur + 1) and 1;
  Move(TxBuf, TxRing[TxCur], Len);
  Tries := 0;
  while not SendOnce(Len) do
  begin
    Inc(Tries);
    if Tries > 400 then
    begin
      Inc(SnTxFail);
      Exit;
    end;
    for T0 := 1 to 20 do ;          { a moment for the card }
  end;
  if Tries > 0 then Inc(SnTxRetried);
  Inc(SnTxFrames);
  for T0 := 1 to SnGapLoops do SnSpin(100);     { SnGapLoops blocks of 100 }
end;

function SnOpen: Boolean;
begin
  SnOpen := False;
  SnErr := '';
  if HaveIp then
  begin
    SnOpen := True;
    Exit;
  end;
  if not HaveDrv then
  begin
    if not FindDriver then Exit;
    HaveDrv := True;
  end;
  MemW[Seg(PktRecv) : Word(Ofs(PktRecv) + 7)]  := Seg(Shared);
  MemW[Seg(PktRecv) : Word(Ofs(PktRecv) + 12)] := Ofs(Shared);
  Shared.Busy := 0;
  Shared.RTail := Shared.RHead;
  { ARP first: it answers who-has for us all along (a peer that cannot ARP
    us stops being able to send to us -- the bridge's long-standing stall) }
  if Acquire(ETH_ARP, Ofs(FiltA)) then
  begin
    ArpHnd := Handle;
    HaveArp := True;
    GetMyMac;
  end;
  if not Acquire(ETH_IP, Ofs(Filt)) then
  begin
    if HaveArp then
    begin
      ReleaseOne(ArpHnd);
      HaveArp := False;
    end;
    Exit;
  end;
  IpHnd := Handle;
  HaveIp := True;
  if not HaveArp then GetMyMac;
  SnOpen := True;
end;

procedure SnClose;
begin
  if HaveIp then ReleaseOne(IpHnd);
  if HaveArp then ReleaseOne(ArpHnd);
  HaveIp := False;
  HaveArp := False;
end;

{ An ARP request for our own address: answer it.  True if it was one. }
function ArpService(L: Word): Boolean;
var I: Integer;
begin
  ArpService := False;
  if L < 42 then Exit;
  if (Shared.Buf[12] <> $08) or (Shared.Buf[13] <> $06) then Exit;
  if (Shared.Buf[20] <> $00) or (Shared.Buf[21] <> $01) then Exit;
  for I := 0 to 3 do
    if Shared.Buf[38 + I] <> SnMyIP[I] then Exit;
  for I := 0 to 59 do TxBuf[I] := 0;
  for I := 0 to 5 do TxBuf[I] := Shared.Buf[22 + I];
  for I := 0 to 5 do TxBuf[6 + I] := SnMyMac[I];
  PutW(TxBuf, 12, ETH_ARP);
  PutW(TxBuf, 14, 1);
  PutW(TxBuf, 16, ETH_IP);
  TxBuf[18] := 6;
  TxBuf[19] := 4;
  PutW(TxBuf, 20, 2);
  for I := 0 to 5 do TxBuf[22 + I] := SnMyMac[I];
  for I := 0 to 3 do TxBuf[28 + I] := SnMyIP[I];
  for I := 0 to 5 do TxBuf[32 + I] := Shared.Buf[22 + I];
  for I := 0 to 3 do TxBuf[38 + I] := Shared.Buf[28 + I];
  SendFrame(60);
  Inc(SnArpReplied);
  ArpService := True;
end;

{ The UDP checksum of the datagram in Shared.Buf, over its pseudo-header:
  the sum of it all, its own checksum included, is FFFFh when it is right }
function UdpSumOk(Ihl, UdpLen: Word): Boolean;
var S: Word;
begin
  S := 0;
  SumBuf(S, Shared.Buf, 14 + 12, 8);
  AddW(S, IPPROTO_UDP);
  AddW(S, UdpLen);
  SumBuf(S, Shared.Buf, 14 + Ihl, UdpLen);
  UdpSumOk := S = $FFFF;
end;

{ Every frame waiting, until a UDP datagram for our address: True with it,
  its sender (SnFromIP/Port/Mac) and the port it was sent to (SnToPort).
  Never waits. }
function SnPoll(var Data; MaxLen: Word; var GotLen: Word): Boolean;
var
  L, Ihl, UdpLen, PayOfs, PayLen, I: Word;
  Dst: PPkt;
  Ok: Boolean;
begin
  SnPoll := False;
  GotLen := 0;
  Dst := PPkt(@Data);
  if not HaveIp then Exit;
  repeat
    Pump;
    if Shared.Busy = 0 then Exit;
    Inc(SnRxFrames);
    L := Shared.PktLen;
    Ok := False;
    if ArpService(L) then
    begin
      Shared.Busy := 0;
      Continue;
    end;
    if (L >= SN_HDRLEN) and (Shared.Buf[12] = $08) and (Shared.Buf[13] = $00)
       and ((Shared.Buf[14] shr 4) = 4) then
    begin
      Ihl := (Shared.Buf[14] and $0F) * 4;
      if (Ihl >= 20) and (L >= 14 + Ihl + 8) and (Shared.Buf[14 + 9] = IPPROTO_UDP)
         and ((GetW(Shared.Buf, 14 + 6) and $3FFF) = 0) then
      begin
        Ok := True;
        for I := 0 to 3 do
          if Shared.Buf[14 + 16 + I] <> SnMyIP[I] then Ok := False;
        if not Ok then
        begin                 { a broadcast -- a game looking for servers (DISCOVER,
                                2026-10-17): 255.255.255.255, or this subnet's }
          Ok := True;
          for I := 0 to 3 do
            if Shared.Buf[14 + 16 + I] <> $FF then Ok := False;
          if not Ok then
          begin
            Ok := True;
            for I := 0 to 3 do
              if Shared.Buf[14 + 16 + I] <> (SnMyIP[I] or (SnMask[I] xor $FF)) then Ok := False;
          end;
        end;
        if Ok then
        begin
          UdpLen := GetW(Shared.Buf, 14 + Ihl + 4);
          if (UdpLen < 8) or (L < 14 + Ihl + UdpLen) then
            Ok := False
          else if (GetW(Shared.Buf, 14 + Ihl + 6) <> 0) and not UdpSumOk(Ihl, UdpLen) then
          begin
            { a garbled frame: a PicoMEM's WiFi has been seen to send them
              (2026-10-15) -- dropped, as a PC's stack would, rather than
              taken as a player's controls or checksum }
            Ok := False;
            Inc(SnRxBadSum);
          end
          else
          begin
            PayOfs := 14 + Ihl + 8;
            PayLen := UdpLen - 8;
            if PayLen > MaxLen then PayLen := MaxLen;
            if PayLen > 0 then Move(Shared.Buf[PayOfs], Dst^[0], PayLen);
            GotLen := PayLen;
            for I := 0 to 3 do SnFromIP[I] := Shared.Buf[14 + 12 + I];
            for I := 0 to 5 do SnFromMac[I] := Shared.Buf[6 + I];
            SnFromPort := GetW(Shared.Buf, 14 + Ihl);
            SnToPort := GetW(Shared.Buf, 14 + Ihl + 2);
          end;
        end;
      end;
    end;
    if not Ok then Inc(SnRxWrong);
    Shared.Busy := 0;
    if Ok then
    begin
      SnPoll := True;
      Exit;
    end;
  until False;
end;

function SnSendTo(const IP: TIP; const Mac: TMac; SrcPort, DstPort: Word;
                  var Data; Len: Word): Boolean;
var
  I, Total, UdpLen, Ck, S: Word;
  Src: PPkt;
begin
  SnSendTo := False;
  if not HaveIp then Exit;
  if Len > SN_MAXUDP then
  begin
    SnErr := 'datagram too big';
    Exit;
  end;
  Src := PPkt(@Data);
  UdpLen := 8 + Len;
  Total := 14 + 20 + UdpLen;
  FillChar(TxBuf, 60, 0);
  for I := 0 to 5 do TxBuf[I] := Mac[I];
  for I := 0 to 5 do TxBuf[6 + I] := SnMyMac[I];
  PutW(TxBuf, 12, ETH_IP);
  TxBuf[14] := $45;
  TxBuf[15] := 0;
  PutW(TxBuf, 16, 20 + UdpLen);
  Inc(IPIdent);
  PutW(TxBuf, 18, IPIdent);
  PutW(TxBuf, 20, 0);
  TxBuf[22] := 64;
  TxBuf[23] := IPPROTO_UDP;
  PutW(TxBuf, 24, 0);
  for I := 0 to 3 do TxBuf[26 + I] := SnMyIP[I];
  for I := 0 to 3 do TxBuf[30 + I] := IP[I];
  S := 0;
  SumBuf(S, TxBuf, 14, 20);
  PutW(TxBuf, 24, S xor $FFFF);
  PutW(TxBuf, 34, SrcPort);
  PutW(TxBuf, 36, DstPort);
  SnLastDst := GetW(TxBuf, 36);
  PutW(TxBuf, 38, UdpLen);
  PutW(TxBuf, 40, 0);
  if Len > 0 then Move(Src^[0], TxBuf[42], Len);
  S := 0;
  SumBuf(S, TxBuf, 26, 8);
  AddW(S, IPPROTO_UDP);
  AddW(S, UdpLen);
  SumBuf(S, TxBuf, 34, UdpLen);
  Ck := S xor $FFFF;
  if Ck = 0 then Ck := $FFFF;
  PutW(TxBuf, 40, Ck);
  if Total < 60 then Total := 60;
  SendFrame(Total);
  SnSendTo := CarryB = 0;
end;

begin
  HaveDrv := False; HaveIp := False; HaveArp := False;
  IPIdent := 0;
  SnVecWant := 0;
  SnErr := '';
  SnRxFrames := 0; SnRxWrong := 0; SnTxFrames := 0; SnTxFail := 0; SnArpReplied := 0;
  SnTxRetried := 0;
  SnRxBadSum := 0;
  TxCur := 0;
  SnGapLoops := 0;
end.
