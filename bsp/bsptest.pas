{ BSPTEST -- the grid walk against a BSP, on the same views of the same maps.
  StevenC & Claude, 2026.  Reads TABLES.DAT and BSPnn.DAT (from mkbsp.py).

  For each of the timedemo's four floors, 64 camera positions in the level's
  open cells, 240 columns each (id's projection, 240x120):

    WALK  Wolf's ray cast: per column the angle's tangent, the first x and y
          crossings by a fraction times the tangent, then crossing by
          crossing -- a tile test and a 32-bit add each -- to the first wall.
    BSP   Doom's way, as the SNES port of Wolf did it: a BSP of the level's
          wall runs, built offline; front to back, a subtree whose box is
          wholly behind the camera skipped, every run that faces the camera
          projected (two endpoints: four IMULs and a divide each), its
          columns claimed in a coverage mask, stopping when all 240 are
          claimed; then each column's intercept on its wall (one multiply),
          which the walk gets for free.

  Both are the same Pascal with the same assembler helpers, so their ratio
  is the algorithms', not the languages'.  Both also report which wall each
  column found, and the columns where they disagree are counted. }
program bsptest;

uses VidFix;

const
  MAXSEG = 1600;
  MAXNODE = 1300;
  NEARD = 16;             { the near plane, 1/16 tile }
  REPS = 2;

type
  TSeg = packed record orient: Byte; facing: ShortInt; line, a1, a2: Word; end;
  TNode = packed record
    axis, coord: Word; lo, hi: SmallInt; first, count: Word;
    bx1, by1, bx2, by2: SmallInt;
  end;
  TCam = packed record x, y, a: Word; end;
  TSegs = array[0..MAXSEG - 1] of TSeg;
  TNodes = array[0..MAXNODE - 1] of TNode;
  TSin = array[0..3599] of SmallInt;
  TTan = array[0..3599] of LongInt;
  TLR = packed record lo: Word; hi: SmallInt; end;

var
  segs: ^TSegs;
  nodes: ^TNodes;
  sinT: ^TSin;
  tanT: ^TTan;
  pix: array[0..239] of SmallInt;
  solidm: array[0..4095] of Byte;
  cams: array[0..63] of TCam;
  nseg, nnode, ncam, scale16: Word;
  hitO: array[0..239] of Byte;
  hitL, hitA: array[0..239] of SmallInt;
  cov: array[0..239] of Byte;
  owner: array[0..239] of Word;
  remain: Integer;
  stopflag: Boolean;
  ccos, csin, camx8, camy8: SmallInt;
  nsegproj, nnodevis: LongInt;
  sink: LongInt;

function Ticks: LongInt;
begin
  Ticks := MemL[$40:$6C];
end;

function Mul1616(a, b: SmallInt): LongInt; assembler;
asm
  mov ax,a
  imul b
end;

{ n div d, d > 0, the caller having made sure the quotient fits 16 bits }
function Div3216(n: LongInt; d: SmallInt): SmallInt; assembler;
asm
  mov ax,word ptr [n]
  mov dx,word ptr [n+2]
  idiv d
end;

{ (frac * v) >> 16, v signed: Wolf's FixedByFrac, two MULs }
function FracMul(frac: Word; v: LongInt): LongInt; assembler;
asm
  mov ax,word ptr [v]
  mov dx,word ptr [v+2]
  mov cx,dx
  or dx,dx
  jns @pos
  neg dx
  neg ax
  sbb dx,0
@pos:
  mov bx,dx
  mul frac
  mov ax,bx
  mov bx,dx
  mul frac
  add ax,bx
  adc dx,0
  or cx,cx
  jns @done
  neg dx
  neg ax
  sbb dx,0
@done:
end;

{ n >> 14, as a 16-bit value }
function Sh14(n: LongInt): SmallInt;
var t: LongInt;
begin
  t := n shl 2;
  Sh14 := TLR(t).hi;
end;

procedure Load(const name: string);
var f: file; magic: array[0..3] of Char; hdr: array[0..2] of Word; i: Integer;
begin
  Assign(f, name);
  Reset(f, 1);
  BlockRead(f, magic, 4);
  BlockRead(f, hdr, 6);
  nseg := hdr[0]; nnode := hdr[1]; ncam := hdr[2];
  BlockRead(f, solidm, 4096);
  BlockRead(f, segs^, nseg * SizeOf(TSeg));
  BlockRead(f, nodes^, nnode * SizeOf(TNode));
  BlockRead(f, cams, ncam * SizeOf(TCam));
  Close(f);
end;

procedure LoadTables;
var f: file; magic: array[0..3] of Char;
begin
  Assign(f, 'TABLES.DAT');
  Reset(f, 1);
  BlockRead(f, magic, 4);
  BlockRead(f, scale16, 2);
  BlockRead(f, pix, SizeOf(pix));
  BlockRead(f, sinT^, SizeOf(TSin));
  BlockRead(f, tanT^, SizeOf(TTan));
  Close(f);
end;

{ ---- the walk ---- }
procedure CastWalk(cx, cy: LongInt; a0: Integer);
var
  i, a, xs, ys, X, Y, tx, ty, cxl, cyl, idx: Integer;
  t, c, yint, xint, ystep, xstep: LongInt;
  xp, yp: Word;
begin
  tx := TLR(cx).hi;
  ty := TLR(cy).hi;
  for i := 0 to 239 do
  begin
    a := a0 + pix[i];
    if a < 0 then Inc(a, 3600) else if a >= 3600 then Dec(a, 3600);
    t := tanT^[a];
    idx := 900 - a;
    if idx < 0 then Inc(idx, 3600);
    c := tanT^[idx];
    if (a < 900) or (a > 2700) then xs := 1 else xs := -1;
    if (a > 0) and (a < 1800) then ys := -1 else ys := 1;
    if xs > 0 then
    begin
      X := tx + 1;
      xp := not TLR(cx).lo;
      yint := cy - FracMul(xp, t);
      ystep := -t;
    end
    else
    begin
      X := tx;
      xp := TLR(cx).lo;
      yint := cy + FracMul(xp, t);
      ystep := t;
    end;
    if ys > 0 then
    begin
      Y := ty + 1;
      yp := not TLR(cy).lo;
      xint := cx - FracMul(yp, c);
      xstep := -c;
    end
    else
    begin
      Y := ty;
      yp := TLR(cy).lo;
      xint := cx + FracMul(yp, c);
      xstep := c;
    end;
    repeat
      if ((ys > 0) and (TLR(yint).hi < Y)) or ((ys < 0) and (TLR(yint).hi >= Y)) then
      begin
        cxl := X;
        if xs < 0 then Dec(cxl);
        cyl := TLR(yint).hi;
        if (cxl < 0) or (cxl > 63) or (cyl < 0) or (cyl > 63) or (solidm[cxl * 64 + cyl] <> 0) then
        begin
          hitO[i] := 0; hitL[i] := X; hitA[i] := cyl;
          Break;
        end;
        Inc(X, xs);
        Inc(yint, ystep);
      end
      else
      begin
        cyl := Y;
        if ys < 0 then Dec(cyl);
        cxl := TLR(xint).hi;
        if (cxl < 0) or (cxl > 63) or (cyl < 0) or (cyl > 63) or (solidm[cxl * 64 + cyl] <> 0) then
        begin
          hitO[i] := 1; hitL[i] := Y; hitA[i] := cxl;
          Break;
        end;
        Inc(Y, ys);
        Inc(xint, xstep);
      end;
    until False;
  end;
end;

{ ---- the BSP ---- }
function ProjCol(side, depth: SmallInt): SmallInt;
var n, lim: LongInt;
begin
  n := Mul1616(side, scale16);
  lim := Mul1616(depth, 8000);
  if n >= lim then ProjCol := 8000
  else if n <= -lim then ProjCol := -8000
  else ProjCol := Div3216(n, depth);
end;

procedure ProjectSeg(s: Word);
var
  x1, y1, x2, y2, r1x, r1y, r2x, r2y, d1, d2, s1, s2, c1, c2, i1, i2, i, tmp: SmallInt;
begin
  Inc(nsegproj);
  with segs^[s] do
    if orient = 0 then
    begin x1 := line; y1 := a1; x2 := line; y2 := a2; end
    else
    begin x1 := a1; y1 := line; x2 := a2; y2 := line; end;
  r1x := x1 * 256 - camx8; r1y := y1 * 256 - camy8;
  r2x := x2 * 256 - camx8; r2y := y2 * 256 - camy8;
  d1 := Sh14(Mul1616(r1x, ccos) - Mul1616(r1y, csin));
  d2 := Sh14(Mul1616(r2x, ccos) - Mul1616(r2y, csin));
  if (d1 < NEARD) and (d2 < NEARD) then Exit;
  s1 := Sh14(Mul1616(r1x, csin) + Mul1616(r1y, ccos));
  s2 := Sh14(Mul1616(r2x, csin) + Mul1616(r2y, ccos));
  if d1 < NEARD then
  begin
    s1 := s1 + Div3216(Mul1616(s2 - s1, NEARD - d1), d2 - d1);
    d1 := NEARD;
  end
  else if d2 < NEARD then
  begin
    s2 := s2 + Div3216(Mul1616(s1 - s2, NEARD - d2), d1 - d2);
    d2 := NEARD;
  end;
  c1 := ProjCol(s1, d1);
  c2 := ProjCol(s2, d2);
  if c1 > c2 then begin tmp := c1; c1 := c2; c2 := tmp; end;
  i1 := (c1 + 120 * 16 + 7) div 16;          { the first column whose centre it covers }
  i2 := (c2 + 120 * 16 + 7) div 16;
  if i1 < 0 then i1 := 0;
  if i2 > 240 then i2 := 240;
  for i := i1 to i2 - 1 do
    if cov[i] = 0 then
    begin
      cov[i] := 1;
      owner[i] := s;
      Dec(remain);
    end;
  if remain = 0 then stopflag := True;
end;

procedure Visit(n: SmallInt);
var near, far: SmallInt; camc, cpos, bx, by, k: SmallInt;
begin
  if (n < 0) or stopflag then Exit;
  Inc(nnodevis);
  with nodes^[n] do
  begin
    { the box's deepest corner: behind the near plane, nothing in it shows }
    if ccos > 0 then bx := bx2 else bx := bx1;
    if csin > 0 then by := by1 else by := by2;
    if Sh14(Mul1616(bx * 256 - camx8, ccos) - Mul1616(by * 256 - camy8, csin)) < NEARD then Exit;
    if axis = 0 then camc := camx8 else camc := camy8;
    cpos := coord * 256;
    if camc < cpos then begin near := lo; far := hi; end
    else begin near := hi; far := lo; end;
    Visit(near);
    if stopflag then Exit;
    for k := first to first + count - 1 do
      with segs^[k] do
        if ((facing > 0) and (camc > cpos)) or ((facing < 0) and (camc < cpos)) then
        begin
          ProjectSeg(k);
          if stopflag then Exit;
        end;
    Visit(far);
  end;
end;

procedure RenderBSP(cx, cy: Word; a0: Integer);
var i, a: Integer;
begin
  camx8 := cx; camy8 := cy;
  ccos := sinT^[(a0 + 900) mod 3600];
  csin := sinT^[a0];
  FillChar(cov, SizeOf(cov), 0);
  remain := 240;
  stopflag := False;
  Visit(0);
  { each column's intercept on its wall: one multiply, as the walk's
    is free }
  for i := 0 to 239 do
  begin
    a := a0 + pix[i];
    if a < 0 then Inc(a, 3600) else if a >= 3600 then Dec(a, 3600);
    sink := sink + FracMul(Word(i * 251), tanT^[a]);
  end;
end;

function Match(i: Integer): Boolean;
begin
  Match := False;
  if cov[i] = 0 then Exit;
  with segs^[owner[i]] do
    Match := (orient = hitO[i]) and (line = Word(hitL[i])) and
             (hitA[i] >= SmallInt(a1)) and (hitA[i] < SmallInt(a2));
end;

const
  Files: array[1..4] of string[12] = ('BSP38.DAT', 'BSP44.DAT', 'BSP57.DAT', 'BSP32.DAT');

var
  fi, c, r, i: Integer;
  t0, tw, tb, bad, cols: LongInt;
  cx, cy: LongInt;
  ms: LongInt;
begin
  GetMem(segs, SizeOf(TSegs));
  GetMem(nodes, SizeOf(TNodes));
  GetMem(sinT, SizeOf(TSin));
  GetMem(tanT, SizeOf(TTan));
  LoadTables;
  WriteLn('BSPTEST -- the grid walk against a BSP, 240 columns -- StevenC & Claude');
  WriteLn('floor  segs nodes   walk ms   bsp ms   bsp/walk  runs/view nodes/view  columns that differ');
  for fi := 1 to 4 do
  begin
    Load(Files[fi]);
    t0 := Ticks;
    for r := 1 to REPS do
      for c := 0 to ncam - 1 do
      begin
        cx := LongInt(cams[c].x) shl 8;
        cy := LongInt(cams[c].y) shl 8;
        CastWalk(cx, cy, cams[c].a);
      end;
    tw := Ticks - t0;
    t0 := Ticks;
    for r := 1 to REPS do
      for c := 0 to ncam - 1 do
        RenderBSP(cams[c].x, cams[c].y, cams[c].a);
    tb := Ticks - t0;
    bad := 0; cols := 0; nsegproj := 0; nnodevis := 0;
    for c := 0 to ncam - 1 do
    begin
      cx := LongInt(cams[c].x) shl 8;
      cy := LongInt(cams[c].y) shl 8;
      CastWalk(cx, cy, cams[c].a);
      RenderBSP(cams[c].x, cams[c].y, cams[c].a);
      for i := 0 to 239 do
      begin
        Inc(cols);
        if not Match(i) then Inc(bad);
      end;
    end;
    Write(Copy(Files[fi], 4, 2):5, nseg:6, nnode:6);
    ms := tw * 5493 div (REPS * ncam);
    Write(ms div 100:7, '.', (ms mod 100) div 10);
    ms := tb * 5493 div (REPS * ncam);
    Write(ms div 100:8, '.', (ms mod 100) div 10);
    if tw > 0 then Write((tb * 100) div tw:9, '%') else Write('        -');
    Write(nsegproj div ncam:10, nnodevis div ncam:11);
    WriteLn(bad:10, ' of ', cols);
  end;
  if sink = 12345 then WriteLn;
end.
