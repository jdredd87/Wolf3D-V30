{ W3MENU -- the detail switches menu for Wolfenstein 3-D on the NEC V30.
  Written by StevenC and Claude (Anthropic), 2026.

  PLAY.BAT runs it in a loop.  It shows the game's optional switches, each
  with a key that turns it on or off, and remembers them in W3MENU.CFG.
  P (or Enter) writes W3RUN.BAT -- "WOLF3DV" and the switches -- and exits
  0, and PLAY.BAT runs that and comes back here; B does the same for the
  200-frame benchmark; Q or Esc exits 1, which ends PLAY.BAT.  So nothing
  of the menu is in memory while the game runs: every 4 KB it kept would
  be a page less for the game's cache.

  With no key for 30 seconds it quits by itself, so a menu nobody is at --
  or one started over the bridge -- never waits for ever.

    W3MENU [/T:secs] [/PLAY]     /T:0 waits for ever; /PLAY makes the
                                 timeout start the game instead of quitting

  No Crt (it would take over the screen and stdout): text goes through
  DOS, keys come from the BIOS (INT 16h), the time from the BIOS tick.
  VidFix, for FPC's INT 10h hook on a 386 with no 387. }

program W3Menu;

uses Dos, VidFix;

const
  NSW = 4;
  SwKey: array[1..NSW] of Char = ('W', 'S', 'F', 'V');
  SwName: array[1..NSW] of string[10] =
    ('LOWWALLS', 'LOWSPRITES', 'FLATWALLS', 'LOWVERT');
  SwText: array[1..NSW] of string[40] =
    ('walls in two-pixel columns',
     'enemies and items in two-pixel columns',
     'every wall one solid colour',
     'half the vertical resolution');
  CfgName = 'W3MENU.CFG';
  RunName = 'W3RUN.BAT';
  TicksPerDay = 1573040;

var
  SwOn: array[1..NSW] of Boolean;
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
var i: Integer; s: string;
begin
  s := '';
  for i := 1 to NSW do
    if SwOn[i] then s := s + ' ' + SwName[i];
  Args := s;
end;

procedure LoadCfg;
var f: Text; s: string; i: Integer;
begin
  for i := 1 to NSW do SwOn[i] := False;
  Assign(f, CfgName);
  {$I-} Reset(f); {$I+}
  if IOResult <> 0 then Exit;
  s := '';
  if not Eof(f) then ReadLn(f, s);
  Close(f);
  for i := 1 to NSW do
    SwOn[i] := (i <= Length(s)) and (s[i] = '1');
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
  WriteLn('  Wolfenstein 3-D for the NEC V30  --  StevenC and Claude');
  WriteLn;
  WriteLn('  Press a switch''s key to turn it on or off:');
  WriteLn;
  for i := 1 to NSW do
  begin
    Write('    ', SwKey[i], '  [');
    if SwOn[i] then Write('X') else Write(' ');
    WriteLn('] ', Pad(SwName[i], 10), '  ', SwText[i]);
  end;
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
