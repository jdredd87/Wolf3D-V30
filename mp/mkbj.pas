{ MKBJ -- the network game's players as BJ, in four colours, built from the
  player's own data.  StevenC & Claude (Anthropic), 2026-10-23.

    MKBJ [folder]       VSWAP.WL6, .WL1 or .SOD in the folder (default: here)
                        -> VSWAPM.WL6 / .WL1 / .SOD beside it

  The same file mp/mkbj.py writes, byte for byte, for players without
  Python: the SS's 49 frames -- standing, walking, firing, pain, dying, the
  body -- with his cap turned into BJ's orange hair and his blue uniform
  into each player's colour (grey, green, red, brown), added after the data's
  own sprites.  WOLF3DM, WOLF3DM1 and SPEARM (and the Windows games) use the
  file when it is there; nothing of id's is changed, and a machine with it
  plays with one without.

  One source for DOS (Free Pascal i8086, any 8086 up: the data is read a
  chunk at a time, never whole) and Windows (i386-win32).  It reads the
  data and writes only the new file. }
program MkBJ;

{$I-}

const
  CLEAR = 255;                    { transparent in a frame }
  NFRAMES = 49;                   { the SS's frames, SPR_SS_S_1 on }
  NCOL = 4;
  MAXCHUNK = 1200;
  { the uniform's ramp (palette 140-159, bright to dark) and how blue each
    colour is in id's palette (mkbj.py's blueness: B when R and G are
    under 40, else 0); the navy blues 227, 228, 232 likewise }
  UNI0 = 140;
  UNIBLUE: array[0..19] of Byte = (0, 0, 252, 252, 252, 236, 224, 212, 200, 188,
                                   176, 164, 152, 136, 124, 112, 100, 88, 76, 64);
  BLUEMAX = 252;
  NAVY: array[0..2] of Byte = (227, 228, 232);
  NAVYBLUE: array[0..2] of Byte = (28, 44, 52);
  HAIR0 = 56;                     { BJ's hair: the orange ramp 56-63 }
  NHAIR = 8;
  CAPROWS = 8;
  { the players' ramps, in mkbj.py's order: P1 grey, P2 green, P3 red, P4 brown }
  RAMPLO: array[0..3] of Byte = (18, 97, 33, 208);
  RAMPN: array[0..3] of Byte = (13, 15, 15, 16);

type
  TImg = array[0..63, 0..63] of Byte;     { [x, y] }
  TBuf = array[0..8191] of Byte;

var
  Folder, Ext, InName, OutName: string;
  Fin, Fout: file;
  N, SprStart, SndStart: Word;
  Offs: array[0..MAXCHUNK - 1] of LongInt;
  Lens: array[0..MAXCHUNK - 1] of Word;
  NoChunk: array[0..MAXCHUNK - 1] of Boolean;   { offset 0: an empty slot }
  Runs: array[0..63, 0..31, 0..2] of Integer;   { Encode's posts: start, end, pixel offset }
  NRun: array[0..63] of Integer;
  NewLen: array[0..NCOL * NFRAMES - 1] of Word;
  Img, Built: TImg;
  Buf, Enc: TBuf;
  EncLen: Word;
  SSBase: Word;

procedure Fail(const S: string);
begin
  WriteLn('MKBJ: ', S);
  Halt(1);
end;

function Exists(const Name: string): Boolean;
var F: file;
begin
  Assign(F, Name);
  Reset(F, 1);
  Exists := IOResult = 0;
  Close(F);
  if IOResult <> 0 then ;
end;

function W(const B: TBuf; P: Word): Word;
begin
  W := B[P] or (Word(B[P + 1]) shl 8);
end;

procedure PutW(var B: TBuf; P, V: Word);
begin
  B[P] := Lo(V);
  B[P + 1] := Hi(V);
end;

procedure ReadAt(Pos: LongInt; Len: Word; var B: TBuf);
var Got: Word;
begin
  Seek(Fin, Pos);
  BlockRead(Fin, B, Len, Got);
  if (IOResult <> 0) or (Got <> Len) then Fail('cannot read ' + InName);
end;

{ a frame out of VSWAP's sprite format into Img (CLEAR where nothing) }
procedure Decode(K: Word);
var
  X, I, P, Y, Left, Right, Last, Start: Word;
  Corr: Integer;
begin
  FillChar(Img, SizeOf(Img), CLEAR);
  if (Offs[SprStart + K] = 0) or (Lens[SprStart + K] > SizeOf(Buf)) then
    Fail('frame missing in the data');
  ReadAt(Offs[SprStart + K], Lens[SprStart + K], Buf);
  Left := W(Buf, 0);
  Right := W(Buf, 2);
  I := 0;
  for X := Left to Right do
  begin
    P := W(Buf, 4 + 2 * I);
    while W(Buf, P) <> 0 do
    begin
      Last := W(Buf, P);
      Corr := Integer(W(Buf, P + 2));
      Start := W(Buf, P + 4);
      for Y := Start div 2 to Last div 2 - 1 do
        Img[X, Y] := Buf[Word(Corr + Integer(Y))];
      Inc(P, 6);
    end;
    Inc(I);
  end;
end;

function UniIndex(C: Byte): Integer;      { its place in the uniform ramp, or -1 }
begin
  if (C >= UNI0) and (C < UNI0 + 20) then UniIndex := C - UNI0 else UniIndex := -1;
end;

function Blueness(C: Byte): Word;
var I: Integer;
begin
  Blueness := 0;
  if UniIndex(C) >= 0 then Blueness := UNIBLUE[UniIndex(C)];
  for I := 0 to 2 do
    if C = NAVY[I] then Blueness := NAVYBLUE[I];
end;

function IsNavy(C: Byte): Boolean;
begin
  IsNavy := (C = NAVY[0]) or (C = NAVY[1]) or (C = NAVY[2]);
end;

function Skin(C: Byte): Boolean;
begin
  Skin := (C >= 192) and (C <= 223);
end;

{ SS -> BJ: down each column from the head's top, the cap's blues (and its
  black band) onto the orange ramp by brightness, stopping at the first
  pixel that is not cap and at an eye (blue between skin) -- mkbj.py's
  convert, the same order, the same arithmetic }
procedure Convert;
var
  X, Y, Top, H: Integer;
  C: Byte;
begin
  Built := Img;
  Top := 64;
  for Y := 0 to 63 do
    for X := 0 to 63 do
      if (Img[X, Y] <> CLEAR) and (Y < Top) then Top := Y;
  if Top = 64 then Exit;
  for X := 0 to 63 do
  begin
    Y := Top;
    while Y < Top + CAPROWS do
    begin
      if Y > 63 then Break;
      C := Built[X, Y];
      if C <> CLEAR then
      begin
        if not ((UniIndex(C) >= 0) or IsNavy(C) or (C = 0)) then Break;
        if (X > 0) and (X < 63) and Skin(Built[X - 1, Y]) and Skin(Built[X + 1, Y]) then Break;
        { mkbj.py: int((1 - b/bluemax) * len(hair)), exact in integers here }
        if C = 0 then H := NHAIR
        else H := (NHAIR * (BLUEMAX - Blueness(C))) div BLUEMAX;
        if H > NHAIR - 1 then H := NHAIR - 1;
        Built[X, Y] := HAIR0 + H;
      end;
      Inc(Y);
    end;
  end;
end;

{ Built through player Col's ramp into Img: the uniform ramp onto it by
  brightness, round(k * (len - 1) / 19) -- never a half, so no tie to break }
procedure Colour(Col: Integer);
var
  T: array[0..255] of Byte;
  I, K, L: Integer;
  X, Y: Integer;
begin
  for I := 0 to 255 do T[I] := I;
  L := RAMPN[Col];
  for K := 0 to 19 do
    T[UNI0 + K] := RAMPLO[Col] + (2 * K * (L - 1) + 19) div 38;
  for X := 0 to 63 do
    for Y := 0 to 63 do
      Img[X, Y] := T[Built[X, Y]];
end;

{ Img in VSWAP's sprite format into Enc: leftpix, rightpix, a column's
  offset each, the pixels, then each column's posts (end*2, pixel offset -
  start, start*2), 0-ended -- mkbj.py's encode }
procedure Encode;
var
  X, Y, S, Left, Right, Head, Px, NCols, I: Integer;
  Any: Boolean;
begin
  Left := -1;
  Right := -1;
  for X := 0 to 63 do
  begin
    Any := False;
    for Y := 0 to 63 do
      if Img[X, Y] <> CLEAR then Any := True;
    if Any then
    begin
      if Left < 0 then Left := X;
      Right := X;
    end;
  end;
  if Left < 0 then
  begin
    Left := 32;
    Right := 32;
  end;
  NCols := Right - Left + 1;
  Head := 4 + 2 * NCols;
  Px := Head;
  for X := Left to Right do
  begin
    NRun[X - Left] := 0;
    Y := 0;
    while Y < 64 do
    begin
      if Img[X, Y] = CLEAR then
      begin
        Inc(Y);
        Continue;
      end;
      S := Y;
      while (Y < 64) and (Img[X, Y] <> CLEAR) do
      begin
        Enc[Px] := Img[X, Y];
        Inc(Px);
        Inc(Y);
      end;
      Runs[X - Left, NRun[X - Left], 0] := S;
      Runs[X - Left, NRun[X - Left], 1] := Y;
      Runs[X - Left, NRun[X - Left], 2] := Px - (Y - S);
      Inc(NRun[X - Left]);
    end;
  end;
  PutW(Enc, 0, Left);
  PutW(Enc, 2, Right);
  for I := 0 to NCols - 1 do
  begin
    PutW(Enc, 4 + 2 * I, Px);
    for S := 0 to NRun[I] - 1 do
    begin
      PutW(Enc, Px, Runs[I, S, 1] * 2);
      PutW(Enc, Px + 2, Word(Runs[I, S, 2] - Runs[I, S, 0]));
      PutW(Enc, Px + 4, Runs[I, S, 0] * 2);
      Inc(Px, 6);
    end;
    PutW(Enc, Px, 0);
    Inc(Px, 2);
  end;
  if Px > 4096 then Fail('a frame came out over 4096 bytes');
  EncLen := Px;
end;

{ every colour's every frame, in mkbj.py's order: colour by colour }
procedure MakeSprite(J: Integer);
begin
  Decode(SSBase + J mod NFRAMES);
  Convert;
  Colour(J div NFRAMES);
  Encode;
end;

procedure BlockOut(var B; Len: Word);
var Put: Word;
begin
  BlockWrite(Fout, B, Len, Put);
  if (IOResult <> 0) or (Put <> Len) then Fail('cannot write ' + OutName);
end;

procedure Main;
var
  I, J, M, NewSnd: Word;
  K: LongInt;
  Pos, HeadLen: LongInt;
  Zero: array[0..511] of Byte;
  L4: LongInt;
  W2: Word;
  Left, Got: Word;
  None: Boolean;
begin
  WriteLn('MKBJ -- the players as BJ, from your own data -- StevenC & Claude');
  Folder := '';
  if ParamCount >= 1 then Folder := ParamStr(1);
  if (Folder <> '') and not (Folder[Length(Folder)] in ['\', '/', ':']) then
    Folder := Folder + '\';
  if Exists(Folder + 'VSWAP.WL6') then Ext := 'WL6'
  else if Exists(Folder + 'VSWAP.WL1') then Ext := 'WL1'
  else if Exists(Folder + 'VSWAP.SOD') then Ext := 'SOD'
  else Fail('no VSWAP.WL6, VSWAP.WL1 or VSWAP.SOD in ' + Folder + '.  MKBJ [folder]');
  if Ext = 'SOD' then SSBase := 142 else SSBase := 138;   { SPR_SS_S_1 (WL_DEF.H) }
  InName := Folder + 'VSWAP.' + Ext;
  OutName := Folder + 'VSWAPM.' + Ext;
  Assign(Fin, InName);
  Reset(Fin, 1);
  if IOResult <> 0 then Fail('cannot open ' + InName);
  ReadAt(0, 6, Buf);
  N := W(Buf, 0);
  SprStart := W(Buf, 2);
  SndStart := W(Buf, 4);
  if (N > MAXCHUNK - NCOL * NFRAMES) or (SndStart > N) or (SprStart + SSBase + NFRAMES > SndStart) then
    Fail(InName + ' is not the VSWAP this was made for');
  for I := 0 to N - 1 do
  begin
    ReadAt(6 + 4 * LongInt(I), 4, Buf);
    Offs[I] := LongInt(W(Buf, 0)) or (LongInt(W(Buf, 2)) shl 16);
  end;
  for I := 0 to N - 1 do
  begin
    ReadAt(6 + 4 * LongInt(N) + 2 * LongInt(I), 2, Buf);
    Lens[I] := W(Buf, 0);
    NoChunk[I] := Offs[I] = 0;            { (mkbj.py's None: offset 0, length 0) }
    if NoChunk[I] then Lens[I] := 0;
  end;
  WriteLn(InName, ': ', N, ' chunks, ', SndStart - SprStart, ' sprites');
  { pass 1: every new frame's length }
  for J := 0 to NCOL * NFRAMES - 1 do
  begin
    MakeSprite(J);
    NewLen[J] := EncLen;
  end;
  { the new header: the frames go in at the end of the sprites, before the
    sounds (whose list is relative to PMSoundStart) }
  M := N + NCOL * NFRAMES;
  NewSnd := SndStart + NCOL * NFRAMES;
  HeadLen := (6 + 6 * LongInt(M) + 511) and not LongInt(511);
  Assign(Fout, OutName);
  Rewrite(Fout, 1);
  if IOResult <> 0 then Fail('cannot make ' + OutName);
  PutW(Buf, 0, M);
  PutW(Buf, 2, SprStart);
  PutW(Buf, 4, NewSnd);
  BlockOut(Buf, 6);
  Pos := HeadLen;
  for K := 0 to M - 1 do            { the offsets }
  begin
    None := False;
    if K < SndStart then begin W2 := Lens[K]; None := NoChunk[K]; end
    else if K < NewSnd then W2 := NewLen[K - SndStart]
    else begin W2 := Lens[K - NCOL * NFRAMES]; None := NoChunk[K - NCOL * NFRAMES]; end;
    if None then L4 := 0 else L4 := Pos;
    Inc(Pos, W2);
    PutW(Buf, 0, Word(L4));
    PutW(Buf, 2, Word(L4 shr 16));
    BlockOut(Buf, 4);
  end;
  for K := 0 to M - 1 do            { the lengths }
  begin
    if K < SndStart then W2 := Lens[K]
    else if K < NewSnd then W2 := NewLen[K - SndStart]
    else W2 := Lens[K - NCOL * NFRAMES];
    PutW(Buf, 0, W2);
    BlockOut(Buf, 2);
  end;
  FillChar(Zero, SizeOf(Zero), 0);
  BlockOut(Zero, HeadLen - (6 + 6 * LongInt(M)));
  { pass 2: the chunks, in order -- id's copied, the frames made again }
  for K := 0 to M - 1 do
  begin
    if (K >= SndStart) and (K < NewSnd) then
    begin
      MakeSprite(K - SndStart);
      BlockOut(Enc, EncLen);
    end
    else
    begin
      if K < SndStart then I := K else I := K - NCOL * NFRAMES;
      if Lens[I] > 0 then
      begin
        Seek(Fin, Offs[I]);
        Left := Lens[I];
        while Left > 0 do
        begin
          if Left > SizeOf(Buf) then Got := SizeOf(Buf) else Got := Left;
          ReadAt(FilePos(Fin), Got, Buf);
          BlockOut(Buf, Got);
          Dec(Left, Got);
        end;
      end;
    end;
  end;
  Close(Fout);
  Close(Fin);
  if IOResult <> 0 then Fail('cannot finish ' + OutName);
  WriteLn(OutName, ': ', M, ' chunks; the players are sprites ', SndStart - SprStart, '-',
          SndStart - SprStart + NCOL * NFRAMES - 1, '.  The game uses it when it is there.');
end;

begin
  Main;
end.
