{ W3MENU -- the detail switches menu for Wolfenstein 3-D (the NEC V30 build).
  Written by StevenC and Claude (Anthropic), 2026.

  PLAY.BAT runs it in a loop.  It shows the game's optional switches, each
  with a key that turns it on or off, and remembers them in W3MENU.CFG.
  + and - pick the game's window size, id's own Change View sizes 4-19
  (VIEW n; "the game's own" passes nothing, so CONFIG.WL6 decides).
  P (or Enter) writes W3RUN.BAT -- "WOLF3DV" and the switches -- and exits
  0, and PLAY.BAT runs that and comes back here; B does the same for the
  200-frame benchmark; Q or Esc exits 1, which ends PLAY.BAT.  So nothing
  of the menu is in memory while the game runs: every 4 KB it kept would
  be a page less for the game's cache.

  With no key for 30 seconds it quits by itself, so a menu nobody is at --
  or one started over the bridge -- never waits for ever.

    W3MENU [/T:secs] [/PLAY]     /T:0 waits for ever; /PLAY makes the
                                 timeout start the game instead of quitting
    W3MENU /CPU                  print this PC's processor and coprocessor
                                 on one line, and exit (SHOWCASE.BAT's)

  No Crt (it would take over the screen and stdout): text goes through
  DOS, keys come from the BIOS (INT 16h), the time from the BIOS tick.
  VidFix, for FPC's INT 10h hook on a 386 with no 387. }

program W3Menu;

uses Dos, Cpu, VidFix;

const
  NSW = 5;
  SwKey: array[1..NSW] of Char = ('W', 'S', 'F', 'V', 'R');
  SwName: array[1..NSW] of string[10] =
    ('LOWWALLS', 'LOWSPRITES', 'FLATWALLS', 'LOWVERT', 'FLATART');
  SwText: array[1..NSW] of string[48] =
    ('walls in two-pixel columns',
     'enemies and items in two-pixel columns',
     'every wall one solid colour, artwork kept',
     'half the vertical resolution',
     'artwork walls solid too (no textures)');
  CfgName = 'W3MENU.CFG';
  RunName = 'W3RUN.BAT';
  TicksPerDay = 1573040;

var
  SwOn: array[1..NSW] of Boolean;
  ViewSz: Integer;            { 4..19, or 0: the game's own setting }
  Timeout: Integer;           { seconds; 0 = never }
  TimeoutPlays: Boolean;

function Ticks: LongInt;
begin
  Ticks := MemL[$40:$6C];
end;

function KeyReady: Boolean;
var r: Registers;
begin
  r.ah := 1;
  Intr($16, r);
  KeyReady := (r.Flags and FZero) = 0;
end;

function GetKey: Char;
var r: Registers;
begin
  r.ah := 0;
  Intr($16, r);
  GetKey := UpCase(Chr(r.al));
end;

procedure ClearScreen;          { scroll the whole page away, cursor home: }
var r: Registers;               { no mode set, so mono and colour alike }
begin
  r.ax := $0600;
  r.bh := $07;
  r.cx := 0;
  r.dx := $184F;
  Intr($10, r);
  r.ah := $0F;                  { the active page, for the cursor }
  Intr($10, r);
  r.ah := $02;
  r.dx := 0;
  Intr($10, r);
end;

function Args: string;
var i: Integer; s, t: string;
begin
  s := '';
  for i := 1 to NSW do
    if SwOn[i] then s := s + ' ' + SwName[i];
  if ViewSz > 0 then
  begin
    Str(ViewSz, t);
    s := s + ' VIEW ' + t;
  end;
  Args := s;
end;

procedure LoadCfg;
var f: Text; s: string; i, code: Integer;
begin
  for i := 1 to NSW do SwOn[i] := False;
  ViewSz := 0;
  Assign(f, CfgName);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then Exit;
  s := '';
  if not Eof(f) then ReadLn(f, s);
  for i := 1 to NSW do
    SwOn[i] := (i <= Length(s)) and (s[i] = '1');
  s := '';
  if not Eof(f) then ReadLn(f, s);    { the window size, if one was picked }
  Close(f);
  Val(s, i, code);
  if (code = 0) and (i >= 4) and (i <= 19) then ViewSz := i;
end;

procedure SaveCfg;
var f: Text; i: Integer;
begin
  Assign(f, CfgName);
  {$I-} Rewrite(f); {$I+}
  if IOResult <> 0 then Exit;
  for i := 1 to NSW do
    if SwOn[i] then Write(f, '1') else Write(f, '0');
  WriteLn(f);
  WriteLn(f, ViewSz);
  Close(f);
end;

procedure WriteRun(bench: Boolean);
var f: Text;
begin
  Assign(f, RunName);
  Rewrite(f);
  WriteLn(f, '@ECHO OFF');
  WriteLn(f, 'REM Written by W3MENU (StevenC & Claude) for PLAY.BAT');
  if bench then
  begin
    WriteLn(f, 'WOLF3DV TIMEDEMO QUICK PRELOAD', Args);
    WriteLn(f, 'PAUSE');
  end
  else
    WriteLn(f, 'WOLF3DV', Args);
  Close(f);
end;

function Pad(const s: string; n: Integer): string;
var t: string;
begin
  t := s;
  while Length(t) < n do t := t + ' ';
  Pad := t;
end;

procedure Draw;
var i: Integer;
begin
  ClearScreen;
  WriteLn;
  WriteLn('  Wolfenstein 3-D  --  optimized by StevenC and Claude');
  WriteLn;
  WriteLn('  Press a switch''s key to turn it on or off:');
  WriteLn;
  for i := 1 to NSW do
  begin
    Write('    ', SwKey[i], '  [');
    if SwOn[i] then Write('X') else Write(' ');
    WriteLn('] ', Pad(SwName[i], 10), '  ', SwText[i]);
  end;
  Write('   +/-  window size:  ');
  if ViewSz = 0 then
    WriteLn('the game''s own (its Change View)')
  else
    WriteLn(ViewSz, '  (', ViewSz * 16, ' x ', ViewSz * 8, '; 0 for the game''s own)');
  WriteLn;
  WriteLn('    A  all on (the fastest)     N  all off (id''s own picture)');
  WriteLn;
  WriteLn('    P  play     B  benchmark these switches     Q  quit');
  WriteLn;
  WriteLn('  WOLF3DV', Args);
  WriteLn;
end;

procedure ShowLeft(secs: LongInt);
begin
  if Timeout = 0 then
    Write(#13'  Your choice: ')
  else if TimeoutPlays then
    Write(#13'  Your choice (plays by itself in ', secs:2, ' s): ')
  else
    Write(#13'  Your choice (quits by itself in ', secs:2, ' s): ');
end;

{ On a 386 or later, which: 3 if the AC flag (EFLAGS bit 18) will not
  toggle -- a 386 has none -- else 4, unless the ID flag (bit 21) toggles
  too, when CPUID gives the family.  32-bit code as bytes: FPC's i8086
  assembler takes no 32-bit registers.  The flags are put back as found. }
function Family386: Word; assembler;
asm
  db $66,$9C                    { pushfd }
  db $66,$58                    { pop eax }
  db $66,$89,$C1                { mov ecx,eax }
  db $66,$35,$00,$00,$04,$00    { xor eax,40000h -- AC }
  db $66,$50                    { push eax }
  db $66,$9D                    { popfd }
  db $66,$9C                    { pushfd }
  db $66,$58                    { pop eax }
  db $66,$51                    { push ecx }
  db $66,$9D                    { popfd: as found }
  db $66,$31,$C8                { xor eax,ecx }
  db $66,$A9,$00,$00,$04,$00    { test eax,40000h }
  mov ax,3
  jz @done
  db $66,$9C                    { pushfd }
  db $66,$58                    { pop eax }
  db $66,$89,$C1                { mov ecx,eax }
  db $66,$35,$00,$00,$20,$00    { xor eax,200000h -- ID }
  db $66,$50                    { push eax }
  db $66,$9D                    { popfd }
  db $66,$9C                    { pushfd }
  db $66,$58                    { pop eax }
  db $66,$51                    { push ecx }
  db $66,$9D                    { popfd: as found }
  db $66,$31,$C8                { xor eax,ecx }
  db $66,$A9,$00,$00,$20,$00    { test eax,200000h }
  mov ax,4
  jz @done
  push bx
  db $66,$B8,$01,$00,$00,$00    { mov eax,1 }
  db $0F,$A2                    { cpuid }
  pop bx
  mov al,ah
  xor ah,ah
  and al,$0F                    { the family }
@done:
end;

{ This PC's processor and coprocessor, for the showcase's screens. }
function CpuLine: string;
var s: string; f: Word;
begin
  f := 0;
  if CpuClass = cpu386 then
  begin
    f := Family386;
    case f of
      3: s := '80386';
      4: s := '80486';
      5: s := 'Pentium-class';
    else
      s := 'Pentium Pro or later';
    end;
  end
  else
    s := CpuName;
  if not HasFpu then
    s := s + ', no coprocessor'
  else if f >= 4 then
    s := s + ' with FPU'
  else
    s := s + ' with ' + FpuName;
  CpuLine := s;
end;

procedure ParseArgs;
var i, code, v: Integer; s: string;
begin
  Timeout := 30;
  TimeoutPlays := False;
  for i := 1 to ParamCount do
  begin
    s := ParamStr(i);
    if (Length(s) > 3) and (UpCase(s[2]) = 'T') and (s[3] = ':') then
    begin
      Val(Copy(s, 4, 5), v, code);
      if (code = 0) and (v >= 0) and (v <= 3600) then Timeout := v;
    end
    else if (UpCase(s[2]) = 'C') then
    begin
      WriteLn('  This PC:  ', CpuLine);   { /CPU: one line, and done }
      Halt(0);
    end
    else if (UpCase(s[2]) = 'P') then
      TimeoutPlays := True;
  end;
end;

var
  start, now, el, lastleft, left: LongInt;
  c: Char;
  i: Integer;

begin
  ParseArgs;
  LoadCfg;
  Draw;
  start := Ticks;
  lastleft := -1;
  repeat
    if KeyReady then
    begin
      c := GetKey;
      case c of
        'A': for i := 1 to NSW do SwOn[i] := True;
        'N': for i := 1 to NSW do SwOn[i] := False;
        '+', '=':
          if ViewSz = 0 then ViewSz := 15
          else if ViewSz < 19 then Inc(ViewSz);
        '-', '_':
          if ViewSz = 0 then ViewSz := 15
          else if ViewSz > 4 then Dec(ViewSz);
        '0': ViewSz := 0;               { back to the game's own setting }
        'P', #13:
          begin
            SaveCfg;
            WriteRun(False);
            WriteLn;
            Halt(0);
          end;
        'B':
          begin
            SaveCfg;
            WriteRun(True);
            WriteLn;
            Halt(0);
          end;
        'Q', #27:
          begin
            SaveCfg;
            WriteLn;
            Halt(1);
          end;
      else
        for i := 1 to NSW do
          if c = SwKey[i] then SwOn[i] := not SwOn[i];
      end;
      Draw;
      start := Ticks;           { a key restarts the countdown }
      lastleft := -1;
    end;
    now := Ticks;
    el := now - start;
    if el < 0 then el := el + TicksPerDay;     { past midnight }
    if Timeout = 0 then
      left := 0
    else
      left := Timeout - (el * 10) div 182;
    if left <> lastleft then
    begin
      ShowLeft(left);
      lastleft := left;
    end;
  until (Timeout > 0) and (left <= 0);
  SaveCfg;                      { the time is up }
  WriteLn;
  if TimeoutPlays then
  begin
    WriteRun(False);
    Halt(0);
  end;
  Halt(1);
end.
