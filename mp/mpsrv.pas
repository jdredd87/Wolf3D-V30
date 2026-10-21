{ MPSRV -- the Wolf3D multiplayer server, for DOS and for Windows.  Written
  by StevenC and Claude (Anthropic), 2026-10-15.

  The same server as mp/mpserver.py (the reference -- MULTIPLAYER.md,
  "Protocol, version 1"), on any DOS machine with a packet driver: it keeps
  the clock at 17.5 steps a second, passes every player's controls to every
  player, lets machines join and leave at any time (a late one is sent every
  step from the first and let in once caught up), checks every machine's
  checksums, and plays bots.  Built for the plain 8086.

    MPSRV [--players 4] [--bots 0] [--map 0] [--skill 2]
          [--mode coop|dm|tdm|ctf] [--ff on|off] [--noenemies]
          [--fraglimit N] [--timelimit MIN] [--itemrespawn SECS]
          [--port 31992] [--control 31999] [--drop-after 60] [--steps N]
          [--once] [--record GAME.MPR] [--name NAME]

  Its console is the keyboard: a command and Enter (help lists them -- the
  same as mpserver.py's).  The same commands come over the network to UDP
  31999 from any machine on its subnet: python mp/mpctl.py --host ADDR CMD.

  The clock: the PIT runs at 70 Hz while it serves, as the game's own does,
  and the BIOS clock is still fed at 18.2 -- a step is 4 of those ticks,
  exactly the game's.  The history (every step, for machines joining late)
  goes into XMS, or into MPSRV.HIS when there is none.  A status line on
  the screen moves with the clock, so a quiet server never looks hung.

  The same source builds MPSRVW.EXE for Windows (python mp/mkmpsrv.py
  --windows): WinSock for the network (mp/winnet.pas), the performance
  counter for the 70 Hz clock, the history in memory, the console read from
  its window a line at a time (or from a pipe), the status in the window's
  title -- and the console port on 127.0.0.1 only, as mpserver.py's. }

program MpSrv;

{$MODE OBJFPC}{$H-}

{$IFDEF WINDOWS}
{$APPTYPE CONSOLE}
uses WinNet;
{$ELSE}
uses About, SrvNet, Dos;
{$ENDIF}

const
  VERSION = 1;
  HELLO = 1; WELCOME = 2; START = 3; INPUTP = 4; STEPS = 5; SYNC = 6;
  DESYNC = 7; BYE = 8; CHAT = 9; CHATMSG = 10; NAMESP = 11; HANG = 12; PAUSEDP = 14;
  SNAPREQP = 17; SNAPDATAP = 18; SNAPGETP = 19;     { the snapshot (2026-10-17) }
  SNAPCHUNK = 900; SNAPWIN = 4;       { a piece; pieces for each SNAPGET }
  SNAP_MIN = 525; SNAP_STALE = 1050;  { steps: younger, replayed; older, asked again }
  SNAPMAX = 49152;                    { the biggest snapshot taken (WOLF3DM's: 31 KB) }
  DISCOVERP = 15; INFOP = 16;     { LAN discovery: a game's NET FIND (2026-10-17) }
  EV_NEXTFLOOR = 1; EV_MAP = 2; EV_TIMELIMIT = 4; EV_FRAGLIMIT = 5;
  BYE_END = 0; BYE_FULL = 1; BYE_BUILD = 2; BYE_DROPPED = 3; BYE_KICKED = 4;
  RULE_DM = 1; RULE_NOFF = 2; RULE_NOENEMIES = 4;
  { START's byte after the starts (2026-10-17): teams -- Gold P1+P3, Silver
    P2+P4 -- and capture the flag, with teams }
  RULE2_TEAM = 1; RULE2_CTF = 2;
  SERVER_SLOT = $FF;
  STEPS_MAX = 64;
  CAUGHT_UP = 4;
  NOBODY = $FFFFFFFF;
  MAXP = 4;
  WATCHN = 4;                     { watchers (NET WATCH, 2026-10-17): slots 4-7 }
  LASTSLOT = MAXP + WATCHN - 1;
  ROWB = 12;                      { a step as stored: 4 players x 3, always }
  RINGN = 4096;                   { the newest steps, in memory }
  SUMBLK = 2048;                  { checksums: one per 50 steps, blocks of these }
  MAXSUMBLK = 256;
  MAXEV = 256;
  T_SEC = 70;                     { ticks of the 70 Hz clock in a second }
{$IFDEF WINDOWS}
  NETNAME = 'the sockets';
{$ELSE}
  NETNAME = 'the card';
{$ENDIF}
  PITDIV = 17045;                 { 1193182 / 70 }
  SPIN: array[0..3] of Char = '|/-\';

type
  TRow = packed array[0..ROWB - 1] of Byte;
  TRing = array[0..RINGN - 1] of TRow;
  TName = string[16];
  TSnapBuf = array[0..49151] of Byte;
  PSnapBuf = ^TSnapBuf;
  TSlot = record
    Used, Bot: Boolean;
    Watch: Boolean;              { a watcher: sent every step, in none }
    IP: TIP; Mac: TMac; Port: Word;
    Name: TName;
    Build: LongWord;
    Ctl: packed array[0..2] of Byte;
    HaveSeq: Boolean; Seq: Word;
    Have: LongWord;              { NOBODY, or the newest step held with none missing }
    HasPlayed: Boolean; Played: LongWord;
    HasWin: Boolean;             { catching up: its gap WinGap at Ticks WinT }
    WinT, WinGap: LongInt;
    Ready, Present: Boolean;
    NoGive: Boolean;             { HELLO's FDh: gives no snapshot (a Win32 machine, 2026-10-21) }
    Inputs: LongInt;
    Heard: LongInt;              { Ticks of the last packet }
    SentFirst, SentLast: LongInt;
    SentAt: LongInt;
    { a bot's moves (gendemo.py's structured random input) }
    Rnd: LongWord;
    Left, Seg_: Integer;
    Bx, By, Bbits: Byte;
    Fire: Boolean;
    Frame: LongInt;
  end;
  TSumEnt = packed record
    Sum: LongWord;
    Slot: Byte;
    Valid: Byte;
  end;
  TSumBlk = array[0..SUMBLK - 1] of TSumEnt;
  PSumBlk = ^TSumBlk;
  TEvent = record
    Step: LongWord;
    Kind: Byte;
    Arg: Word;
  end;
  TTimer = packed record
    Ticks: LongInt;              { +0 }
    Acc: Word;                   { +4 }
  end;

var
  { settings }
  Players, Bots, Humans, MapNum, Skill, Rules, Rules2, Respawn: Integer;
  Frags, Minutes: Word;
  GamePort, CtlPort: Word;
  StepLimit: LongInt;
  Once, Quiet: Boolean;
  ServerName: ShortString;       { --name: what a game's server list calls it }
  DropAfter: LongInt;            { ticks }
  { the game }
  Playing, Paused: Boolean;
  NoSnap: Boolean;               { --nosnap }
  Snap, PullBuf: PSnapBuf;       { the snapshot, for joiners; one being pulled }
  SnapStep, SnapLen: LongInt;    { SnapLen 0: none }
  PullOn: Boolean;
  PullDonor, PullTries: Integer;
  PullStep, PullTotal, PullGot, PullBegan, PullAsked, SnapRest: LongInt;
  WaitFor: Integer;              { everyone waits for this joiner (--joinwait), -1 none }
  JoinWait: LongInt;             { seconds; 0 never }
  NextJoin, NextFeed: LongInt;
  Slots: array[0..LASTSLOT] of TSlot;
  Newest: LongInt;               { the newest step made; -1 none }
  NextStep, StartedAt, NextStart, NextNames, NextPausedT: LongInt;
  Ring: ^TRing;
  SumBlks: array[0..MAXSUMBLK - 1] of PSumBlk;
  Events: array[0..MAXEV - 1] of TEvent;
  NEv: Integer;
  ScoresStep: LongInt;
  Scores: array[0..MAXP - 1, 0..1] of SmallInt;
  HaveScores: Boolean;
  LiveTime, LiveFrag: LongInt;   { limits changed in play; -1 none }
  Desyncs, SentN, RecvN: LongInt;
  Games: Integer;
  Said: Byte;
  { "next" settings: -1 = unchanged }
  NxMap, NxSkill, NxBots, NxTime, NxFrag, NxResp, NxMode, NxEnemies, NxFF: Integer;
  Banned: array[0..15] of TIP;
  NBanned: Integer;
  { the clock }
  Timer: TTimer;
  OldInt8, OldInt23: Pointer;
  TimerOn: Boolean;
  { the history's store }
  XmsEntry: Pointer;
  XmsHandle: Word;
  XmsKB: LongWord;
  UseXms, UseFile: Boolean;
  HisFile: File;
  Flushed: LongInt;              { steps written to the file }
  XMove: packed record
    Len: LongWord;
    SrcH: Word; SrcOfs: LongWord;
    DstH: Word; DstOfs: LongWord;
  end;
  XmsOk: Word;
  { packets }
  Rx, Tx: array[0..SN_MAXUDP - 1] of Byte;
  RxLen: Word;
  { the console }
  Typed: ShortString;
  Reply: array[0..1399] of Char;
  ReplyLen: Integer;
  Replying: Boolean;
  StopNow: Boolean;
  LogF: Text;
  LogOpen, LogDirty: Boolean;
  LastFlush: LongInt;
  LastSpin: LongInt;
  StatusText: ShortString;

{ ---------------------------------------------------------------- the clock }

{$IFNDEF WINDOWS}
{ INT 8 at 70 Hz: counts, and passes the BIOS its 18.2 Hz.  +3/+5 are patched
  with the BIOS's handler, +11 with our data segment, +16 with Ofs(Timer). }
procedure Int8Isr; assembler; nostackframe;
asm
  db  0EBh, 05h          { +0  jmp short +7 }
  db  0EAh               { +2  jmp far: the BIOS's INT 8 }
  dw  0, 0               { +3, +5 }
  db  01Eh               { +7  push ds }
  db  050h               { +8  push ax }
  db  053h               { +9  push bx }
  db  0B8h               { +10 mov ax, imm16 }
  dw  0                  { +11 patched: our data segment }
  db  08Eh, 0D8h         { +13 mov ds, ax }
  db  0BBh               { +15 mov bx, imm16 }
  dw  0                  { +16 patched: Ofs(Timer) }
  add  word ptr [bx], 1
  adc  word ptr [bx + 2], 0
  add  word ptr [bx + 4], PITDIV
  jc   @@chain
  mov  al, 20h
  out  20h, al
  pop  bx
  pop  ax
  pop  ds
  iret
@@chain:
  pop  bx
  pop  ax
  pop  ds
  db  0EBh               { jmp short back to +2 }
  db  0                  {   patched: the distance }
end;

procedure Int23Isr; assembler; nostackframe;   { Ctrl-C: ignored -- the }
asm                                             { timer must be put back }
  iret
end;

{ the 70 Hz count -- read until two reads agree, since the interrupt may
  carry into the high word between the two halves of one }
function Ticks: LongInt;
var A, B: LongInt;
begin
  repeat
    A := Timer.Ticks;
    B := Timer.Ticks;
  until A = B;
  Ticks := A;
end;

procedure SetPit(Divisor: Word); assembler;
asm
  pushf
  cli
  mov  al, 36h
  out  43h, al
  mov  ax, Divisor
  out  40h, al
  mov  al, ah
  out  40h, al
  popf
end;

function TimerStart: Boolean;
var
  S, O, J: Word;
  B: Byte;
  I: Integer;
begin
  TimerStart := False;
  S := Seg(Int8Isr); O := Ofs(Int8Isr);
  { the bytes the patches go into must be where they are said to be }
  if (Mem[S:O] <> $EB) or (Mem[S:O + 2] <> $EA) or (Mem[S:O + 7] <> $1E)
     or (Mem[S:O + 10] <> $B8) or (Mem[S:O + 15] <> $BB) then
  begin
    WriteLn('the timer handler is not laid out as expected -- not starting');
    Exit;
  end;
  { the jump back to +2: find the last EBh 00h pair, the chain's }
  J := 0;
  for I := 18 to 60 do
    if (Mem[S:O + I] = $EB) and (Mem[S:O + I + 1] = 0) then J := I;
  if J = 0 then
  begin
    WriteLn('the timer handler''s chain jump was not found -- not starting');
    Exit;
  end;
  B := Byte(2 - (J + 2));                  { a short jump back to +2 }
  GetIntVec(8, OldInt8);
  asm
    pushf
    cli
  end;
  MemW[S:O + 3] := Ofs(OldInt8^);
  MemW[S:O + 5] := Seg(OldInt8^);
  MemW[S:O + 11] := Seg(Timer);
  MemW[S:O + 16] := Ofs(Timer);
  Mem[S:O + J + 1] := B;
  Timer.Ticks := 0;
  Timer.Acc := 0;
  SetIntVec(8, @Int8Isr);
  asm
    popf
  end;
  SetPit(PITDIV);
  TimerOn := True;
  TimerStart := True;
end;

procedure TimerStop;
begin
  if not TimerOn then Exit;
  SetPit(0);
  SetIntVec(8, OldInt8);
  TimerOn := False;
end;

{$ELSE}
function QueryPerformanceCounter(var C: Int64): LongBool; stdcall; external 'kernel32.dll';
function QueryPerformanceFrequency(var F: Int64): LongBool; stdcall; external 'kernel32.dll';

var
  QpcFreq, QpcBase: Int64;

{ the same 70 Hz count as the DOS build's, out of the performance counter }
function Ticks: LongInt;
var C: Int64;
begin
  QueryPerformanceCounter(C);
  Ticks := ((C - QpcBase) * T_SEC) div QpcFreq;
end;

function TimerStart: Boolean;
begin
  QueryPerformanceFrequency(QpcFreq);
  QueryPerformanceCounter(QpcBase);
  TimerOn := QpcFreq > 0;
  TimerStart := TimerOn;
end;

procedure TimerStop;
begin
  TimerOn := False;
end;

{$ENDIF}

{ ---------------------------------------------------------------- the log }

function I2S(L: LongInt): ShortString;
var S: ShortString;
begin
  Str(L, S);
  I2S := S;
end;

function Pad(const S: ShortString; N: Integer): ShortString;
var R: ShortString;
begin
  R := S;
  while Length(R) < N do R := R + ' ';
  Pad := R;
end;

function Secs(T: LongInt): ShortString;
begin
  Secs := I2S(T div T_SEC) + '.' + Copy(I2S(100 + (T mod T_SEC) * 100 div T_SEC), 2, 2);
end;

function LPad(const S: ShortString; N: Integer): ShortString;
var R: ShortString;
begin
  R := S;
  while Length(R) < N do R := ' ' + R;
  LPad := R;
end;

procedure ClearStatus;
begin
{$IFNDEF WINDOWS}
  Write(StdErr, #13, '':79, #13);
{$ENDIF}
end;

procedure Log(const S: ShortString);
var
  L: ShortString;
begin
  L := '[' + LPad(Secs(Ticks), 7) + '] ' + S;
  if LogOpen then
  begin
    WriteLn(LogF, L);
    LogDirty := True;              { written out by LogTick, once a second }
  end;
  if Quiet then Exit;
  ClearStatus;
  WriteLn(L);
  LastSpin := -1;
end;

{ MPSRV.LOG to the disk at most once a second (2026-10-16): a flush on every
  line cost the V30 -- whose disk is its PicoMEM's -- long enough that the
  frames arriving meanwhile overflowed the receive ring (518 in a run) }
procedure LogTick;
begin
  if LogOpen and LogDirty and (Ticks - LastFlush >= T_SEC) then
  begin
    Flush(LogF);
    LogDirty := False;
    LastFlush := Ticks;
  end;
end;

{ the console's own lines: to the screen, and back to a remote console }
procedure Say(const S: ShortString);
var I: Integer;
begin
  ClearStatus;
  WriteLn('[console] ', S);
  if LogOpen then
  begin
    WriteLn(LogF, '[console] ', S);
    LogDirty := True;
  end;
  if Replying then
    for I := 1 to Length(S) + 1 do
      if ReplyLen < SizeOf(Reply) then
      begin
        if I <= Length(S) then Reply[ReplyLen] := S[I] else Reply[ReplyLen] := #10;
        Inc(ReplyLen);
      end;
  LastSpin := -1;
end;

{ ------------------------------------------------------------ the history }

{$IFNDEF WINDOWS}
{ XMove and XmsEntry are in the data segment DS already points at (checked
  at start-up), so DS:SI is the move structure for function 0Bh }
function XmsCall(Fn: Byte; DXv: Word; var AXr, DXr, BXr: Word): Boolean;
var A, D, B, XO: Word;
begin
  XO := Ofs(XMove);
  asm
    push ds
    push si
    mov  ah, Fn
    mov  dx, DXv
    mov  si, XO
    call far [XmsEntry]
    pop  si
    pop  ds
    mov  A, ax
    mov  D, dx
    mov  B, bx
  end;
  AXr := A; DXr := D; BXr := B;
  XmsCall := A = 1;
end;

procedure XmsInit;
var
  A, D, B, S, O: Word;
  Ok: Byte;
begin
  UseXms := False;
  asm
    mov  ax, 4300h
    int  2Fh
    mov  Ok, al
  end;
  if Ok <> $80 then Exit;
  asm
    push es
    mov  ax, 4310h
    int  2Fh
    mov  S, es
    mov  O, bx
    pop  es
  end;
  XmsEntry := Ptr(S, O);
  XmsCall($08, 0, A, D, B);                { the largest free block, KB }
  if A < 64 then Exit;
  if A > 32768 then A := 32768;
  XmsKB := A;
  if not XmsCall($09, A, A, D, B) then Exit;
  XmsHandle := D;
  UseXms := True;
end;

procedure XmsDone;
var A, D, B: Word;
begin
  if UseXms then XmsCall($0A, XmsHandle, A, D, B);
  UseXms := False;
end;

procedure XmsPut(StepN: LongInt; var Row: TRow);
var A, D, B: Word;
begin
  XMove.Len := ROWB;
  XMove.SrcH := 0;
  XMove.SrcOfs := (LongWord(Seg(Row)) shl 16) or Ofs(Row);
  XMove.DstH := XmsHandle;
  XMove.DstOfs := LongWord(StepN) * ROWB;
  XmsCall($0B, 0, A, D, B);
end;

procedure XmsGet(First, Count: LongInt; var Dst);
var A, D, B: Word;
begin
  XMove.Len := LongWord(Count) * ROWB;
  XMove.SrcH := XmsHandle;
  XMove.SrcOfs := LongWord(First) * ROWB;
  XMove.DstH := 0;
  XMove.DstOfs := (LongWord(Seg(Dst)) shl 16) or Ofs(Dst);
  XmsCall($0B, 0, A, D, B);
end;

function HistCapacity: LongInt;
begin
  if UseXms then HistCapacity := (XmsKB * 1024) div ROWB
  else HistCapacity := 30000000;
end;

procedure HistReset;
begin
  Newest := -1;
  Flushed := 0;
  if UseFile then
  begin
    {$I-}
    Close(HisFile);
    {$I+}
    if IOResult <> 0 then ;
    Rewrite(HisFile, 1);
  end;
end;

{ steps up to UpTo (all older than the ring's tail) into the file }
procedure HistFlush(UpTo: LongInt);
var
  N: LongInt;
begin
  while Flushed <= UpTo do
  begin
    N := 64;
    if Flushed + N - 1 > UpTo then N := UpTo - Flushed + 1;
    if (Flushed and (RINGN - 1)) + N > RINGN then N := RINGN - (Flushed and (RINGN - 1));
    Seek(HisFile, Flushed * ROWB);
    BlockWrite(HisFile, Ring^[Flushed and (RINGN - 1)], N * ROWB);
    Inc(Flushed, N);
  end;
end;

procedure HistAdd(var Row: TRow);
begin
  Inc(Newest);
  Ring^[Newest and (RINGN - 1)] := Row;
  if UseXms then XmsPut(Newest, Row)
  else if UseFile and (Newest - Flushed >= 256) then HistFlush(Newest - 128);
end;

{ Count steps from First into Dst (Count <= STEPS_MAX) }
procedure HistGet(First, Count: LongInt; var Dst);
var
  P: ^TRow;
  K: LongInt;
begin
  if First > Newest - RINGN + 8 then
  begin
    P := @Dst;
    for K := 0 to Count - 1 do
    begin
      P^ := Ring^[(First + K) and (RINGN - 1)];
      Inc(P);
    end;
  end
  else if UseXms then
    XmsGet(First, Count, Dst)
  else
  begin
    HistFlush(Newest - 128);
    Seek(HisFile, First * ROWB);
    BlockRead(HisFile, Dst, Count * ROWB);
  end;
end;

{$ELSE}
const
  HBLK = 65536;                   { steps a block: 768 KB }
type
  THBlk = array[0..HBLK - 1] of TRow;
  PHBlk = ^THBlk;
var
  HBlks: array[0..1023] of PHBlk; { 67 million steps: a thousand hours of four }

procedure XmsInit;
begin
  UseXms := False;
end;

procedure XmsDone;
begin
end;

function HistCapacity: LongInt;
begin
  HistCapacity := 1024 * LongInt(HBLK);
end;

procedure HistReset;
begin
  Newest := -1;                   { the blocks stay, for the next game }
end;

procedure HistAdd(var Row: TRow);
var B: LongInt;
begin
  Inc(Newest);
  B := Newest div HBLK;
  if HBlks[B] = nil then New(HBlks[B]);
  HBlks[B]^[Newest mod HBLK] := Row;
end;

procedure HistGet(First, Count: LongInt; var Dst);
var
  P: ^TRow;
  K, S: LongInt;
begin
  P := @Dst;
  for K := 0 to Count - 1 do
  begin
    S := First + K;
    P^ := HBlks[S div HBLK]^[S mod HBLK];
    Inc(P);
  end;
end;

{$ENDIF}

{ ------------------------------------------------------------ checksums }

procedure SumsClear;
var I: Integer;
begin
  for I := 0 to MAXSUMBLK - 1 do
    if SumBlks[I] <> nil then
    begin
      Dispose(SumBlks[I]);
      SumBlks[I] := nil;
    end;
end;

function SumAt(StepN: LongWord): PSumBlk;
var B: LongWord;
begin
  SumAt := nil;
  B := (StepN div 50) div SUMBLK;
  if B >= MAXSUMBLK then Exit;
  if SumBlks[B] = nil then
  begin
    New(SumBlks[B]);
    FillChar(SumBlks[B]^, SizeOf(TSumBlk), 0);
  end;
  SumAt := SumBlks[B];
end;

{ ---------------------------------------------------------------- packets }

procedure Head(Kind: Byte);
begin
  Tx[0] := Ord('W'); Tx[1] := Ord('M'); Tx[2] := VERSION; Tx[3] := Kind;
end;

procedure PutW(Ofs: Integer; V: Word);
begin
  Tx[Ofs] := Lo(V); Tx[Ofs + 1] := Hi(V);
end;

procedure PutL(Ofs: Integer; V: LongWord);
begin
  Tx[Ofs] := V and $FF; Tx[Ofs + 1] := (V shr 8) and $FF;
  Tx[Ofs + 2] := (V shr 16) and $FF; Tx[Ofs + 3] := V shr 24;
end;

function GetW(Ofs: Integer): Word;
begin
  GetW := Rx[Ofs] or (Word(Rx[Ofs + 1]) shl 8);
end;

function GetL(Ofs: Integer): LongWord;
begin
  GetL := Rx[Ofs] or (LongWord(Rx[Ofs + 1]) shl 8) or (LongWord(Rx[Ofs + 2]) shl 16)
          or (LongWord(Rx[Ofs + 3]) shl 24);
end;

var
  SentTo: array[0..LASTSLOT] of LongInt;     { debug: sends a slot, and the }
  LastDst: array[0..LASTSLOT] of Word;       { port the last went to }

procedure SendTo(I: Integer; Len: Word);
begin
  SnSendTo(Slots[I].IP, Slots[I].Mac, GamePort, Slots[I].Port, Tx, Len);
  Inc(SentN);
  Inc(SentTo[I]);
  LastDst[I] := SnLastDst;
end;

procedure SendFrom(Len: Word);         { to whoever sent the packet in Rx }
begin
  SnSendTo(SnFromIP, SnFromMac, SnToPort, SnFromPort, Tx, Len);
  Inc(SentN);
end;

function ByeLen(Slot, Reason: Byte; const Text: ShortString): Word;
var I, N: Integer;
begin
  Head(BYE);
  Tx[4] := Slot; Tx[5] := Reason;
  ByeLen := 6;
  if Reason = BYE_KICKED then
  begin
    N := Length(Text);
    if N > 40 then N := 40;
    Tx[6] := N;
    for I := 1 to N do Tx[6 + I] := Ord(Text[I]);
    ByeLen := 7 + N;
  end;
end;

function StartLen: Word;
var I: Integer;
begin
  Head(START);
  Tx[4] := Players; Tx[5] := MapNum; Tx[6] := Skill; Tx[7] := Rules;
  for I := 0 to Players * 4 - 1 do Tx[8 + I] := 0;
  Tx[8 + Players * 4] := Rules2;      { an older game stops reading before it }
  StartLen := 9 + Players * 4;
end;

function NamesLen: Word;
var I, K: Integer;
begin
  Head(NAMESP);
  Tx[4] := Players;
  for I := 0 to Players - 1 do
    for K := 0 to 15 do
      if Slots[I].Used and (K < Length(Slots[I].Name)) then Tx[5 + I * 16 + K] := Ord(Slots[I].Name[K + 1])
      else Tx[5 + I * 16 + K] := 0;
  NamesLen := 5 + Players * 16;
end;

{ ---------------------------------------------------------------- slots }

function Who(I: Integer): ShortString;
begin
  if I >= MAXP then
  begin
    Who := 'W' + I2S(I - MAXP + 1) + ' ' + Slots[I].Name;
    Exit;
  end;
  if Slots[I].Used then Who := 'P' + I2S(I + 1) + ' ' + Slots[I].Name
  else Who := 'P' + I2S(I + 1);
end;

function IsPerson(I: Integer): Boolean;
begin
  IsPerson := Slots[I].Used and not Slots[I].Bot;
end;

{ a person or a watcher: whoever is sent the steps, the names, BYE }
function IsReceiver(I: Integer): Boolean;
begin
  IsReceiver := Slots[I].Used and not Slots[I].Bot;
end;

function AnyPeople: Boolean;
var I: Integer;
begin
  AnyPeople := False;
  for I := 0 to Players - 1 do
    if IsPerson(I) then AnyPeople := True;
end;

function SlotOf: Integer;        { the person whose address sent Rx; -1 none }
var I: Integer;
begin
  SlotOf := -1;
  for I := 0 to LASTSLOT do
    if IsReceiver(I) and SameIP(Slots[I].IP, SnFromIP) and (Slots[I].Port = SnFromPort) then
    begin
      SlotOf := I;
      Exit;
    end;
end;

function HaveStr(I: Integer): ShortString;
begin
  if Slots[I].Have = NOBODY then HaveStr := 'none' else HaveStr := I2S(Slots[I].Have);
end;

procedure NewBot(K: Integer);
var I: Integer;
begin
  I := Humans + K;
  FillChar(Slots[I], SizeOf(TSlot), 0);
  with Slots[I] do
  begin
    Used := True; Bot := True;
    Name := 'BOT' + I2S(K + 1);
    Ready := True; Present := True;
    Rnd := 4242 + K;
    Have := NOBODY;
  end;
end;

function BotRand(var S: TSlot; N: LongWord): LongWord;   { 0..N-1 }
begin
  S.Rnd := S.Rnd * 1103515245 + 12345;
  BotRand := ((S.Rnd shr 8) and $FFFF) mod N;
end;

{ the next step of a bot's controls: gendemo.py's runs, turns and strafes }
procedure BotNext(var S: TSlot; var C: TRow; Ofs: Integer);
var
  K: LongWord;
  B: Byte;
  X: Integer;
begin
  if S.Left <= 0 then
  begin
    K := BotRand(S, 100);
    S.Left := 4 + BotRand(S, 27);
    S.Seg_ := 0;
    S.Bx := 0; S.By := 0; S.Bbits := 0;
    if K < 30 then begin S.By := Byte(-70); S.Bbits := 4; end                 { run }
    else if K < 45 then S.By := Byte(-35)                                     { walk }
    else if K < 70 then                                                       { turnrun }
    begin
      X := 15 + BotRand(S, 56);
      if BotRand(S, 2) = 0 then X := -X;
      S.Bx := Byte(X); S.By := Byte(-70); S.Bbits := 4;
    end
    else if K < 85 then                                                       { turn }
    begin
      X := 25 + BotRand(S, 46);
      if BotRand(S, 2) = 0 then X := -X;
      S.Bx := Byte(X);
    end
    else if K < 95 then                                                       { strafe }
    begin
      if BotRand(S, 2) = 0 then S.Bx := Byte(-35) else S.Bx := 35;
      if BotRand(S, 2) = 0 then S.By := 0 else S.By := Byte(-35);
      S.Bbits := 2;
    end
    else S.By := 35;                                                          { back }
    S.Fire := BotRand(S, 100) < 35;
  end;
  B := S.Bbits;
  if S.Frame mod 9 = 4 then B := B or 8;
  if S.Fire and (S.Seg_ < 8) then B := B or 1;
  C[Ofs] := B; C[Ofs + 1] := S.Bx; C[Ofs + 2] := S.By;
  Inc(S.Frame); Inc(S.Seg_); Dec(S.Left);
end;

procedure ResetGame;
var K: Integer;
begin
  Playing := False;
  Paused := False;
  WaitFor := -1;
  SnapLen := 0;
  PullOn := False;
  HistReset;
  SumsClear;
  NEv := 0;
  HaveScores := False;
  LiveTime := -1; LiveFrag := -1;
  for K := 0 to Bots - 1 do NewBot(K);
end;

procedure ApplyNext; forward;
procedure GameOver(const Why: ShortString); forward;
procedure RecOpen; forward;              { the recording: below MakeStep's StepsLen }
procedure RecClose; forward;
procedure RecOther(Len: Word); forward;

procedure Leave(I: Integer; const Why: ShortString; Reason: Integer; const Text: ShortString);
var K: Integer; L: Word;
begin
  if Reason >= 0 then
  begin
    L := ByeLen(I, Reason, Text);
    for K := 1 to 3 do SendTo(I, L);
  end;
  Log(Who(I) + ' ' + Why + ' (' + I2S(Slots[I].Inputs) + ' inputs, had step ' + HaveStr(I) + ')');
  Slots[I].Used := False;
  NextNames := 0;
  if Playing and not AnyPeople then GameOver('everyone has left');
end;

procedure GameOver(const Why: ShortString);
var T: LongInt; I, K: Integer;
begin
  RecClose;
  for K := 1 to 3 do                   { the watchers: the game they watched is over }
    for I := MAXP to LASTSLOT do
      if Slots[I].Used then SendTo(I, ByeLen(I, BYE_END, ''));
  for I := MAXP to LASTSLOT do
    Slots[I].Used := False;
  T := Ticks - StartedAt;
  if T <= 0 then T := 1;
  Log('game over, ' + Why + ': ' + I2S(Newest + 1) + ' steps in ' + Secs(T) + ' s');
  Inc(Games);
  ApplyNext;
  ResetGame;
  if Once then StopNow := True
  else Log('waiting for players');
end;

function RespawnBits(S: Integer): Integer;
var N: Integer;
begin
  N := (S + 2) div 5;
  if N < 0 then N := 0;
  if N > 31 then N := 31;
  RespawnBits := N shl 3;
end;

procedure Join(const AName: TName; ABuild: LongWord; var I: Integer);
var
  K, F: Integer;
begin
  I := -1;
  F := -1;
  for K := 0 to Humans - 1 do
    if (F < 0) and not Slots[K].Used then F := K;
  if F < 0 then
  begin
    Log('refused ' + AName + ' from ' + IPStr(SnFromIP) + ': the server is full');
    SendFrom(ByeLen($FF, BYE_FULL, ''));
    Exit;
  end;
  for K := 0 to Players - 1 do
    if IsPerson(K) and (Slots[K].Build <> ABuild) then
    begin
      Log('refused ' + AName + ': build ' + HexStr(ABuild, 8) + ', not ' + HexStr(Slots[K].Build, 8));
      SendFrom(ByeLen($FF, BYE_BUILD, ''));
      Exit;
    end;
  I := F;
  FillChar(Slots[I], SizeOf(TSlot), 0);
  with Slots[I] do
  begin
    Used := True;
    IP := SnFromIP; Mac := SnFromMac; Port := SnFromPort;
    Name := AName;
    Build := ABuild;
    Ctl[0] := 0; Ctl[1] := 0; Ctl[2] := 0;
    Have := NOBODY;
    Heard := Ticks;
    SentFirst := -1; SentLast := -1;
  end;
  if Playing then
    Log(Who(I) + ' joined from ' + IPStr(SnFromIP) + ':' + I2S(SnFromPort) + ' (build '
        + HexStr(ABuild, 8) + '), into a game at step ' + I2S(Newest + 1))
  else
    Log(Who(I) + ' joined from ' + IPStr(SnFromIP) + ':' + I2S(SnFromPort) + ' (build '
        + HexStr(ABuild, 8) + ')');
  NextNames := 0;
end;

{ a machine that asked to watch (HELLO's slot FEh): a number of its own, 4-7;
  it is sent every step, and is in none of them (2026-10-17) }
procedure JoinWatch(const AName: TName; ABuild: LongWord; var I: Integer);
var
  K, F: Integer;
begin
  I := -1;
  F := -1;
  for K := MAXP to LASTSLOT do
    if (F < 0) and not Slots[K].Used then F := K;
  if F < 0 then
  begin
    Log('refused ' + AName + ' from ' + IPStr(SnFromIP) + ': watchers are full');
    SendFrom(ByeLen($FF, BYE_FULL, ''));
    Exit;
  end;
  for K := 0 to Players - 1 do
    if IsPerson(K) and (Slots[K].Build <> ABuild) then
    begin
      Log('refused ' + AName + ': build ' + HexStr(ABuild, 8) + ', not ' + HexStr(Slots[K].Build, 8));
      SendFrom(ByeLen($FF, BYE_BUILD, ''));
      Exit;
    end;
  I := F;
  FillChar(Slots[I], SizeOf(TSlot), 0);
  with Slots[I] do
  begin
    Used := True;
    Watch := True;
    IP := SnFromIP; Mac := SnFromMac; Port := SnFromPort;
    Name := AName;
    Build := ABuild;
    Have := NOBODY;
    Heard := Ticks;
    SentFirst := -1; SentLast := -1;
  end;
  Log(Who(I) + ' watches from ' + IPStr(SnFromIP) + ':' + I2S(SnFromPort) + ' (build '
      + HexStr(ABuild, 8) + ')');
end;

function Banned_(const A: TIP): Boolean;
var K: Integer;
begin
  Banned_ := False;
  for K := 0 to NBanned - 1 do
    if SameIP(Banned[K], A) then Banned_ := True;
end;

function SeqNewer(A, B: Word): Boolean;
begin
  SeqNewer := (A <> B) and (Word(A - B) < $8000);
end;

{ INFO, in Tx: what this server is playing and who -- the answer to a game's
  DISCOVER (NET FIND, 2026-10-17).  MULTIPLAYER.md has the layout. }
function InfoLen: Word;
var I, K, People: Integer; B: LongWord;
begin
  Head(INFOP);
  People := 0;
  B := 0;
  for I := 0 to Players - 1 do
    if IsPerson(I) then
    begin
      Inc(People);
      if B = 0 then B := Slots[I].Build;
    end;
  if Playing then Tx[4] := 1 else Tx[4] := 0;
  Tx[5] := Players; Tx[6] := People; Tx[7] := Bots; Tx[8] := 0;
  for I := MAXP to LASTSLOT do
    if Slots[I].Used then Inc(Tx[8]);
  Tx[9] := MapNum; Tx[10] := Skill; Tx[11] := Rules; Tx[12] := Rules2; Tx[13] := 0;
  PutL(14, Newest + 1);
  PutL(18, B);
  for K := 0 to 15 do
    if K < Length(ServerName) then Tx[22 + K] := Ord(ServerName[K + 1]) else Tx[22 + K] := 0;
  for I := 0 to 3 do
    for K := 0 to 15 do
      if (I < Players) and Slots[I].Used and (K < Length(Slots[I].Name)) then
        Tx[38 + 16 * I + K] := Ord(Slots[I].Name[K + 1])
      else
        Tx[38 + 16 * I + K] := 0;
  InfoLen := 102;
end;

{ the first step a joiner plays: after its snapshot's, if it began from one }
function FromStr: ShortString;
begin
  if (RxLen >= 18) and (GetL(14) <> NOBODY) then FromStr := I2S(LongInt(GetL(14)) + 1)
  else FromStr := '0';
end;

{ ------------------------------------- the snapshot a joiner starts from (2026-10-17) }

{ A joiner into a game more than 30 s old does not replay it from the first
  step: the server asks the player least behind for a snapshot of the game
  at a step two seconds ahead (SNAPREQ), pulls it in pieces (SNAPGET,
  SNAPDATA), keeps it a minute for the next joiner, and gives it to joiners
  the same way.  None in 20 s: the joiner replays from the first step. }

procedure SnapNone(I: Integer; Step: LongWord);
begin
  Head(SNAPDATAP); PutL(4, Step); PutL(8, 0); PutL(12, 0); Tx[16] := 0; Tx[17] := 0;
  SendTo(I, 18);
end;

procedure SnapAsk(Tries: Integer);
var K, Best: Integer;
begin
  Best := -1;
  for K := 0 to Players - 1 do
    with Slots[K] do
      if Used and not Bot and not NoGive and Present and HasPlayed and ((Best < 0) or (Played > Slots[Best].Played)) then
        Best := K;
  if (Best < 0) or (Tries > 3) then
  begin
    PullOn := False;
    SnapRest := Ticks + 30 * T_SEC;
    Exit;
  end;
  PullOn := True; PullDonor := Best; PullStep := Newest + 35; PullTotal := 0; PullGot := 0;
  PullBegan := Ticks; PullAsked := Ticks; PullTries := Tries;
  Head(SNAPREQP); PutL(4, PullStep);
  SendTo(Best, 8);
  Log('asked ' + Who(Best) + ' for a snapshot at step ' + I2S(PullStep));
end;

{ a joiner's SNAPGET: pieces of the snapshot, or why there are none }
procedure SnapGive(I: Integer);
var K: Integer; Off, O, N: LongInt;
begin
  Off := GetL(8);
  if NoSnap or not Playing or (Newest < SNAP_MIN) then begin SnapNone(I, 0); Exit; end;
  if (SnapLen > 0) and ((SnapStep >= Newest - SNAP_STALE) or (not PullOn and (Ticks < SnapRest))) then
  begin
    for K := 0 to SNAPWIN - 1 do
    begin
      O := Off + LongInt(K) * SNAPCHUNK;
      if O >= SnapLen then Break;
      N := SnapLen - O;
      if N > SNAPCHUNK then N := SNAPCHUNK;
      Head(SNAPDATAP); PutL(4, SnapStep); PutL(8, SnapLen); PutL(12, O);
      Tx[16] := Lo(Word(N)); Tx[17] := Hi(Word(N));
      Move(Snap^[O], Tx[18], N);
      SendTo(I, 18 + N);
    end;
    Exit;
  end;
  if not PullOn and (Ticks >= SnapRest) then SnapAsk(0);
  if PullOn then SnapNone(I, $FFFFFFFF) else SnapNone(I, 0);
end;

{ the player's SNAPDATA: the next piece, or "missed" -- asked again }
procedure SnapTake(I: Integer);
var Total, O: LongInt; N: Word; P: PSnapBuf;
begin
  if not PullOn or (I <> PullDonor) or (LongInt(GetL(4)) <> PullStep) then Exit;
  Total := GetL(8);
  if Total = 0 then begin SnapAsk(PullTries + 1); Exit; end;
  if Total > SNAPMAX then
  begin
    Log('a snapshot of ' + I2S(Total) + ' bytes: too big');
    PullOn := False; SnapRest := Ticks + 30 * T_SEC;
    Exit;
  end;
  PullTotal := Total;
  O := GetL(12);
  N := Rx[16] or (Word(Rx[17]) shl 8);
  if (O = PullGot) and (N > 0) and (RxLen >= 18 + N) and (O + N <= SNAPMAX) then
  begin
    Move(Rx[18], PullBuf^[O], N);
    Inc(PullGot, N);
    PullAsked := Ticks - T_SEC;          { the next pieces, now }
    if PullGot >= PullTotal then
    begin
      P := Snap; Snap := PullBuf; PullBuf := P;
      SnapLen := PullTotal; SnapStep := PullStep; PullOn := False;
      Log('a snapshot of step ' + I2S(SnapStep) + ' from ' + Who(I) + ': ' + I2S(SnapLen)
          + ' bytes in ' + Secs(Ticks - PullBegan) + ' s');
    end;
  end;
end;

{ in the loop: ask again, or for the next pieces }
procedure SnapPull;
var T, Wait: LongInt;
begin
  T := Ticks;
  if not Slots[PullDonor].Used or (T - PullBegan > 20 * T_SEC) then
  begin
    Log('no snapshot came: a joiner replays from the first step');
    PullOn := False; SnapRest := T + 30 * T_SEC;
    Exit;
  end;
  if PullTotal > 0 then Wait := T_SEC div 10 else Wait := T_SEC div 2;
  if T - PullAsked < Wait then Exit;
  PullAsked := T;
  if (PullTotal = 0) and (Newest < PullStep) then
  begin
    Head(SNAPREQP); PutL(4, PullStep);
    SendTo(PullDonor, 8);
  end
  else
  begin
    Head(SNAPGETP); PutL(4, PullStep); PutL(8, PullGot);
    SendTo(PullDonor, 12);
  end;
end;

procedure HandleGame;
var
  I, K, N: Integer;
  Name: TName;
  Build, Have, Played, StepN, Sum: LongWord;
  P: PSumBlk;
  E: LongWord;
  Kind: Byte;
  L: Word;
  Text: ShortString;
begin
  if (RxLen < 4) or (Rx[0] <> Ord('W')) or (Rx[1] <> Ord('M')) or (Rx[2] <> VERSION) then Exit;
  Inc(RecvN);
  Kind := Rx[3];
  if Kind = HANG then
  begin
    Text := '';
    K := 4;
    while (K < RxLen) and (Rx[K] <> 13) and (Rx[K] <> 10) and (Length(Text) < 200) do
    begin
      Text := Text + Chr(Rx[K]);
      Inc(K);
    end;
    Log('HANG from ' + IPStr(SnFromIP) + ': ' + Text);
    Exit;
  end;
  if Kind = DISCOVERP then             { a game looking for servers: what this one is }
  begin
    SendFrom(InfoLen);
    Exit;
  end;
  I := SlotOf;
  if I >= 0 then Slots[I].Heard := Ticks;
  if (Kind = SNAPGETP) and (I >= 0) and (RxLen >= 12) then begin SnapGive(I); Exit; end;
  if (Kind = SNAPDATAP) and (I >= 0) and (RxLen >= 18) then begin SnapTake(I); Exit; end;
  case Kind of
    HELLO:
      begin
        if RxLen < 25 then Exit;
        Name := '';
        for K := 0 to 15 do
          if (Rx[4 + K] <> 0) and (Length(Name) = K) then Name := Name + Chr(Rx[4 + K]);
        Build := GetL(20);
        if (I < 0) and Banned_(SnFromIP) then
        begin
          Log('refused ' + Name + ' from ' + IPStr(SnFromIP) + ': banned');
          SendFrom(ByeLen($FF, BYE_KICKED, 'banned from this server'));
          Exit;
        end;
        if (I >= 0) and Slots[I].Ready then
        begin
          Leave(I, 'is back (restarted)', -1, '');
          I := -1;
        end;
        if I < 0 then
        begin
          if Rx[24] = $FE then JoinWatch(Name, Build, I)    { NET WATCH }
          else Join(Name, Build, I);
          if I < 0 then Exit;
        end;
        Slots[I].NoGive := Rx[24] = $FD;    { its snapshot is its memory: a DOS joiner cannot read it }
        Head(WELCOME);
        Tx[4] := I; Tx[5] := Players; Tx[6] := MapNum; Tx[7] := Skill; Tx[8] := Rules; Tx[9] := 0;
        PutW(10, Frags); PutW(12, Minutes);
        PutL(14, Newest + 1);
        SendTo(I, 18);
        SendTo(I, StartLen);
      end;
    INPUTP:
      begin
        if I < 0 then
        begin
          SendFrom(ByeLen($FF, BYE_DROPPED, ''));
          Exit;
        end;
        if RxLen < 14 then Exit;
        if Slots[I].Watch then           { a watcher: what it holds and has played }
        begin
          if not Slots[I].Ready then
          begin
            Slots[I].Ready := True;
            if Playing then
              Log(Who(I) + ' has loaded the level: catching up from step ' + FromStr + ' of ' + I2S(Newest + 1))
            else
              Log(Who(I) + ' has loaded the level');
          end;
          Have := GetL(10);
          if (Have <> NOBODY) and ((Slots[I].Have = NOBODY) or (Have > Slots[I].Have)) then
            Slots[I].Have := Have;
          if RxLen >= 18 then
          begin
            Played := GetL(14);
            Slots[I].HasPlayed := Played <> NOBODY;
            Slots[I].Played := Played;
          end;
          Inc(Slots[I].Inputs);
          Exit;
        end;
        if not Slots[I].Ready then
        begin
          Slots[I].Ready := True;
          if not Playing then
          begin
            Playing := True;
            StartedAt := Ticks;
            NextStep := StartedAt;
            Log(Who(I) + ' has loaded the level: the game starts');
            RecOpen;
          end
          else
            Log(Who(I) + ' has loaded the level: catching up from step ' + FromStr + ' of ' + I2S(Newest + 1));
        end;
        if (not Slots[I].HaveSeq) or SeqNewer(GetW(8), Slots[I].Seq) then
        begin
          Slots[I].HaveSeq := True;
          Slots[I].Seq := GetW(8);
          Slots[I].Ctl[0] := Rx[5]; Slots[I].Ctl[1] := Rx[6]; Slots[I].Ctl[2] := Rx[7];
        end;
        Have := GetL(10);
        if (Have <> NOBODY) and ((Slots[I].Have = NOBODY) or (Have > Slots[I].Have)) then
          Slots[I].Have := Have;
        if RxLen >= 18 then
        begin
          Played := GetL(14);
          Slots[I].HasPlayed := Played <> NOBODY;
          Slots[I].Played := Played;
        end;
        Inc(Slots[I].Inputs);
      end;
    SYNC:
      begin
        if (I < 0) or (RxLen < 14) then Exit;
        StepN := GetL(6);
        Sum := GetL(10);
        if (RxLen >= 30) and ((not HaveScores) or (LongInt(StepN) >= ScoresStep)) then
        begin
          HaveScores := True;
          ScoresStep := StepN;
          for K := 0 to MAXP - 1 do
          begin
            Scores[K, 0] := SmallInt(GetW(14 + K * 4));
            Scores[K, 1] := SmallInt(GetW(16 + K * 4));
          end;
        end;
        P := SumAt(StepN);
        if P = nil then Exit;
        E := (StepN div 50) mod SUMBLK;
        if P^[E].Valid = 0 then
        begin
          P^[E].Valid := 1;
          P^[E].Sum := Sum;
          P^[E].Slot := I;
        end
        else if P^[E].Sum <> Sum then
        begin
          Inc(Desyncs);
          Log('DESYNC at step ' + I2S(StepN) + ': ' + Who(I) + ' has ' + HexStr(Sum, 8) + ', P'
              + I2S(P^[E].Slot + 1) + ' had ' + HexStr(P^[E].Sum, 8));
          Head(DESYNC);
          PutL(4, StepN);
          Tx[8] := 1 shl I;
          SendTo(I, 9);
        end;
      end;
    BYE:
      if I >= 0 then Leave(I, 'left', -1, '');
    CHAT:
      begin
        if (I < 0) or (I >= MAXP) or (RxLen < 7) then Exit;
        N := Rx[6];
        if 7 + N > RxLen then N := RxLen - 7;
        Text := '';
        for K := 0 to N - 1 do Text := Text + Chr(Rx[7 + K]);
        Log(Who(I) + ' says: ' + Text);
        Head(CHATMSG);
        Tx[4] := I; Tx[5] := Rx[5]; Tx[6] := N;
        for K := 0 to N - 1 do Tx[7 + K] := Rx[7 + K];
        L := 7 + N;
        for K := 0 to LASTSLOT do
          if IsReceiver(K) then SendTo(K, L);
        RecOther(L);
      end;
  end;
end;

{ ---------------------------------------------------------------- the clock's step }

{ STEPS in Tx: steps First to Last (at most STEPS_MAX), and the server's
  events among them }
function StepsLen(First, Last: LongInt): Word;
var
  K, NE, P: Integer;
  Rows: array[0..STEPS_MAX - 1] of TRow;
  Len: Word;
begin
  HistGet(First, Last - First + 1, Rows);
  Head(STEPS);
  PutL(4, First);
  Tx[8] := Last - First + 1;
  Tx[9] := Players;
  Len := 10;
  for K := 0 to Last - First do
  begin
    for P := 0 to Players * 3 - 1 do Tx[Len + P] := Rows[K][P];
    Inc(Len, Players * 3);
  end;
  NE := 0;
  for K := 0 to NEv - 1 do
    if (LongInt(Events[K].Step) >= First) and (LongInt(Events[K].Step) <= Last) and (NE < 20) then
      Inc(NE);
  if NE > 0 then
  begin
    Tx[Len] := NE;
    Inc(Len);
    NE := 0;
    for K := 0 to NEv - 1 do
      if (LongInt(Events[K].Step) >= First) and (LongInt(Events[K].Step) <= Last) and (NE < 20) then
      begin
        PutL(Len, Events[K].Step);
        Tx[Len + 4] := Events[K].Kind;
        PutW(Len + 5, Events[K].Arg);
        Inc(Len, 7);
        Inc(NE);
      end;
  end
  else
  begin
    Tx[Len] := 0;                      { no events: a count of none, for what follows }
    Inc(Len);
  end;
  PutL(Len, Newest);                   { the newest step there is: how far a joiner
  Inc(Len, 4);                           has to go (2026-10-17) }
  StepsLen := Len;
end;

{ ---------------------------------------------------------------- the recording

  --record GAME.MPR (2026-10-17): every packet a watcher is sent, as it is
  sent -- "WMR1", then each packet after its length (u16): WELCOME (a
  watcher's), START, NAMES when they change, STEPS (64 at a time, with the
  events), CHATMSG -- for WOLF3DM REPLAY.  Written as the game goes, every
  floor, so a server that stops still leaves the game so far. }

type
  TRecBuf = array[0..SN_MAXUDP - 1] of Byte;

var
  RecFile: File;
  Recording: Boolean;
  RecPath, RecName: string[80];
  RecNames: string[80];
  RecFirst: LongInt;                   { the first step not yet written }
  RecBuf: ^TRecBuf;                    { from the heap, when a recording opens: the
                                         DOS server's DGROUP has no 1.5 KB to spare }

procedure RecWrite(var Buf; Len: Word);
var L: Word;
begin
  L := Len;
  {$I-}
  BlockWrite(RecFile, L, 2);
  BlockWrite(RecFile, Buf, Len);
  {$I+}
  if IOResult <> 0 then
  begin
    Log('the recording: a write failed -- it stops here');
    {$I-} Close(RecFile); {$I+}
    if IOResult <> 0 then ;
    Recording := False;
  end;
end;

procedure RecFlush;                    { the steps made so far }
var Last: LongInt; L: Word;
begin
  while Recording and (RecFirst <= Newest) do
  begin
    Last := RecFirst + STEPS_MAX - 1;
    if Last > Newest then Last := Newest;
    L := StepsLen(RecFirst, Last);
    RecWrite(Tx, L);
    RecFirst := Last + 1;
  end;
end;

procedure RecOther(Len: Word);         { the packet in Tx, at this point of the game }
begin
  if not Recording then Exit;
  Move(Tx, RecBuf^, Len);
  RecFlush;
  if Recording then RecWrite(RecBuf^, Len);
end;

procedure RecNamesNow;
var I: Integer; S: string[80];
begin
  if not Recording then Exit;
  S := '';
  for I := 0 to Players - 1 do
    if Slots[I].Used then S := S + Slots[I].Name + '|' else S := S + '|';
  if S = RecNames then Exit;
  RecNames := S;
  RecOther(NamesLen);
end;

procedure RecOpen;
var Ext: string[12]; I: Integer;
begin
  if RecPath = '' then Exit;
  RecName := RecPath;
  if Games > 0 then                    { a second game on: GAME.MPR, GAMEB.MPR ... }
  begin
    I := Length(RecName);
    while (I > 0) and (RecName[I] <> '.') and (RecName[I] <> '\') do Dec(I);
    if (I > 0) and (RecName[I] = '.') then
    begin
      Ext := Copy(RecName, I, 255);
      RecName := Copy(RecName, 1, I - 1) + Chr(Ord('A') + Games) + Ext;
    end
    else RecName := RecName + Chr(Ord('A') + Games);
  end;
  Assign(RecFile, RecName);
  {$I-} Rewrite(RecFile, 1); {$I+}
  if IOResult <> 0 then
  begin
    Log('cannot write the recording ' + RecName);
    Exit;
  end;
  if RecBuf = nil then New(RecBuf);
  Recording := True;
  RecFirst := 0;
  RecNames := '';
  RecBuf^[0] := Ord('W'); RecBuf^[1] := Ord('M'); RecBuf^[2] := Ord('R'); RecBuf^[3] := Ord('1');
  {$I-} BlockWrite(RecFile, RecBuf^, 4); {$I+}
  if IOResult <> 0 then ;
  Head(WELCOME);                       { a watcher's }
  Tx[4] := MAXP; Tx[5] := Players; Tx[6] := MapNum; Tx[7] := Skill; Tx[8] := Rules; Tx[9] := 0;
  PutW(10, Frags); PutW(12, Minutes);
  PutL(14, 0);
  RecWrite(Tx, 18);
  RecWrite(Tx, StartLen);
  RecNamesNow;
  Log('recording the game in ' + RecName);
end;

procedure RecClose;
begin
  if not Recording then Exit;
  RecFlush;
  if Recording then
  begin
    {$I-} Close(RecFile); {$I+}
    if IOResult <> 0 then ;
    Recording := False;
    Log('recorded ' + I2S(RecFirst) + ' steps as ' + RecName + ' -- WOLF3DM REPLAY ' + RecName);
  end;
end;

{ Every machine the steps it lacks -- also while the game is held, so a
  joiner catches up while everyone waits for it (2026-10-17) }
procedure SendSteps;
var
  I: Integer;
  First, Last, Now: LongInt;
  Len: Word;
begin
  Now := Ticks;
  for I := 0 to LASTSLOT do
  begin
    if not IsReceiver(I) or not Slots[I].Ready then Continue;
    if Slots[I].Have = NOBODY then First := 0 else First := Slots[I].Have + 1;
    Last := First + STEPS_MAX - 1;
    if Last > Newest then Last := Newest;
    if First > Newest then Continue;
    with Slots[I] do
    begin
      if (First = SentFirst) and (Last = SentLast) and (Now - SentAt < 18) then Continue;
      SentFirst := First; SentLast := Last; SentAt := Now;
    end;
    Len := StepsLen(First, Last);
    SendTo(I, Len);
  end;
end;

procedure MakeStep;
var
  Row: TRow;
  I: Integer;
  Done: LongWord;
  HasDone: Boolean;
  Off: Word;
begin
  for I := 0 to ROWB - 1 do Row[I] := 0;
  for I := 0 to Players - 1 do
  begin
    Off := I * 3;
    if not Slots[I].Used then
    begin
      Row[Off] := 0; Row[Off + 1] := $80; Row[Off + 2] := $80;
    end
    else if Slots[I].Bot then
      BotNext(Slots[I], Row, Off)
    else
    begin
      with Slots[I] do
        if (not Present) and Ready then
        begin
          HasDone := True;
          if HasPlayed then Done := Played
          else if Have <> NOBODY then Done := Have
          else HasDone := False;
          if (Newest < 0) or (HasDone and (LongInt(Done) >= Newest - CAUGHT_UP)) then
          begin
            Present := True;
            if Newest >= 0 then Log(Who(I) + ' is in the game at step ' + I2S(Newest + 1));
          end;
        end;
      if Slots[I].Present then
      begin
        Row[Off] := Slots[I].Ctl[0]; Row[Off + 1] := Slots[I].Ctl[1]; Row[Off + 2] := Slots[I].Ctl[2];
      end
      else
      begin
        Row[Off] := 0; Row[Off + 1] := $80; Row[Off + 2] := $80;
      end;
    end;
  end;
  HistAdd(Row);
  if Recording then
  begin
    RecNamesNow;                       { who came or went }
    if Newest - RecFirst + 1 >= STEPS_MAX then RecFlush;
  end;
  SendSteps;
end;

{ ---------------------------------------------------------------- the console }

{ --mode's word: 0 coop, 1 dm, 2 tdm, 3 ctf }
function ModeOf(const S: ShortString): Integer;
begin
  if S = 'coop' then ModeOf := 0 else if S = 'dm' then ModeOf := 1
  else if S = 'tdm' then ModeOf := 2 else if S = 'ctf' then ModeOf := 3
  else ModeOf := -1;
end;

procedure SetMode(M: Integer; var R: Integer);
begin
  if M = 0 then R := R and not RULE_DM else R := R or RULE_DM;
  if M = 2 then Rules2 := RULE2_TEAM
  else if M = 3 then Rules2 := RULE2_TEAM or RULE2_CTF
  else Rules2 := 0;
end;

function Settings: ShortString;
var S: ShortString;
begin
  S := 'map ' + I2S(MapNum) + ' (E' + I2S(MapNum div 10 + 1) + 'L' + I2S(MapNum mod 10 + 1) + '), ';
  if Rules2 and RULE2_CTF <> 0 then S := S + 'capture the flag'
  else if Rules2 and RULE2_TEAM <> 0 then S := S + 'team deathmatch'
  else if Rules and RULE_DM <> 0 then S := S + 'deathmatch' else S := S + 'co-op';
  S := S + ', skill ' + I2S(Skill) + ', bots ' + I2S(Bots);
  if Rules and RULE_NOENEMIES <> 0 then S := S + ', enemies off' else S := S + ', enemies on';
  if Rules and RULE_NOFF <> 0 then S := S + ', ff off' else S := S + ', ff on';
  if Rules shr 3 <> 0 then S := S + ', items back after ' + I2S((Rules shr 3) * 5) + ' s'
  else S := S + ', items back never';
  if Minutes <> 0 then S := S + ', timelimit ' + I2S(Minutes);
  if Frags <> 0 then S := S + ', fraglimit ' + I2S(Frags);
  if LiveFrag >= 0 then S := S + ', fraglimit ' + I2S(LiveFrag) + ' in this game';
  if LiveTime >= 0 then S := S + ', timelimit ' + I2S(LiveTime) + ' in this game';
  if Paused then S := S + ', PAUSED';
  if WaitFor >= 0 then S := S + ', WAITING for ' + Who(WaitFor) + ' to catch up';
  Settings := S;
end;

function Pending: ShortString;
var S: ShortString;
begin
  S := '';
  if NxMap >= 0 then S := S + ' map ' + I2S(NxMap);
  case NxMode of
    0: S := S + ' mode coop';
    1: S := S + ' mode dm';
    2: S := S + ' mode tdm';
    3: S := S + ' mode ctf';
  end;
  if NxSkill >= 0 then S := S + ' skill ' + I2S(NxSkill);
  if NxBots >= 0 then S := S + ' bots ' + I2S(NxBots);
  if NxTime >= 0 then S := S + ' timelimit ' + I2S(NxTime);
  if NxFrag >= 0 then S := S + ' fraglimit ' + I2S(NxFrag);
  if NxResp >= 0 then S := S + ' itemrespawn ' + I2S(NxResp);
  if NxEnemies >= 0 then if NxEnemies = 1 then S := S + ' enemies on' else S := S + ' enemies off';
  if NxFF >= 0 then if NxFF = 1 then S := S + ' ff on' else S := S + ' ff off';
  Pending := S;
end;

procedure ApplyNext;
var
  R, K, N: Integer;
  Ok: Boolean;
begin
  if Pending = '' then Exit;
  if NxMap >= 0 then MapNum := NxMap;
  if NxSkill >= 0 then Skill := NxSkill;
  R := Rules and 7;
  if NxMode >= 0 then
  begin
    SetMode(NxMode, R);
    if NxResp < 0 then if NxMode <> 0 then NxResp := 30 else NxResp := 0;
  end;
  if NxEnemies >= 0 then
    if NxEnemies = 1 then R := R and not RULE_NOENEMIES else R := R or RULE_NOENEMIES;
  if NxFF >= 0 then
    if NxFF = 1 then R := R and not RULE_NOFF else R := R or RULE_NOFF;
  if NxResp >= 0 then Respawn := NxResp else Respawn := (Rules shr 3) * 5;
  Rules := (R and 7) or RespawnBits(Respawn);
  if NxTime >= 0 then Minutes := NxTime;
  if NxFrag >= 0 then Frags := NxFrag;
  if NxBots >= 0 then
  begin
    N := NxBots;
    if N > Players - 1 then N := Players - 1;
    Ok := True;
    for K := Players - N to Players - 1 do
      if IsPerson(K) then Ok := False;
    if not Ok then
      Say('bots: a person is in a slot the bots would take -- left at ' + I2S(Bots))
    else
    begin
      for K := 0 to Players - 1 do
        if Slots[K].Used and Slots[K].Bot then Slots[K].Used := False;
      Bots := N; Humans := Players - N;
      for K := 0 to Bots - 1 do NewBot(K);
    end;
  end;
  NxMap := -1; NxSkill := -1; NxBots := -1; NxTime := -1; NxFrag := -1;
  NxResp := -1; NxMode := -1; NxEnemies := -1; NxFF := -1;
  Say('now: ' + Settings);
end;

procedure Status;
var
  I: Integer;
  T: LongInt;
  S: ShortString;
begin
  if Playing then
  begin
    T := (Ticks - StartedAt) div T_SEC;
    Say('playing: step ' + I2S(Newest + 1) + ', ' + I2S(T div 60) + ':' + Copy(I2S(100 + T mod 60), 2, 2)
        + ' in; ' + Settings);
  end
  else
    Say('waiting for players; ' + Settings);
  for I := MAXP to LASTSLOT do
    if Slots[I].Used then
      Say('  ' + Pad(Who(I), 20) + ' watching, has step ' + HaveStr(I));
  for I := 0 to Players - 1 do
    if not Slots[I].Used then Say('  P' + I2S(I + 1) + '  (empty)')
    else if Slots[I].Bot then Say('  P' + I2S(I + 1) + '  ' + Pad(Slots[I].Name, 16) + ' the server''s bot')
    else
      with Slots[I] do
      begin
        if Present then S := 'in the game' else if Ready then S := 'catching up' else S := 'loading';
        S := S + ', has step ' + HaveStr(I);
        if (Have <> NOBODY) and (Newest >= 0) then
          if Newest - LongInt(Have) > 0 then S := S + ', ' + I2S(Newest - LongInt(Have)) + ' behind'
          else S := S + ', 0 behind';
        if Ready and not Present and HasPlayed and (Newest >= LongInt(Played)) then
          S := S + ', ' + I2S(Newest - LongInt(Played)) + ' to play';
        Say('  P' + I2S(I + 1) + '  ' + Pad(Name, 16) + ' ' + IPStr(IP) + ':' + I2S(Port) + '  ' + S
            + ', ' + I2S(Inputs) + ' inputs, heard ' + Secs(Ticks - Heard) + ' s ago');
      end;
  if Pending <> '' then Say('next game:' + Pending);
  { the counters (2026-10-15): so a long run can be watched from afar }
  Say('  net: ' + I2S(Desyncs) + ' desyncs; packets sent ' + I2S(SentN) + ', received ' + I2S(RecvN)
      + '; ' + NETNAME + ': ' + I2S(SnTxFail) + ' refused, ' + I2S(SnRxBadSum) + ' bad checksums, '
      + I2S(SnDropped) + ' dropped (no room)');
end;

procedure SayAll(const Text: ShortString);
var I, K, N: Integer; L: Word;
begin
  Said := Said mod 255 + 1;
  N := Length(Text);
  if N > 60 then N := 60;
  Head(CHATMSG);
  Tx[4] := SERVER_SLOT; Tx[5] := Said; Tx[6] := N;
  for K := 1 to N do Tx[6 + K] := Ord(Text[K]);
  L := 7 + N;
  for K := 1 to 3 do
    for I := 0 to LASTSLOT do
      if IsReceiver(I) then SendTo(I, L);
  RecOther(L);
  Log('SERVER says: ' + Copy(Text, 1, N));
end;

procedure Resume;
var I, K: Integer;
begin
  NextStep := Ticks;                   { the clock goes on from now }
  Head(PAUSEDP); Tx[4] := 0; Tx[5] := 0;
  for K := 1 to 3 do
    for I := 0 to LASTSLOT do
      if IsReceiver(I) then SendTo(I, 6);
end;

{ ------------------------------------- a joiner that cannot catch up (--joinwait) }

procedure GoOn(const Why: ShortString);
begin
  Log('going on at step ' + I2S(Newest + 1) + ': ' + Why);
  WaitFor := -1;
  if not Paused then Resume;
end;

{ Once a second: each joiner's gap.  One that will not be in within
  --joinwait, at the rate it is closing, holds the game; the game goes on
  once what is left can be closed in half that with it going -- 17.5 steps
  a second come on top (2026-10-17).  In whole numbers: Dt in ticks, a rate
  (WinGap - Gap) * T_SEC / Dt steps a second. }
procedure Joiners;
var
  I: Integer;
  T, Dt, Gap, Closed: LongInt;
begin
  T := Ticks;
  if (WaitFor >= 0) and (not Slots[WaitFor].Used or Slots[WaitFor].Present) then
    if Slots[WaitFor].Used then GoOn(Who(WaitFor) + ' is in the game')
    else GoOn('the one waited for has gone');
  for I := 0 to Players - 1 do
    with Slots[I] do
    begin
      if not Used or Bot or Present or not Ready or not HasPlayed or (Newest < 0) then
      begin
        HasWin := False;
        Continue;
      end;
      Gap := Newest - LongInt(Played);
      if Gap < 0 then Gap := 0;
      if not HasWin then
      begin
        HasWin := True; WinT := T; WinGap := Gap;
        Continue;
      end;
      Dt := T - WinT;
      if Dt <= 0 then Continue;
      Closed := WinGap - Gap;
      if WaitFor = I then
      begin
        if Dt < 3 * T_SEC then Continue;
        WinT := T; WinGap := Gap;
        { held: Closed*T_SEC/Dt is its own speed; less 17.5, the live gain }
        if (Gap <= 35) or ((2 * Closed * T_SEC > 35 * Dt)
           and (4 * Gap * Dt <= JoinWait * (2 * Closed * T_SEC - 35 * Dt))) then
          GoOn(Who(I) + ' has caught up enough (' + I2S(Closed * T_SEC div Dt)
               + ' steps a second, ' + I2S(Gap) + ' to go)');
      end
      else if (WaitFor < 0) and not Paused and (JoinWait > 0) then
      begin
        if Dt < 10 * T_SEC then Continue;
        WinT := T; WinGap := Gap;
        if (Closed <= 0) or (Gap * Dt > Closed * T_SEC * JoinWait) then
        begin
          WaitFor := I;
          NextPausedT := 0;
          if Closed <= 0 then
            Log('everyone waits for ' + Who(I) + ': ' + I2S(Gap) + ' steps behind, not gaining')
          else
            Log('everyone waits for ' + Who(I) + ': ' + I2S(Gap) + ' steps behind, '
                + I2S(Gap * Dt div (Closed * T_SEC)) + ' s to catch up at '
                + I2S(Closed * T_SEC div Dt) + ' steps a second gained');
        end;
      end;
    end;
end;

procedure SetPause(On: Boolean);
var I, K: Integer;
begin
  Paused := On;
  if On then
  begin
    NextPausedT := 0;
    Log('paused from the console at step ' + I2S(Newest + 1));
  end
  else
  begin
    Log('going again from the console at step ' + I2S(Newest + 1));
    if WaitFor < 0 then Resume
    else NextPausedT := 0;             { now the wait for the joiner, said }
  end;
end;

function AddEvent(Kind: Byte; Arg: Word): LongInt;
begin
  if NEv < MAXEV then
  begin
    Events[NEv].Step := Newest + 1;
    Events[NEv].Kind := Kind;
    Events[NEv].Arg := Arg;
    Inc(NEv);
  end;
  AddEvent := Newest + 1;
end;

var
  W: array[0..7] of string[63];   { a command's words (not 255 each: DGROUP, 2026-10-17) }
  NW: Integer;

procedure Split(const Line: ShortString);
var I: Integer;
begin
  NW := 0;
  for I := 0 to 7 do W[I] := '';
  I := 1;
  while I <= Length(Line) do
  begin
    while (I <= Length(Line)) and (Line[I] = ' ') do Inc(I);
    if I > Length(Line) then Break;
    if NW > 7 then Break;
    while (I <= Length(Line)) and (Line[I] <> ' ') do
    begin
      W[NW] := W[NW] + Line[I];
      Inc(I);
    end;
    Inc(NW);
  end;
end;

function Lower(const S: ShortString): ShortString;
var I: Integer; R: ShortString;
begin
  R := S;
  for I := 1 to Length(R) do
    if R[I] in ['A'..'Z'] then R[I] := Chr(Ord(R[I]) + 32);
  Lower := R;
end;

function NumW(const S: ShortString; var V: LongInt): Boolean;
var C: Integer;
begin
  Val(S, V, C);
  NumW := (S <> '') and (C = 0);
end;

function MapW(K: Integer; var N: LongInt): Boolean;   { E L, or N }
var E, L: LongInt;
begin
  MapW := False;
  if (NW > K + 1) and NumW(W[K], E) and NumW(W[K + 1], L) then
  begin
    if (E < 1) or (E > 6) or (L < 1) or (L > 10) then
    begin
      Say('episode 1-6, floor 1-10');
      Exit;
    end;
    N := (E - 1) * 10 + (L - 1);
    MapW := True;
  end
  else if (NW > K) and NumW(W[K], N) then
  begin
    if (N < 0) or (N > 59) then
    begin
      Say('map 0-59');
      Exit;
    end;
    MapW := True;
  end
  else Say('map E L, or map N');
end;

function SlotW(const S: ShortString): Integer;
var V: LongInt;
begin
  SlotW := -1;
  if NumW(S, V) and (V >= 1) and (V <= Players) and IsPerson(V - 1) then SlotW := V - 1;
end;

function RestFrom(const Line: ShortString; K: Integer): ShortString;
var I, N: Integer;
begin
  { the line after its first K words }
  I := 1; N := 0;
  while (I <= Length(Line)) and (N < K) do
  begin
    while (I <= Length(Line)) and (Line[I] = ' ') do Inc(I);
    while (I <= Length(Line)) and (Line[I] <> ' ') do Inc(I);
    Inc(N);
  end;
  while (I <= Length(Line)) and (Line[I] = ' ') do Inc(I);
  RestFrom := Copy(Line, I, 255);
end;

procedure Help;
begin
  Say('help                     this list');
  Say('status                   the game, and every slot');
  Say('say TEXT                 a message on every player''s screen, as SERVER');
  Say('scores                   every player''s frags and deaths, as the game has them');
  Say('kick N [reason]          slot N (1-4) out of the game; its screen says why');
  Say('ban N | ban ADDRESS      kick, and refuse that address from now on');
  Say('unban ADDRESS | bans     ... and back again; the list');
  Say('end [reason]             end the game for everyone');
  Say('pause | resume           hold the game for everyone, and let it go on');
  Say('map E L | map N          everyone to that floor now (the tally first)');
  Say('nextfloor                everyone to the next floor now');
  Say('timelimit MIN | fraglimit N   change the game''s limit now (0: none)');
  Say('next                     the settings the next game starts with');
  Say('next map E L | next map N    next mode coop|dm|tdm|ctf    next skill 0-3');
  Say('next bots N    next timelimit MIN    next fraglimit N    next itemrespawn SECS');
  Say('next enemies on|off      next ff on|off');
  Say('quiet on|off             the log''s lines off, or on again');
  Say('quit                     end the game and stop the server');
end;

procedure DoNext;
var
  V: LongInt;
  What: ShortString;
begin
  if NW < 2 then
  begin
    Say('now: ' + Settings);
    if Pending <> '' then Say('next game:' + Pending);
    Exit;
  end;
  What := Lower(W[1]);
  if What = 'map' then
  begin
    if not MapW(2, V) then Exit;
    NxMap := V;
  end
  else if What = 'mode' then
  begin
    NxMode := ModeOf(Lower(W[2]));
    if NxMode < 0 then begin Say('next mode: coop, dm, tdm or ctf'); Exit; end;
  end
  else if (What = 'skill') or (What = 'bots') or (What = 'timelimit') or (What = 'fraglimit')
          or (What = 'itemrespawn') then
  begin
    if not NumW(W[2], V) or (V < 0) or ((What = 'skill') and (V > 3))
       or ((What = 'itemrespawn') and (V > 155)) or (V > 65535) then
    begin
      Say('next ' + What + ': out of range');
      Exit;
    end;
    if What = 'skill' then NxSkill := V
    else if What = 'bots' then NxBots := V
    else if What = 'timelimit' then NxTime := V
    else if What = 'fraglimit' then NxFrag := V
    else NxResp := V;
  end
  else if (What = 'enemies') or (What = 'ff') then
  begin
    if Lower(W[2]) = 'on' then V := 1 else if Lower(W[2]) = 'off' then V := 0
    else begin Say('next ' + What + ': on or off'); Exit; end;
    if What = 'enemies' then NxEnemies := V else NxFF := V;
  end
  else
  begin
    Say('next what? -- try help');
    Exit;
  end;
  if not Playing then ApplyNext
  else Say('next game: ' + What + ' ' + RestFrom(W[0] + ' ' + W[1] + ' ' + W[2] + ' ' + W[3], 2));
end;

procedure DoNow(const Cmd: ShortString);
var
  V: LongInt;
  At: LongInt;
  What: ShortString;
begin
  if not Playing then
  begin
    Say(Cmd + ': no game is running -- for the next one, next ' + Cmd);
    Exit;
  end;
  if Cmd = 'map' then
  begin
    if not MapW(1, V) then Exit;
    At := AddEvent(EV_MAP, V);
    What := 'everyone to map ' + I2S(V) + ' (E' + I2S(V div 10 + 1) + 'L' + I2S(V mod 10 + 1) + ')';
  end
  else if Cmd = 'nextfloor' then
  begin
    At := AddEvent(EV_NEXTFLOOR, 0);
    What := 'everyone to the next floor';
  end
  else
  begin
    if not NumW(W[1], V) or (V < 0) or (V > 65535) then
    begin
      Say(Cmd + ': 0-65535');
      Exit;
    end;
    if Cmd = 'timelimit' then
    begin
      At := AddEvent(EV_TIMELIMIT, V);
      LiveTime := V;
    end
    else
    begin
      At := AddEvent(EV_FRAGLIMIT, V);
      LiveFrag := V;
    end;
    if V = 0 then What := Cmd + ' none' else What := Cmd + ' ' + I2S(V);
  end;
  if Paused then What := What + ' (when the game goes on)';
  Say(What + ', at step ' + I2S(At));
  Log('console: ' + What + ' at step ' + I2S(At));
end;

{ False on quit }
function DoLine(const Line: ShortString): Boolean;
var
  Cmd: ShortString;
  I, K: Integer;
  A: TIP;
  L: Word;
begin
  DoLine := True;
  Split(Line);
  if NW = 0 then Exit;
  Cmd := Lower(W[0]);
  if (Cmd = 'help') or (Cmd = '?') then Help
  else if (Cmd = 'status') or (Cmd = 'st') or (Cmd = 'players') then Status
  else if Cmd = 'say' then
  begin
    if NW < 2 then Say('say: what?') else SayAll(Copy(RestFrom(Line, 1), 1, 60));
  end
  else if Cmd = 'scores' then
  begin
    if not HaveScores then Say('scores: none yet -- the players send theirs every 50 steps')
    else
    begin
      Say('scores at step ' + I2S(ScoresStep) + ':');
      for I := 0 to Players - 1 do
        if Slots[I].Used then
          Say('  P' + I2S(I + 1) + '  ' + Pad(Slots[I].Name, 16) + ' ' + I2S(Scores[I, 0]) + ' frags  '
              + I2S(Scores[I, 1]) + ' deaths');
    end;
  end
  else if Cmd = 'kick' then
  begin
    I := SlotW(W[1]);
    if I < 0 then Say('kick: no person in slot ' + W[1])
    else if NW > 2 then Leave(I, 'was kicked from the console (' + RestFrom(Line, 2) + ')', BYE_KICKED, RestFrom(Line, 2))
    else Leave(I, 'was kicked from the console (no reason given)', BYE_KICKED, '');
  end
  else if (Cmd = 'pause') or (Cmd = 'resume') then
  begin
    if not Playing then Say(Cmd + ': no game is running')
    else if Paused = (Cmd = 'pause') then
    begin
      if Paused then Say('already paused') else Say('already going');
    end
    else SetPause(Cmd = 'pause');
  end
  else if (Cmd = 'map') or (Cmd = 'nextfloor') or (Cmd = 'timelimit') or (Cmd = 'fraglimit') then
    DoNow(Cmd)
  else if Cmd = 'ban' then
  begin
    if NW < 2 then
    begin
      Say('ban: a slot (1-4) or an address');
      Exit;
    end;
    I := SlotW(W[1]);
    if I >= 0 then A := Slots[I].IP
    else if not ParseIP(W[1], A) then
    begin
      Say('ban: a slot (1-4) or an address');
      Exit;
    end;
    if (NBanned < 16) and not Banned_(A) then
    begin
      Banned[NBanned] := A;
      Inc(NBanned);
    end;
    Say('banned ' + IPStr(A));
    for K := 0 to Players - 1 do
      if IsPerson(K) and SameIP(Slots[K].IP, A) then
        Leave(K, 'was banned from the console', BYE_KICKED, 'banned from this server');
  end
  else if Cmd = 'unban' then
  begin
    I := -1;
    if ParseIP(W[1], A) then
      for K := 0 to NBanned - 1 do
        if SameIP(Banned[K], A) then I := K;
    if I < 0 then Say('unban: not banned: ' + W[1])
    else
    begin
      Banned[I] := Banned[NBanned - 1];
      Dec(NBanned);
      Say('unbanned ' + W[1]);
    end;
  end
  else if Cmd = 'bans' then
  begin
    if NBanned = 0 then Say('banned: nobody')
    else for K := 0 to NBanned - 1 do Say('banned: ' + IPStr(Banned[K]));
  end
  else if Cmd = 'end' then
  begin
    if not Playing then Say('end: no game is running')
    else
    begin
      for K := 1 to 3 do
        for I := 0 to LASTSLOT do
          if IsReceiver(I) then
          begin
            L := ByeLen(I, BYE_END, '');
            SendTo(I, L);
          end;
      for I := 0 to LASTSLOT do
        if IsReceiver(I) then Slots[I].Used := False;
      if NW > 1 then GameOver('ended from the console (' + RestFrom(Line, 1) + ')')
      else GameOver('ended from the console');
      if StopNow then DoLine := False;
    end;
  end
  else if Cmd = 'debug' then
  begin
    for I := 0 to Players - 1 do
      Say('  P' + I2S(I + 1) + ' used ' + I2S(Ord(Slots[I].Used)) + ' port ' + I2S(Slots[I].Port)
          + ' sent ' + I2S(SentTo[I]) + ' last to port ' + I2S(LastDst[I]) + ' ip ' + IPStr(Slots[I].IP));
  end
  else if Cmd = 'next' then DoNext
  else if Cmd = 'quiet' then
  begin
    Quiet := Lower(W[1]) = 'on';
    if Quiet then Say('log off') else Say('log on');
  end
  else if (Cmd = 'quit') or (Cmd = 'exit') then
  begin
    Say('stopping');
    DoLine := False;
  end
  else Say('unknown: ' + Cmd + ' -- try help');
end;

{ a console line over the network (CtlPort), from the server's own subnet }
procedure HandleControl;
var
  Line: ShortString;
  K: Integer;
  Go: Boolean;
  I: Integer;
  Ok: Boolean;
begin
  Ok := True;
{$IFNDEF WINDOWS}
  for I := 0 to 3 do
    if (SnFromIP[I] and SnMask[I]) <> (SnMyIP[I] and SnMask[I]) then Ok := False;
{$ENDIF}
  if not Ok then Exit;
  Line := '';
  for K := 0 to RxLen - 1 do
    if (Length(Line) < 250) and (Rx[K] >= 32) then Line := Line + Chr(Rx[K]);
  Replying := True;
  ReplyLen := 0;
  Go := DoLine(Line);
  Replying := False;
  if ReplyLen = 0 then
  begin
    Line := '(done)';
    for K := 1 to Length(Line) do Reply[K - 1] := Line[K];
    ReplyLen := Length(Line);
  end;
  if ReplyLen > 0 then
  begin
    Move(Reply, Tx, ReplyLen);
    SendFrom(ReplyLen);
  end;
  if not Go then StopNow := True;
end;

{$IFNDEF WINDOWS}
procedure ShowStatus(Force: Boolean);
var
  T, Ppl: LongInt;
  I: Integer;
  S: ShortString;
begin
  T := Ticks div (T_SEC div 4);
  if (T = LastSpin) and not Force then Exit;
  LastSpin := T;
  Ppl := 0;
  for I := 0 to Players - 1 do if IsPerson(I) then Inc(Ppl);
  if Playing then S := 'step ' + I2S(Newest + 1) else S := 'waiting';
  if Paused then S := S + ' PAUSED';
  if WaitFor >= 0 then S := S + ' WAITING';
  S := SPIN[T and 3] + ' MPSRV ' + S + ', ' + I2S(Ppl) + ' in, rx ' + I2S(RecvN) + ' tx ' + I2S(SentN)
       + '  > ' + Typed;
  if Length(S) > 79 then S := Copy(S, Length(S) - 78, 79);
  StatusText := S;
  Write(StdErr, #13, Pad(S, 79), #13, S);
end;

procedure PollKeys;
var
  Ch: Char;
  Avail: Byte;
  K: Word;
begin
  repeat
    asm
      mov  ah, 1
      int  16h
      mov  Avail, 0
      jz   @@none
      mov  Avail, 1
    @@none:
    end;
    if Avail = 0 then Exit;
    asm
      mov  ah, 0
      int  16h
      mov  K, ax
    end;
    Ch := Chr(Lo(K));
    if Ch = #13 then
    begin
      ClearStatus;
      WriteLn('> ', Typed);
      if not DoLine(Typed) then StopNow := True;
      Typed := '';
    end
    else if Ch = #8 then
    begin
      if Length(Typed) > 0 then Delete(Typed, Length(Typed), 1);
    end
    else if Ch = #27 then Typed := ''
    else if Ch = #3 then
    begin
      Say('Ctrl-C: stopping');
      StopNow := True;
    end
    else if (Ch >= ' ') and (Length(Typed) < 70) then Typed := Typed + Ch;
    ShowStatus(True);
  until False;
end;

{$ELSE}
function SetConsoleTitleA(T: PChar): LongBool; stdcall; external 'kernel32.dll';
function GetStdHandle(N: LongWord): PtrUInt; stdcall; external 'kernel32.dll';
function ReadFile(H: PtrUInt; var Buf; N: LongWord; var Got: LongWord; Ov: Pointer): LongBool;
  stdcall; external 'kernel32.dll';
function SetConsoleCtrlHandler(H: Pointer; Add: LongBool): LongBool; stdcall; external 'kernel32.dll';

{ the status in the window's title, so it never gets in the way of typing }
procedure ShowStatus(Force: Boolean);
var
  T, Ppl: LongInt;
  I: Integer;
  S: ShortString;
begin
  T := Ticks div T_SEC;
  if (T = LastSpin) and not Force then Exit;
  LastSpin := T;
  Ppl := 0;
  for I := 0 to Players - 1 do if IsPerson(I) then Inc(Ppl);
  if Playing then S := 'step ' + I2S(Newest + 1) else S := 'waiting';
  if Paused then S := S + ' PAUSED';
  if WaitFor >= 0 then S := S + ' WAITING';
  S := 'MPSRV ' + SPIN[T and 3] + ' ' + S + ', ' + I2S(Ppl) + ' in, rx ' + I2S(RecvN) + ' tx '
       + I2S(SentN) + ', ' + I2S(Desyncs) + ' desyncs' + #0;
  SetConsoleTitleA(@S[1]);
end;

{ the console's lines: a thread reads them (from the window, or a pipe) and
  the server's loop carries them out, between packets }
const
  KQ = 16;
var
  KLines: array[0..KQ - 1] of ShortString;
  KHead, KTail: LongInt;
  KLock: TRTLCriticalSection;

function KeyReader(P: Pointer): PtrInt;
var
  Ch: Char;
  Got: LongWord;
  L: ShortString;
  H: PtrUInt;
begin
  H := GetStdHandle(LongWord(-10));        { STD_INPUT_HANDLE }
  L := '';
  while ReadFile(H, Ch, 1, Got, nil) and (Got = 1) do
    if Ch = #10 then
    begin
      EnterCriticalSection(KLock);
      if KHead - KTail < KQ then
      begin
        KLines[KHead mod KQ] := L;
        Inc(KHead);
      end;
      LeaveCriticalSection(KLock);
      L := '';
    end
    else if (Ch <> #13) and (Length(L) < 250) then L := L + Ch;
  KeyReader := 0;
end;

procedure PollKeys;
var
  L: ShortString;
  Got: Boolean;
begin
  repeat
    EnterCriticalSection(KLock);
    Got := KTail < KHead;
    if Got then
    begin
      L := KLines[KTail mod KQ];
      Inc(KTail);
    end;
    LeaveCriticalSection(KLock);
    if not Got then Exit;
    if not DoLine(L) then StopNow := True;
  until StopNow;
end;

{ Ctrl-C, Ctrl-Break, the window closed: stop as quit does -- everyone is
  told goodbye }
function CtrlHandler(Ctrl: LongWord): LongBool; stdcall;
begin
  StopNow := True;
  CtrlHandler := True;
end;

{$ENDIF}

{ ---------------------------------------------------------------- start-up }

function Arg(const Name: ShortString; Default: LongInt): LongInt;
var I: Integer; V: LongInt; C: Integer;
begin
  Arg := Default;
  for I := 1 to ParamCount - 1 do
    if Lower(ParamStr(I)) = Name then
    begin
      Val(ParamStr(I + 1), V, C);
      if C = 0 then Arg := V;
    end;
end;

function ArgS(const Name, Default: ShortString): ShortString;
var I: Integer;
begin
  ArgS := Default;
  for I := 1 to ParamCount - 1 do
    if Lower(ParamStr(I)) = Name then ArgS := Lower(ParamStr(I + 1));
end;

function ArgCase(const Name, Default: ShortString): ShortString;   { as typed }
var I: Integer;
begin
  ArgCase := Default;
  for I := 1 to ParamCount - 1 do
    if Lower(ParamStr(I)) = Name then ArgCase := Copy(ParamStr(I + 1), 1, 16);
end;

function ArgRaw(const Name: ShortString): ShortString;   { as typed, all of it }
var I: Integer;
begin
  ArgRaw := '';
  for I := 1 to ParamCount - 1 do
    if Lower(ParamStr(I)) = Name then ArgRaw := ParamStr(I + 1);
end;

function Flag(const Name: ShortString): Boolean;
var I: Integer;
begin
  Flag := False;
  for I := 1 to ParamCount do
    if Lower(ParamStr(I)) = Name then Flag := True;
end;

{ MPSRV /? (StevenC, 2026-10-16: "expand the /? help ... a descriptive comment on
  each option ... even examples").  Kept under 80 columns, for a DOS screen. }
procedure ShowHelp;
const
{$IFDEF WINDOWS}
  X = 'MPSRVW';
{$ELSE}
  X = 'MPSRV';
{$ENDIF}
begin
{$IFDEF WINDOWS}
  WriteLn('MPSRVW -- the Wolf3D multiplayer server for Windows -- StevenC & Claude');
{$ELSE}
  WriteLn('MPSRV -- the Wolf3D multiplayer server for DOS -- StevenC & Claude');
{$ENDIF}
  WriteLn;
  WriteLn('Hosts a WOLF3DM.EXE network game for up to four players: it keeps the');
  WriteLn('clock (17.5 steps a second), passes every player''s controls to everyone,');
  WriteLn('lets players join and leave at any time, and checks that every machine is');
  WriteLn('playing the same game.  The same server as mp/mpserver.py (Python).');
  WriteLn;
  WriteLn('usage: ', X, ' [options]       every option has a default -- none are needed');
  WriteLn;
  WriteLn('THE GAME                                                       (the default)');
  WriteLn('  --players N      slots in the game, 1 to 4, bots included          (4)');
  WriteLn('  --bots N         how many of the slots the server plays itself --  (0)');
  WriteLn('                   the last ones; they wander, open doors and fire');
  WriteLn('  --mode M         coop: together, against the enemies               (coop)');
  WriteLn('                   dm: deathmatch, everyone against everyone');
  WriteLn('                   tdm: team deathmatch -- Gold (P1, P3) against');
  WriteLn('                   Silver (P2, P4); a team''s frags are its score');
  WriteLn('                   ctf: capture the flag -- the same teams, a flag');
  WriteLn('                   at P1''s and P2''s start; the frag limit counts');
  WriteLn('                   captures');
  WriteLn('  --map N          the first floor: (episode-1)*10 + (floor-1),      (0: E1L1)');
  WriteLn('                   so 0-59 -- E2L1 is 10, E6L10 is 59');
  WriteLn('  --skill N        0 "can I play, daddy?" to 3 "I am death incarnate" (2)');
  WriteLn('  --noenemies      no enemies at all: an empty map, for deathmatch');
  WriteLn('  --ff on|off      friendly fire in co-op                            (on)');
  WriteLn('  --fraglimit N    deathmatch: the floor ends at N frags             (0: none)');
  WriteLn('  --timelimit MIN  a floor ends after MIN minutes                    (0: none)');
  WriteLn('  --itemrespawn S  a taken item comes back after S seconds, in steps of 5,');
  WriteLn('                   up to 155                 (30 in deathmatch, never in co-op)');
  WriteLn;
  WriteLn('THE SERVER');
  WriteLn('  --port N         the UDP port the game talks on; players then join (31992)');
  WriteLn('                   with PORT N');
  WriteLn('  --name NAME      what a game''s server list (WOLF3DM NET FIND) calls');
{$IFDEF WINDOWS}
  WriteLn('                   it, up to 16 letters                (MPSRVW (Windows))');
{$ELSE}
  WriteLn('                   it, up to 16 letters                     (MPSRV (DOS))');
{$ENDIF}
{$IFDEF WINDOWS}
  WriteLn('  --control N      the console port for python mp/mpctl.py, on       (31999)');
  WriteLn('                   127.0.0.1 only -- this PC; 0 turns it off');
{$ELSE}
  WriteLn('  --control N      the console port for python mp/mpctl.py --host,   (31999)');
  WriteLn('                   from any machine on this network; 0 turns it off');
{$ENDIF}
  WriteLn('  --drop-after S   a player not heard from for S seconds loses its   (60)');
  WriteLn('                   slot -- a WiFi dropout shorter than that is ridden out');
  WriteLn('  --joinwait S     a player joining late who would take more than S      (60)');
  WriteLn('                   seconds to catch up has everyone wait for them --');
  WriteLn('                   until the rest can be closed in S/2; 0: never wait');
  WriteLn('  --nosnap         a player joining late replays the game from the first');
  WriteLn('                   step -- not from a snapshot of it (the default)');
  WriteLn('  --once           stop when the game ends, instead of waiting for the next');
  WriteLn('  --record FILE    record each game, every floor, for WOLF3DM REPLAY FILE');
  WriteLn('                   (GAME.MPR; a second game is GAMEB.MPR, and so on)');
  WriteLn('  --steps N        stop after N steps -- for tests (a step is 1/17.5 s)');
  WriteLn('  --quiet          no log lines on the screen (MPSRV.LOG still gets them)');
{$IFNDEF WINDOWS}
  WriteLn('  --noxms          keep the game''s history in MPSRV.HIS on the disk, not in');
  WriteLn('                   XMS (it goes there anyway when there is no XMS)');
{$ENDIF}
  WriteLn('  --txgap US       microseconds to wait after each packet sent      (1000)');
  WriteLn('                   -- a PicoMEM card''s WiFi garbles packets sent back to');
  WriteLn('                   back; 0 for none, when no player has one');
  WriteLn;
  WriteLn('THE CONSOLE -- type a command and Enter while it runs (help lists them all),');
{$IFDEF WINDOWS}
  WriteLn('or from another window on this PC:  python mp/mpctl.py status');
{$ELSE}
  WriteLn('or from a PC on this network:  python mp/mpctl.py --host ADDRESS status');
{$ENDIF}
  WriteLn('  status   scores   say TEXT   kick N [reason]   ban N|ADDRESS   unban ADDRESS');
  WriteLn('  pause    resume   map E L    nextfloor   timelimit MIN   fraglimit N');
  WriteLn('  next ...   (the next game''s settings)    end   quiet on|off   quit');
  WriteLn;
  WriteLn('EXAMPLES');
  WriteLn('  ', X, ' --mode dm --noenemies');
  WriteLn('        deathmatch on E1L1 with no enemies, items back after 30 s');
  WriteLn('  ', X, ' --mode dm --noenemies --map 9 --timelimit 10 --fraglimit 25');
  WriteLn('        the secret floor of episode 1: 10 minutes or 25 frags a floor');
  WriteLn('  ', X, ' --players 4 --bots 2 --mode dm --noenemies');
  WriteLn('        two people and two server bots -- a full game from two machines');
  WriteLn('  ', X, ' --mode coop --skill 3 --map 20 --ff off');
  WriteLn('        co-op from E3L1 at the hardest skill, no friendly fire');
  WriteLn('  ', X, ' --mode coop --bots 1 --itemrespawn 60');
  WriteLn('        co-op with a server bot along; ammo and health back after a minute');
  WriteLn('  ', X, ' --port 31993 --control 31998');
  WriteLn('        a second server beside another; its players add PORT 31993');
  WriteLn;
  WriteLn('JOINING -- on each player''s machine, in the game''s directory:');
  WriteLn('  WOLF3DM NET <this machine''s address> NAME <a name>   (or PLAY, then M)');
{$IFDEF WINDOWS}
  WriteLn('Windows Firewall must let it in: allow it if Windows asks the first time.');
{$ELSE}
  WriteLn('It needs a packet driver and its address in mTCP''s config or C:\AI\NET.CFG.');
  WriteLn('A machine that serves cannot also play.   (', X, ' /? | MORE: a page at a time)');
{$ENDIF}
end;

procedure Cleanup;
var I, K: Integer; L: Word;
begin
  RecClose;
  for K := 1 to 5 do
  begin
    for I := 0 to LASTSLOT do
      if IsReceiver(I) then
      begin
        L := ByeLen(I, BYE_END, '');
        SendTo(I, L);
      end;
  end;
  TimerStop;
{$IFNDEF WINDOWS}
  SetIntVec($23, OldInt23);
{$ENDIF}
  SnClose;
  XmsDone;
  if UseFile then
  begin
    {$I-}
    Close(HisFile);
    Erase(HisFile);
    {$I+}
    if IOResult <> 0 then ;
  end;
  if LogOpen then
  begin
    {$I-}
    Close(LogF);
    {$I+}
    if IOResult <> 0 then ;
    LogOpen := False;
  end;
end;

var
  OldExit: CodePointer;

procedure AtExit;
begin
  ExitProc := OldExit;
  TimerStop;                     { whatever happened: the clock back as it was }
  SnClose;
  XmsDone;
end;

var
  T, NextT: LongInt;
  I, K: Integer;
  L: Word;
  RunFor: LongInt;
  Spins, GapUs: LongInt;
  Busy: Boolean;
begin
  { FPC 3.2.2's i8086 runtime: ParamStr is '' until ParamCount runs }
  if (ParamCount > 0) and ((ParamStr(1) = '/?') or (Lower(ParamStr(1)) = '/h')
     or (ParamStr(1) = '-?') or (Lower(ParamStr(1)) = '-h') or (Lower(ParamStr(1)) = '--help')
     or (Lower(ParamStr(1)) = 'help')) then
  begin
    ShowHelp;
    Halt(0);
  end;
{$IFDEF WINDOWS}
  WriteLn('MPSRVW -- the Wolf3D multiplayer server for Windows -- StevenC & Claude');
{$ELSE}
  WriteLn('MPSRV -- the Wolf3D multiplayer server for DOS -- StevenC & Claude');
{$ENDIF}
  Players := Arg('--players', 4);
  if Players < 1 then Players := 1;
  if Players > MAXP then Players := MAXP;
  MapNum := Arg('--map', 0);
  Skill := Arg('--skill', 2);
  Bots := Arg('--bots', 0);
  if Bots < 0 then Bots := 0;
  if Bots > Players - 1 then Bots := Players - 1;
  Humans := Players - Bots;
  Rules := 0;
  Rules2 := 0;
  I := ModeOf(Lower(ArgS('--mode', 'coop')));
  if I < 0 then begin WriteLn('--mode: coop, dm, tdm or ctf'); Halt(1); end;
  SetMode(I, Rules);
  if ArgS('--ff', 'on') = 'off' then Rules := Rules or RULE_NOFF;
  if Flag('--noenemies') then Rules := Rules or RULE_NOENEMIES;
  if Rules and RULE_DM <> 0 then Respawn := Arg('--itemrespawn', 30) else Respawn := Arg('--itemrespawn', 0);
  Rules := (Rules and 7) or RespawnBits(Respawn);
  Frags := Arg('--fraglimit', 0);
  Minutes := Arg('--timelimit', 0);
  GamePort := Arg('--port', 31992);
  CtlPort := Arg('--control', 31999);
  StepLimit := Arg('--steps', 0);
  Once := Flag('--once');
  RecPath := ArgRaw('--record');
{$IFDEF WINDOWS}
  ServerName := ArgCase('--name', 'MPSRVW (Windows)');
{$ELSE}
  ServerName := ArgCase('--name', 'MPSRV (DOS)');
{$ENDIF}
  Quiet := Flag('--quiet');
  DropAfter := Arg('--drop-after', 60) * T_SEC;
  JoinWait := Arg('--joinwait', 60);
  WaitFor := -1;
  NoSnap := Flag('--nosnap');
  SnapLen := 0; PullOn := False; SnapRest := 0;
  Snap := nil; PullBuf := nil;
  if not NoSnap then
  begin
    ReturnNilIfGrowHeapFails := True;
    GetMem(Snap, Word(SNAPMAX));        { (SizeOf: a 16-bit SizeInt, 49152 is out of it) }
    GetMem(PullBuf, Word(SNAPMAX));
    if (Snap = nil) or (PullBuf = nil) then NoSnap := True;
  end;
  NxMap := -1; NxSkill := -1; NxBots := -1; NxTime := -1; NxFrag := -1;
  NxResp := -1; NxMode := -1; NxEnemies := -1; NxFF := -1;
  NBanned := 0; Said := 0; Games := 0;
  Desyncs := 0; SentN := 0; RecvN := 0;
  Typed := ''; StopNow := False; Replying := False; LastSpin := -1;
  for I := 0 to MAXSUMBLK - 1 do SumBlks[I] := nil;
  for I := 0 to LASTSLOT do Slots[I].Used := False;

  if not SnReadConfig then
  begin
    WriteLn(SnErr);
    Halt(3);
  end;
  New(Ring);
  {$I-}
  Assign(LogF, 'MPSRV.LOG');
  Append(LogF);
  if IOResult <> 0 then Rewrite(LogF);
  {$I+}
  LogOpen := IOResult = 0;
{$IFNDEF WINDOWS}
  if (Seg(XMove) <> DSeg) or (Seg(XmsEntry) <> DSeg) then
  begin
    WriteLn('the XMS calls need their data in DS -- not starting');
    Halt(7);
  end;
{$ENDIF}
  if not Flag('--noxms') then XmsInit;     { --noxms: the file, to test it }
  UseFile := False;
{$IFNDEF WINDOWS}
  if not UseXms then
  begin
    Assign(HisFile, 'MPSRV.HIS');
    {$I-}
    Rewrite(HisFile, 1);
    {$I+}
    UseFile := IOResult = 0;
    if not UseFile then
    begin
      WriteLn('no XMS, and MPSRV.HIS cannot be written -- nowhere to keep the game');
      Halt(4);
    end;
  end;
{$ENDIF}
  SnSetPorts(GamePort, CtlPort);
  if not SnOpen then
  begin
    WriteLn('the network: ', SnErr);
    XmsDone;
    Halt(5);
  end;
  OldExit := ExitProc;
  ExitProc := @AtExit;
{$IFDEF WINDOWS}
  InitCriticalSection(KLock);
  KHead := 0; KTail := 0;
  BeginThread(@KeyReader, nil);
  SetConsoleCtrlHandler(@CtrlHandler, True);
{$ELSE}
  GetIntVec($23, OldInt23);
  SetIntVec($23, @Int23Isr);
{$ENDIF}
  if not TimerStart then
  begin
    SnClose;
    XmsDone;
    Halt(6);
  end;
{$IFNDEF WINDOWS}
  { the pause after each frame: SnSpin's loops in one 70 Hz tick, measured }
  T := Ticks;
  while Ticks = T do ;
  T := Ticks;
  Spins := 0;
  while Ticks = T do
  begin
    SnSpin(100);
    Inc(Spins);
  end;
  GapUs := Arg('--txgap', 1000);
  SnGapLoops := (Spins * GapUs) div 14286;    { blocks of 100 loops; a tick is 14,286 us }
  if (GapUs > 0) and (SnGapLoops = 0) then SnGapLoops := 1;
{$ELSE}
  Spins := 0;
  GapUs := Arg('--txgap', 1000);              { the same pause, on the performance counter: a
  SnGapUs := GapUs;                             PicoMEM joining late lost its catch-up to
                                                frames sent back to back (2026-10-16) }
{$ENDIF}
  ResetGame;
{$IFDEF WINDOWS}
  Log('MPSRVW on ' + IPStr(SnMyIP) + ' (Windows)');
  Log('after each frame a pause of ' + I2S(GapUs) + ' us (--txgap)');
  Log('the history in memory: room for ' + I2S(HistCapacity) + ' steps');
{$ELSE}
  Log('MPSRV on ' + IPStr(SnMyIP) + ' (' + SnCfgUsed + ', packet driver at ' + HexStr(SnVec, 2) + 'h)');
  if UseXms then Log('the history in XMS: ' + I2S(XmsKB) + ' KB, ' + I2S(HistCapacity) + ' steps')
  else Log('the history in MPSRV.HIS (no XMS)');
{$ENDIF}
  if Rules and RULE_NOENEMIES <> 0 then
    Log('listening on UDP ' + I2S(GamePort) + ': ' + I2S(Players) + ' slots (' + I2S(Humans) + ' for people, '
        + I2S(Bots) + ' bots), map ' + I2S(MapNum) + ', rules ' + I2S(Rules) + ' (' + Settings + ')')
  else
    Log('listening on UDP ' + I2S(GamePort) + ': ' + I2S(Players) + ' slots (' + I2S(Humans) + ' for people, '
        + I2S(Bots) + ' bots), map ' + I2S(MapNum) + ', rules ' + I2S(Rules) + ' (' + Settings + ')');
{$IFDEF WINDOWS}
  if CtlPort <> 0 then Log('console: this window, and UDP ' + I2S(CtlPort) + ' on 127.0.0.1 (python mp/mpctl.py)')
  else Log('console: this window');
{$ELSE}
  if CtlPort <> 0 then Log('console: the keyboard, and UDP ' + I2S(CtlPort) + ' from this subnet');
  Log('after each frame a pause of ' + I2S(GapUs) + ' us (' + I2S(SnGapLoops) + ' x 100 loops, '
      + I2S(Spins) + ' a tick; --txgap)');
{$ENDIF}
  NextStart := 0; NextNames := 0; NextPausedT := 0; NextJoin := 0; NextFeed := 0;

  repeat
    PollKeys;
    T := Ticks;
    if T >= NextStart then
    begin
      NextStart := T + T_SEC div 2;
      for I := 0 to LASTSLOT do
        if IsReceiver(I) and not Slots[I].Ready then SendTo(I, StartLen);
    end;
    if T >= NextNames then
    begin
      NextNames := T + 2 * T_SEC;
      L := NamesLen;
      for I := 0 to LASTSLOT do
        if IsReceiver(I) then SendTo(I, L);
    end;
    for I := 0 to LASTSLOT do
      if IsReceiver(I) then
        if Slots[I].Ready and (T - Slots[I].Heard > DropAfter) then
          Leave(I, 'was not heard from for ' + I2S((T - Slots[I].Heard) div T_SEC) + ' s: its slot is free',
                BYE_DROPPED, '')
        else if (not Slots[I].Ready) and (T - Slots[I].Heard > 60 * T_SEC) then
          Leave(I, 'never loaded the level: its slot is free', -1, '');
    if Playing and (T >= NextJoin) then
    begin
      NextJoin := T + T_SEC;
      Joiners;
    end;
    if PullOn then SnapPull;
    if Playing and (Paused or (WaitFor >= 0)) then
    begin
      if T >= NextPausedT then
      begin
        NextPausedT := T + T_SEC div 2;
        Head(PAUSEDP);
        if Paused then begin Tx[4] := 1; Tx[5] := 0; end
        else begin Tx[4] := 2; Tx[5] := WaitFor; end;
        for I := 0 to LASTSLOT do
          if IsReceiver(I) then SendTo(I, 6);
      end;
      if T - NextFeed >= 0 then          { a joiner's catch-up goes on }
      begin
        NextFeed := T + 4;
        SendSteps;
      end;
    end;
    if Playing and not Paused and (WaitFor < 0) then
      while (Ticks - NextStep >= 0) and Playing and not StopNow do
      begin
        if Newest + 1 >= HistCapacity then
        begin
          Log('the history is full: ' + I2S(Newest + 1) + ' steps');
          for K := 1 to 3 do
            for I := 0 to LASTSLOT do
              if IsReceiver(I) then SendTo(I, ByeLen(I, BYE_END, ''));
          for I := 0 to LASTSLOT do
            if IsReceiver(I) then Slots[I].Used := False;
          GameOver('the history is full');
          Break;
        end;
        MakeStep;
        Inc(NextStep, 4);
        if (StepLimit > 0) and (Newest + 1 >= StepLimit) then StopNow := True;
      end;
    Busy := False;
    while SnPoll(Rx, SizeOf(Rx), RxLen) do
    begin
      Busy := True;
      if SnToPort = GamePort then HandleGame
      else if (CtlPort <> 0) and (SnToPort = CtlPort) then HandleControl;
      if StopNow then Break;
    end;
    ShowStatus(False);
    LogTick;
    if not Busy and not StopNow then SnWait(1);   { Windows: a millisecond's sleep; DOS: nothing }
  until StopNow;

  ClearStatus;
  if Playing then
  begin
    RunFor := Ticks - StartedAt;
    if RunFor <= 0 then RunFor := 1;
    Log('ended: ' + I2S(Newest + 1) + ' steps in ' + Secs(RunFor) + ' s; packets sent ' + I2S(SentN)
        + ', received ' + I2S(RecvN) + '; ' + I2S(Desyncs) + ' desyncs');
    Log('  ' + NETNAME + ': ' + I2S(SnTxFrames) + ' frames sent, ' + I2S(SnTxRetried) + ' after a wait, '
        + I2S(SnTxFail) + ' refused; ' + I2S(SnDropped) + ' received frames dropped (no room), '
        + I2S(SnRxBadSum) + ' for a wrong checksum');
    for I := 0 to Players - 1 do
      if Slots[I].Used then
        Log('  ' + Who(I) + ': ' + I2S(Slots[I].Inputs) + ' inputs, had step ' + HaveStr(I));
  end
  else
    Log('ended with no game running; packets sent ' + I2S(SentN) + ', received ' + I2S(RecvN) + '; '
        + I2S(Desyncs) + ' desyncs');
  NextT := Ticks;
  Cleanup;
  ExitProc := OldExit;
end.
