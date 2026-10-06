{ MPPING -- multiplayer phase 2: how fast, and how reliably, do two DOS
  machines' packets cross the network?  Written by StevenC and Claude
  (Anthropic), 2026.  MULTIPLAYER.md has the plan.

    MPPING ECHO peer [port] [secs]   send back every packet from peer
    MPPING PING peer [port] [n]      n packets of a step's size, each waiting
                                     for its echo; the round trips, the
                                     losses and the late ones

  Port 31992 by default (the multiplayer port).  A packet is 48 bytes -- a
  STEPS packet for four players with some steps of redundancy -- carrying a
  sequence number, so a late echo is told from a lost one.  Timing is by the
  BIOS tick (55 ms), so a round trip is the total over many: n packets in T
  ticks.  The network is the bridge's own unit (starter\net.pas), opened
  for one peer and closed on every way out: a receive callback left
  pointing into freed memory would take this machine off the network.

  A heartbeat on the screen (stderr), driven by the clock, says it is alive:
  the spinner turns while the program runs, whether packets come or not. }

program MPPing;

{$MODE OBJFPC}{$H-}

uses About, Net;

const
  PKTLEN = 48;
  SPIN: array[0..3] of Char = '|/-\';

var
  Peer: TIP;
  Port: Word;
  Buf: array[0..NET_MAXUDP-1] of Byte;
  Got: Word;
  LastSpin: LongInt;
  ErrOut: Text;

procedure Heartbeat;
var
  T: LongInt;
begin
  T := NetTicks;
  if T <> LastSpin then
  begin
    LastSpin := T;
    Write(ErrOut, SPIN[T and 3], #8);
    Flush(ErrOut);
  end;
end;

function Num(const S: ShortString; Default: LongInt): LongInt;
var
  V: LongInt;
  C: Integer;
begin
  Val(S, V, C);
  if (S = '') or (C <> 0) then Num := Default else Num := V;
end;

procedure DoEcho(Secs: LongInt);
var
  Deadline, Count: LongInt;
begin
  Count := 0;
  Deadline := NetTicks + Secs * 182 div 10;
  WriteLn('echo: ', IPStr(Peer), ' port ', Port, ' for ', Secs, ' s');
  while NetTicks < Deadline do
  begin
    Heartbeat;
    if NetUdpRecv(Port, Buf, SizeOf(Buf), Got, 1) then
    begin
      NetUdpSend(Port, Port, Buf, Got);
      Inc(Count);
      if (Buf[0] = $FF) and (Buf[1] = $FF) then Break;   { the pinger is done }
    end;
  end;
  WriteLn('echoed ', Count, ' packets');
end;

procedure DoPing(N: LongInt);
var
  I, Lost, Late, T0, T1, Waited, MaxWait: LongInt;
  Seq: Word;
  Ok: Boolean;
begin
  Lost := 0;
  Late := 0;
  MaxWait := 0;
  WriteLn('ping: ', IPStr(Peer), ' port ', Port, ', ', N, ' packets of ', PKTLEN, ' bytes');
  FillChar(Buf, SizeOf(Buf), $5A);
  T0 := NetTicks;
  for I := 1 to N do
  begin
    Heartbeat;
    Seq := Word(I);
    Buf[0] := Lo(Seq);
    Buf[1] := Hi(Seq);
    Waited := NetTicks;
    NetUdpSend(Port, Port, Buf, PKTLEN);
    Ok := False;
    repeat
      Heartbeat;
      if NetUdpRecv(Port, Buf, SizeOf(Buf), Got, 9) then   { half a second }
      begin
        if (Buf[0] = Lo(Seq)) and (Buf[1] = Hi(Seq)) then
          Ok := True
        else
          Inc(Late);                     { an older one's echo, arriving late }
      end
      else
        Break;
    until Ok;
    if Ok then
    begin
      Waited := NetTicks - Waited;
      if Waited > MaxWait then MaxWait := Waited;
    end
    else
      Inc(Lost);
  end;
  T1 := NetTicks;
  Buf[0] := $FF;
  Buf[1] := $FF;
  NetUdpSend(Port, Port, Buf, PKTLEN);   { tell the echo it can stop }
  WriteLn('sent ', N, ', lost ', Lost, ', late echoes ', Late);
  WriteLn('total ', T1 - T0, ' ticks: ', ((T1 - T0) * 549 div 10) * 100 div N div 100,
          ' ms a round trip on average (', ((T1 - T0) * 5490 div N) mod 100, ' hundredths)');
  WriteLn('slowest round trip: ', MaxWait, ' ticks (', MaxWait * 55, ' ms, to the tick)');
end;

var
  Mode: ShortString;
  I: Integer;
begin
  Assign(ErrOut, '');
  Rewrite(ErrOut);
  Mode := ParamStr(1);
  for I := 1 to Length(Mode) do Mode[I] := UpCase(Mode[I]);
  if ((Mode <> 'ECHO') and (Mode <> 'PING')) or not ParseIP(ParamStr(2), Peer) then
  begin
    WriteLn('MPPING ECHO peer [port] [secs]  |  MPPING PING peer [port] [n]');
    Halt(2);
  end;
  Port := Num(ParamStr(3), 31992);
  if not NetReadConfig then
  begin
    WriteLn('no network config: ', NetErr);
    Halt(3);
  end;
  if not NetOpen(Peer) then
  begin
    WriteLn('cannot open the network to ', IPStr(Peer), ': ', NetErr);
    Halt(4);
  end;
  if Mode = 'ECHO' then
    DoEcho(Num(ParamStr(4), 60))
  else
    DoPing(Num(ParamStr(4), 200));
  NetClose;
  Write(ErrOut, ' ', #8);
end.
