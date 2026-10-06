{ MPCLI -- a multiplayer client with no game: joins a server, sends random
  controls at a set frame rate, and keeps the steps it is given -- the wire
  half of WOLF3DM, to prove a DOS machine speaks the protocol through the
  network and the server's firewall.  Written by StevenC and Claude
  (Anthropic), 2026.  MULTIPLAYER.md's "Protocol, version 1" is the spec.

    MPCLI server [fps] [port]          (fps 5 by default: a V30's)

  At the end (the server's BYE) it reports the steps it holds and a CRC of
  them -- every client of one match must print the same CRC -- and how
  many STEPS packets and repeated rows it saw.  Its SYNC sums are that CRC
  every 50 steps, so the server checks them as it would a game's.  A
  clock-driven heartbeat on stderr; the network closed on every way out. }

program MPCli;

{$MODE OBJFPC}{$H-}

uses About, Net;

const
  MAXSTEPS = 5000;                  { x ROW = 60 KB: one 16-bit segment }
  ROW = 12;                         { up to 4 players x 3 bytes }
  SPIN: array[0..3] of Char = '|/-\';
  NOBODY = $FFFFFFFF;

type
  TRows = array[0..MAXSTEPS-1, 0..ROW-1] of Byte;

var
  Server: TIP;
  Port: Word;
  Fps: Integer;
  Buf: array[0..NET_MAXUDP-1] of Byte;
  Got: Word;
  Rows: ^TRows;
  HaveRow: array[0..MAXSTEPS-1] of Boolean;
  Have: LongInt;                    { highest step held with none missing; -1 none }
  Players, Slot: Integer;
  Synced: LongInt;
  StepsPkts, Dups: LongInt;
  LastSpin: LongInt;
  CrcTab: array[0..255] of LongWord;

procedure Heartbeat;
var
  T: LongInt;
begin
  T := NetTicks;
  if T <> LastSpin then
  begin
    LastSpin := T;
    Write(StdErr, SPIN[T and 3], #8);
    Flush(StdErr);
  end;
end;

procedure MakeCrc;
var
  I, J: Integer;
  C: LongWord;
begin
  for I := 0 to 255 do
  begin
    C := I;
    for J := 1 to 8 do
      if (C and 1) <> 0 then C := (C shr 1) xor $EDB88320 else C := C shr 1;
    CrcTab[I] := C;
  end;
end;

{ the CRC-32 of steps 0..n-1, each players*3 bytes -- zlib's, as mpfake's }
function StepsCrc(N: LongInt): LongWord;
var
  C: LongWord;
  S: LongInt;
  I: Integer;
begin
  C := $FFFFFFFF;
  for S := 0 to N - 1 do
    for I := 0 to Players * 3 - 1 do
      C := CrcTab[(C xor Rows^[S, I]) and $FF] xor (C shr 8);
  StepsCrc := not C;
end;

procedure Head(Kind: Byte);
begin
  Buf[0] := Ord('W'); Buf[1] := Ord('M'); Buf[2] := 1; Buf[3] := Kind;
end;

procedure PutL(Ofs: Integer; V: LongWord);
begin
  Buf[Ofs] := V and $FF; Buf[Ofs + 1] := (V shr 8) and $FF;
  Buf[Ofs + 2] := (V shr 16) and $FF; Buf[Ofs + 3] := V shr 24;
end;

function GetL(Ofs: Integer): LongWord;
begin
  GetL := Buf[Ofs] or (LongWord(Buf[Ofs + 1]) shl 8) or (LongWord(Buf[Ofs + 2]) shl 16)
          or (LongWord(Buf[Ofs + 3]) shl 24);
end;

procedure Send(Len: Word);
begin
  NetUdpSend(Port, Port, Buf, Len);
end;

{ one packet, if any, within Ticks; returns its type, 0 for none }
function Receive(Ticks: LongInt): Byte;
begin
  Receive := 0;
  if NetUdpRecv(Port, Buf, SizeOf(Buf), Got, Ticks) and (Got >= 4)
     and (Buf[0] = Ord('W')) and (Buf[1] = Ord('M')) and (Buf[2] = 1) then
    Receive := Buf[3];
end;

procedure TakeSteps;
var
  First: LongWord;
  Count, I, J, N: Integer;
  S: LongInt;
begin
  Inc(StepsPkts);
  First := GetL(4);
  Count := Buf[8];
  N := Buf[9] * 3;
  for I := 0 to Count - 1 do
  begin
    S := First + I;
    if (S >= 0) and (S < MAXSTEPS) then
      if HaveRow[S] then Inc(Dups)
      else
      begin
        for J := 0 to N - 1 do Rows^[S, J] := Buf[10 + I * N + J];
        HaveRow[S] := True;
      end;
  end;
  while (Have + 1 < MAXSTEPS) and HaveRow[Have + 1] do Inc(Have);
  while Synced + 50 <= Have + 1 do
  begin
    Inc(Synced, 50);
    Head(6);
    Buf[4] := Slot; Buf[5] := 0;
    PutL(6, Synced);
    PutL(10, StepsCrc(Synced));
    Send(14);
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

var
  Tries, I: Integer;
  K: Byte;
  Seq: Word;
  Next, Last, Started: LongInt;
  Joined, Go, Done: Boolean;
  Name: ShortString;
begin
  { FPC 3.2.2's i8086-msdos runtime: ParamStr is '' until ParamCount runs }
  if (ParamCount < 1) or not ParseIP(ParamStr(1), Server) then
  begin
    WriteLn('MPCLI server [fps] [port]');
    Halt(2);
  end;
  Fps := Num(ParamStr(2), 5);
  Port := Num(ParamStr(3), 31992);
  New(Rows);
  FillChar(HaveRow, SizeOf(HaveRow), 0);
  MakeCrc;
  Have := -1; Synced := 0; StepsPkts := 0; Dups := 0;
  Randomize;
  if not NetReadConfig then
  begin
    WriteLn('no network config: ', NetErr);
    Halt(3);
  end;
  Tries := 0;
  while not NetOpen(Server) do
  begin
    Inc(Tries);
    Heartbeat;
    if Tries >= 40 then
    begin
      WriteLn('cannot open the network to ', IPStr(Server), ': ', NetErr);
      Halt(4);
    end;
  end;
  Name := 'MPCLI ' + IPStr(NetMyIP);
  WriteLn('joining ', IPStr(Server), ' port ', Port, ' as "', Name, '", ', Fps, ' fps');

  { HELLO every half second until WELCOME, then wait for START }
  Joined := False; Go := False; Done := False;
  Last := -100;
  Started := NetTicks;
  while not Go and (NetTicks - Started < 18 * 120) do
  begin
    Heartbeat;
    if not Joined and (NetTicks - Last >= 9) then
    begin
      Last := NetTicks;
      Head(1);
      FillChar(Buf[4], 16, 0);
      for I := 1 to Length(Name) do if I <= 16 then Buf[3 + I] := Ord(Name[I]);
      PutL(20, $12345678);          { the build: mpfake's, so they can share a match }
      Buf[24] := $FF;
      Send(25);
    end;
    K := Receive(1);
    if (K = 2) and not Joined then
    begin
      Joined := True;
      Slot := Buf[4];
      Players := Buf[5];
      WriteLn('welcome: slot ', Slot, ' (P', Slot + 1, ') of ', Players);
    end
    else if (K = 3) and Joined then
    begin
      Players := Buf[4];
      Go := True;
      WriteLn('start: ', Players, ' players, map ', Buf[5]);
    end
    else if K = 8 then
    begin
      WriteLn('the server said BYE before the start');
      NetClose;
      Halt(5);
    end;
  end;
  if not Go then
  begin
    WriteLn('no START in two minutes');
    NetClose;
    Halt(6);
  end;

  { play: INPUT every 1/fps of a second, steps as they come, until BYE }
  Seq := 0;
  Next := NetTicks;
  Started := NetTicks;
  while not Done and (NetTicks - Started < 18 * 900) do
  begin
    Heartbeat;
    if NetTicks >= Next then
    begin
      Next := NetTicks + (182 div 10) div Fps;   { above 18 fps: every tick --
                                                    the BIOS clock is the pacer }
      if Next = NetTicks then Inc(Next);
      Inc(Seq);
      Head(4);
      Buf[4] := Slot;
      Buf[5] := Random(256) and $0F;               { buttons: no weapon keys }
      Buf[6] := Byte(ShortInt(Random(141) - 70));   { turn }
      Buf[7] := Byte(ShortInt(Random(141) - 70));   { move }
      Buf[8] := Lo(Seq); Buf[9] := Hi(Seq);
      if Have < 0 then PutL(10, NOBODY) else PutL(10, Have);
      Send(14);
    end;
    K := Receive(0);
    case K of
      5: TakeSteps;
      7: WriteLn('DESYNC reported at step ', GetL(4), ', mask ', Buf[8]);
      8: Done := True;
    end;
  end;
  NetClose;
  Write(StdErr, ' ', #8);
  WriteLn('ended: ', Have + 1, ' steps held, CRC ', HexStr(StepsCrc(Have + 1), 8),
          '; ', StepsPkts, ' STEPS packets, ', Dups, ' repeated rows');
end.
