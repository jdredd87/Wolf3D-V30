	IDEAL
	MODEL	MEDIUM,C
	P186				; NEC V30 build: the V30 runs the 80186 set
	JUMPS				; out-of-range Jcc become Jcc-around-JMP; in-range ones are untouched

SCREENSEG	=	0a000h
SC_INDEX	=	03c4h

FINEANGLES	=	3600
DEG90		=	900
DEG180		=	1800
DEG270		=	2700
DEG360		=	3600

OP_JLE		=	07eh
OP_JGE		=	07dh
OP_INCBX	=	043h			; NEC V30 build: the tile steps, patched per ray
OP_DECBX	=	04bh
OP_INCBP	=	045h
OP_DECBP	=	04dh
OP_JG		=	07fh			; the loop-bottom tests, the inverse of OP_JLE/OP_JGE
OP_JL		=	07ch
OP_INCDX	=	042h			; T += ytilestep in the horizontal step
OP_DECDX	=	04ah

EXTRN	finetangent:DWORD	; far array, starts at offset 0

EXTRN	HitHorizDoor:FAR
EXTRN	HitVertDoor:FAR
EXTRN	HitHorizPWall:FAR
EXTRN	HitVertPWall:FAR
EXTRN	ScaleShape:FAR
EXTRN	PM_GetPage:FAR
EXTRN	RunPage:FAR				; WL_BSP.C, for DrawRunA: a new tile's page
EXTRN	GetBonus:FAR
EXTRN	CalcRotate:FAR
EXTRN	RemoveObj:FAR
EXTRN	SightPlayer:FAR				; step 63: the AI's calls into id's C
EXTRN	OpenDoor:FAR
EXTRN	TakeDamage:FAR
EXTRN	BadWalkDir:FAR				; WL_STATE.C: Quit ("Walk: Bad dir")
EXTRN	BadMoveDir:FAR				; WL_STATE.C: Quit ("MoveObj: bad dir!")
EXTRN	TPathHitWall:FAR			; WL_ACT2.C: T_Path's sprintf and Quit
EXTRN	NOLANGUAGE F_LDIV@:FAR		; Borland's signed long divide (H_LDIV.ASM)


DATASEG

EXTRN	viewwidth:WORD
EXTRN	viewheight:WORD				; step 81
EXTRN	lowvert:WORD				; step 82
EXTRN	flatbuf:WORD				; step 84: FLATWALLS' buffer (a locked memptr)
EXTRN	solidart:WORD				; step 84: 1 with FLATART
EXTRN	pixstep:WORD				; step 79: 1, or 2 for LOWDETAIL
EXTRN	mapsegs:WORD				; unsigned _seg *mapsegs[MAPPLANES]
EXTRN	farmapylookup:WORD			; unsigned [MAPSIZE]: y*64
EXTRN	doorobjlist:BYTE			; doorobj_t [MAXDOORS], 9 bytes each

EXTRN	tilemap:BYTE
EXTRN	spotvis:BYTE
EXTRN	vismark:BYTE
EXTRN	pixelangle:WORD


EXTRN	midangle:WORD
EXTRN	angle:WORD

EXTRN	focaltx:WORD
EXTRN	focalty:WORD
EXTRN	viewtx:WORD
EXTRN	viewty:WORD
EXTRN	viewx:DWORD
EXTRN	viewy:DWORD
EXTRN	viewcos:DWORD			; sign-magnitude: bit 31 sign, low word fraction
EXTRN	viewsin:DWORD
EXTRN	mindist:DWORD
EXTRN	heightnumerator:DWORD
EXTRN	vislist:WORD			; visobj_t vislist[]: viewx, viewheight, shapenum
EXTRN	visptr:WORD
EXTRN	visstep:WORD
EXTRN	farthest:WORD
EXTRN	statobjlist:WORD		; statobj_t statobjlist[], 8 bytes each
EXTRN	laststatobj:WORD
EXTRN	player:WORD				; objtype *player
EXTRN	centerx:WORD
EXTRN	scale:DWORD				; fixed: a long

ttgx	dd	?					; TransformTile's working values
ttgy	dd	?
ttnx	dd	?
ttny	dd	?
EXTRN	lastside:WORD			; the wall-post state HitVertWall/HitHorizWall keep
EXTRN	lastintercept:DWORD
EXTRN	lasttilehit:WORD
EXTRN	postsource:DWORD
EXTRN	postx:WORD
EXTRN	postwidth:WORD
EXTRN	vertwall:WORD
EXTRN	horizwall:WORD
EXTRN	PMSpriteStart:WORD		; DOORWALL is PMSpriteStart-8

EXTRN	xpartialup:WORD
EXTRN	ypartialup:WORD
EXTRN	xpartialdown:WORD
EXTRN	ypartialdown:WORD

EXTRN	tilehit:WORD
EXTRN	pixx:WORD
EXTRN	wallheight:WORD			; array of VIEWWIDTH entries
EXTRN	maxscaleshl2:WORD
EXTRN	fullscalefarcall:DWORD
EXTRN	bufferofs:WORD
EXTRN	mapmasks1:BYTE
EXTRN	mapmasks2:BYTE
EXTRN	mapmasks3:BYTE

EXTRN	xtile:WORD
EXTRN	ytile:WORD
EXTRN	xtilestep:WORD
EXTRN	ytilestep:WORD
EXTRN	xintercept:DWORD
EXTRN	yintercept:DWORD
EXTRN	xstep:DWORD
EXTRN	ystep:DWORD

EXTRN	doorposition:WORD		; table of door position values
EXTRN	plux:WORD				; the player's x and y in 1/256 tiles
EXTRN	areabyplayer:WORD		; boolean[NUMAREAS] -- enums are words here
EXTRN	tics:WORD
EXTRN	actorat:WORD			; objtype *actorat[64][64] -- near pointers
EXTRN	pluy:WORD


EXTRN	pwallpos:WORD			; amound a pushable wall has been moved

curquad		dw	0				; NEC V30 build: the quadrant the loop is patched for
chvkey		dw	8000h			; CalcHeightV's last xintercept (high word) and gxt,
chvgxlo		dw	0				; CalcHeightH's last yintercept and gyt; 8000h
chvgxhi		dw	0				; matches no intercept, so a frame starts empty
chhkey		dw	8000h
chhgylo		dw	0
chhgyhi		dw	0
tsave		dw	0				; T, across a door or pushwall test
yadj		dw	64				; xtilestep<<6, as added into vyadc's word
lastkey		dw	0FFFFh			; step 51: tilehit<<7 | side<<6 | tile of the last
	PUBLIC	lastkey					; wall post, or FFFFh (C invalidates it)
;
; step 62: the band of rows VGAClearScreen leaves to the walls
;
postmin		dw	0				; the least scale*4 of the frame's wall posts
	PUBLIC	postmin					; (0 until a frame has been drawn: no band)
bandlim		dw	0				; B*4, B the band's half height; 0 for no band
	PUBLIC	bandlim
bandhalf	dw	0				; B
	PUBLIC	bandhalf
bandtop		dw	0				; (half-B)*80, the band's first row
	PUBLIC	bandtop
ceilcolor	dw	0				; the level's ceiling colour (both bytes)
	PUBLIC	ceilcolor
fixn		dw	0				; a short post's rows to fill, each side
fixofs2		dw	0				; and where its floor part starts
; step 63: a direction's step in x and in y -- east, northeast, north,
; northwest, west, southwest, south, southeast
dirdx		db	1,1,0,-1,-1,-1,0,1
dirdy		db	0,-1,-1,-1,0,1,1,1
clx1		dw	0				; CheckLine's working storage
visord		dw	50 DUP (0)		; DrawVisList's drawing order (MAXVISABLE entries)
cly1		dw	0
clhalf		dw	0
clend		dw	0

CODESEG


;============================
;
; CalcHeight
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's CalcHeight, moved here.  It
; runs once per ray.  The C version built a stack frame, pushed eight words
; for two far-style calls to FixedByFrac and spilled every intermediate to
; the stack; this does the same arithmetic in registers, bit for bit:
;
;	gxt = FixedByFrac (xintercept-viewx, viewcos)
;	gyt = FixedByFrac (yintercept-viewy, viewsin)
;	nx  = max (gxt-gyt, mindist)
;	return heightnumerator / (int)(nx>>8)		; one IDIV, as before
;
; FixedByFrac(a,b): |a| * (low word of b) >> 16, negated if exactly one of
; a and b (bit 31) is negative -- the low word of the low product dropped,
; exactly as the C routine does it.
;
;============================

MACRO	FIXBYFRAC	frac
	LOCAL	pos,done
	mov	cx,dx				; cx:ax = a (it arrives in dx:ax)
	mov	si,[WORD frac+2]	; sign of the result = sign of the fraction...
	or	cx,cx
	jns	pos
	neg	cx
	neg	ax
	sbb	cx,0
	xor	si,8000h			; ...toggled when a is negative
pos:
	mov	bx,[WORD frac]
	mul	bx					; fraction*fraction
	mov	di,dx				; keep only its high word
	mov	ax,cx
	mul	bx					; units*fraction
	add	ax,di
	adc	dx,0
	test	si,8000h
	jz	done
	neg	dx
	neg	ax
	sbb	dx,0
done:
ENDM

; The same, with the fraction's two words as immediates that AsmRefresh
; patches in once a frame (at signlab+1 and fraclab+1: BE iw, BB iw).
MACRO	FIXBYFRACI	signlab,fraclab
	LOCAL	pos,done
	mov	cx,dx
signlab:
	mov	si,1234h
	or	cx,cx
	jns	pos
	neg	cx
	neg	ax
	sbb	cx,0
	xor	si,8000h
pos:
fraclab:
	mov	bx,1234h
	mul	bx
	mov	di,dx
	mov	ax,cx
	mul	bx
	add	ax,di
	adc	dx,0
	test	si,8000h
	jz	done
	neg	dx
	neg	ax
	sbb	dx,0
done:
ENDM

; The same with the sign in BP, for CalcHeightV and CalcHeightH (step 61):
; their callers need SI back and nothing else, so they keep no registers.
MACRO	FIXBYFRACB	signlab,fraclab
	LOCAL	pos,done
	mov	cx,dx
signlab:
	mov	bp,1234h
	or	cx,cx
	jns	pos
	neg	cx
	neg	ax
	sbb	cx,0
	xor	bp,8000h
pos:
fraclab:
	mov	bx,1234h
	mul	bx
	mov	di,dx
	mov	ax,cx
	mul	bx
	add	ax,di
	adc	dx,0
	test	bp,8000h
	jz	done
	neg	dx
	neg	ax
	sbb	dx,0
done:
ENDM

; NEC V30 build: viewx, viewy, viewcos, viewsin, mindist and heightnumerator
; do not change during a frame, so they are immediates here, patched in by
; AsmRefresh before it traces the first ray (the 1234h placeholders force
; the imm16 encodings being patched; the offsets are checked in the
; listing).  The asm hit routines call CalcHeightN; id's C door and pushwall
; routines, which are only ever called from inside AsmRefresh, call the FAR
; CalcHeight.

PROC	CalcHeightN NEAR
	push	si
	push	di

	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
chvxlo:
	sub	ax,1234h				; viewx, low word (2D iw: at +1)
chvxhi:
	sbb	dx,1234h				; high word (81 DA iw: at +2)
	FIXBYFRACI	chcossign,chcosfrac	; dx:ax = gxt
	push	dx
	push	ax

	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
chvylo:
	sub	ax,1234h				; viewy
chvyhi:
	sbb	dx,1234h
	FIXBYFRACI	chsinsign,chsinfrac	; dx:ax = gyt

	pop	bx
	pop	cx					; cx:bx = gxt
	sub	bx,ax
	sbb	cx,dx				; cx:bx = nx = gxt-gyt

chmdhi:
	cmp	cx,1234h			; if (nx < mindist) nx = mindist -- signed (81 F9 iw)
	jg	@@distok
	jl	@@clamp
chmdlo:
	cmp	bx,1234h			; (81 FB iw)
	jae	@@distok
@@clamp:
chmdlo2:
	mov	bx,1234h			; (BB iw)
chmdhi2:
	mov	cx,1234h			; (B9 iw)
@@distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
chhnlo:
	mov	ax,1234h			; heightnumerator (B8 iw)
chhnhi:
	mov	dx,1234h			; (BA iw)
	idiv	bx

	pop	di
	pop	si
	ret
ENDP

;
; NEC V30 build: the same for the ray loop's wall hits, which know more.  A
; vertical wall's columns all hit at one xintercept -- the wall's plane,
; low word 0 -- so CalcHeightV remembers gxt against xintercept's high word
; and a column along the same wall reuses it, two MULs fewer; CalcHeightH
; does the same with gyt for a horizontal wall.  Each has its own patched
; immediates, so neither calls anything.  AsmRefresh forgets both at the
; start of every frame, as the view has changed.
;
PROC	CalcHeightV NEAR
								; (step 61: nothing kept; the sign is in BP)
	mov	ax,[WORD xintercept+2]
	cmp	ax,[chvkey]
	jne	@@miss
	mov	ax,[chvgxlo]			; dx:ax = gxt, as for the last column
	mov	dx,[chvgxhi]
@@have:
	push	dx
	push	ax

	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
cvvylo:
	sub	ax,1234h				; viewy
cvvyhi:
	sbb	dx,1234h
	FIXBYFRACB	cvsinsign,cvsinfrac	; dx:ax = gyt

	pop	bx
	pop	cx					; cx:bx = gxt
	sub	bx,ax
	sbb	cx,dx				; cx:bx = nx = gxt-gyt

cvmdhi:
	cmp	cx,1234h			; if (nx < mindist) nx = mindist -- signed (81 F9 iw)
	jg	@@distok
	jl	@@clamp
cvmdlo:
	cmp	bx,1234h			; (81 FB iw)
	jae	@@distok
@@clamp:
cvmdlo2:
	mov	bx,1234h			; (BB iw)
cvmdhi2:
	mov	cx,1234h			; (B9 iw)
@@distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
cvhnlo:
	mov	ax,1234h			; heightnumerator (B8 iw)
cvhnhi:
	mov	dx,1234h			; (BA iw)
	idiv	bx

	ret

@@miss:
	mov	[chvkey],ax
	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
cvvxlo:
	sub	ax,1234h				; viewx, low word (2D iw: at +1)
cvvxhi:
	sbb	dx,1234h				; high word (81 DA iw: at +2)
	FIXBYFRACB	cvcossign,cvcosfrac	; dx:ax = gxt
	mov	[chvgxlo],ax
	mov	[chvgxhi],dx
	jmp	@@have
ENDP

PROC	CalcHeightH NEAR
								; (step 61: nothing kept; the sign is in BP)
	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
czvxlo:
	sub	ax,1234h				; viewx, low word (2D iw: at +1)
czvxhi:
	sbb	dx,1234h				; high word (81 DA iw: at +2)
	FIXBYFRACB	czcossign,czcosfrac	; dx:ax = gxt
	push	dx
	push	ax

	mov	ax,[WORD yintercept+2]
	cmp	ax,[chhkey]
	jne	@@miss
	mov	ax,[chhgylo]			; dx:ax = gyt, as for the last column
	mov	dx,[chhgyhi]
@@have:
	pop	bx
	pop	cx					; cx:bx = gxt
	sub	bx,ax
	sbb	cx,dx				; cx:bx = nx = gxt-gyt

czmdhi:
	cmp	cx,1234h			; if (nx < mindist) nx = mindist -- signed (81 F9 iw)
	jg	@@distok
	jl	@@clamp
czmdlo:
	cmp	bx,1234h			; (81 FB iw)
	jae	@@distok
@@clamp:
czmdlo2:
	mov	bx,1234h			; (BB iw)
czmdhi2:
	mov	cx,1234h			; (B9 iw)
@@distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
czhnlo:
	mov	ax,1234h			; heightnumerator (B8 iw)
czhnhi:
	mov	dx,1234h			; (BA iw)
	idiv	bx

	ret

@@miss:
	mov	[chhkey],ax
	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
czvylo:
	sub	ax,1234h				; viewy
czvyhi:
	sbb	dx,1234h
	FIXBYFRACB	czsinsign,czsinfrac	; dx:ax = gyt
	mov	[chhgylo],ax
	mov	[chhgyhi],dx
	jmp	@@have
ENDP

PROC	CalcHeight
PUBLIC	CalcHeight
	call	CalcHeightN
	retf
ENDP


;============================
;
; DrawVisList
;
; NEC V30 build, StevenC & Claude: the end of DrawScaleds, which draws the
; visible sprites back to front.  Profiled, its selection loop was a third
; of DrawScaleds -- the compiler kept visstep, height and least in memory,
; so each comparison was several memory round trips.  Same algorithm, same
; order: each pass takes the FIRST entry with the smallest viewheight (a
; strict <, starting from 32000), draws it with ScaleShape, and marks it
; 32000.  If a pass found none, farthest would stay as it was, as in C.
;
;	for (i = 0; i<numvisable; i++)
;	{
;		least = 32000;
;		for (visstep=&vislist[0] ; visstep<visptr ; visstep++)
;			if (visstep->viewheight < least)
;				least = visstep->viewheight, farthest = visstep;
;		ScaleShape(farthest->viewx,farthest->shapenum,farthest->viewheight);
;		farthest->viewheight = 32000;
;	}
;
;============================

VIS_VIEWX		=	0
VIS_HEIGHT		=	2
VIS_SHAPENUM	=	4
VIS_SIZE		=	6

PROC	DrawVisList
PUBLIC	DrawVisList
	push	si
	push	di

	mov	ax,[visptr]
	sub	ax,OFFSET vislist
	mov	cl,VIS_SIZE
	div	cl						; AL = numvisable (at most MAXVISABLE, 50)
	xor	ah,ah
	mov	cx,ax
	jcxz	@@done
	mov	di,[visptr]
	mov	bx,[farthest]
;
; NEC V30 build, StevenC & Claude (step 46): id picks the nearest-first
; order by selection -- a pass over the whole list per object drawn, the
; FIRST of the smallest heights each time.  That is exactly a stable sort
; by height, so the list is sorted once here, by insertion, into visord,
; and drawn in that order.  id's loop never picks a height of 32000 or
; more (it marks drawn objects 32000, and re-draws the last object
; instead) and compares signed; a list holding such a height is left to
; id's loop, so every case draws what id's did.
;
	mov	si,OFFSET vislist
	xor	bx,bx						; visord index, bytes
@@collect:
	cmp	[WORD si+VIS_HEIGHT],32000
	jae	@@idloop					; unsigned: 32000 up, and "negative" ones
	mov	[visord+bx],si
	add	bx,2
	add	si,VIS_SIZE
	cmp	si,di
	jb	@@collect

	mov	si,2						; insertion sort, by signed height
@@isort:
	cmp	si,bx
	jae	@@sorted
	mov	ax,[visord+si]				; key
	push	di
	mov	di,ax
	mov	dx,[di+VIS_HEIGHT]			; its height
	pop	di
	push	si
@@ishift:
	mov	di,[visord+si-2]
	cmp	[di+VIS_HEIGHT],dx
	jle	@@iplace					; not greater: stop (keeps equal ones in order)
	mov	[visord+si],di
	sub	si,2
	jnz	@@ishift
@@iplace:
	mov	[visord+si],ax
	pop	si
	add	si,2
	jmp	@@isort
@@sorted:
	mov	di,[visptr]
	xor	si,si
@@draw:
	mov	bx,[visord+si]
	mov	[farthest],bx
	push	cx
	push	si
	push	[WORD bx+VIS_HEIGHT]
	push	[WORD bx+VIS_SHAPENUM]
	push	[WORD bx+VIS_VIEWX]
	call	ScaleShape
	add	sp,6
	pop	si
	pop	cx
	mov	bx,[farthest]
	mov	[WORD bx+VIS_HEIGHT],32000
	add	si,2
	loop	@@draw
	mov	[visstep],di				; where the C loop left it
	jmp	@@done

@@idloop:
	mov	di,[visptr]
	mov	bx,[farthest]
@@pass:
	mov	si,OFFSET vislist
	mov	dx,32000				; least
	cmp	si,di
	jae	@@found
	EVEN
@@scan:
	mov	ax,[si+VIS_HEIGHT]
	cmp	ax,dx
	jge	@@next					; signed, as the C compares ints
	mov	dx,ax
	mov	bx,si					; farthest = visstep
@@next:
	add	si,VIS_SIZE
	cmp	si,di
	jb	@@scan

@@found:
	mov	[farthest],bx
	push	cx
	push	[WORD bx+VIS_HEIGHT]
	push	[WORD bx+VIS_SHAPENUM]
	push	[WORD bx+VIS_VIEWX]
	call	ScaleShape
	add	sp,6
	pop	cx
	mov	bx,[farthest]
	mov	[WORD bx+VIS_HEIGHT],32000
	loop	@@pass

	mov	[visstep],di			; where the C loop left it
@@done:
	pop	di
	pop	si
	retf
ENDP


;============================
;
; PlaceStatics
;
; NEC V30 build, StevenC & Claude: the first loop of DrawScaleds, over every
; static object on the level (up to 400), in registers.  It is game logic
; as well as drawing -- GetBonus picks up an item the player is on -- so
; TransformTile and GetBonus are called exactly when, and in the order,
; the C called them:
;
;	visptr = &vislist[0];
;	for (statptr = &statobjlist[0] ; statptr !=laststatobj ; statptr++)
;	{
;		if ((visptr->shapenum = statptr->shapenum) == -1)
;			continue;						// object has been deleted
;		if (!*statptr->visspot)
;			continue;						// not visable
;		if (TransformTile (statptr->tilex,statptr->tiley
;			,&visptr->viewx,&visptr->viewheight) && statptr->flags & FL_BONUS)
;		{
;			GetBonus (statptr);
;			continue;
;		}
;		if (!visptr->viewheight)
;			continue;						// to close to the object
;		if (visptr < &vislist[MAXVISABLE-1])	// don't let it overflow
;			visptr++;
;	}
;
; (The C also wrote shapenum into the spare slot for skipped objects; only
; slots below visptr are ever read, so that write is left out.)
;
;============================

ST_TILEX		=	0
ST_TILEY		=	1
ST_VISSPOT		=	2
ST_SHAPENUM		=	4
ST_FLAGS		=	6
ST_SIZE			=	8
FL_BONUS		=	2
MAXVISABLE		=	50

PROC	PlaceStatics
PUBLIC	PlaceStatics
	push	si
	push	di

	mov	di,OFFSET vislist			; DI = visptr
	mov	si,OFFSET statobjlist		; SI = statptr
	mov	al,[BYTE vismark]
	mov	[BYTE cs:@@mark+2],al		; this frame's mark, as an immediate below
	mov	[BYTE cs:@@mark0+2],al
	mov	[BYTE cs:@@mark1+2],al
	mov	[BYTE cs:@@mark2+2],al
	mov	[BYTE cs:@@mark3+2],al
	mov	cx,[laststatobj]			; NEC V30 build (step 49): the bound in CX
	jmp	@@test4						; (taken: a 486 runs the patched bytes)

; Laid out for the V30: an object not seen this frame -- nearly all of them
; -- falls straight through to the next; only a seen one jumps out.
;
; NEC V30 build (step 59): four at a time while four are left, then one at
; a time.  A seen one goes to @@seenstat with SI on it, and @@next carries on
; from the one after, so the order is the C's.  DX = the bound less three
; statics, remade after every C call (as CX is).
;
	EVEN
@@loop4:
	mov	bx,[si+ST_VISSPOT]
@@mark0:
	cmp	[BYTE bx],0					; (the 0 is vismark, patched above)
	je	@@seen0
	mov	bx,[si+ST_SIZE+ST_VISSPOT]
@@mark1:
	cmp	[BYTE bx],0
	je	@@seen1
	mov	bx,[si+2*ST_SIZE+ST_VISSPOT]
@@mark2:
	cmp	[BYTE bx],0
	je	@@seen2
	mov	bx,[si+3*ST_SIZE+ST_VISSPOT]
@@mark3:
	cmp	[BYTE bx],0
	je	@@seen3
	add	si,4*ST_SIZE
@@test4:
	mov	dx,cx
	sub	dx,3*ST_SIZE
	cmp	si,dx
	jb	@@loop4						; four or more left
	jmp	@@test

@@seen3:
	add	si,ST_SIZE
@@seen2:
	add	si,ST_SIZE
@@seen1:
	add	si,ST_SIZE
@@seen0:
	jmp	@@seenstat

@@loop:
	mov	bx,[si+ST_VISSPOT]			; (both tests are pure: order is free)
@@mark:
	cmp	[BYTE bx],0					; (the 0 is vismark, patched above)
	je	@@seenstat
	add	si,ST_SIZE
@@test:
	cmp	si,cx
	jne	@@loop
	jmp	@@statdone

@@next:
	add	si,ST_SIZE
	jmp	@@test4

@@seenstat:
	mov	ax,[si+ST_SHAPENUM]
	cmp	ax,-1
	je	@@next						; deleted
	mov	[di+VIS_SHAPENUM],ax

	lea	ax,[di+VIS_HEIGHT]
	push	ax						; &visptr->viewheight
	push	di						; &visptr->viewx
	mov	al,[si+ST_TILEY]
	xor	ah,ah
	push	ax
	mov	al,[si+ST_TILEX]
	push	ax						; (AH still 0)
	call	TransformTile
	add	sp,8
	mov	cx,[laststatobj]			; (C and TransformTile use CX)
	or	ax,ax
	jz	@@notbonus
	test	[BYTE si+ST_FLAGS],FL_BONUS
	jz	@@notbonus
	push	si
	call	GetBonus
	add	sp,2
	mov	cx,[laststatobj]
	jmp	@@next

@@notbonus:
	cmp	[WORD di+VIS_HEIGHT],0
	je	@@next						; too close
	cmp	di,OFFSET vislist+(MAXVISABLE-1)*VIS_SIZE
	jae	@@next						; don't let it overflow
	add	di,VIS_SIZE

	jmp	@@next

@@statdone:
	mov	[visptr],di
	pop	di
	pop	si
	retf
ENDP


;============================
;
; ScalePostA
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's ScalePost for the asm hit
; routines, called NEAR.  They used to reach it through FarScalePost -- a far
; call, a near call and a C frame for every post drawn.  The body is the
; C's asm exactly: the scaler for the post's height, the column's map masks,
; up to three bytes wide.  Keeps SI -- all its callers, the two hit
; routines, need back (step 49: AsmRefresh reloads the rest after a hit).
;
;============================

PROC	ScalePostA NEAR
PUBLIC	ScalePostA					; public only so profiles can name it
	push	si

	mov	bx,[postx]
	mov	di,bx
	shl	bx,1
	mov	bp,[wallheight+bx]		; fractional height (low 3 bits frac)
	and	bp,0fff8h				; bp = heightscaler*4
	shr	bp,1
	cmp	bp,[maxscaleshl2]
	jle	@@heightok
	mov	bp,[maxscaleshl2]
@@heightok:
	cmp	bp,[postmin]			; the least wall of the frame so far (a new
	jb	@@newmin				; one is rare: kept out of the way)
@@minok:
	cmp	bp,[bandlim]
	jb	@@short					; shorter than the band left uncleared
	add	bp,OFFSET fullscalefarcall

	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,[postwidth]			; bx = pixel*8+pixwidth

	mov	al,[mapmasks1-1+bx]		; -1 because no widths of 0
	mov	dx,SC_INDEX+1
	out	dx,al					; set bit mask register
	les	si,[postsource]			; ES:SI = the texture column
	mov	cx,SCREENSEG
	mov	ds,cx					; DS = the screen
	call	[DWORD bp]				; SS:BP -- scale the line of pixels

	mov	al,[ss:mapmasks2-1+bx]
	or	al,al
	jz	@@done
	inc	di						; a strip that crosses two bytes
	out	dx,al
	call	[DWORD bp]

	mov	al,[ss:mapmasks3-1+bx]
	or	al,al
	jz	@@done
	inc	di						; three bytes
	out	dx,al
	call	[DWORD bp]

@@done:
	mov	ax,ss
	mov	ds,ax
	pop	si
	ret

@@newmin:
	mov	[postmin],bp
	jmp	@@minok

;
; NEC V30 build (step 62): this wall covers rows half-c .. half+c-1, c the
; scale (scaler 0 is scaler 1), and VGAClearScreen left half-B .. half+B-1
; to the walls: fill the difference in each byte the post draws, after its
; wall and with its masks.  (c < B <= half, so none of it is wall.)
;
@@short:
	mov	ax,bp
	shr	ax,2					; the scale
	jnz	@@cok
	inc	ax
@@cok:
	mov	cx,[bandhalf]
	sub	cx,ax
	mov	[fixn],cx				; B-c rows each side
	add	ax,[bandhalf]
	mov	cx,ax
	shl	ax,4
	shl	cx,6
	add	ax,cx					; (B+c)*80
	add	ax,[bandtop]
	mov	[fixofs2],ax			; row half+c
	add	bp,OFFSET fullscalefarcall

	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,[postwidth]			; bx = pixel*8+pixwidth

	mov	al,[mapmasks1-1+bx]		; -1 because no widths of 0
	mov	dx,SC_INDEX+1
	out	dx,al					; set bit mask register
	les	si,[postsource]			; ES:SI = the texture column
	mov	cx,SCREENSEG
	mov	ds,cx					; DS = the screen
	call	[DWORD bp]				; SS:BP -- scale the line of pixels
	call	BandFix

	mov	al,[ss:mapmasks2-1+bx]
	or	al,al
	jz	@@done
	inc	di						; a strip that crosses two bytes
	out	dx,al
	call	[DWORD bp]
	call	BandFix

	mov	al,[ss:mapmasks3-1+bx]
	or	al,al
	jz	@@done
	inc	di						; three bytes
	out	dx,al
	call	[DWORD bp]
	call	BandFix
	jmp	@@done
ENDP


;
; BandFix: the ceiling and floor rows a short post owes the band, in the
; byte at DI (row 0 of the view) with the map mask already set.  DS is the
; screen; keeps every register but AX and CX.
;
PROC	BandFix NEAR
	push	di
	add	di,[ss:bandtop]
	mov	cx,[ss:fixn]
	mov	al,[BYTE ss:ceilcolor]
@@ceiling:
	mov	[di],al
	add	di,80
	loop	@@ceiling
	pop	di
	push	di
	add	di,[ss:fixofs2]
	mov	cx,[ss:fixn]
	mov	al,19h					; the floor, as VGAClearScreen fills it
@@floor:
	mov	[di],al
	add	di,80
	loop	@@floor
	pop	di
	ret
ENDP


;
; DropFill (step 92, StevenC & Claude): the post id drops -- postx, postwidth
; pixels -- gets, column by column, the ceiling and floor rows of the band
; VGAClearScreen skipped (BandFix with a wall of height 0), which is what
; id's picture shows there.  Nothing when no band was skipped.  Keeps SI and
; DS; DropFillF is the same for C.
;
PROC	DropFill NEAR
PUBLIC	DropFill
	mov	cx,[bandhalf]
	jcxz	@@none
	push	si
	mov	[fixn],cx				; B rows each side, from row half-B
	mov	ax,cx
	shl	ax,4
	shl	cx,6
	add	ax,cx					; B*80
	add	ax,[bandtop]
	mov	[fixofs2],ax			; the floor from row half
	mov	si,[postx]
	mov	bp,[postwidth]
	mov	dx,SC_INDEX+1
	mov	ax,SCREENSEG
	mov	ds,ax
@@col:
	mov	cx,si
	and	cl,3
	mov	al,1
	shl	al,cl
	out	dx,al					; this pixel's plane
	mov	di,si
	shr	di,2
	add	di,[ss:bufferofs]
	call	BandFix
	inc	si
	dec	bp
	jnz	@@col
	mov	ax,ss
	mov	ds,ax
	pop	si
@@none:
	ret
ENDP

PROC	DropFillF FAR
PUBLIC	DropFillF
	push	di
	push	bp
	call	DropFill
	pop	bp
	pop	di
	retf
ENDP


;
; ScalePostF: ScalePostA for WL_DRAW.C's door and pushwall routines and the
; frame's last post, keeping the registers a C caller relies on
;
PROC	ScalePostF FAR
PUBLIC	ScalePostF
	push	di
	push	bp
	call	ScalePostA
	pop	bp
	pop	di
	retf
ENDP

;============================
;
; BSPCols (the BSP branch, StevenC & Claude): DrawRun's column loop, from
; WL_BSP.C, where Borland kept every value in memory and reloaded it per
; use.  For each column from c->col to c->end: the height, the stepped
; height, its whole part (at least 1); the texel, the stepped u*h over it
; by one DIV, clamped to the run; its texture column, flipped for the
; side; then the post -- the same texture column as the last widens it,
; another draws the last (ScalePostA) and starts this one -- and both
; steps advance exactly (a quotient, and a remainder carried).
;
; int BSPCols (bspcols *c) -- AX 0 when c->col reaches c->end; 1 when the
; next column is on another tile than c->tile, which is set to it and the
; column left undone: the C loads that tile's page and calls again.
;
; The struct is DrawRun's local (SS = DS); the offsets are the C's own.
;
BC_COL	=	0
BC_END	=	2
BC_HV	=	4						; bspstep H: v (16.16), q, r, e, d
BC_HQ	=	8
BC_HR	=	12
BC_HE	=	14
BC_HD	=	16
BC_UV	=	18						; bspstep UH
BC_UQ	=	22
BC_UR	=	26
BC_UE	=	28
BC_UD	=	30
BC_TILE	=	32
BC_A1	=	34
BC_UMAX	=	36
BC_PAGE	=	38
BC_FLIP	=	40

PROC	BSPCols FAR
PUBLIC	BSPCols
;
; (2026-10-04) Everything constant for the call -- the end column, the
; texel bound, the tile and its first texel, the flip, the page, and the
; height's and uh's steps -- is patched into the loop as immediates (the
; last two bytes of each instruction labelled bk_), so the loop reads no
; struct: SI holds uh's low word, its high word and the error are kept in
; the code segment, and all of it is written back on the way out.
;
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	bx,[bp+6]
	mov	[cs:bcv_ptr],bx
	mov	ax,[bx+BC_END]
	mov	[WORD cs:bk_end-2],ax
	mov	ax,[cs:bc_lod1]
	mov	[WORD cs:bk_lod1-2],ax
	mov	ax,[cs:bc_lod2]
	mov	[WORD cs:bk_lod2-2],ax
	mov	ax,[bx+BC_UMAX]
	mov	[WORD cs:bk_umax1-2],ax
	mov	[WORD cs:bk_umax2-2],ax
	mov	ax,[bx+BC_A1]
	mov	[WORD cs:bk_a1-2],ax
	mov	ax,[bx+BC_TILE]
	mov	[WORD cs:bk_tile-2],ax
	mov	ax,[bx+BC_FLIP]
	mov	[WORD cs:bk_flip-2],ax
	mov	ax,[bx+BC_PAGE]
	mov	[WORD cs:bk_page-2],ax
	mov	ax,[bx+BC_HQ]
	mov	[WORD cs:bk_hq0-2],ax
	mov	ax,[bx+BC_HQ+2]
	mov	[WORD cs:bk_hq1-2],ax
	mov	ax,[bx+BC_UQ]
	mov	[WORD cs:bk_uq0-2],ax
	mov	ax,[bx+BC_UQ+2]
	mov	[WORD cs:bk_uq1-2],ax
	mov	ax,[bx+BC_UR]
	mov	[WORD cs:bk_ur-2],ax
	mov	ax,[bx+BC_UD]
	mov	[WORD cs:bk_ud1-2],ax
	mov	[WORD cs:bk_ud2-2],ax
	mov	ax,[bx+BC_UV+2]
	mov	[cs:bcv_uvhi],ax
	mov	ax,[bx+BC_UE]
	mov	[cs:bcv_ue],ax
	mov	si,[bx+BC_UV]			; SI uh's low word
	mov	di,[bx+BC_COL]			; DI the column
	mov	bp,[bx+BC_HV]			; CX:BP the height, 16.16
	mov	cx,[bx+BC_HV+2]
	jmp	@@col					; (and the patched bytes leave the queue)

@@col:
	cmp	di,1234h
bk_end:
	jge	@@done
	jcxz	@@h0					; under a pixel: at least 1
@@hok:
	cmp	cx,1234h				; (2026-10-04) level of detail: a wall
bk_lod1:							; shorter than this is far, and only
	jae	@@sample				; every second column of it is textured
	cmp	[postwidth],0			; -- every fourth under bk_lod2 -- the
	je	@@sample				; post widened over the rest, as LOWWALLS
	mov	ax,di					; does, for all walls, in the walk
	and	ax,1
	cmp	cx,1234h
bk_lod2:
	jae	@@lodm
	mov	ax,di
	and	ax,3
@@lodm:
	or	ax,ax
	jz	@@sample
	cmp	[postwidth],8			; (ScalePostA's widest post)
	jae	@@sample
	inc	[postwidth]
	mov	bx,di
	shl	bx,1
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	jmp	@@step
@@sample:
	mov	ax,si					; u = uh/h
	mov	dx,[cs:bcv_uvhi]
	cmp	dx,cx
	jae	@@umax
	div	cx
	cmp	ax,1234h
bk_umax1:
	ja	@@umax
@@uok:
	mov	bx,ax
	shr	bx,6
	add	bx,1234h
bk_a1:
	cmp	bx,1234h
bk_tile:
	jne	@@newtile
	and	ax,63					; the texture column, flipped by a mask
	shl	ax,6					; (0FC0h - t is t xor 0FC0h)
	xor	ax,1234h
bk_flip:
	cmp	[postwidth],0
	je	@@newpost
	cmp	ax,[WORD postsource]	; (the page is the same: a new tile's
	jne	@@flush					; page comes after the post is drawn)
	inc	[postwidth]				; the same texture column: wider
	mov	bx,di
	shl	bx,1
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	jmp	@@step
@@flush:
	push	ax
	push	cx
	push	di
	push	bp
	call	ScalePostA				; keeps SI
	pop	bp
	pop	di
	pop	cx
	pop	ax
@@newpost:
	mov	[WORD postsource],ax
	mov	ax,1234h
bk_page:
	mov	[WORD postsource+2],ax
	mov	[postx],di
	mov	[postwidth],1
	mov	bx,di
	shl	bx,1
	mov	[wallheight+bx],cx

@@step:
	add	bp,1234h				; the height
bk_hq0:
	adc	cx,1234h
bk_hq1:
	add	si,1234h				; uh, exactly: a remainder carried
bk_uq0:
	adc	[WORD cs:bcv_uvhi],1234h
bk_uq1:
	mov	ax,[cs:bcv_ue]
	add	ax,1234h
bk_ur:
	jc	@@uc					; (e + r can pass 0FFFFh: unsigned)
	cmp	ax,1234h
bk_ud1:
	jb	@@un
@@uc:
	sub	ax,1234h
bk_ud2:
	add	si,1
	adc	[WORD cs:bcv_uvhi],0
@@un:
	mov	[cs:bcv_ue],ax
	inc	di
	jmp	@@col

@@h0:
	inc	cx
	jmp	@@hok
@@umax:
	or	dx,dx					; uh below 0 (rounding at the start): 0
	js	@@u0
	mov	ax,1234h
bk_umax2:
	jmp	@@uok
@@u0:
	xor	ax,ax
	jmp	@@uok

@@newtile:
	mov	dx,bx
	mov	bx,[cs:bcv_ptr]
	mov	[bx+BC_TILE],dx
	mov	ax,1
	jmp	@@ret
@@done:
	mov	bx,[cs:bcv_ptr]
	xor	ax,ax
@@ret:
	mov	[bx+BC_COL],di			; where it stopped, and the height there
	mov	[bx+BC_HV],bp
	mov	[bx+BC_HV+2],cx
	mov	[bx+BC_UV],si
	mov	dx,[cs:bcv_uvhi]
	mov	[bx+BC_UV+2],dx
	mov	dx,[cs:bcv_ue]
	mov	[bx+BC_UE],dx
	pop	di
	pop	si
	pop	bp
	retf
ENDP

bcv_ptr		dw	0
bc_lod1		dw	256						; wallheight under which a wall is far:
bc_lod2		dw	128						; 64 and 32 pixels high (8 to a pixel row
										; pair: wallheight>>3 is the scaler)
bcv_uvhi		dw	0
bcv_ue		dw	0
		db	0						; (parity: the cap made BSPCols 7 bytes longer)



;============================
;
; HitVertWall / HitHorizWall
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's two wall-hit routines,
; which AsmRefresh calls once per ray.  In C each was a far call with a
; frame and its state compared through memory; here the ray loop jumps to
; them and they jump on to nextpix (step 62).  Every register is free on
; entry -- AsmRefresh has
; stored xtile, ytile and the intercepts and reloads everything at
; nextpix -- so only SI and DI need keeping across the C calls made here.
; Statement for statement the C (with CalcHeight skipped for a wide-scale
; column, as the C now does):
;
;	texture = ((unsigned)yintercept>>4)&0xfc0;
;	if (xtilestep == -1)
;		texture = 0xfc0-texture, xintercept += TILEGLOBAL;
;	if (lastside==1 && lastintercept == xtile && lasttilehit == tilehit)
;	{
;		if (texture == (unsigned)postsource)
;			postwidth++, wallheight[pixx] = wallheight[pixx-1];	// wide scale
;		else
;		{
;			wallheight[pixx] = CalcHeight();
;			ScalePost ();
;			(unsigned)postsource = texture; postwidth = 1; postx = pixx;
;		}
;	}
;	else
;	{
;		wallheight[pixx] = CalcHeight();
;		if (lastside != -1) ScalePost ();
;		lastside = true; lastintercept = xtile; lasttilehit = tilehit;
;		postx = pixx; postwidth = 1;
;		if (tilehit & 0x40)			// check for adjacent doors
;		{
;			ytile = yintercept>>TILESHIFT;
;			wallpic = tilemap[xtile-xtilestep][ytile]&0x80 ? DOORWALL+3
;				: vertwall[tilehit & ~0x40];
;		}
;		else
;			wallpic = vertwall[tilehit];
;		postsource = PM_GetPage(wallpic):texture;
;	}
;
; HitHorizWall is the same with x and y exchanged, lastside 0, DOORWALL+2,
; horizwall[], and the texture mirrored when ytilestep is NOT -1.
;
;============================

PROC	HitVertWallA NEAR
PUBLIC	HitVertWallA				; public only so profiles can name it
	mov	si,[WORD yintercept]
	shr	si,4
	and	si,0fc0h				; SI = texture
hvwx:								; step 71: EB (xtilestep 1) or 3C (-1),
	jmp	SHORT hvw_tex				; patched by the quadrant code
	mov	ax,0fc0h
	sub	ax,si
	mov	si,ax
	inc	bp						; xintercept += TILEGLOBAL (step 75: in BP)
hvw_tex:
;
; NEC V30 build (step 51): id's test -- lastside, both words of
; lastintercept and lasttilehit, four compares against memory -- is one
; compare of the key AsmRefresh built in CX: tilehit<<7 | side<<6 | tile.
; Tiles are under 64 and tilehit a byte, so the key holds all three
; exactly, never FFFFh; C invalidates it wherever it changes that state.
;
	cmp	cx,[lastkey]
	jne	hvw_nwt				; (a short hop: see hvw_nwt)
	cmp	si,[WORD postsource]
hvwmrg:									; step 97: JMP with LOWWALLS4 (EB for 75)
	jne	SHORT hvw_newcol
wideadd1:								; step 79: pixstep, patched (83 06 iw ib: at +4)
	add	[WORD postwidth],1		; wide scale
	mov	bx,[pixx]
	shl	bx,1
widecp1:								; step 79: wallheight-2*pixstep, patched
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	jmp	nextpix				; step 62: jumped to, not called
hvw_nwt:
	jmp	hvw_newwall			; step 67: the new-wall test's hop
; step 67: the inline height's cache miss, within reach of its test
cvi_miss:
	mov	[chvkey],ax
	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
cvvxloc:
	sub	ax,1234h				; viewx, low word (2D iw: at +1)
cvvxhic:
	sbb	dx,1234h				; high word (81 DA iw: at +2)
	FIXBYFRACB	cvcossignc,cvcosfracc	; dx:ax = gxt
	mov	[chvgxlo],ax
	mov	[chvgxhi],dx
	jmp	cvi_have
hvw_drop:						; step 92: past the first column, id drops
	cmp	[pixx],0				; the pending post -- give its columns the
	je	hvw_first				; band the clear skipped
	call	DropFill
	jmp	hvw_first
hvw_newcol:
	mov	[WORD xintercept],0		; step 75: the hit, stored as a post starts
	mov	[WORD xintercept+2],bp
	mov	[xtile],bx
	mov	[WORD yintercept+2],dx
	mov	[ytile],dx
; step 67: CalcHeightV inline, no call
								; (step 61: nothing kept; the sign is in BP)
	mov	ax,[WORD xintercept+2]
	cmp	ax,[chvkey]
	jne	cvi_miss
	mov	ax,[chvgxlo]			; dx:ax = gxt, as for the last column
	mov	dx,[chvgxhi]
cvi_have:
	push	dx
	push	ax

	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
cvvyloc:
	sub	ax,1234h				; viewy
cvvyhic:
	sbb	dx,1234h
	FIXBYFRACB	cvsinsignc,cvsinfracc	; dx:ax = gyt

	pop	bx
	pop	cx					; cx:bx = gxt
	sub	bx,ax
	sbb	cx,dx				; cx:bx = nx = gxt-gyt

cvmdhic:
	cmp	cx,1234h			; if (nx < mindist) nx = mindist -- signed (81 F9 iw)
	jg	cvi_distok
	jl	cvi_clamp
cvmdloc:
	cmp	bx,1234h			; (81 FB iw)
	jae	cvi_distok
cvi_clamp:
cvmdlo2c:
	mov	bx,1234h			; (BB iw)
cvmdhi2c:
	mov	cx,1234h			; (B9 iw)
cvi_distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
cvhnloc:
	mov	ax,1234h			; heightnumerator (B8 iw)
cvhnhic:
	mov	dx,1234h			; (BA iw)
	idiv	bx
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	push	si						; step 68: ScalePostA inline -- the post
	mov	bx,[postx]				; this column closes
	mov	di,bx
	shl	bx,1
	mov	bp,[wallheight+bx]		; fractional height (low 3 bits frac)
	and	bp,0fff8h				; bp = heightscaler*4
	shr	bp,1
	cmp	bp,[maxscaleshl2]
	jle	cvp_hok
	mov	bp,[maxscaleshl2]
cvp_hok:
	cmp	bp,[postmin]			; the least wall of the frame (rarely new)
	jb	cvp_newmin
cvp_minok:
	cmp	bp,[bandlim]
	jb	cvp_short				; shorter than the band: ScalePostA's own path
	add	bp,OFFSET fullscalefarcall
	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,[postwidth]			; bx = pixel*8+pixwidth
	mov	al,[mapmasks1-1+bx]		; -1 because no widths of 0
	mov	dx,SC_INDEX+1
	out	dx,al					; set bit mask register
	les	si,[postsource]			; ES:SI = the texture column
	mov	cx,SCREENSEG
	mov	ds,cx					; DS = the screen
	call	[DWORD bp]				; SS:BP -- scale the line of pixels
	mov	al,[ss:mapmasks2-1+bx]
	or	al,al
	jz	cvp_done
	inc	di						; a strip that crosses two bytes
	out	dx,al
	call	[DWORD bp]
	mov	al,[ss:mapmasks3-1+bx]
	or	al,al
	jz	cvp_done
	inc	di						; three bytes
	out	dx,al
	call	[DWORD bp]
cvp_done:
	mov	ax,ss
	mov	ds,ax
	pop	si
	mov	[WORD postsource],si
postw1:								; step 79: pixstep, patched (C7 06 iw iw: at +4)
	mov	[WORD postwidth],1
	mov	ax,[pixx]
	mov	[postx],ax
	jmp	nextpix
cvp_newmin:
	mov	[postmin],bp
	jmp	cvp_minok
cvp_short:
	call	ScalePostA				; (it recomputes; postmin is a least value)
	jmp	cvp_done
hvw_newwall:
	cmp	[cs:wl_skip],0			; a skip before this ray: another wall
	jne	wl_undo
	mov	[WORD xintercept],0		; step 75: the hit, stored as a post starts
	mov	[WORD xintercept+2],bp
	mov	[xtile],bx
	mov	[WORD yintercept+2],dx
	mov	[ytile],dx
	mov	[lastkey],cx
	call	CalcHeightV
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	cmp	[lastside],-1
	je	hvw_drop				; step 92: rare, out of line
	call	ScalePostA
hvw_first:
	mov	[lastside],1
	mov	ax,[xtile]
	cwd
	mov	[WORD lastintercept],ax
	mov	[WORD lastintercept+2],dx
	mov	bx,[lastkey]				; step 76: tilehit, from the wall key
	shr	bx,7
	mov	[lasttilehit],bx
	mov	ax,[pixx]
	mov	[postx],ax
postw2:								; step 79: pixstep, patched (C7 06 iw iw: at +4)
	mov	[WORD postwidth],1
	test	bl,40h
	jz	hvw_plain
	mov	ax,[WORD yintercept+2]	; ytile = yintercept>>TILESHIFT
	mov	[ytile],ax
	mov	di,[xtile]
	sub	di,[xtilestep]
	shl	di,6
	add	di,ax
	test	[BYTE tilemap+di],80h
	jz	hvw_notdoor
	mov	ax,[PMSpriteStart]
	sub	ax,8-3					; DOORWALL+3
	jmp	hvw_getpage
hvw_notdoor:
	and	bx,NOT 40h
hvw_plain:
	shl	bx,1
	mov	ax,[vertwall+bx]
hvw_getpage:
	push	ax
hvwgp:								; step 81: FLATWALLS calls FlatPage here
	call	PM_GetPage
	add	sp,2
	mov	[WORD postsource+2],ax
	mov	[WORD postsource],si
	jmp	nextpix				; step 62: jumped to, not called
ENDP


; (HitHorizWallA is in AsmRefresh since step 70, after hithoriz)


;============================
;
; PlaceActors
;
; NEC V30 build, StevenC & Claude: the second loop of DrawScaleds, over every
; actor, in registers.  Game logic as well as drawing -- it wakes an actor
; the player can see (active) and sets or clears FL_VISABLE -- so every
; store and call is the C's, in the C's order:
;
;	for (obj = player->next;obj;obj=obj->next)
;	{
;		if (!(visptr->shapenum = obj->state->shapenum))
;			continue;					// no shape
;		spotloc = (obj->tilex<<6)+obj->tiley;
;		if (seen(spotloc) || for each of the eight neighbours n,
;			(seen(spotloc+n) && !tilemap[spotloc+n]))
;		{
;			obj->active = true;
;			TransformActor (obj);
;			if (!obj->viewheight)
;				continue;				// too close or far away
;			visptr->viewx = obj->viewx;
;			visptr->viewheight = obj->viewheight;
;			if (visptr->shapenum == -1)
;				visptr->shapenum = obj->temp1;	// special shape
;			if (obj->state->rotate)
;				visptr->shapenum += CalcRotate (obj);
;			if (visptr < &vislist[MAXVISABLE-1])
;				visptr++;
;			obj->flags |= FL_VISABLE;
;		}
;		else
;			obj->flags &= ~FL_VISABLE;
;	}
;
; seen(s) is spotvis[s] == vismark.  The objtype offsets below are the
; compiler's own, read from its listings.
;
;============================

OB_ACTIVE		=	0					; objtype, word-aligned since the NEC V30
OB_STATE		=	6					; build's pad bytes after flags and
OB_FLAGS		=	8					; areanumber (WL_DEF.H) -- checked
OB_TILEX		=	24					; against the compiler's listing of
OB_TILEY		=	26					; TransformActor
OB_VIEWX		=	30
OB_VIEWHEIGHT	=	32
OB_X			=	16
OB_AREANUMBER	=	28
OB_TICCOUNT		=	2
SS_TICTIME		=	4					; statetype: think and action are far
SS_THINK		=	6					; code pointers (medium model), next a
SS_ACTION		=	10					; near data pointer
SS_NEXT			=	14
FL_NEVERMARK	=	4
FL_NONMARK		=	128
OB_Y			=	20
OB_TRANSX		=	34
OB_TRANSY		=	38
OB_TEMP1		=	50
OB_NEXT			=	56
SS_ROTATE		=	0					; statetype
SS_SHAPENUM		=	2
FL_VISABLE		=	8

PROC	PlaceActors
PUBLIC	PlaceActors
	push	si
	push	di

	mov	di,[visptr]					; where PlaceStatics left it
	mov	bx,[player]
	mov	si,[bx+OB_NEXT]
	jmp	@@test

; Laid out for the V30, where a taken jump flushes the prefetch queue: an
; actor with a shape that nobody can see -- the common case -- runs straight
; through all nine tests, and only a spot that was seen jumps out, to check
; for a wall.
	EVEN
@@loop:
	mov	bx,[si+OB_STATE]
	mov	ax,[bx+SS_SHAPENUM]
	mov	[di+VIS_SHAPENUM],ax		; as the C does, before the test
	or	ax,ax
	jz	@@next0						; no shape: flags left alone
	mov	bx,[si+OB_TILEX]
	shl	bx,6
	add	bx,[si+OB_TILEY]			; spotloc
	mov	al,[BYTE vismark]
	cmp	[BYTE spotvis+bx],al
	je	@@seen_t					; (a short hop: see below)
	cmp	[BYTE spotvis+bx-1],al
	je	@@c0						; seen: is there a wall?
@@r0:
	cmp	[BYTE spotvis+bx+1],al
	je	@@c1						; seen: is there a wall?
@@r1:
	cmp	[BYTE spotvis+bx-65],al
	je	@@c2						; seen: is there a wall?
@@r2:
	cmp	[BYTE spotvis+bx-64],al
	je	@@c3						; seen: is there a wall?
@@r3:
	cmp	[BYTE spotvis+bx-63],al
	je	@@c4						; seen: is there a wall?
@@r4:
	cmp	[BYTE spotvis+bx+65],al
	je	@@c5						; seen: is there a wall?
@@r5:
	cmp	[BYTE spotvis+bx+64],al
	je	@@c6						; seen: is there a wall?
@@r6:
	cmp	[BYTE spotvis+bx+63],al
	je	@@c7						; seen: is there a wall?
@@r7:
	and	[BYTE si+OB_FLAGS],NOT FL_VISABLE	; unseen
@@next0:
	mov	si,[si+OB_NEXT]
	or	si,si
	jnz	@@loop
	jmp	@@done
;
; NEC V30 build: TASM's JUMPS turns a conditional jump that cannot reach
; into "jump the other way over a JMP", so a branch that is normally NOT
; taken became one that always is -- one taken jump for every
; unseen actor.  These short hops keep the common path falling through.
;
@@seen_t:
	jmp	@@seen

@@c0:
	cmp	[BYTE tilemap+bx-1],0
	je	@@seen
	jmp	@@r0
@@c1:
	cmp	[BYTE tilemap+bx+1],0
	je	@@seen
	jmp	@@r1
@@c2:
	cmp	[BYTE tilemap+bx-65],0
	je	@@seen
	jmp	@@r2
@@c3:
	cmp	[BYTE tilemap+bx-64],0
	je	@@seen
	jmp	@@r3
@@c4:
	cmp	[BYTE tilemap+bx-63],0
	je	@@seen
	jmp	@@r4
@@c5:
	cmp	[BYTE tilemap+bx+65],0
	je	@@seen
	jmp	@@r5
@@c6:
	cmp	[BYTE tilemap+bx+64],0
	je	@@seen
	jmp	@@r6
@@c7:
	cmp	[BYTE tilemap+bx+63],0
	je	@@seen
	jmp	@@r7

@@seen:
	mov	[WORD si+OB_ACTIVE],1
	call	TransformActorA			; NEAR, SI = the actor
	cmp	[WORD si+OB_VIEWHEIGHT],0
	je	@@next						; too close or far away
	mov	ax,[si+OB_VIEWX]
	mov	[di+VIS_VIEWX],ax
	mov	ax,[si+OB_VIEWHEIGHT]
	mov	[di+VIS_HEIGHT],ax
	cmp	[WORD di+VIS_SHAPENUM],-1
	jne	@@shapeok
	mov	ax,[si+OB_TEMP1]
	mov	[di+VIS_SHAPENUM],ax		; special shape
@@shapeok:
	mov	bx,[si+OB_STATE]
	cmp	[WORD bx+SS_ROTATE],0
	je	@@norot
	push	si
	call	CalcRotate
	add	sp,2
	add	[di+VIS_SHAPENUM],ax
@@norot:
	cmp	di,OFFSET vislist+(MAXVISABLE-1)*VIS_SIZE
	jae	@@full						; don't let it overflow
	add	di,VIS_SIZE
@@full:
	or	[BYTE si+OB_FLAGS],FL_VISABLE

@@next:
	mov	si,[si+OB_NEXT]
@@test:
	or	si,si
	jnz	@@loop

@@done:
	mov	[visptr],di
	pop	di
	pop	si
	retf
ENDP

;============================
;
; The BSP branch's culling and object visibility (StevenC & Claude), from
; WL_BSP.C, where they were a third of the V30's frame with the column
; loop gone: Borland's code called a helper for each dot product and kept
; everything in memory.  The frame's view is kept here, in the code segment
; (DGROUP is full): the camera in 8.8 tiles, the three planes' 8.8 inward
; normals (behind the camera, left edge, right edge), which corner of a box
; each plane tests, and the box that bounds what can be seen.
;
; void BSPSetPlanes (int cam8x, int cam8y, int p0x, int p0y, int p1x,
;	int p1y, int p2x, int p2y)
; void BSPSetBox (int x1, int y1, int x2, int y2)
; int BSPOutside (int x1, int y1, int x2, int y2) -- in tiles: 1 when the box
;	is wholly behind one of the planes
; void BSPMarkVis (void) -- spotvis for every static and actor in view,
;	nearer than the wall drawn in its column, and in an area the player's
;	reaches through open doors (areabyplayer: the box alone let through
;	most of a level's statics whenever a far wall was in view)
;
PROC	BSPSetPlanes FAR
PUBLIC	BSPSetPlanes
	push	bp
	mov	bp,sp
	mov	ax,[bp+6]
	mov	[cs:bv_cx],ax
	mov	ax,[bp+8]
	mov	[cs:bv_cy],ax
	push	si
	xor	si,si
@@plane:
	mov	ax,[bp+10+si]			; the normal's x: the box's x2 when it
	mov	[cs:bv_p+si],ax			; points along +x, else x1
	mov	dx,10
	or	ax,ax
	jns	@@xs
	mov	dx,6
@@xs:
	mov	[cs:bv_sel+si],dx
	sub	dx,6					; (and as offsets into bx_box: 0 or 4)
	mov	[cs:bv_sel2+si],dx
	mov	ax,[bp+12+si]			; and y: y2 or y1
	mov	[cs:bv_p+2+si],ax
	mov	dx,12
	or	ax,ax
	jns	@@ys
	mov	dx,8
@@ys:
	mov	[cs:bv_sel+2+si],dx
	sub	dx,6					; (2 or 6)
	mov	[cs:bv_sel2+2+si],dx
	add	si,4
	cmp	si,12
	jb	@@plane
	pop	si
	pop	bp
	retf
ENDP

PROC	BSPSetBox FAR
PUBLIC	BSPSetBox
	push	bp
	mov	bp,sp
	mov	ax,[bp+6]
	mov	[cs:bv_box],ax
	mov	ax,[bp+8]
	mov	[cs:bv_box+2],ax
	mov	ax,[bp+10]
	mov	[cs:bv_box+4],ax
	mov	ax,[bp+12]
	mov	[cs:bv_box+6],ax
	pop	bp
	retf
ENDP

PROC	BSPOutside FAR
PUBLIC	BSPOutside
	push	bp
	mov	bp,sp
	push	si
	push	di
	xor	di,di					; plane offset
@@plane:
	mov	si,[cs:bv_sel+di]
	mov	ax,[bp+si]				; the corner furthest along the normal
	shl	ax,8
	sub	ax,[cs:bv_cx]
	imul	[WORD cs:bv_p+di]
	mov	cx,ax
	mov	bx,dx
	mov	si,[cs:bv_sel+2+di]
	mov	ax,[bp+si]
	shl	ax,8
	sub	ax,[cs:bv_cy]
	imul	[WORD cs:bv_p+2+di]
	add	ax,cx
	adc	dx,bx
	js	@@out					; still behind the plane
	add	di,4
	cmp	di,12
	jb	@@plane
	xor	ax,ax
	jmp	@@ret
@@out:
	mov	ax,1
@@ret:
	pop	di
	pop	si
	pop	bp
	retf
ENDP

;
; int BSPClassify (int x1, int y1, int x2, int y2) -- as BSPOutside, but 2
; when the box is wholly inside all three planes (its nearest corner to each
; is in front too): then nothing below it in the tree needs testing.
;
PROC	BSPClassify FAR
PUBLIC	BSPClassify
	push	bp
	mov	bp,sp
	push	si
	push	di
	xor	di,di					; plane offset
	mov	[cs:bv_in],2			; wholly inside, until a near corner is not
@@plane:
	mov	si,[cs:bv_sel+di]
	mov	ax,[bp+si]				; the corner furthest along the normal
	shl	ax,8
	sub	ax,[cs:bv_cx]
	imul	[WORD cs:bv_p+di]
	mov	cx,ax
	mov	bx,dx
	mov	si,[cs:bv_sel+2+di]
	mov	ax,[bp+si]
	shl	ax,8
	sub	ax,[cs:bv_cy]
	imul	[WORD cs:bv_p+2+di]
	add	ax,cx
	adc	dx,bx
	js	@@out					; still behind the plane
	cmp	[cs:bv_in],0
	je	@@next					; already known to straddle one
	mov	si,16					; the nearest corner: the other x and y
	sub	si,[cs:bv_sel+di]
	mov	ax,[bp+si]
	shl	ax,8
	sub	ax,[cs:bv_cx]
	imul	[WORD cs:bv_p+di]
	mov	cx,ax
	mov	bx,dx
	mov	si,20
	sub	si,[cs:bv_sel+2+di]
	mov	ax,[bp+si]
	shl	ax,8
	sub	ax,[cs:bv_cy]
	imul	[WORD cs:bv_p+2+di]
	add	ax,cx
	adc	dx,bx
	jns	@@next
	mov	[cs:bv_in],0			; straddles this plane
@@next:
	add	di,4
	cmp	di,12
	jb	@@plane
	mov	ax,[cs:bv_in]
	jmp	@@ret
@@out:
	mov	ax,1
@@ret:
	pop	di
	pop	si
	pop	bp
	retf
ENDP


PROC	BSPMarkVis FAR
PUBLIC	BSPMarkVis
	push	bp
	push	si
	push	di
	mov	ax,[cs:bv_box]			; (2026-10-04) the frame's box, patched
	mov	[WORD cs:bm_x1-2],ax	; into the loop as immediates: it is
	mov	ax,[cs:bv_box+4]		; tested once for every static
	mov	[WORD cs:bm_x2-2],ax
	mov	ax,[cs:bv_box+2]
	mov	[WORD cs:bm_y1-2],ax
	mov	ax,[cs:bv_box+6]
	mov	[WORD cs:bm_y2-2],ax
	mov	si,OFFSET statobjlist
	jmp	@@stat
@@stat:
	cmp	si,[laststatobj]
	jae	@@actors
	cmp	[WORD si+ST_SHAPENUM],-1
	je	@@snext
	mov	ah,[si+ST_TILEX]		; the tile's middle, 8.8
	mov	al,128
	cmp	ax,1234h
bm_x1:
	jl	@@snext
	cmp	ax,1234h
bm_x2:
	jg	@@snext
	mov	dh,[si+ST_TILEY]
	mov	dl,128
	cmp	dx,1234h
bm_y1:
	jl	@@snext
	cmp	dx,1234h
bm_y2:
	jg	@@snext
	mov	bl,dh					; its area: shut off from the player's by
	xor	bh,bh					; closed doors, it cannot be seen
	shl	bx,1
	mov	bx,[farmapylookup+bx]
	mov	cl,ah
	xor	ch,ch
	add	bx,cx
	shl	bx,1
	mov	es,[mapsegs]			; plane 0
	mov	cl,[es:bx]
	sub	cl,107					; AREATILE (defined further down)
	cmp	cl,37					; NUMAREAS: not an area tile, so test it
	jae	@@stest
	mov	bl,cl
	xor	bh,bh
	shl	bx,1
	cmp	[areabyplayer+bx],0
	je	@@snext
@@stest:
	mov	di,[si+ST_VISSPOT]
	call	VisTest
@@snext:
	add	si,ST_SIZE
	jmp	@@stat

@@actors:
	mov	bx,[player]
	mov	si,[bx+OB_NEXT]
@@act:
	or	si,si
	jz	@@done
	mov	bl,[si+OB_AREANUMBER]	; shut off by closed doors: not seen
	xor	bh,bh
	shl	bx,1
	cmp	[areabyplayer+bx],0
	je	@@anext
	mov	ax,[WORD si+OB_X+1]		; x >> 8
	mov	dx,[WORD si+OB_Y+1]
	mov	di,[si+OB_TILEX]
	shl	di,6
	add	di,[si+OB_TILEY]
	add	di,OFFSET spotvis
	call	VisTest
@@anext:
	mov	si,[si+OB_NEXT]
	jmp	@@act
@@done:
	pop	di
	pop	si
	pop	bp
	retf
ENDP

;
; VisTest: AX, DX the object (8.8 tiles); DI the spotvis byte to set.
; Keeps SI and DI.  The depth must be at least 1/64 tile, the side planes
; get half a tile of slack (an object straddling the view's edge is drawn,
; as the walk's rays would have found its tile), and the column and height
; are the C's, from 8.8 operands -- close enough to decide what is seen.
;
PROC	VisTest NEAR
	sub	ax,[cs:bv_cx]
	sub	dx,[cs:bv_cy]
	mov	[cs:vt_dx],ax
	mov	[cs:vt_dy],dx
	imul	[WORD cs:bv_p]			; nx = dx*p0x + dy*p0y
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dy]
	imul	[WORD cs:bv_p+2]
	add	cx,ax
	adc	bx,dx
	js	@@out
	jnz	@@front
	cmp	cx,400h
	jb	@@out
@@front:
	mov	[WORD cs:vt_nx],cx
	mov	[WORD cs:vt_nx+2],bx
	mov	ax,[cs:vt_dx]			; the left plane
	imul	[WORD cs:bv_p+4]
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dy]
	imul	[WORD cs:bv_p+6]
	add	ax,cx
	adc	dx,bx
	cmp	dx,-1					; less than -128*256: out
	jl	@@out
	jg	@@right
	cmp	ax,8000h
	jb	@@out
@@right:
	mov	ax,[cs:vt_dx]			; the right plane
	imul	[WORD cs:bv_p+8]
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dy]
	imul	[WORD cs:bv_p+10]
	add	ax,cx
	adc	dx,bx
	cmp	dx,-1
	jl	@@out
	jg	@@ny
	cmp	ax,8000h
	jb	@@out
@@ny:
	mov	ax,[cs:vt_dy]			; ny = dy*p0x - dx*p0y
	imul	[WORD cs:bv_p]
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dx]
	imul	[WORD cs:bv_p+2]
	sub	cx,ax
	sbb	bx,dx
	mov	al,ch					; ny >> 8
	mov	ah,bl
	imul	[WORD scale]			; DX:AX = ny8 * scale
	mov	cx,[WORD cs:vt_nx+1]	; nx >> 8, at least 4
	xor	bx,bx
	or	dx,dx
	jns	@@pos
	neg	dx
	neg	ax
	sbb	dx,0
	inc	bx						; left of the centre
@@pos:
	cmp	dx,cx
	jae	@@out					; thousands of columns off
	div	cx
	or	bx,bx
	jz	@@rt
	neg	ax
@@rt:
	add	ax,[centerx]
	jns	@@c0
	xor	ax,ax
@@c0:
	cmp	ax,[viewwidth]
	jl	@@c1
	mov	ax,[viewwidth]
	dec	ax
@@c1:
	mov	bx,ax
	shl	bx,1
	mov	ax,[WORD heightnumerator]	; its height, as ColHeight's
	mov	dx,[WORD heightnumerator+2]
	cmp	dx,cx
	jae	@@tall
	div	cx
	cmp	ax,7fffh
	jbe	@@h
@@tall:
	mov	ax,7fffh
@@h:
	cmp	ax,[wallheight+bx]
	jle	@@out					; the wall is nearer
	mov	al,[BYTE vismark]
	mov	[di],al
@@out:
	ret
ENDP

;
; int BSPColRange (int x1, int y1, int x2, int y2, int *c1, int *c2) -- the
; columns a segment's ends (in tiles) land on, roughly: from 8.8 operands,
; so within some two and a half columns, and only for ends at least a tile
; in front of the camera (else 0: the C projects it properly).  Two thirds
; of the runs a frame projects turn out to lie wholly behind walls already
; drawn; this finds most of them for a few IMULs instead of a projection.
;
PROC	BSPColRange FAR
PUBLIC	BSPColRange
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	ax,[bp+6]
	mov	dx,[bp+8]
	call	ApproxCol
	jc	@@unk
	mov	si,ax
	mov	ax,[bp+10]
	mov	dx,[bp+12]
	call	ApproxCol
	jc	@@unk
	mov	bx,[bp+14]
	mov	[bx],si
	mov	bx,[bp+16]
	mov	[bx],ax
	mov	ax,1
	jmp	@@ret
@@unk:
	xor	ax,ax
@@ret:
	pop	di
	pop	si
	pop	bp
	retf
ENDP

;
; ApproxCol: AX, DX a point in tiles -> AX its column; CF when it is less
; than a tile in front, or too far to the side to say
;
PROC	ApproxCol NEAR
	mov	ah,al					; 8.8
	xor	al,al
	mov	dh,dl
	xor	dl,dl
	sub	ax,[cs:bv_cx]
	sub	dx,[cs:bv_cy]
	mov	[cs:vt_dx],ax
	mov	[cs:vt_dy],dx
	imul	[WORD cs:bv_p]			; nx
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dy]
	imul	[WORD cs:bv_p+2]
	add	cx,ax
	adc	bx,dx
	or	bx,bx
	jle	@@unk					; less than a tile (BX:CX < 10000h)
	mov	[WORD cs:vt_nx],cx
	mov	[WORD cs:vt_nx+2],bx
	mov	ax,[cs:vt_dy]			; ny
	imul	[WORD cs:bv_p]
	mov	cx,ax
	mov	bx,dx
	mov	ax,[cs:vt_dx]
	imul	[WORD cs:bv_p+2]
	sub	cx,ax
	sbb	bx,dx
	mov	al,ch
	mov	ah,bl
	imul	[WORD scale]
	mov	cx,[WORD cs:vt_nx+1]
	xor	bx,bx
	or	dx,dx
	jns	@@pos
	neg	dx
	neg	ax
	sbb	dx,0
	inc	bx
@@pos:
	cmp	dx,cx
	jae	@@unk
	div	cx
	cmp	ax,7fffh
	ja	@@unk
	or	bx,bx
	jz	@@rt
	neg	ax
@@rt:
	add	ax,[centerx]
	clc
	ret
@@unk:
	stc
	ret
ENDP

;============================
;
; BSPWalk (the BSP branch, StevenC & Claude): WL_BSP.C's Walk, the tree
; front to back, with its node and run tests -- in C it was a frame and a
; far call per node to BSPClassify, BoxHidden, BSPColRange and Covered,
; and one per run to BSPOutside: some 14% of the V30's frame.  Here the
; tests are near routines on the frame's view (bv_ in the code segment),
; and C is called only for a run that survives them all (DrawRun).
;
; void BSPWalk (bspnode far *nodes, bsprun far *runs, bsprange far *solid,
;	int far *left)
; unsigned BSPWalkStat (int which) -- the last frame's nodes, culled,
;	hidden subtrees, runs drawn
;
; A node is 13 bytes (Borland packs bytes): axis, coord, lo, hi, first,
; count, x1, y1, x2, y2.  A run 4: of, line, a1, a2.  A range 4: a, b.
;
WN_AXIS	=	0
WN_COORD =	1
WN_LO	=	2
WN_HI	=	4
WN_FIRST =	6
WN_COUNT =	8
WN_X1	=	9
WN_SIZE	=	13

PROC	BSPWalk FAR
PUBLIC	BSPWalk
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	ax,[bp+6]
	mov	[WORD cs:wk_nodes],ax
	mov	ax,[bp+8]
	mov	[WORD cs:wk_nodes+2],ax
	mov	ax,[bp+10]
	mov	[WORD cs:wk_runs],ax
	mov	ax,[bp+12]
	mov	[WORD cs:wk_runs+2],ax
	mov	ax,[bp+14]
	mov	[WORD cs:wk_solid],ax
	mov	ax,[bp+16]
	mov	[WORD cs:wk_solid+2],ax
	mov	ax,[bp+18]
	mov	[WORD cs:wk_left],ax
	mov	ax,[bp+20]
	mov	[WORD cs:wk_left+2],ax
	xor	ax,ax
	mov	[cs:wk_cnt],ax
	mov	[cs:wk_cnt+2],ax
	mov	[cs:wk_cnt+4],ax
	mov	[cs:wk_cnt+6],ax
	mov	[cs:wk_cnt+8],ax
	xor	bx,bx						; node 0, not known inside
	call	WalkNode
	pop	di
	pop	si
	pop	bp
	retf
ENDP

PROC	BSPWalkStat FAR
PUBLIC	BSPWalkStat
	push	bp
	mov	bp,sp
	mov	bx,[bp+6]
	shl	bx,1
	mov	ax,[cs:wk_cnt+bx]
	pop	bp
	retf
ENDP

;
; ES:DI = node AX (AX kept)
;
PROC	NodeAt NEAR
	push	ax
	push	dx
	mov	dx,WN_SIZE
	mul	dx
	add	ax,[WORD cs:wk_nodes]
	mov	di,ax
	mov	es,[WORD cs:wk_nodes+2]
	pop	dx
	pop	ax
	ret
ENDP

;
; AX = bspleft (the columns no wall has claimed); flags from OR AX,AX
;
PROC	LeftNow NEAR
	push	es
	push	bx
	les	bx,[DWORD cs:wk_left]
	mov	ax,[es:bx]
	pop	bx
	pop	es
	or	ax,ax
	ret
ENDP

;
; WalkNode: AX the node (-1 none), BX 1 if its box is known wholly in view.
; Recursive on the near side; the far side is a loop.
;
WL_N	=	-2
WL_IN	=	-4
WL_FAR	=	-6
WL_SIDE	=	-8							; bit 0: camera below the line, 1: above
WL_K	=	-10
WL_R	=	-12

PROC	WalkNode NEAR
	push	bp
	mov	bp,sp
	sub	sp,12
	mov	[bp+WL_N],ax
	mov	[bp+WL_IN],bx
@@node:
	mov	ax,[bp+WL_N]
	or	ax,ax
	js	@@ret
	call	LeftNow
	jle	@@ret
	inc	[WORD cs:wk_cnt]
	mov	ax,[bp+WL_N]
	call	NodeAt
	mov	al,[es:di+WN_X1]			; its box, for the tests
	xor	ah,ah
	mov	[cs:bx_box],ax
	mov	al,[es:di+WN_X1+1]
	mov	[cs:bx_box+2],ax
	mov	al,[es:di+WN_X1+2]
	mov	[cs:bx_box+4],ax
	mov	al,[es:di+WN_X1+3]
	mov	[cs:bx_box+6],ax
	cmp	[WORD bp+WL_IN],0
	jne	@@inview
	call	BoxClass
	cmp	ax,1
	jne	@@notout
	inc	[WORD cs:wk_cnt+2]
	jmp	@@ret						; nothing below it is in view
@@notout:
	cmp	ax,2
	jne	@@inview
	mov	[WORD bp+WL_IN],1			; wholly in view: all below it too
@@inview:
	call	BoxHid
	jnc	@@seen
	inc	[WORD cs:wk_cnt+4]
	jmp	@@ret						; wholly behind what is drawn
@@seen:
	mov	ax,[bp+WL_N]
	call	NodeAt
	mov	cl,[es:di+WN_COORD]			; the camera's side of the line, by the
	xor	ch,ch						; whole tile of viewx or viewy
	mov	dx,[WORD viewx+2]
	mov	si,[WORD viewx]
	cmp	[BYTE es:di+WN_AXIS],0
	je	@@xaxis
	mov	dx,[WORD viewy+2]
	mov	si,[WORD viewy]
@@xaxis:
	xor	bx,bx
	cmp	dx,cx
	jge	@@notbelow
	mov	bx,1						; below: cam < coord<<16
	mov	ax,[es:di+WN_LO]			; near side lo, far side hi
	mov	dx,[es:di+WN_HI]
	jmp	@@sides
@@notbelow:
	jg	@@above
	or	si,si
	jz	@@onit
@@above:
	mov	bx,2						; above: cam > coord<<16
@@onit:
	mov	ax,[es:di+WN_HI]
	mov	dx,[es:di+WN_LO]
@@sides:
	mov	[bp+WL_SIDE],bx
	mov	[bp+WL_FAR],dx
	mov	bx,[bp+WL_IN]
	call	WalkNode					; the near side first
	call	LeftNow
	jle	@@ret

	mov	ax,[bp+WL_N]				; the node's own runs, those that face
	call	NodeAt						; the camera
	mov	al,[es:di+WN_COUNT]
	xor	ah,ah
	mov	[bp+WL_K],ax
	mov	ax,[es:di+WN_FIRST]
	shl	ax,1
	shl	ax,1
	add	ax,[WORD cs:wk_runs]
	mov	[bp+WL_R],ax
@@run:
	cmp	[WORD bp+WL_K],0
	je	@@nextnode
	les	di,[DWORD cs:wk_runs]
	mov	di,[bp+WL_R]
	mov	al,[es:di]					; of
	test	al,2
	jz	@@lowside
	test	[BYTE bp+WL_SIDE],2			; looks up: drawn when the camera is above
	jz	@@skiprun
	jmp	@@faces
@@lowside:
	test	[BYTE bp+WL_SIDE],1			; looks down: when the camera is below
	jz	@@skiprun
@@faces:
	cmp	[WORD bp+WL_IN],0
	jne	@@draw
	mov	bl,[es:di+1]				; line
	xor	bh,bh
	mov	cl,[es:di+2]				; a1
	xor	ch,ch
	mov	dl,[es:di+3]				; a2
	xor	dh,dh
	test	al,1
	jnz	@@horiz
	mov	[cs:bx_box],bx				; x = line, y from a1 to a2
	mov	[cs:bx_box+2],cx
	mov	[cs:bx_box+4],bx
	mov	[cs:bx_box+6],dx
	jmp	@@test
@@horiz:
	mov	[cs:bx_box],cx				; y = line, x from a1 to a2
	mov	[cs:bx_box+2],bx
	mov	[cs:bx_box+4],dx
	mov	[cs:bx_box+6],bx
@@test:
	call	BoxClass
	cmp	ax,1
	je	@@skiprun
@@draw:
	inc	[WORD cs:wk_cnt+6]
	call	LeftNow						; the columns unclaimed before it
	push	ax
	mov	ax,[bp+WL_R]
	call	DrawRunA					; keeps BP
	call	LeftNow						; the automap: a run that claimed any
	pop	dx							; column was seen -- its tiles explored
	cmp	ax,dx
	je	SHORT @@unseen
	mov	ax,[bp+WL_R]
	call	MarkRun
@@unseen:
@@skiprun:
	add	[WORD bp+WL_R],4
	dec	[WORD bp+WL_K]
	jmp	@@run
@@nextnode:
	mov	ax,[bp+WL_FAR]				; the far side: a loop, not a call
	mov	[bp+WL_N],ax
	jmp	@@node
@@ret:
	mov	sp,bp
	pop	bp
	ret
ENDP
		db	0						; (parity, after the automap's marking above)

;
; BoxClass: the box in bx_box (tiles) against the view's planes -- AX 1 if
; wholly behind one, 2 if wholly inside all three, else 0.  Keeps DI.
;
PROC	BoxClass NEAR
	push	di
	xor	di,di
	mov	[cs:bv_in],2
@@plane:
	mov	si,[cs:bv_sel2+di]
	mov	ax,[cs:bx_box+si]			; the corner furthest along the normal
	shl	ax,8
	sub	ax,[cs:bv_cx]
	imul	[WORD cs:bv_p+di]
	mov	cx,ax
	mov	bx,dx
	mov	si,[cs:bv_sel2+2+di]
	mov	ax,[cs:bx_box+si]
	shl	ax,8
	sub	ax,[cs:bv_cy]
	imul	[WORD cs:bv_p+2+di]
	add	ax,cx
	adc	dx,bx
	js	@@out
	cmp	[cs:bv_in],0
	je	@@next
	mov	si,4						; the nearest corner: the other x and y
	sub	si,[cs:bv_sel2+di]
	mov	ax,[cs:bx_box+si]
	shl	ax,8
	sub	ax,[cs:bv_cx]
	imul	[WORD cs:bv_p+di]
	mov	cx,ax
	mov	bx,dx
	mov	si,8
	sub	si,[cs:bv_sel2+2+di]
	mov	ax,[cs:bx_box+si]
	shl	ax,8
	sub	ax,[cs:bv_cy]
	imul	[WORD cs:bv_p+2+di]
	add	ax,cx
	adc	dx,bx
	jns	@@next
	mov	[cs:bv_in],0
@@next:
	add	di,4
	cmp	di,12
	jb	@@plane
	mov	ax,[cs:bv_in]
	pop	di
	ret
@@out:
	mov	ax,1
	pop	di
	ret
ENDP

;
; BoxHid: CF set if the box in bx_box lies wholly behind what is drawn --
; its two silhouette corners (which two by where the camera is: Doom's
; checkcoord), their rough columns (ApproxCol), and those columns, widened
; by 4, inside one claimed range.  Clobbers all but BP.
;
BH_SLACK	=	4

PROC	BoxHid NEAR
	mov	ax,[cs:bx_box]				; the camera left of, within or right of
	shl	ax,8						; the box: 0, 1, 2; above, within, below:
	xor	bx,bx						; 0, 3, 6
	cmp	[cs:bv_cx],ax
	jl	@@hx
	inc	bx
	mov	ax,[cs:bx_box+4]
	shl	ax,8
	cmp	[cs:bv_cx],ax
	jle	@@hx
	inc	bx
@@hx:
	mov	ax,[cs:bx_box+2]
	shl	ax,8
	cmp	[cs:bv_cy],ax
	jl	@@hy
	add	bx,3
	mov	ax,[cs:bx_box+6]
	shl	ax,8
	cmp	[cs:bv_cy],ax
	jle	@@hy
	add	bx,3
@@hy:
	cmp	bx,4
	je	@@no						; the camera is in it
	shl	bx,1
	shl	bx,1
	mov	si,bx						; 4 bytes a case: x, y, x, y selectors
	mov	bl,[cs:bh_tab+si]
	xor	bh,bh
	mov	ax,[cs:bx_box+bx]
	mov	bl,[cs:bh_tab+si+1]
	mov	dx,[cs:bx_box+bx]
	push	si
	call	ApproxCol
	pop	si
	jc	@@no
	mov	[cs:bh_c1],ax
	mov	bl,[cs:bh_tab+si+2]
	xor	bh,bh
	mov	ax,[cs:bx_box+bx]
	mov	bl,[cs:bh_tab+si+3]
	mov	dx,[cs:bx_box+bx]
	call	ApproxCol
	jc	@@no
	mov	bx,[cs:bh_c1]
	call	CoveredA
	ret
@@no:
	clc
	ret
ENDP

;============================
;
; DrawRunA (the BSP branch, StevenC & Claude): WL_BSP.C's DrawRun -- one
; wall run, projected at its ends and drawn through the gaps in the claimed
; columns -- with all its arithmetic here: Ends (the view-space ends by id's
; FixedByFrac, the cut at the near plane, the clip to the view's sides),
; ColHeight, StepInit and MulDivFloor, each statement for statement as the
; C, so the picture is the same.  C is left only what runs once a span or
; less: the texture page of a new tile (RunPage) and the claim (BSPClaim).
;
; AX: the run's offset (its segment is wk_runs+2).  Keeps BP.
;
; An end, in the code segment: nx, ny, u (longs), then col (64ths), h, uh.
;
EN_NX	=	0
EN_NY	=	4
EN_U	=	8
EN_COL	=	12
EN_H	=	16
EN_UH	=	18
EN_SIZE	=	22
BC_SIZE	=	42							; bspcols, as BSPCols reads it

DR_CS	=	-2
DR_CE	=	-4
DR_C1	=	-6
DR_C2	=	-8
DR_K	=	-10							; solid[k], as an offset
DR_COL	=	-12
DR_END	=	-14
DR_BC	=	-14-BC_SIZE					; the bspcols struct

PROC	DrawRunA NEAR
	push	bp
	mov	bp,sp
	sub	sp,14+BC_SIZE
	push	si
	push	di
	les	di,[DWORD cs:wk_runs]
	mov	di,ax
	mov	al,[es:di]					; of
	xor	ah,ah
	mov	[cs:dr_of],ax
	mov	al,[es:di+1]
	mov	[cs:dr_line],ax
	mov	al,[es:di+2]
	mov	[cs:dr_a1],ax
	mov	al,[es:di+3]
	mov	[cs:dr_a2],ax
	test	[BYTE cs:dr_of],4			; a block's face: only while one stands
	jz	@@noblock
	mov	bx,[cs:dr_line]
	test	[BYTE cs:dr_of],2
	jz	@@bl1
	dec	bx
@@bl1:
	test	[BYTE cs:dr_of],1
	jnz	@@blh
	shl	bx,6						; tilemap[x][a1]
	add	bx,[cs:dr_a1]
	jmp	@@blt
@@blh:
	mov	ax,[cs:dr_a1]				; tilemap[a1][y]
	shl	ax,6
	add	bx,ax
@@blt:
	mov	al,[tilemap+bx]
	or	al,al
	jz	@@ret
	test	al,80h
	jnz	@@ret
@@noblock:
	;
	; roughly where it lands: behind what is drawn there already?
	;
	test	[BYTE cs:dr_of],1
	jnz	@@pch
	mov	ax,[cs:dr_line]
	mov	dx,[cs:dr_a1]
	call	ApproxCol
	jc	@@project
	mov	[cs:bh_c1],ax
	mov	ax,[cs:dr_line]
	mov	dx,[cs:dr_a2]
	jmp	@@pc2
@@pch:
	mov	ax,[cs:dr_a1]
	mov	dx,[cs:dr_line]
	call	ApproxCol
	jc	@@project
	mov	[cs:bh_c1],ax
	mov	ax,[cs:dr_a2]
	mov	dx,[cs:dr_line]
@@pc2:
	call	ApproxCol
	jc	@@project
	mov	bx,[cs:bh_c1]
	call	CoveredA
	jnc	@@project
	inc	[WORD cs:wk_cnt+8]
	jmp	@@ret

@@project:
	;
	; Ends: the view-space ends, by id's FixedByFrac
	;
	xor	ax,ax
	mov	[WORD cs:dr_e1+EN_U],ax
	mov	[WORD cs:dr_e1+EN_U+2],ax
	mov	[WORD cs:dr_e2+EN_U+2],ax
	mov	ax,[cs:dr_a2]
	sub	ax,[cs:dr_a1]
	shl	ax,6
	mov	[WORD cs:dr_e2+EN_U],ax
	test	[BYTE cs:dr_of],1
	jnz	@@ehoriz
	mov	ax,[cs:dr_line]				; x = line for both ends
	call	GXview
	call	MulCosSave					; A = gx*cos
	mov	[WORD cs:dr_ta],ax
	mov	[WORD cs:dr_ta+2],dx
	call	MulSinRe					; D = gx*sin
	mov	[WORD cs:dr_td],ax
	mov	[WORD cs:dr_td+2],dx
	mov	ax,[cs:dr_a1]
	mov	si,OFFSET dr_e1
	call	VEnd
	mov	ax,[cs:dr_a2]
	mov	si,OFFSET dr_e2
	call	VEnd
	jmp	@@ends
@@ehoriz:
	mov	ax,[cs:dr_line]				; y = line for both ends
	call	GYview
	call	MulSinSave					; B = gy*sin
	mov	[WORD cs:dr_tb],ax
	mov	[WORD cs:dr_tb+2],dx
	call	MulCosRe					; C = gy*cos
	mov	[WORD cs:dr_tc],ax
	mov	[WORD cs:dr_tc+2],dx
	mov	ax,[cs:dr_a1]
	mov	si,OFFSET dr_e1
	call	HEnd
	mov	ax,[cs:dr_a2]
	mov	si,OFFSET dr_e2
	call	HEnd
@@ends:
	call	EndsTail
	jc	@@ret
@@inorder:
	mov	ax,[WORD cs:dr_e1+EN_COL]	; (an end is within COLLO..COLHI)
	mov	[bp+DR_C1],ax
	mov	bx,[WORD cs:dr_e2+EN_COL]
	mov	[bp+DR_C2],bx
	xor	cx,cx						; cs = c1 < 0 ? 0 : (c1+63) >> 6
	or	ax,ax
	js	@@cs0
	add	ax,63
	shr	ax,6
	mov	cx,ax
@@cs0:
	mov	[bp+DR_CS],cx
	mov	ax,[viewwidth]				; ce = c2 > viewwidth<<6 ? viewwidth
	mov	dx,ax						;	 : (c2+63) >> 6
	shl	dx,6
	cmp	bx,dx
	jg	@@ce
	add	bx,63
	sar	bx,6
	mov	ax,bx
@@ce:
	mov	[bp+DR_CE],ax
	cmp	cx,ax
	jge	@@ret
	les	si,[DWORD cs:wk_solid]		; solid[k]: the first ending past cs
@@fk:
	cmp	[es:si+2],cx
	jg	@@fkd
	add	si,4
	jmp	@@fk
@@fkd:
	mov	[bp+DR_K],si
	cmp	[es:si],cx					; wholly behind what is drawn
	jg	@@bcset
	cmp	[es:si+2],ax
	jge	@@ret
@@bcset:
	mov	ax,0FC0h					; flip: vertical ? up : !up
	test	[BYTE cs:dr_of],1
	jnz	@@fh
	test	[BYTE cs:dr_of],2
	jnz	@@fset
	xor	ax,ax
	jmp	@@fset
@@fh:
	test	[BYTE cs:dr_of],2
	jz	@@fset
	xor	ax,ax
@@fset:
	mov	[bp+DR_BC+BC_FLIP],ax
	mov	ax,[cs:dr_a1]
	mov	[bp+DR_BC+BC_A1],ax
	mov	ax,[cs:dr_a2]
	sub	ax,[cs:dr_a1]
	shl	ax,6
	dec	ax
	mov	[bp+DR_BC+BC_UMAX],ax
	mov	[WORD bp+DR_BC+BC_TILE],-1
	mov	[WORD bp+DR_BC+BC_PAGE],0
	mov	ax,[bp+DR_CS]
	mov	[bp+DR_COL],ax

@@gap:
	mov	ax,[bp+DR_COL]
	cmp	ax,[bp+DR_CE]
	jge	@@claim
	les	si,[DWORD cs:wk_solid]
	mov	si,[bp+DR_K]
	cmp	[es:si],ax
	jg	@@span
	mov	ax,[es:si+2]				; claimed: on past it
	mov	[bp+DR_COL],ax
	add	[WORD bp+DR_K],4
	jmp	@@gap
@@span:
	mov	bx,[es:si]					; end = min (solid[k].a, ce)
	cmp	bx,[bp+DR_CE]
	jle	@@endok
	mov	bx,[bp+DR_CE]
@@endok:
	mov	[bp+DR_END],bx
	sub	bx,ax						; bspleft -= end - col
	les	si,[DWORD cs:wk_left]
	sub	[es:si],bx
	;
	; StepInit (&H, h1<<16, h2<<16, ...) and (&UH, uh1, uh2, ...), off =
	; (col<<6) - c1, d = c2 - c1
	;
	mov	ax,[bp+DR_COL]
	shl	ax,6
	sub	ax,[bp+DR_C1]
	mov	[cs:dr_off],ax
	mov	ax,[bp+DR_C2]
	sub	ax,[bp+DR_C1]
	mov	[cs:dr_d],ax
	xor	ax,ax						; H: a = h1<<16, b = h2<<16
	mov	[WORD cs:dr_sa],ax
	mov	[WORD cs:dr_sb],ax
	mov	ax,[WORD cs:dr_e1+EN_H]
	mov	[WORD cs:dr_sa+2],ax
	mov	ax,[WORD cs:dr_e2+EN_H]
	mov	[WORD cs:dr_sb+2],ax
	lea	di,[bp+DR_BC+BC_HV]
	call	StepInitA
	mov	ax,[WORD cs:dr_e1+EN_UH]
	mov	[WORD cs:dr_sa],ax
	mov	ax,[WORD cs:dr_e1+EN_UH+2]
	mov	[WORD cs:dr_sa+2],ax
	mov	ax,[WORD cs:dr_e2+EN_UH]
	mov	[WORD cs:dr_sb],ax
	mov	ax,[WORD cs:dr_e2+EN_UH+2]
	mov	[WORD cs:dr_sb+2],ax
	lea	di,[bp+DR_BC+BC_UV]
	call	StepInitA
	mov	ax,[bp+DR_COL]
	mov	[bp+DR_BC+BC_COL],ax
	mov	ax,[bp+DR_END]
	mov	[bp+DR_BC+BC_END],ax
	mov	[postwidth],0
@@cols:
	lea	ax,[bp+DR_BC]
	push	ax
	call	BSPCols
	add	sp,2
	or	ax,ax
	jz	@@spandone
	cmp	[postwidth],0				; a new tile: its page -- after the post,
	je	@@np						; which PM_GetPage could evict
	call	ScalePostF					; (keeps BP: ScalePostA does not)
	mov	[postwidth],0
@@np:
	push	[WORD bp+DR_BC+BC_TILE]		; RunPage (vertical, up, line, tile)
	push	[cs:dr_line]
	mov	ax,[cs:dr_of]
	and	ax,2
	push	ax
	mov	ax,[cs:dr_of]
	and	ax,1
	xor	ax,1
	push	ax
	call	RunPage
	add	sp,8
	mov	[bp+DR_BC+BC_PAGE],ax
	jmp	@@cols
@@spandone:
	cmp	[postwidth],0
	je	@@nf
	call	ScalePostF
	mov	[postwidth],0
@@nf:
	mov	ax,[bp+DR_END]
	mov	[bp+DR_COL],ax
	jmp	@@gap
@@claim:
	push	[WORD bp+DR_CE]
	push	[WORD bp+DR_CS]
	call	BSPClaim
	add	sp,4
@@ret:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
ENDP
	nop							; (BSPClaim's call is a byte shorter now: keeps the parity)

;
; EndsTail: the ends in dr_e1, dr_e2 (nx, ny, u) cut at the near plane,
; their columns and heights, clipped to the view's sides when far off it,
; and put in screen order -- CF when nothing of it is left to draw
;
PROC	EndsTail NEAR
	mov	si,OFFSET dr_e1
	call	BelowNear
	jnc	@@n1ok
	mov	si,OFFSET dr_e2
	call	BelowNear
	jc	@@rej						; wholly behind the near plane
	call	NearCut1
	jmp	@@nearok
@@n1ok:
	mov	si,OFFSET dr_e2
	call	BelowNear
	jnc	@@nearok
	call	NearCut2
@@nearok:
	call	UPos
	mov	si,OFFSET dr_e1
	call	ColHeightA
	mov	si,OFFSET dr_e2
	call	ColHeightA
	mov	si,OFFSET dr_e1				; an end far off the screen: clip first
	call	ColFar
	jc	@@clip
	mov	si,OFFSET dr_e2
	call	ColFar
	jnc	@@clipped
@@clip:
	mov	ax,[WORD scale]
	mov	bx,[centerx]
	add	bx,2
	call	SideClipA
	jc	@@rej
	mov	ax,[WORD scale]
	neg	ax
	mov	bx,[viewwidth]
	add	bx,2
	sub	bx,[centerx]
	call	SideClipA
	jc	@@rej
	call	UPos
	mov	si,OFFSET dr_e1
	call	ColHeightA
	mov	si,OFFSET dr_e2
	call	ColHeightA
@@clipped:
	;
	; the ends in screen order; the columns whose rays cross the run
	;
	mov	ax,[WORD cs:dr_e1+EN_COL]
	mov	dx,[WORD cs:dr_e1+EN_COL+2]
	cmp	dx,[WORD cs:dr_e2+EN_COL+2]
	jl	@@inorder
	jg	@@swap
	cmp	ax,[WORD cs:dr_e2+EN_COL]
	jbe	@@inorder
@@swap:
	push	ds
	push	es
	mov	ax,cs
	mov	ds,ax
	mov	es,ax
	mov	si,OFFSET dr_e1				; e1 <-> e2 (through dr_et)
	mov	di,OFFSET dr_et
	mov	cx,EN_SIZE/2
	rep	movsw
	mov	si,OFFSET dr_e2
	mov	di,OFFSET dr_e1
	mov	cx,EN_SIZE/2
	rep	movsw
	mov	si,OFFSET dr_et
	mov	di,OFFSET dr_e2
	mov	cx,EN_SIZE/2
	rep	movsw
	pop	es
	pop	ds
@@inorder:
	clc
	ret
@@rej:
	stc
	ret
ENDP

;
; void BSPFace (long gx1, long gy1, long gx2, long gy2, unsigned page,
;	unsigned dp, unsigned flip, byte far *claim) -- a door, or a face of the
; moving pushwall: the segment from (gx1,gy1) to (gx2,gy2), view-relative,
; the lower end first, its texels 0 to 64 along it, drawn in each column
; where it is nearer than what is there.  dp: a door's position (the part
; of the texture before it is the open part, not drawn); flip: 0 or 0FC0h.
; WL_BSP.C's DrawDoors and BlockFace, the column loop in C before.
;
FC_GX1	=	6
FC_GY1	=	10
FC_GX2	=	14
FC_GY2	=	18
FC_PAGE	=	22
FC_DP	=	24
FC_FLIP	=	26
FC_CLAIM =	28
FL_H	=	-14							; bspstep H, then UH (14 bytes each)
FL_UH	=	-28
FL_COL	=	-30
FL_CE	=	-32

PROC	BSPFace FAR
PUBLIC	BSPFace
	push	bp
	mov	bp,sp
	sub	sp,32
	push	si
	push	di
	xor	ax,ax
	mov	[WORD cs:dr_e1+EN_U],ax
	mov	[WORD cs:dr_e1+EN_U+2],ax
	mov	[WORD cs:dr_e2+EN_U+2],ax
	mov	[WORD cs:dr_e2+EN_U],64
	mov	si,OFFSET dr_e1
	mov	ax,[bp+FC_GX1]
	mov	dx,[bp+FC_GX1+2]
	mov	bx,[bp+FC_GY1]
	mov	cx,[bp+FC_GY1+2]
	call	GEnd
	mov	si,OFFSET dr_e2
	mov	ax,[bp+FC_GX2]
	mov	dx,[bp+FC_GX2+2]
	mov	bx,[bp+FC_GY2]
	mov	cx,[bp+FC_GY2+2]
	call	GEnd
	call	EndsTail
	jc	@@ret
	mov	ax,[WORD cs:dr_e1+EN_COL]	; c1, c2; cs, ce as DrawRunA's
	mov	[cs:fc_c1],ax
	mov	bx,[WORD cs:dr_e2+EN_COL]
	mov	[cs:fc_c2],bx
	xor	cx,cx
	or	ax,ax
	js	@@cs0
	add	ax,63
	shr	ax,6
	mov	cx,ax
@@cs0:
	mov	[bp+FL_COL],cx
	mov	ax,[viewwidth]
	mov	dx,ax
	shl	dx,6
	cmp	bx,dx
	jg	@@ce
	add	bx,63
	sar	bx,6
	mov	ax,bx
@@ce:
	mov	[bp+FL_CE],ax
	cmp	cx,ax
	jge	@@ret
	shl	cx,6						; the steps: off = (cs<<6) - c1, d = c2 - c1
	sub	cx,[cs:fc_c1]
	mov	[cs:dr_off],cx
	mov	ax,[cs:fc_c2]
	sub	ax,[cs:fc_c1]
	mov	[cs:dr_d],ax
	xor	ax,ax
	mov	[WORD cs:dr_sa],ax
	mov	[WORD cs:dr_sb],ax
	mov	ax,[WORD cs:dr_e1+EN_H]
	mov	[WORD cs:dr_sa+2],ax
	mov	ax,[WORD cs:dr_e2+EN_H]
	mov	[WORD cs:dr_sb+2],ax
	lea	di,[bp+FL_H]
	call	StepInitA
	mov	ax,[WORD cs:dr_e1+EN_UH]
	mov	[WORD cs:dr_sa],ax
	mov	ax,[WORD cs:dr_e1+EN_UH+2]
	mov	[WORD cs:dr_sa+2],ax
	mov	ax,[WORD cs:dr_e2+EN_UH]
	mov	[WORD cs:dr_sb],ax
	mov	ax,[WORD cs:dr_e2+EN_UH+2]
	mov	[WORD cs:dr_sb+2],ax
	lea	di,[bp+FL_UH]
	call	StepInitA

@@col:
	mov	si,[bp+FL_COL]
	cmp	si,[bp+FL_CE]
	jge	@@ret
	mov	cx,[bp+FL_H+2]				; h, at least 1
	or	cx,cx
	jnz	@@hok
	inc	cx
@@hok:
	les	bx,[DWORD cs:wk_left]		; a wall in front of it?  (every column
	cmp	[WORD es:bx],0				; is a wall's when none is left)
	je	@@claimed
	les	bx,[bp+FC_CLAIM]
	cmp	[BYTE es:bx+si],0
	je	@@front
@@claimed:
	mov	bx,si
	shl	bx,1
	cmp	cx,[wallheight+bx]
	jbe	@@next
@@front:
	mov	dx,[bp+FL_UH+2]				; u = uh/h, 0 to 63
	or	dx,dx
	js	@@u0
	cmp	dx,cx
	jae	@@u63
	mov	ax,[bp+FL_UH]
	div	cx
	cmp	ax,63
	jbe	@@uok
@@u63:
	mov	ax,63
	jmp	@@uok
@@u0:
	xor	ax,ax
@@uok:
	shl	ax,10						; frac = u << 10
	cmp	ax,[bp+FC_DP]
	jb	@@next						; the open part: what is behind shows
	sub	ax,[bp+FC_DP]
	shr	ax,4
	and	ax,0FC0h
	xor	ax,[bp+FC_FLIP]
	mov	[WORD postsource],ax
	mov	ax,[bp+FC_PAGE]
	mov	[WORD postsource+2],ax
	mov	bx,si
	shl	bx,1
	mov	[wallheight+bx],cx
	les	bx,[DWORD cs:wk_left]		; a column no wall reached: the door's now
	cmp	[WORD es:bx],0
	je	@@post
	les	bx,[bp+FC_CLAIM]
	cmp	[BYTE es:bx+si],0
	jne	@@post
	mov	[BYTE es:bx+si],1
	les	bx,[DWORD cs:wk_left]
	dec	[WORD es:bx]
@@post:
	mov	[postx],si
	mov	[postwidth],1
	call	ScalePostF					; keeps BP, DI
@@next:
	mov	ax,[bp+FL_H+4]				; H += q, the remainder carried
	add	[bp+FL_H],ax
	mov	ax,[bp+FL_H+6]
	adc	[bp+FL_H+2],ax
	mov	ax,[bp+FL_H+10]
	add	ax,[bp+FL_H+8]
	jc	@@hc
	cmp	ax,[bp+FL_H+12]
	jb	@@hn
@@hc:
	sub	ax,[bp+FL_H+12]
	add	[WORD bp+FL_H],1
	adc	[WORD bp+FL_H+2],0
@@hn:
	mov	[bp+FL_H+10],ax
	mov	ax,[bp+FL_UH+4]				; UH likewise
	add	[bp+FL_UH],ax
	mov	ax,[bp+FL_UH+6]
	adc	[bp+FL_UH+2],ax
	mov	ax,[bp+FL_UH+10]
	add	ax,[bp+FL_UH+8]
	jc	@@uc
	cmp	ax,[bp+FL_UH+12]
	jb	@@un
@@uc:
	sub	ax,[bp+FL_UH+12]
	add	[WORD bp+FL_UH],1
	adc	[WORD bp+FL_UH+2],0
@@un:
	mov	[bp+FL_UH+10],ax
	inc	[WORD bp+FL_COL]
	jmp	@@col
@@ret:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	retf
ENDP

;
; GEnd: the end at SI from its view-relative position, DX:AX = gx and
; CX:BX = gy: nx = gx*cos - gy*sin, ny = gy*cos + gx*sin (FixedByFrac)
;
PROC	GEnd NEAR
	mov	[WORD cs:fc_gy],bx
	mov	[WORD cs:fc_gy+2],cx
	call	MulCosSave					; gx*cos
	mov	[WORD cs:si+EN_NX],ax
	mov	[WORD cs:si+EN_NX+2],dx
	call	MulSinRe					; gx*sin
	mov	[WORD cs:si+EN_NY],ax
	mov	[WORD cs:si+EN_NY+2],dx
	mov	ax,[WORD cs:fc_gy]
	mov	dx,[WORD cs:fc_gy+2]
	call	MulSinSave					; gy*sin
	sub	[WORD cs:si+EN_NX],ax
	sbb	[WORD cs:si+EN_NX+2],dx
	call	MulCosRe					; gy*cos
	add	[WORD cs:si+EN_NY],ax
	adc	[WORD cs:si+EN_NY+2],dx
	ret
ENDP

fc_c1	dw	0
fc_c2	dw	0
fc_gy	dd	0

;
; FBF: id's FixedByFrac -- DX:AX times BX, a fraction, its sign in bit 15 of
; SI; DX:AX out.  Clobbers CX, DI, SI.
;
PROC	FBF NEAR
	or	dx,dx
	jns	@@pos
	neg	dx
	neg	ax
	sbb	dx,0
	xor	si,8000h
@@pos:
	mov	cx,dx
	mul	bx
	mov	di,dx
	mov	ax,cx
	mul	bx
	add	ax,di
	adc	dx,0
	test	si,8000h
	jz	@@ok
	neg	dx
	neg	ax
	sbb	dx,0
@@ok:
	ret
ENDP

;
; DX:AX = (AX:0) - viewx / - viewy: a tile line, from the camera
;
PROC	GXview NEAR
	mov	dx,ax
	xor	ax,ax
	sub	ax,[WORD viewx]
	sbb	dx,[WORD viewx+2]
	ret
ENDP

PROC	GYview NEAR
	mov	dx,ax
	xor	ax,ax
	sub	ax,[WORD viewy]
	sbb	dx,[WORD viewy+2]
	ret
ENDP

;
; DX:AX times viewcos or viewsin; the Save forms keep DX:AX in dr_g for a
; Re form after (the same operand again).  Keep SI's caller value: no.
;
PROC	MulCosSave NEAR
	mov	[WORD cs:dr_g],ax
	mov	[WORD cs:dr_g+2],dx
	push	si
	mov	bx,[WORD viewcos]
	mov	si,[WORD viewcos+2]
	call	FBF
	pop	si
	ret
ENDP

PROC	MulSinSave NEAR
	mov	[WORD cs:dr_g],ax
	mov	[WORD cs:dr_g+2],dx
	push	si
	mov	bx,[WORD viewsin]
	mov	si,[WORD viewsin+2]
	call	FBF
	pop	si
	ret
ENDP

PROC	MulCosRe NEAR
	mov	ax,[WORD cs:dr_g]
	mov	dx,[WORD cs:dr_g+2]
	push	si
	mov	bx,[WORD viewcos]
	mov	si,[WORD viewcos+2]
	call	FBF
	pop	si
	ret
ENDP

PROC	MulSinRe NEAR
	mov	ax,[WORD cs:dr_g]
	mov	dx,[WORD cs:dr_g+2]
	push	si
	mov	bx,[WORD viewsin]
	mov	si,[WORD viewsin+2]
	call	FBF
	pop	si
	ret
ENDP

;
; VEnd: the end of a run along x = line at y = AX (tiles), into the end at
; SI: nx = A - gy*sin, ny = gy*cos + D (A, D: the line's, in dr_ta, dr_td)
;
PROC	VEnd NEAR
	call	GYview
	call	MulSinSave
	mov	bx,[WORD cs:dr_ta]
	mov	cx,[WORD cs:dr_ta+2]
	sub	bx,ax
	sbb	cx,dx
	mov	[WORD cs:si+EN_NX],bx
	mov	[WORD cs:si+EN_NX+2],cx
	call	MulCosRe
	add	ax,[WORD cs:dr_td]
	adc	dx,[WORD cs:dr_td+2]
	mov	[WORD cs:si+EN_NY],ax
	mov	[WORD cs:si+EN_NY+2],dx
	ret
ENDP

;
; HEnd: the end of a run along y = line at x = AX: nx = gx*cos - B,
; ny = C + gx*sin (B, C: the line's, in dr_tb, dr_tc)
;
PROC	HEnd NEAR
	call	GXview
	call	MulCosSave
	sub	ax,[WORD cs:dr_tb]
	sbb	dx,[WORD cs:dr_tb+2]
	mov	[WORD cs:si+EN_NX],ax
	mov	[WORD cs:si+EN_NX+2],dx
	call	MulSinRe
	add	ax,[WORD cs:dr_tc]
	adc	dx,[WORD cs:dr_tc+2]
	mov	[WORD cs:si+EN_NY],ax
	mov	[WORD cs:si+EN_NY+2],dx
	ret
ENDP

;
; CF if the end at SI is nearer than NEARD (1/64 tile)
;
PROC	BelowNear NEAR
	mov	dx,[WORD cs:si+EN_NX+2]
	or	dx,dx
	js	@@yes
	jnz	@@no
	cmp	[WORD cs:si+EN_NX],400h
	jb	@@yes
@@no:
	clc
	ret
@@yes:
	stc
	ret
ENDP

;
; FracA: (DX:AX)/(CX:BX) as a 16.16 fraction 0..1 (signs alike) -> DX:AX
;
PROC	FracA NEAR
	or	cx,cx
	jns	@@dpos
	neg	dx
	neg	ax
	sbb	dx,0
	neg	cx
	neg	bx
	sbb	cx,0
@@dpos:
	or	dx,dx						; num <= 0: 0
	js	@@zero
	jnz	@@pos
	or	ax,ax
	jz	@@zero
@@pos:
	cmp	dx,cx						; num >= den: 1
	jl	@@lt
	jg	@@one
	cmp	ax,bx
	jae	@@one
@@lt:
	or	cx,cx						; den to 15 bits, num with it
	jnz	@@sh
	cmp	bx,7fffh
	jbe	@@div
@@sh:
	sar	dx,1
	rcr	ax,1
	sar	cx,1
	rcr	bx,1
	jmp	@@lt
@@div:
	mov	dx,ax						; (num << 16) / den, num < den
	xor	ax,ax
	div	bx
	xor	dx,dx
	ret
@@zero:
	xor	ax,ax
	xor	dx,dx
	ret
@@one:
	xor	ax,ax
	mov	dx,1
	ret
ENDP

;
; MulFracA: DX:AX times dr_t (16.16, 0..1) -> DX:AX
;
PROC	MulFracA NEAR
	cmp	[WORD cs:dr_t+2],0
	jne	@@whole
	push	si
	push	di
	push	cx
	mov	bx,[WORD cs:dr_t]
	xor	si,si
	call	FBF
	pop	cx
	pop	di
	pop	si
@@whole:
	ret
ENDP

;
; the cut at the near plane: t = (NEARD - nx1)/(nx2 - nx1), and the end
; behind it moved there (NearCut1: end 1; NearCut2: end 2)
;
PROC	NearT NEAR
	mov	ax,400h
	xor	dx,dx
	sub	ax,[WORD cs:dr_e1+EN_NX]
	sbb	dx,[WORD cs:dr_e1+EN_NX+2]
	mov	bx,[WORD cs:dr_e2+EN_NX]
	mov	cx,[WORD cs:dr_e2+EN_NX+2]
	sub	bx,[WORD cs:dr_e1+EN_NX]
	sbb	cx,[WORD cs:dr_e1+EN_NX+2]
	call	FracA
	mov	[WORD cs:dr_t],ax
	mov	[WORD cs:dr_t+2],dx
	ret
ENDP

;
; DX:AX = end2.field - end1.field, field at BX
;
PROC	Diff21 NEAR
	mov	ax,[WORD cs:dr_e2+bx]
	mov	dx,[WORD cs:dr_e2+bx+2]
	sub	ax,[WORD cs:dr_e1+bx]
	sbb	dx,[WORD cs:dr_e1+bx+2]
	ret
ENDP

PROC	NearCut1 NEAR
	call	NearT
	mov	bx,EN_NY					; ny1 += MulFrac (ny2-ny1,t)
	call	Diff21
	call	MulFracA
	add	[WORD cs:dr_e1+EN_NY],ax
	adc	[WORD cs:dr_e1+EN_NY+2],dx
	mov	bx,EN_U						; u1 += MulFrac (u2-u1,t)
	call	Diff21
	call	MulFracA
	add	[WORD cs:dr_e1+EN_U],ax
	adc	[WORD cs:dr_e1+EN_U+2],dx
	mov	[WORD cs:dr_e1+EN_NX],400h
	mov	[WORD cs:dr_e1+EN_NX+2],0
	ret
ENDP

PROC	NearCut2 NEAR
	call	NearT
	mov	bx,EN_NY					; ny2 = ny1 + MulFrac (ny2-ny1,t)
	call	Diff21
	call	MulFracA
	add	ax,[WORD cs:dr_e1+EN_NY]
	adc	dx,[WORD cs:dr_e1+EN_NY+2]
	mov	[WORD cs:dr_e2+EN_NY],ax
	mov	[WORD cs:dr_e2+EN_NY+2],dx
	mov	bx,EN_U						; u2 = u1 + MulFrac (u2-u1,t)
	call	Diff21
	call	MulFracA
	add	ax,[WORD cs:dr_e1+EN_U]
	adc	dx,[WORD cs:dr_e1+EN_U+2]
	mov	[WORD cs:dr_e2+EN_U],ax
	mov	[WORD cs:dr_e2+EN_U+2],dx
	mov	[WORD cs:dr_e2+EN_NX],400h
	mov	[WORD cs:dr_e2+EN_NX+2],0
	ret
ENDP

;
; u1, u2 at least 0
;
PROC	UPos NEAR
	cmp	[WORD cs:dr_e1+EN_U+2],0
	jge	@@u1
	mov	[WORD cs:dr_e1+EN_U],0
	mov	[WORD cs:dr_e1+EN_U+2],0
@@u1:
	cmp	[WORD cs:dr_e2+EN_U+2],0
	jge	@@u2
	mov	[WORD cs:dr_e2+EN_U],0
	mov	[WORD cs:dr_e2+EN_U+2],0
@@u2:
	ret
ENDP

;
; CF if the end at SI is outside COLLO..COLHI (-100 to viewwidth+100
; columns, in 64ths)
;
PROC	ColFar NEAR
	mov	ax,[WORD cs:si+EN_COL]
	mov	dx,[WORD cs:si+EN_COL+2]
	cmp	dx,0FFFFh					; below -6400 (0FFFFE700h)?
	jl	@@yes
	jne	@@hi
	cmp	ax,0E700h
	jb	@@yes
	clc
	ret
@@hi:
	or	dx,dx
	jnz	@@yes
	mov	bx,[viewwidth]
	add	bx,100
	shl	bx,6
	cmp	ax,bx
	ja	@@yes
	clc
	ret
@@yes:
	stc
	ret
ENDP

;
; BSPClaim (2026-10-04, from WL_BSP.C's Claim): [cs,ce) is claimed, merged
; with every range in solid[] it overlaps or touches.  solid[] ends with a
; range reaching 7FFFh, so the first search needs no bound.  The count is
; the C's nsolid, through the pointer BSPNSolid was given.
;
CL_MAX	=	(320/2+4)*4					; MAXSOLID, in bytes

;
; BSPNoLod: NOLOD -- every column textured, however far the wall
;
PROC	BSPNoLod FAR
PUBLIC	BSPNoLod
	mov	[cs:bc_lod1],0
	mov	[cs:bc_lod2],0
	retf
ENDP
		db	0						; (parity)

PROC	BSPNSolid FAR
PUBLIC	BSPNSolid
	push	bp
	mov	bp,sp
	mov	ax,[bp+6]
	mov	[WORD cs:wk_nsolid],ax
	mov	ax,[bp+8]
	mov	[WORD cs:wk_nsolid+2],ax
	pop	bp
	retf
ENDP

PROC	BSPClaim FAR
PUBLIC	BSPClaim
	push	bp
	mov	bp,sp
	push	si
	push	di
	push	ds
	mov	ax,[bp+6]					; cs
	mov	dx,[bp+8]					; ce
	les	di,[DWORD cs:wk_nsolid]
	mov	cx,[es:di]
	shl	cx,2						; nsolid, in bytes
	lds	bx,[DWORD cs:wk_solid]		; DS:BX the ranges
	xor	si,si
@@fi:
	cmp	[bx+si+2],ax				; i: the first ending at cs or after
	jge	@@gi
	add	si,4
	jmp	@@fi
@@gi:
	mov	di,si
@@fj:
	cmp	di,cx						; j: past every one starting by ce
	jge	@@gj
	cmp	[bx+di],dx
	jg	@@gj
	add	di,4
	jmp	@@fj
@@gj:
	cmp	di,si
	jne	@@merge
	cmp	cx,CL_MAX					; touches nothing: a new range at i
	jge	@@ret
	mov	[cs:cl_a],ax
	mov	[cs:cl_b],dx
	mov	[cs:cl_i],si
	push	ds
	pop	es
	mov	dx,cx						; the words from i to the end, moved up
	sub	dx,si
	shr	dx,1
	mov	si,bx
	add	si,cx
	sub	si,2
	mov	di,si
	add	di,4
	mov	cx,dx
	std
	rep	movsw
	cld
	mov	si,[cs:cl_i]
	mov	ax,[cs:cl_a]
	mov	[bx+si],ax
	mov	ax,[cs:cl_b]
	mov	[bx+si+2],ax
	les	di,[DWORD cs:wk_nsolid]
	inc	[WORD es:di]
	jmp	@@ret
@@merge:
	cmp	ax,[bx+si]					; solid[i].a = min (it, cs)
	jge	@@a
	mov	[bx+si],ax
@@a:
	mov	ax,[bx+di-2]				; solid[i].b = max (ce, solid[j-1].b)
	cmp	dx,ax
	jle	@@b
	mov	ax,dx
@@b:
	mov	[bx+si+2],ax
	mov	ax,di
	sub	ax,si
	cmp	ax,4
	jle	@@ret
	mov	[cs:cl_d],ax				; more than one merged: close the gap
	push	ds
	pop	es
	mov	dx,cx
	sub	dx,di
	shr	dx,1
	lea	ax,[bx+di]
	lea	di,[bx+si+4]
	mov	si,ax
	mov	cx,dx
	cld
	rep	movsw
	mov	ax,[cs:cl_d]
	shr	ax,2
	dec	ax
	les	di,[DWORD cs:wk_nsolid]
	sub	[es:di],ax
@@ret:
	pop	ds
	pop	di
	pop	si
	pop	bp
	retf
ENDP

cl_a	dw	0
cl_b	dw	0
cl_i	dw	0
cl_d	dw	0
wk_nsolid	dd	0
		db	0						; (parity: what follows stays where it was)

;
; ColHeightA: WL_BSP.C's ColHeight for the end at SI (nx, ny, u in, col,
; h, uh out)
;
PROC	ColHeightA NEAR
	mov	[cs:ch_neg],0
	mov	ax,[WORD cs:si+EN_NY]
	mov	dx,[WORD cs:si+EN_NY+2]
	or	dx,dx
	jns	@@nypos
	neg	dx
	neg	ax
	sbb	dx,0
	mov	[cs:ch_neg],1
@@nypos:
	mov	[WORD cs:ch_ny],ax
	mov	[WORD cs:ch_ny+2],dx
	mov	cx,[WORD cs:si+EN_NX+1]		; h = heightnumerator / (nx>>8)
	mov	ax,[WORD heightnumerator]
	mov	dx,[WORD heightnumerator+2]
	cmp	dx,cx
	jae	@@hclamp
	div	cx
	cmp	ax,7fffh
	jbe	@@hok
@@hclamp:
	mov	ax,7fffh
@@hok:
	mov	[WORD cs:si+EN_H],ax
	mul	[WORD cs:si+EN_U]			; uh = u*h
	mov	[WORD cs:si+EN_UH],ax
	mov	[WORD cs:si+EN_UH+2],dx
	mov	ax,[WORD cs:ch_ny]			; m = |ny|*scale
	mul	[WORD scale]
	mov	cx,ax
	mov	bx,dx
	mov	ax,[WORD cs:ch_ny+2]
	mul	[WORD scale]
	add	bx,ax
	mov	ax,[WORD cs:si+EN_NX]
	mov	dx,[WORD cs:si+EN_NX+2]
@@norm8:
	or	dh,dh						; (2026-10-04) a byte at a time while the
	jz	@@norm						; top byte is set -- such a value needs
	mov	al,ah						; ten shifts or more, so never too many
	mov	ah,dl
	mov	dl,dh
	xor	dh,dh
	mov	cl,ch
	mov	ch,bl
	mov	bl,bh
	xor	bh,bh
	jmp	@@norm8
@@norm:
	or	dx,dx
	jnz	@@shift
	test	ax,8000h
	jz	@@div
@@shift:
	shr	dx,1
	rcr	ax,1
	shr	bx,1
	rcr	cx,1
	jmp	@@norm
@@div:
	mov	[cs:ch_n],ax
	mov	ax,bx
	xor	dx,dx
	div	[WORD cs:ch_n]
	or	ax,ax
	jnz	@@far
	mov	ax,cx
	div	[WORD cs:ch_n]
	cmp	ax,7fffh
	ja	@@far
	mov	[cs:ch_q],ax
	mov	ax,dx
	mov	cx,64
	mul	cx
	div	[WORD cs:ch_n]
	mov	[cs:ch_f],ax
	jmp	@@col
@@far:
	mov	[WORD cs:ch_q],7fffh
	mov	[WORD cs:ch_f],0
@@col:
	mov	ax,[cs:ch_q]				; off = q*64 + f
	mov	cx,64
	mul	cx
	add	ax,[cs:ch_f]
	adc	dx,0
	cmp	[cs:ch_neg],0
	je	@@pl
	neg	dx
	neg	ax
	sbb	dx,0
@@pl:
	mov	bx,[centerx]				; col = centerx*64 +- off
	shl	bx,6
	add	ax,bx
	adc	dx,0
	mov	[WORD cs:si+EN_COL],ax
	mov	[WORD cs:si+EN_COL+2],dx
	ret
ENDP

;
; MulS16A: (DX:AX) * BX, signed, the low 32 bits -> DX:AX.  Clobbers CX.
;
PROC	MulS16A NEAR
	push	si
	xor	si,si
	or	dx,dx
	jns	@@xp
	neg	dx
	neg	ax
	sbb	dx,0
	xor	si,1
@@xp:
	or	bx,bx
	jns	@@kp
	neg	bx
	xor	si,1
@@kp:
	mov	cx,ax
	mov	ax,dx
	mul	bx
	push	ax
	mov	ax,cx
	mul	bx
	pop	cx
	add	dx,cx
	or	si,si
	jz	@@r
	neg	dx
	neg	ax
	sbb	dx,0
@@r:
	pop	si
	ret
ENDP

;
; d for the end at SI: (ny>>4)*a + (nx>>4)*b, a and b in sc_a, sc_b
;
PROC	SideD NEAR
	mov	ax,[WORD cs:si+EN_NY]
	mov	dx,[WORD cs:si+EN_NY+2]
	REPT 4
	sar	dx,1
	rcr	ax,1
	ENDM
	mov	bx,[cs:sc_a]
	call	MulS16A
	push	dx
	push	ax
	mov	ax,[WORD cs:si+EN_NX]
	mov	dx,[WORD cs:si+EN_NX+2]
	REPT 4
	sar	dx,1
	rcr	ax,1
	ENDM
	mov	bx,[cs:sc_b]
	call	MulS16A
	pop	bx
	pop	cx
	add	ax,bx
	adc	dx,cx
	ret
ENDP

;
; SideClipA: WL_BSP.C's SideClip, AX = a, BX = b; CF when the run is wholly
; outside that side
;
PROC	SideClipA NEAR
	mov	[cs:sc_a],ax
	mov	[cs:sc_b],bx
	mov	si,OFFSET dr_e1
	call	SideD
	mov	[WORD cs:sc_d1],ax
	mov	[WORD cs:sc_d1+2],dx
	mov	si,OFFSET dr_e2
	call	SideD
	mov	[WORD cs:sc_d2],ax
	mov	[WORD cs:sc_d2+2],dx
	mov	cx,[WORD cs:sc_d1+2]
	or	cx,dx
	jns	@@in						; both at or above 0
	mov	cx,[WORD cs:sc_d1+2]
	and	cx,dx
	js	@@out						; both below
	mov	ax,[WORD cs:sc_d1]			; t = Frac (d1, d1-d2)
	mov	dx,[WORD cs:sc_d1+2]
	mov	bx,ax
	mov	cx,dx
	sub	bx,[WORD cs:sc_d2]
	sbb	cx,[WORD cs:sc_d2+2]
	call	FracA
	mov	[WORD cs:dr_t],ax
	mov	[WORD cs:dr_t+2],dx
	cmp	[WORD cs:sc_d1+2],0
	jge	@@cut2
	mov	bx,EN_NX					; end 1 moved
	call	Diff21
	call	MulFracA
	push	dx
	push	ax
	mov	bx,EN_NY
	call	Diff21
	call	MulFracA
	push	dx
	push	ax
	mov	bx,EN_U
	call	Diff21
	call	MulFracA
	add	[WORD cs:dr_e1+EN_U],ax
	adc	[WORD cs:dr_e1+EN_U+2],dx
	pop	ax
	pop	dx
	add	[WORD cs:dr_e1+EN_NY],ax
	adc	[WORD cs:dr_e1+EN_NY+2],dx
	pop	ax
	pop	dx
	add	[WORD cs:dr_e1+EN_NX],ax
	adc	[WORD cs:dr_e1+EN_NX+2],dx
	jmp	@@in
@@cut2:
	mov	bx,EN_NX					; end 2 = end 1 + MulFrac (diff,t)
	call	Diff21
	call	MulFracA
	push	dx
	push	ax
	mov	bx,EN_NY
	call	Diff21
	call	MulFracA
	push	dx
	push	ax
	mov	bx,EN_U
	call	Diff21
	call	MulFracA
	add	ax,[WORD cs:dr_e1+EN_U]
	adc	dx,[WORD cs:dr_e1+EN_U+2]
	mov	[WORD cs:dr_e2+EN_U],ax
	mov	[WORD cs:dr_e2+EN_U+2],dx
	pop	ax
	pop	dx
	add	ax,[WORD cs:dr_e1+EN_NY]
	adc	dx,[WORD cs:dr_e1+EN_NY+2]
	mov	[WORD cs:dr_e2+EN_NY],ax
	mov	[WORD cs:dr_e2+EN_NY+2],dx
	pop	ax
	pop	dx
	add	ax,[WORD cs:dr_e1+EN_NX]
	adc	dx,[WORD cs:dr_e1+EN_NX+2]
	mov	[WORD cs:dr_e2+EN_NX],ax
	mov	[WORD cs:dr_e2+EN_NX+2],dx
@@in:
	clc
	ret
@@out:
	stc
	ret
ENDP

;
; MulDivFloorA: floor((DX:AX)*CX / BX) -> DX:AX, its remainder (0..BX-1)
; in DI -- 48-bit product, three DIVs (WL_BSP.C's MulDivFloor)
;
PROC	MulDivFloorA NEAR
	push	si
	xor	si,si
	or	dx,dx
	jns	@@pos
	neg	dx
	neg	ax
	sbb	dx,0
	inc	si
@@pos:
	push	bx
	mov	bx,dx						; hi
	mul	cx							; lo*x
	mov	[cs:md_p0],ax
	mov	di,dx
	mov	ax,bx
	mul	cx							; hi*x
	add	ax,di
	adc	dx,0						; DX:AX = p2:p1
	pop	cx							; the divisor
	mov	bx,ax
	mov	ax,dx
	xor	dx,dx
	div	cx
	mov	ax,bx
	div	cx
	mov	bx,ax						; q1
	mov	ax,[cs:md_p0]
	div	cx							; AX = q0, DX = r
	mov	di,dx
	mov	dx,bx
	or	si,si
	jz	@@r
	or	di,di
	jz	@@exact
	neg	dx							; -w - 1, rem d - r
	neg	ax
	sbb	dx,0
	sub	ax,1
	sbb	dx,0
	neg	di
	add	di,cx
	jmp	@@r
@@exact:
	neg	dx
	neg	ax
	sbb	dx,0
@@r:
	pop	si
	ret
ENDP

;
; StepInitA: the bspstep at SS:DI from dr_sa to dr_sb over dr_d 64ths,
; starting dr_off in: q = floor (dv*64/d), v = a + floor (dv*off/d)
;
PROC	StepInitA NEAR
	mov	ax,[cs:dr_d]
	mov	[di+12],ax					; d (bspstep: v 0, q 4, r 8, e 10, d 12)
	mov	ax,[WORD cs:dr_sb]
	mov	dx,[WORD cs:dr_sb+2]
	sub	ax,[WORD cs:dr_sa]
	sbb	dx,[WORD cs:dr_sa+2]
	mov	[WORD cs:dr_dv],ax
	mov	[WORD cs:dr_dv+2],dx
	push	di
	mov	cx,64
	mov	bx,[cs:dr_d]
	call	MulDivFloorA
	mov	bx,di
	pop	di
	mov	[di+4],ax					; q
	mov	[di+6],dx
	mov	[di+8],bx					; r
	mov	ax,[WORD cs:dr_dv]
	mov	dx,[WORD cs:dr_dv+2]
	push	di
	mov	cx,[cs:dr_off]
	mov	bx,[cs:dr_d]
	call	MulDivFloorA
	mov	bx,di
	pop	di
	add	ax,[WORD cs:dr_sa]
	adc	dx,[WORD cs:dr_sa+2]
	mov	[di],ax						; v
	mov	[di+2],dx
	mov	[di+10],bx					; e
	ret
ENDP

;
; CoveredA: BX, AX two rough columns (either way round): CF if every column
; between them, widened by 4, is claimed already, or none is on the screen
;
PROC	CoveredA NEAR
	cmp	bx,ax
	jle	@@ord
	xchg	bx,ax
@@ord:
	sub	bx,BH_SLACK
	add	ax,BH_SLACK+1
	or	bx,bx
	jns	@@c1pos
	xor	bx,bx
@@c1pos:
	cmp	ax,[viewwidth]
	jle	@@c2ok
	mov	ax,[viewwidth]
@@c2ok:
	cmp	bx,ax
	jge	@@yes
	les	si,[DWORD cs:wk_solid]
@@find:
	cmp	[es:si+2],bx
	jg	@@found
	add	si,4
	jmp	@@find
@@found:
	cmp	[es:si],bx
	jg	@@no
	cmp	[es:si+2],ax
	jl	@@no
@@yes:
	stc
	ret
@@no:
	clc
	ret
ENDP

dr_of	dw	0
dr_line	dw	0
dr_a1	dw	0
dr_a2	dw	0
dr_e1	db	EN_SIZE DUP (0)			; the run's two ends, and one to swap with
dr_e2	db	EN_SIZE DUP (0)
dr_et	db	EN_SIZE DUP (0)
dr_g	dd	0
dr_ta	dd	0
dr_tb	dd	0
dr_tc	dd	0
dr_td	dd	0
dr_t	dd	0
dr_sa	dd	0
dr_sb	dd	0
dr_dv	dd	0
dr_off	dw	0
dr_d	dw	0
ch_neg	dw	0
ch_ny	dd	0
ch_n	dw	0
ch_q	dw	0
ch_f	dw	0
sc_a	dw	0
sc_b	dw	0
sc_d1	dd	0
sc_d2	dd	0
md_p0	dw	0

bh_tab	db	4,2,0,6, 0,2,4,2, 0,2,4,6	; per case: the two corners' x and y,
		db	0,2,0,6, 0,0,0,0, 4,2,4,6	; as offsets into bx_box (x1 0, y1 2,
		db	0,2,4,6, 0,6,4,6, 4,2,0,6	; x2 4, y2 6)
bh_c1	dw	0
bx_box	dw	4 DUP (0)				; the box being tested, in tiles
bv_sel2	dw	6 DUP (0)				; each plane's corner, as bx_box offsets
wk_nodes	dd	0
wk_runs		dd	0
wk_solid	dd	0
wk_left		dd	0
wk_cnt		dw	5 DUP (0)			; nodes, culled, hidden, runs drawn, runs hidden



bv_cx		dw	0				; the camera, 8.8 tiles
bv_cy		dw	0
bv_p		dw	6 DUP (0)		; three planes' normals, 8.8
bv_sel		dw	6 DUP (0)		; the frame offsets of each plane's corner
bv_box		dw	4 DUP (0)		; x1, y1, x2, y2: what can be seen
vt_dx		dw	0
vt_dy		dw	0
vt_nx		dd	0
bv_in		dw	0				; BSPClassify: 2 while wholly inside


;============================
;
; LDivS (step 98, StevenC & Claude): DX:AX / CX:BX, signed by unsigned, the
; quotient truncated toward zero as C's long division gives it -- for
; TransformActorA and TransformTile's ny*scale/nx.  Borland's LDIV@ divides
; a bit at a time whenever the divisor passes 16 bits, which nx nearly
; always does.  Here: the divisor shifted to 16 bits (and the dividend with
; it), one DIV for an estimate, then the estimate corrected exactly --
; q*D is never more than the dividend, and the remainder is less than D.
; A quotient of 64K or more goes to LDIV@ as before (an object far off to
; the side; never in the attract loop).  Python checked the method against
; exact division over 2,000,000 random cases.  Keeps BP, DS, ES.
;
;============================

PROC	LDivS NEAR
	xor	si,si
	or	dx,dx
	jns	@@npos
	neg	dx
	neg	ax
	sbb	dx,0
	inc	si							; the quotient negated at the end
@@npos:
	or	cx,cx
	jnz	@@wide
	mov	di,ax						; a 16-bit divisor: two DIVs, exact
	mov	ax,dx
	xor	dx,dx
	div	bx
	mov	cx,ax
	mov	ax,di
	div	bx
	mov	dx,cx
	jmp	@@sign
@@wide:
	mov	[cs:ld_nlo],ax
	mov	[cs:ld_nhi],dx
	mov	[cs:ld_dlo],bx
	mov	[cs:ld_dhi],cx
@@norm:
	shr	cx,1
	rcr	bx,1
	shr	dx,1
	rcr	ax,1
	or	cx,cx
	jnz	@@norm
	cmp	dx,bx
	jae	@@slow						; the quotient would pass 16 bits
	div	bx
	mov	di,ax						; the estimate
@@check:
	mov	ax,di						; P = q*D, 48 bits
	mul	[cs:ld_dlo]
	mov	bx,ax
	mov	cx,dx
	mov	ax,di
	mul	[cs:ld_dhi]
	add	cx,ax
	adc	dx,0
	or	dx,dx						; P > N: one less
	jnz	@@less
	cmp	cx,[cs:ld_nhi]
	ja	@@less
	jb	@@notmore
	cmp	bx,[cs:ld_nlo]
	ja	@@less
@@notmore:
	mov	ax,[cs:ld_nlo]				; N - P >= D: one more
	mov	dx,[cs:ld_nhi]
	sub	ax,bx
	sbb	dx,cx
	cmp	dx,[cs:ld_dhi]
	jb	@@exact
	ja	@@more
	cmp	ax,[cs:ld_dlo]
	jb	@@exact
@@more:
	cmp	di,0FFFFh
	je	@@slow
	inc	di
	jmp	@@check
@@less:
	dec	di
	jmp	@@check
@@exact:
	mov	ax,di
	xor	dx,dx
@@sign:
	or	si,si
	jz	@@ret
	neg	dx
	neg	ax
	sbb	dx,0
@@ret:
	ret
@@slow:
	push	[cs:ld_dhi]					; LDIV@ (dividend, divisor), as before:
	push	[cs:ld_dlo]					; the dividend made positive, so the sign
	push	[cs:ld_nhi]					; is ours to put back
	push	[cs:ld_nlo]
	call	F_LDIV@						; pops its own arguments
	jmp	@@sign
ENDP

ld_nlo	dw	0
ld_nhi	dw	0
ld_dlo	dw	0
ld_dhi	dw	0


;============================
;
; TransformActorA -- SI = the actor
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's TransformActor, called NEAR
; from PlaceActors for every actor in a visible tile.  The C made four far
; calls to FixedByFrac with long arguments on the stack and one to LXMUL@;
; here they are inline, as in TransformTile below, whose arithmetic this is
; with the actor's own x and y, ACTORSIZE (4000h) for the fudge, and the
; results stored in the actor:
;
;	gx = ob->x-viewx;  gy = ob->y-viewy;
;	nx = FixedByFrac(gx,viewcos) - FixedByFrac(gy,viewsin) - ACTORSIZE;
;	ny = FixedByFrac(gy,viewcos) + FixedByFrac(gx,viewsin);
;	ob->transx = nx;  ob->transy = ny;
;	if (nx<mindist) { ob->viewheight = 0; return; }
;	ob->viewx = centerx + ny*scale/nx;
;	ob->viewheight = heightnumerator/(nx>>8);		; one IDIV, as the C
;
; Keeps SI, DI and BP, as the C did.  The actor is addressed through BP,
; which reads SS -- DGROUP, like DS -- because FIXBYFRAC needs SI.
;
;============================

PROC	TransformActorA NEAR
PUBLIC	TransformActorA				; public only so profiles can name it
	push	si
	push	di
	push	bp
	mov	bp,si

	mov	ax,[bp+OB_X]				; gx = ob->x-viewx
	mov	dx,[bp+OB_X+2]
	sub	ax,[WORD viewx]
	sbb	dx,[WORD viewx+2]
	mov	[WORD ttgx],ax
	mov	[WORD ttgx+2],dx
	mov	ax,[bp+OB_Y]				; gy = ob->y-viewy
	mov	dx,[bp+OB_Y+2]
	sub	ax,[WORD viewy]
	sbb	dx,[WORD viewy+2]
	mov	[WORD ttgy],ax
	mov	[WORD ttgy+2],dx

	mov	ax,[WORD ttgx]				; nx
	mov	dx,[WORD ttgx+2]
	FIXBYFRAC	viewcos
	mov	[WORD ttnx],ax
	mov	[WORD ttnx+2],dx
	mov	ax,[WORD ttgy]
	mov	dx,[WORD ttgy+2]
	FIXBYFRAC	viewsin
	sub	[WORD ttnx],ax
	sbb	[WORD ttnx+2],dx
	sub	[WORD ttnx],4000h			; ACTORSIZE
	sbb	[WORD ttnx+2],0

	mov	ax,[WORD ttgy]				; ny
	mov	dx,[WORD ttgy+2]
	FIXBYFRAC	viewcos
	mov	[WORD ttny],ax
	mov	[WORD ttny+2],dx
	mov	ax,[WORD ttgx]
	mov	dx,[WORD ttgx+2]
	FIXBYFRAC	viewsin
	add	ax,[WORD ttny]
	adc	dx,[WORD ttny+2]
	mov	[WORD ttny],ax
	mov	[WORD ttny+2],dx
	mov	[bp+OB_TRANSY],ax			; ob->transy = ny
	mov	[bp+OB_TRANSY+2],dx

	mov	ax,[WORD ttnx]
	mov	dx,[WORD ttnx+2]
	mov	[bp+OB_TRANSX],ax			; ob->transx = nx
	mov	[bp+OB_TRANSX+2],dx
	cmp	dx,[WORD mindist+2]			; too close?  (signed long compare)
	jg	@@far
	jl	@@close
	cmp	ax,[WORD mindist]
	jae	@@far
@@close:
	mov	[WORD bp+OB_VIEWHEIGHT],0
	jmp	@@ret

@@far:
	mov	ax,[WORD ttny]				; ny*scale, low 32 bits
	mul	[WORD scale]
	mov	si,ax
	mov	di,dx
	mov	ax,[WORD ttny+2]
	mul	[WORD scale]
	add	di,ax
	mov	ax,[WORD ttny]
	mul	[WORD scale+2]
	add	di,ax						; DI:SI = ny*scale
	mov	ax,si						; DI:SI / nx (step 98: LDivS, not
	mov	dx,di						; Borland's LDIV@)
	mov	bx,[WORD ttnx]
	mov	cx,[WORD ttnx+2]
	call	LDivS
	add	ax,[centerx]
	mov	[bp+OB_VIEWX],ax			; ob->viewx

	mov	ax,[WORD heightnumerator]
	mov	dx,[WORD heightnumerator+2]
	idiv	[WORD ttnx+1]				; nx>>8
	mov	[bp+OB_VIEWHEIGHT],ax		; ob->viewheight

@@ret:
	pop	bp
	pop	di
	pop	si
	ret
ENDP


;============================
;
; TransformTile (int tx, int ty, int *dispx, int *dispheight)
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's routine, once per visible
; static object, which was four far calls to FixedByFrac and two to
; Borland's long multiply and divide helpers.  The same arithmetic:
;
;	gx = ((long)tx<<TILESHIFT)+0x8000-viewx;
;	gy = ((long)ty<<TILESHIFT)+0x8000-viewy;
;	nx = FixedByFrac(gx,viewcos) - FixedByFrac(gy,viewsin) - 0x2000;
;	ny = FixedByFrac(gy,viewcos) + FixedByFrac(gx,viewsin);
;	if (nx<mindist)
;		{ *dispheight = 0; return false; }
;	*dispx = centerx + ny*scale/nx;
;	*dispheight = heightnumerator/(int)(nx>>8);			; one IDIV
;	return (nx<TILEGLOBAL && ny>-TILEGLOBAL/2 && ny<TILEGLOBAL/2);
;
; ny*scale is the low 32 bits of a long product, as Borland's LXMUL@ keeps
; them -- three MULs; the divide is still Borland's LDIV@, which has the
; V30 fast path, so the truncation is its own.
;
;============================

PROC	TransformTile
PUBLIC	TransformTile
	push	bp
	mov	bp,sp
	push	si
	push	di

	mov	ax,8000h					; gx = (tx:8000h) - viewx
	mov	dx,[bp+6]
	sub	ax,[WORD viewx]
	sbb	dx,[WORD viewx+2]
	mov	[WORD ttgx],ax
	mov	[WORD ttgx+2],dx
	mov	ax,8000h					; gy = (ty:8000h) - viewy
	mov	dx,[bp+8]
	sub	ax,[WORD viewy]
	sbb	dx,[WORD viewy+2]
	mov	[WORD ttgy],ax
	mov	[WORD ttgy+2],dx

	mov	ax,[WORD ttgx]				; nx
	mov	dx,[WORD ttgx+2]
	FIXBYFRAC	viewcos
	mov	[WORD ttnx],ax
	mov	[WORD ttnx+2],dx
	mov	ax,[WORD ttgy]
	mov	dx,[WORD ttgy+2]
	FIXBYFRAC	viewsin
	sub	[WORD ttnx],ax
	sbb	[WORD ttnx+2],dx
	sub	[WORD ttnx],2000h			; the size of an object
	sbb	[WORD ttnx+2],0

	mov	ax,[WORD ttgy]				; ny
	mov	dx,[WORD ttgy+2]
	FIXBYFRAC	viewcos
	mov	[WORD ttny],ax
	mov	[WORD ttny+2],dx
	mov	ax,[WORD ttgx]
	mov	dx,[WORD ttgx+2]
	FIXBYFRAC	viewsin
	add	[WORD ttny],ax
	adc	[WORD ttny+2],dx

	mov	ax,[WORD ttnx]				; too close?  (signed long compare)
	mov	dx,[WORD ttnx+2]
	cmp	dx,[WORD mindist+2]
	jg	@@far
	jl	@@close
	cmp	ax,[WORD mindist]
	jae	@@far
@@close:
	mov	bx,[bp+12]
	mov	[WORD bx],0					; *dispheight = 0
	xor	ax,ax						; return false
	jmp	@@ret

@@far:
	mov	ax,[WORD ttny]				; ny*scale, low 32 bits
	mul	[WORD scale]
	mov	si,ax
	mov	di,dx
	mov	ax,[WORD ttny+2]
	mul	[WORD scale]
	add	di,ax
	mov	ax,[WORD ttny]
	mul	[WORD scale+2]
	add	di,ax						; DI:SI = ny*scale
	mov	ax,si						; DI:SI / nx (step 98: LDivS, not
	mov	dx,di						; Borland's LDIV@)
	mov	bx,[WORD ttnx]
	mov	cx,[WORD ttnx+2]
	call	LDivS
	add	ax,[centerx]
	mov	bx,[bp+10]
	mov	[bx],ax						; *dispx

	mov	ax,[WORD heightnumerator]
	mov	dx,[WORD heightnumerator+2]
	idiv	[WORD ttnx+1]				; nx>>8
	mov	bx,[bp+12]
	mov	[bx],ax						; *dispheight

	xor	ax,ax						; see if it should be grabbed
	cmp	[WORD ttnx+2],0
	jg	@@ret						; nx >= TILEGLOBAL
	mov	dx,[WORD ttny+2]
	mov	cx,[WORD ttny]
	cmp	dx,-1						; ny > -TILEGLOBAL/2 ?
	jl	@@ret
	jg	@@nyabove
	cmp	cx,8000h
	jbe	@@ret
@@nyabove:
	cmp	dx,0						; ny < TILEGLOBAL/2 ?
	jg	@@ret
	jl	@@grab
	cmp	cx,8000h
	jae	@@ret
@@grab:
	mov	ax,1
@@ret:
	pop	di
	pop	si
	pop	bp
	retf
ENDP


;============================
;
; AsmRefresh
;
;
;============================

PROC	AsmRefresh
PUBLIC	AsmRefresh

	push	si
	push	di
	push	bp

	mov	al,[vismark]			; NEC V30 build: this frame's mark, patched into
	mov	[BYTE cs:vspotop+4],al		; the two spotvis stores (C6 84 disp16 imm8)
	mov	[BYTE cs:hspotop+4],al

	mov	ax,[WORD viewx]			; and CalcHeight's constants for this frame,
								; in all three of its forms
	mov	[WORD cs:chvxlo+1],ax
	mov	[WORD cs:cvvxlo+1],ax
	mov	[WORD cs:cvvxloc+1],ax
	mov	[WORD cs:czvxlo+1],ax
	mov	[WORD cs:czvxloc+1],ax
	mov	ax,[WORD viewx+2]
	mov	[WORD cs:chvxhi+2],ax
	mov	[WORD cs:cvvxhi+2],ax
	mov	[WORD cs:cvvxhic+2],ax
	mov	[WORD cs:czvxhi+2],ax
	mov	[WORD cs:czvxhic+2],ax
	mov	ax,[WORD viewy]
	mov	[WORD cs:chvylo+1],ax
	mov	[WORD cs:cvvylo+1],ax
	mov	[WORD cs:cvvyloc+1],ax
	mov	[WORD cs:czvylo+1],ax
	mov	[WORD cs:czvyloc+1],ax
	mov	ax,[WORD viewy+2]
	mov	[WORD cs:chvyhi+2],ax
	mov	[WORD cs:cvvyhi+2],ax
	mov	[WORD cs:cvvyhic+2],ax
	mov	[WORD cs:czvyhi+2],ax
	mov	[WORD cs:czvyhic+2],ax
	mov	ax,[WORD viewcos+2]
	mov	[WORD cs:chcossign+1],ax
	mov	[WORD cs:cvcossign+1],ax
	mov	[WORD cs:cvcossignc+1],ax
	mov	[WORD cs:czcossign+1],ax
	mov	[WORD cs:czcossignc+1],ax
	mov	ax,[WORD viewcos]
	mov	[WORD cs:chcosfrac+1],ax
	mov	[WORD cs:cvcosfrac+1],ax
	mov	[WORD cs:cvcosfracc+1],ax
	mov	[WORD cs:czcosfrac+1],ax
	mov	[WORD cs:czcosfracc+1],ax
	mov	ax,[WORD viewsin+2]
	mov	[WORD cs:chsinsign+1],ax
	mov	[WORD cs:cvsinsign+1],ax
	mov	[WORD cs:cvsinsignc+1],ax
	mov	[WORD cs:czsinsign+1],ax
	mov	[WORD cs:czsinsignc+1],ax
	mov	ax,[WORD viewsin]
	mov	[WORD cs:chsinfrac+1],ax
	mov	[WORD cs:cvsinfrac+1],ax
	mov	[WORD cs:cvsinfracc+1],ax
	mov	[WORD cs:czsinfrac+1],ax
	mov	[WORD cs:czsinfracc+1],ax
	mov	ax,[WORD mindist+2]
	mov	[WORD cs:chmdhi+2],ax
	mov	[WORD cs:chmdhi2+1],ax
	mov	[WORD cs:cvmdhi+2],ax
	mov	[WORD cs:cvmdhic+2],ax
	mov	[WORD cs:cvmdhi2+1],ax
	mov	[WORD cs:cvmdhi2c+1],ax
	mov	[WORD cs:czmdhi+2],ax
	mov	[WORD cs:czmdhic+2],ax
	mov	[WORD cs:czmdhi2+1],ax
	mov	[WORD cs:czmdhi2c+1],ax
	mov	ax,[WORD mindist]
	mov	[WORD cs:chmdlo+2],ax
	mov	[WORD cs:chmdlo2+1],ax
	mov	[WORD cs:cvmdlo+2],ax
	mov	[WORD cs:cvmdloc+2],ax
	mov	[WORD cs:cvmdlo2+1],ax
	mov	[WORD cs:cvmdlo2c+1],ax
	mov	[WORD cs:czmdlo+2],ax
	mov	[WORD cs:czmdloc+2],ax
	mov	[WORD cs:czmdlo2+1],ax
	mov	[WORD cs:czmdlo2c+1],ax
	mov	ax,[WORD heightnumerator]
	mov	[WORD cs:chhnlo+1],ax
	mov	[WORD cs:cvhnlo+1],ax
	mov	[WORD cs:cvhnloc+1],ax
	mov	[WORD cs:czhnlo+1],ax
	mov	[WORD cs:czhnloc+1],ax
	mov	ax,[WORD heightnumerator+2]
	mov	[WORD cs:chhnhi+1],ax
	mov	[WORD cs:cvhnhi+1],ax
	mov	[WORD cs:cvhnhic+1],ax
	mov	[WORD cs:czhnhi+1],ax
	mov	[WORD cs:czhnhic+1],ax
	mov	[chvkey],8000h			; and the wall caches are empty
	mov	[chhkey],8000h
	mov	[postmin],7FFFh			; step 62: no posts yet this frame

	mov	ax,[midangle]			; step 57: the frame's centre angle and width
	mov	[WORD cs:pxmid+1],ax
	mov	ax,[viewwidth]
	mov	[WORD cs:npvw+2],ax
	mov	ax,[pixstep]			; step 79: LOWDETAIL's step, everywhere it counts
	mov	[BYTE cs:wideadd1+4],al
	mov	[BYTE cs:wideadd2+4],al
	mov	[WORD cs:postw1+4],ax
	mov	[WORD cs:postw2+4],ax
	mov	[WORD cs:postw3+4],ax
	mov	[WORD cs:postw4+4],ax
	mov	[BYTE cs:pxstep+2],al	; step 97: ADD BX,pixstep
	xor	cx,cx					; (2026-10-04) the walk's level of detail,
	xor	dx,dx					; at full detail only
	cmp	ax,1
	jne	@@nolod
	mov	cx,[cs:bc_lod1]
	mov	dx,[cs:bc_lod2]
@@nolod:
	mov	[WORD cs:wl_lod1k-2],cx
	mov	[WORD cs:wl_lod2k-2],dx
	mov	cx,[viewwidth]
	dec	cx
	mov	[WORD cs:wl_vw1k-2],cx
	mov	[cs:wl_skip],0
	mov	[cs:wl_until],0
	mov	bl,75h					; JNE: a ray's post widens the last when the
	cmp	al,4					; texture column is the same -- but not with
	jb	@@pxmrg					; LOWWALLS4, where three rays' 12 columns would
	mov	bl,0EBh					; pass ScalePostA's 8 (JMP: always a new post)
@@pxmrg:
	mov	[BYTE cs:hvwmrg],bl
	mov	[BYTE cs:hhwmrg],bl
	mov	ax,OFFSET wallheight
	sub	ax,[pixstep]
	sub	ax,[pixstep]
	mov	[WORD cs:widecp1+2],ax
	mov	[WORD cs:widecp2+2],ax
	mov	[curquad],0				; the first ray patches its quadrant in
	mov	[WORD cs:qlo+2],7FFFh	; and takes id's chain to get there
	mov	[pixx],0
;
; A taken jump, so the patch just made to qlo -- some 25 bytes ahead -- is
; what runs: a 486 may already hold the old CMP in its 32-byte prefetch
; queue, and then, as a timer interrupt happened to fall, the frame's first
; ray took last frame's quadrant without its patch block.  (A V30 prefetches
; 6 bytes and never did.)  Found when step 47 put per-frame values in that
; block: the whole-loop CRC on the 486 differed, and moved with the layout.
;
	xor	bx,bx					; pixx, which is 0 (step 69: in at pixxbx)
	jmp	pixxbx
;---------------------------------------------------------------------------
;
; Setup to trace a ray through pixx view pixel
;
; CX : angle of the ray through pixx
; ES : points to segment of finetangent array for this block of code
;
; Upon entrance to initialize block
;
; BX : xpartial
; BP : ypartial
;
;---------------------------------------------------------------------------
	EVEN
;
; NEC V30 build (step 69): a ray ends with one jump, to nextpix, which falls
; into the next ray's setup; the frame's exit is a short jump back.
;
done:
	pop	bp
	pop	di
	pop	si
	retf
;
; wl_undo (2026-10-04): the ray after a skip found another wall, or a door
; or the pushwall: the skip is taken back -- the post narrowed again -- and
; the skipped rays cast after all, with no skipping until the ray that
; found the change comes round again.  Nothing global has changed yet.
;
wl_undo:
	mov	ax,[cs:wl_skip]
	sub	[postwidth],ax
	mov	bx,[cs:wl_skipx]
	add	ax,bx
	mov	[cs:wl_until],ax
	mov	[cs:wl_skip],0
	mov	[pixx],bx
	jmp	pixxbx
wl_skip		dw	0
wl_skipx	dw	0
wl_until	dw	0
	EVEN
nextpix:
	mov	bx,[pixx]
;
; (2026-10-04, the BSP branch) level of detail in the walk: a wall the ray
; just found shorter than wl_lod1 (64 pixels) skips the next ray, one under
; wl_lod2 (32) the next three -- the post widened over them and their
; heights copied, as LOWWALLS does for every column.  Patched per frame; 0
; (NOLOD, or LOWWALLS's own step) turns it off.
;
	mov	[cs:wl_skip],0			; the ray just done kept any skip before it
	cmp	bx,[cs:wl_until]		; just undone: no skipping until past it
	jb	pxstep
	mov	di,bx
	shl	di,1
	mov	ax,[wallheight+di]
	cmp	ax,1234h
wl_lod1k:
	jae	pxstep
	mov	cx,1
	cmp	ax,1234h
wl_lod2k:
	jae	@@lk
	mov	cx,3
@@lk:
	mov	dx,1234h				; viewwidth-1
wl_vw1k:
	sub	dx,bx					; the columns after this one
	cmp	cx,dx
	jle	@@lc
	mov	cx,dx
@@lc:
	mov	dx,8					; and a post no wider than ScalePostA's 8
	sub	dx,[postwidth]
	cmp	cx,dx
	jle	@@ld
	mov	cx,dx
@@ld:
	or	cx,cx
	jle	pxstep
	add	[postwidth],cx
	mov	[cs:wl_skip],cx			; to be verified by the next ray's wall
	inc	bx
	mov	[cs:wl_skipx],bx		; the first column skipped
	dec	bx
	add	bx,cx
@@lf:
	mov	[wallheight+di+2],ax
	add	di,2
	loop	@@lf
pxstep:
	add	bx,1					; step 97: pixstep, patched (83 C3 ib: at +2)
	mov	[pixx],bx
npvw:
	cmp	bx,1234h				; viewwidth, patched per frame (81 FB iw)
	jge	done
pixxbx:								; step 57: nextpix comes here with BX = pixx
	shl	bx,1
	mov	ax,SEG finetangent
	mov	es,ax
pxmid:
	mov	cx,1234h				; midangle, the center of view area (B9 iw:
	add	cx,[pixelangle+bx]		; patched per frame), + delta for this pixel
;
; NEC V30 build, StevenC & Claude: a ray is nearly always in the quadrant
; of the ray before, and the test chain below cost two to four taken jumps
; (JUMPS made most of them long) plus the quadrant's own check.  So the
; range and body of the current quadrant are patched in here -- by the
; quadrant code, only when a ray changes quadrant -- and a ray inside it
; goes straight there.  Anything else, the first ray of a frame included
; (7FFFh), takes id's chain.
;
qlo:
	cmp	cx,1234h				; the quadrant's first angle (81 F9 iw: at +2)
	jl	@@qslow
qhi:
	cmp	cx,1234h				; one past its last
	jge	@@qslow
qjmp:
	db	0E9h					; JMP rel16 to the quadrant's body, patched
	dw	0
@@qslow:
	cmp	cx,0
	jge	not0
;----------
;
; -90 - -1 degree arc
;
;----------
	add	cx,FINEANGLES			; -90 is the same as 270
	jmp	entry360

not0:
	cmp	cx,DEG90
	jge	not90
;----------
;
; 0-89 degree arc
;
;----------
entry90:
	cmp	[curquad],1				; NEC V30 build: the loop is patched for a
	je	@@q1					; quadrant, and only a change of quadrant --
	mov	[curquad],1				; twice a frame at most -- patches it again
	mov	[WORD cs:qlo+2],0		; and the fast entry at pixxbx
	mov	[WORD cs:qhi+2],DEG90
	mov	ax,OFFSET @@q1		; rel16, computed here: TASM's own
	sub	ax,OFFSET qjmp+3	; label arithmetic came out 6 bytes off
	mov	[WORD cs:qjmp+1],ax	; (JUMPS moves labels between passes)
	mov	[xtilestep],1			; xtilestep = 1
	mov	[ytilestep],-1			; ytilestep = -1
	mov	[BYTE cs:hvwx],0EBh	; step 71: the hit routines' tests
	mov	[BYTE cs:hhwy],3Ch
	mov	[BYTE cs:vertop],OP_JLE		; patch a jle in
	mov	[BYTE cs:vertop2],OP_JG		; and its inverse at the loop's bottom
	mov	[BYTE cs:horizop2],OP_JL	; (id's horizop was jge: its inverse)
	mov	[BYTE cs:vxtileop],OP_INCBX	; xtile += xtilestep
	mov	[BYTE cs:vtop+2],64			; T += xtilestep<<6
	mov	[yadj],64
	mov	[BYTE cs:htop],OP_DECDX		; T += ytilestep
;
; NEC V30 build (step 47): the frame's constants, into this quadrant's
; body and into initvars -- this runs on the first ray of every frame
; (curquad is reset) and whenever a ray changes quadrant
;
	mov	ax,[xpartialup]
	mov	[WORD cs:q1a+1],ax
	mov	ax,[ypartialdown]
	mov	[WORD cs:q1b+1],ax
	mov	ax,[WORD viewy]
	mov	[WORD cs:q1y+1],ax
	mov	ax,[WORD viewy+2]
	mov	[WORD cs:q1z+1],ax
	mov	ax,[WORD viewx]
	mov	[WORD cs:q1x+1],ax
	mov	ax,[WORD viewx+2]
	mov	[WORD cs:q1w+2],ax
	mov	ax,[focaltx]
	inc	ax
	mov	[WORD cs:ivxt+1],ax	; xtile = focaltx+xtilestep
	shl	ax,6
	mov	[WORD cs:ivx64+2],ax	; xtile<<6
	mov	dx,[focalty]
	dec	dx
	mov	[WORD cs:ivyt+2],dx	; ytile = focalty+ytilestep
	add	ax,dx
	mov	[WORD cs:ivt+1],ax		; T = (xtile<<6)+ytile
@@q1:
;
; ystep = -finetangent[...]: stored, patched in, and times xpartialup for
; yintercept
;
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx]			; the tangent, positive
	mov	di,[es:bx+2]
	mov	si,ax
	mov	dx,di
	neg	dx
	neg	si
	sbb	dx,0				; dx:si = ystep
	mov	[WORD cs:vyadd+1],si
	add	dx,64				; its high word plus xtilestep<<6
	mov	[WORD cs:vyadc+2],dx
q1a:
	mov	bp,1234h			; xpartialup, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0				; dx:ax = xpartialup * the tangent, >>16
q1y:
	mov	bx,1234h			; viewy, patched in per frame
q1z:
	mov	si,1234h
	sub	bx,ax
	sbb	si,dx
	push	si					; yintercept, for initvars (step 57)
	push	bx
;
; xstep = finetangent[...], and times ypartialdown for xintercept
;
	mov	bx,DEG90-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	di,[es:bx+2]
	mov	[WORD cs:hxadd+2],ax
	mov	[WORD cs:hxadc+2],di
q1b:
	mov	bp,1234h			; ypartialdown, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0
q1x:
	add	ax,1234h			; viewx, patched in per frame
q1w:
	adc	dx,1234h
	mov	bp,ax				; BP = xintercept's low word (step 52)
	mov	cx,dx				; CX = xinttile
	jmp	initvars

not90:
	cmp	cx,DEG180
	jge	not180
;----------
;
; 90-179 degree arc
;
;----------
	cmp	[curquad],2
	je	@@q2
	mov	[curquad],2
	mov	[WORD cs:qlo+2],DEG90		; and the fast entry at pixxbx
	mov	[WORD cs:qhi+2],DEG180
	mov	ax,OFFSET @@q2		; rel16, computed here: TASM's own
	sub	ax,OFFSET qjmp+3	; label arithmetic came out 6 bytes off
	mov	[WORD cs:qjmp+1],ax	; (JUMPS moves labels between passes)
	mov	ax,-1
	mov	[xtilestep],ax			; xtilestep = -1
	mov	[ytilestep],ax			; ytilestep = -1
	mov	[BYTE cs:hvwx],3Ch	; step 71: the hit routines' tests
	mov	[BYTE cs:hhwy],3Ch
	mov	[BYTE cs:vertop],OP_JLE		; patch a jle in
	mov	[BYTE cs:vertop2],OP_JG
	mov	[BYTE cs:horizop2],OP_JG	; (id's horizop was jle)
	mov	[BYTE cs:vxtileop],OP_DECBX	; xtile += xtilestep
	mov	[BYTE cs:vtop+2],-64
	mov	[yadj],-64
	mov	[BYTE cs:htop],OP_DECDX
;
; NEC V30 build (step 47): the frame's constants, into this quadrant's
; body and into initvars -- this runs on the first ray of every frame
; (curquad is reset) and whenever a ray changes quadrant
;
	mov	ax,[xpartialdown]
	mov	[WORD cs:q2a+1],ax
	mov	ax,[ypartialdown]
	mov	[WORD cs:q2b+1],ax
	mov	ax,[WORD viewy]
	mov	[WORD cs:q2y+1],ax
	mov	ax,[WORD viewy+2]
	mov	[WORD cs:q2z+1],ax
	mov	ax,[WORD viewx]
	mov	[WORD cs:q2x+1],ax
	mov	ax,[WORD viewx+2]
	mov	[WORD cs:q2w+1],ax
	mov	ax,[focaltx]
	dec	ax
	mov	[WORD cs:ivxt+1],ax	; xtile = focaltx+xtilestep
	shl	ax,6
	mov	[WORD cs:ivx64+2],ax	; xtile<<6
	mov	dx,[focalty]
	dec	dx
	mov	[WORD cs:ivyt+2],dx	; ytile = focalty+ytilestep
	add	ax,dx
	mov	[WORD cs:ivt+1],ax		; T = (xtile<<6)+ytile
@@q2:
;
; ystep = -finetangent[...]: stored, patched in, and times xpartialdown for
; yintercept
;
	mov	bx,DEG180-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]			; the tangent, positive
	mov	di,[es:bx+2]
	mov	si,ax
	mov	dx,di
	neg	dx
	neg	si
	sbb	dx,0				; dx:si = ystep
	mov	[WORD cs:vyadd+1],si
	sub	dx,64				; its high word plus xtilestep<<6
	mov	[WORD cs:vyadc+2],dx
q2a:
	mov	bp,1234h			; xpartialdown, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0				; dx:ax = xpartialdown * the tangent, >>16
q2y:
	mov	bx,1234h			; viewy, patched in per frame
q2z:
	mov	si,1234h
	sub	bx,ax
	sbb	si,dx
	push	si					; yintercept, for initvars (step 57)
	push	bx
;
; xstep = -finetangent[...], and times ypartialdown for xintercept
;
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG90*4]
	mov	di,[es:bx+2-DEG90*4]
	mov	si,ax
	mov	dx,di
	neg	dx
	neg	si
	sbb	dx,0				; dx:si = xstep
	mov	[WORD cs:hxadd+2],si
	mov	[WORD cs:hxadc+2],dx
q2b:
	mov	bp,1234h			; ypartialdown, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0
q2x:
	mov	bp,1234h			; viewx, patched in per frame
q2w:
	mov	cx,1234h
	sub	bp,ax				; BP = xintercept's low word (step 52)
	sbb	cx,dx				; CX = xinttile
	jmp	initvars

not180:
	cmp	cx,DEG270
	jge	not270
;----------
;
; 180-269 degree arc
;
;----------
	cmp	[curquad],3
	je	@@q3
	mov	[curquad],3
	mov	[WORD cs:qlo+2],DEG180		; and the fast entry at pixxbx
	mov	[WORD cs:qhi+2],DEG270
	mov	ax,OFFSET @@q3		; rel16, computed here: TASM's own
	sub	ax,OFFSET qjmp+3	; label arithmetic came out 6 bytes off
	mov	[WORD cs:qjmp+1],ax	; (JUMPS moves labels between passes)
	mov	[xtilestep],-1			; xtilestep = -1
	mov	[ytilestep],1			; ytilestep = 1
	mov	[BYTE cs:hvwx],3Ch	; step 71: the hit routines' tests
	mov	[BYTE cs:hhwy],0EBh
	mov	[BYTE cs:vertop],OP_JGE		; patch a jge in
	mov	[BYTE cs:vertop2],OP_JL
	mov	[BYTE cs:horizop2],OP_JG	; (id's horizop was jle)
	mov	[BYTE cs:vxtileop],OP_DECBX	; xtile += xtilestep
	mov	[BYTE cs:vtop+2],-64
	mov	[yadj],-64
	mov	[BYTE cs:htop],OP_INCDX
;
; NEC V30 build (step 47): the frame's constants, into this quadrant's
; body and into initvars -- this runs on the first ray of every frame
; (curquad is reset) and whenever a ray changes quadrant
;
	mov	ax,[xpartialdown]
	mov	[WORD cs:q3a+1],ax
	mov	ax,[ypartialup]
	mov	[WORD cs:q3b+1],ax
	mov	ax,[WORD viewy]
	mov	[WORD cs:q3y+1],ax
	mov	ax,[WORD viewy+2]
	mov	[WORD cs:q3z+2],ax
	mov	ax,[WORD viewx]
	mov	[WORD cs:q3x+1],ax
	mov	ax,[WORD viewx+2]
	mov	[WORD cs:q3w+1],ax
	mov	ax,[focaltx]
	dec	ax
	mov	[WORD cs:ivxt+1],ax	; xtile = focaltx+xtilestep
	shl	ax,6
	mov	[WORD cs:ivx64+2],ax	; xtile<<6
	mov	dx,[focalty]
	inc	dx
	mov	[WORD cs:ivyt+2],dx	; ytile = focalty+ytilestep
	add	ax,dx
	mov	[WORD cs:ivt+1],ax		; T = (xtile<<6)+ytile
@@q3:
;
; ystep = finetangent[...]: stored, patched in, and times xpartialdown for
; yintercept
;
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG180*4]			; the tangent, positive
	mov	di,[es:bx+2-DEG180*4]
	mov	[WORD cs:vyadd+1],ax
	mov	dx,di
	sub	dx,64				; its high word plus xtilestep<<6
	mov	[WORD cs:vyadc+2],dx
q3a:
	mov	bp,1234h			; xpartialdown, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0				; dx:ax = xpartialdown * the tangent, >>16
q3y:
	add	ax,1234h			; viewy, patched in per frame
q3z:
	adc	dx,1234h
	push	dx					; yintercept, for initvars (step 57)
	push	ax
;
; xstep = -finetangent[...], and times ypartialup for xintercept
;
	mov	bx,DEG270-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	di,[es:bx+2]
	mov	si,ax
	mov	dx,di
	neg	dx
	neg	si
	sbb	dx,0				; dx:si = xstep
	mov	[WORD cs:hxadd+2],si
	mov	[WORD cs:hxadc+2],dx
q3b:
	mov	bp,1234h			; ypartialup, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0
q3x:
	mov	bp,1234h			; viewx, patched in per frame
q3w:
	mov	cx,1234h
	sub	bp,ax				; BP = xintercept's low word (step 52)
	sbb	cx,dx				; CX = xinttile
	jmp	initvars

not270:
	cmp	cx,DEG360
	jge	not360
;----------
;
; 270-359 degree arc
;
;----------
entry360:
	cmp	[curquad],4
	je	@@q4
	mov	[curquad],4
	mov	[WORD cs:qlo+2],DEG270		; and the fast entry at pixxbx
	mov	[WORD cs:qhi+2],DEG360
	mov	ax,OFFSET @@q4		; rel16, computed here: TASM's own
	sub	ax,OFFSET qjmp+3	; label arithmetic came out 6 bytes off
	mov	[WORD cs:qjmp+1],ax	; (JUMPS moves labels between passes)
	mov	ax,1
	mov	[xtilestep],ax			; xtilestep = 1
	mov	[ytilestep],ax			; ytilestep = 1
	mov	[BYTE cs:hvwx],0EBh	; step 71: the hit routines' tests
	mov	[BYTE cs:hhwy],0EBh
	mov	[BYTE cs:vertop],OP_JGE		; patch a jge in
	mov	[BYTE cs:vertop2],OP_JL
	mov	[BYTE cs:horizop2],OP_JL	; (id's horizop was jge)
	mov	[BYTE cs:vxtileop],OP_INCBX	; xtile += xtilestep
	mov	[BYTE cs:vtop+2],64
	mov	[yadj],64
	mov	[BYTE cs:htop],OP_INCDX
;
; NEC V30 build (step 47): the frame's constants, into this quadrant's
; body and into initvars -- this runs on the first ray of every frame
; (curquad is reset) and whenever a ray changes quadrant
;
	mov	ax,[xpartialup]
	mov	[WORD cs:q4a+1],ax
	mov	ax,[ypartialup]
	mov	[WORD cs:q4b+1],ax
	mov	ax,[WORD viewy]
	mov	[WORD cs:q4y+1],ax
	mov	ax,[WORD viewy+2]
	mov	[WORD cs:q4z+2],ax
	mov	ax,[WORD viewx]
	mov	[WORD cs:q4x+1],ax
	mov	ax,[WORD viewx+2]
	mov	[WORD cs:q4w+2],ax
	mov	ax,[focaltx]
	inc	ax
	mov	[WORD cs:ivxt+1],ax	; xtile = focaltx+xtilestep
	shl	ax,6
	mov	[WORD cs:ivx64+2],ax	; xtile<<6
	mov	dx,[focalty]
	inc	dx
	mov	[WORD cs:ivyt+2],dx	; ytile = focalty+ytilestep
	add	ax,dx
	mov	[WORD cs:ivt+1],ax		; T = (xtile<<6)+ytile
@@q4:
;
; ystep = finetangent[...]: stored, patched in, and times xpartialup for
; yintercept
;
	mov	bx,DEG360-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]			; the tangent, positive
	mov	di,[es:bx+2]
	mov	[WORD cs:vyadd+1],ax
	mov	dx,di
	add	dx,64				; its high word plus xtilestep<<6
	mov	[WORD cs:vyadc+2],dx
q4a:
	mov	bp,1234h			; xpartialup, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0				; dx:ax = xpartialup * the tangent, >>16
q4y:
	add	ax,1234h			; viewy, patched in per frame
q4z:
	adc	dx,1234h
	push	dx					; yintercept, for initvars (step 57)
	push	ax
;
; xstep = finetangent[...], and times ypartialup for xintercept
;
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG270*4]
	mov	di,[es:bx+2-DEG270*4]
	mov	[WORD cs:hxadd+2],ax
	mov	[WORD cs:hxadc+2],di
q4b:
	mov	bp,1234h			; ypartialup, patched in per frame
	mul	bp
	mov	si,dx
	mov	ax,di
	mul	bp
	add	ax,si
	adc	dx,0
q4x:
	add	ax,1234h			; viewx, patched in per frame
q4w:
	adc	dx,1234h
	mov	bp,ax				; BP = xintercept's low word (step 52)
	mov	cx,dx				; CX = xinttile
	jmp	initvars

not360:
;----------
;
; 360-449 degree arc
;
;----------
	sub	cx,FINEANGLES			; -449 is the same as 89
	jmp	entry90

;---------------------------------------------------------------------------
;
; initialise variables for intersection testing
;
; NEC V30 build, StevenC & Claude: each quadrant above knows the signs of
; its steps, so it multiplies the positive tangent and adds the product to
; viewy/viewx or subtracts it -- the same 32-bit result as id's, which
; negated the tangent, tested its sign here, negated it back, multiplied
; and negated the product.  The partial is in a register for both MULs,
; and xtile<<6 is made once for xspot and T.  In: yintercept pushed (high
; word first), BP = xintercept's low word, CX = xinttile.
;
;---------------------------------------------------------------------------
initvars:
;
; NEC V30 build (step 47): xtile, xtile<<6, ytile and T are the same for
; every ray of a quadrant in a frame, so the quadrant code patches them in.
;
ivxt:
	mov	bx,1234h					; xtile = focaltx+xtilestep (BB iw: at +1);
										; the hits store it (step 57)
	pop	ax							; yintercept, from the quadrant code: AX
	pop	si							; the low word, SI yinttile
ivx64:
	add	si,1234h					; xspot = (xtile<<6) + yinttile (81 C6 iw)
ivt:
	mov	dx,1234h					; T = (xtile<<6)+ytile
	mov	di,cx
	shl	di,6
ivyt:
	add	di,1234h					; yspot = (xinttile<<6) + ytile, ytile
										; patched in (step 52: BP holds xintercept)
										; NEC V30 build: AX = low word of yintercept
									; (and no screen segment in ES: nothing
									; from here to the next ray reads it --
									; ScalePost loads its own)


;---------------------------------------------------------------------------
;
; trace along this angle until we hit a wall
;
; CORE LOOP!
;
; All variables are killed when a wall is hit
;
; AX : low word of yintercept -- NEC V30 build, StevenC & Claude: kept in
;      AX while tracing instead of added to in memory every vertical step;
;      stored back first thing at every hit, reloaded at every continue
; BX : xtile
; CX : high word of xintercept
; DX : T = (xtile<<6)+ytile -- NEC V30 build (was the high word of
;      yintercept, which is now computed only at a hit: yinttile = xspot -
;      (xtile<<6))
; SI : xspot (xtile<<6)+yinttile (index into tilemap and spotvis)
; DI : yspot (xinttile<<6)+ytile (index into tilemap and spotvis)
; BP : low word of xintercept -- NEC V30 build (step 52): was ytile, which
;      the loop does not need: T - (xtile<<6) is ytile, so yspot is
;      T + ((xinttile-xtile)<<6), unchanged by a vertical step.  Where ytile
;      is wanted, at a horizontal hit, it is made from T and xtile
; ES : screenseg
;
; NEC V30 build: id's vertical test compared yinttile with ytile.  xspot and
; T carry the same xtile<<6, so xspot-T is exactly yinttile-ytile and the
; loop compares those instead -- which lets a vertical step move xspot
; directly: xtile+=xtilestep and yintercept+=ystep together add ystep's
; high word, the carry and xtilestep<<6 to it, one ADC with the sum patched
; in per ray, where id rebuilt xspot with a shift of six (13 clocks on a
; V30).  Nothing overflows: |yinttile| stays within a step (at most ~1146
; tiles, finetangent[899]) of the map.  The horizontal side keeps id's test,
; because there xinttile can run a thousand tiles past the map and
; xinttile<<6 would not fit.  Both loops test at the bottom, with the
; inverse condition patched in beside id's.
;
;---------------------------------------------------------------------------

;-----------
;
; check intersections with vertical walls
;
;-----------

vertcheck:
	cmp	si,dx						; yinttile against ytile, via xspot and T
vertop:								; 0x7e = jle (ytilestep==-1)
	jle	SHORT horizentry					; 0x7d = jge (ytilestep==1)
	EVEN
vertentry:
	cmp	[BYTE tilemap+si],bh		; tilehit = *((byte *)tilemap+xspot);
	jnz	hitvert						; BH, xtile's high byte, is always 0 --
									; a byte shorter than id's TEST ...,0FFh
passvert:
vspotop:
	mov	[BYTE spotvis+si],1			; = vismark, patched in at +4 per frame
;
; The steps below are patched in per ray by the quadrant code above, as id
; already patched vertop/horizop.  The 1234h placeholders force the full
; imm16 encodings being patched.
;
vxtileop:
	inc	bx							; xtile+=xtilestep: INC BX or DEC BX
vtop:
	add	dx,64						; T += xtilestep<<6 (imm8 at +2: 64 or -64)
vyadd:
	add	ax,1234h					; yintercept += ystep (low word at +1, in AX)
vyadc:
	adc	si,1234h					; xspot += ystep's high word + xtilestep<<6 (at +2)
	cmp	si,dx
vertop2:							; the inverse of vertop: 0x7f = jg, 0x7c = jl
	jg	SHORT vertentry

;-----------
;
; check intersections with horizontal walls
;
;-----------
	EVEN
horizentry:
	cmp	[BYTE tilemap+di],bh		; tilehit = *((byte *)tilemap+yspot);
	jnz	hithoriz
passhoriz:
hspotop:
	mov	[BYTE spotvis+di],1			; = vismark, patched in at +4 per frame
htop:
	inc	dx							; T += ytilestep: INC DX or DEC DX, patched
hxadd:
	add	bp,1234h					; xintercept += xstep (low word at +2)
hxadc:
	adc	cx,1234h					; (high word at +2)
	mov	di,cx
	sub	di,bx
	shl	di,6
	add	di,dx						; yspot = (xinttile<<6)+ytile, as
	cmp	cx,bx						; T + ((xinttile-xtile)<<6)
horizop2:							; the inverse of id's horizop (jle/jge
	jl	SHORT horizentry					; on xtilestep): 0x7f = jg, 0x7c = jl
	jmp	vertentry

	EVEN
hitvert:
	mov	[WORD yintercept],ax		; the low word back to memory first
	mov	al,[BYTE tilemap+si]		; tilehit = *((byte *)tilemap+xspot);
									; (step 76: stored only by the door path)
	or	al,al						; set flags
	jns	notvertdoor
	jmp	vertdoor
notvertdoor:
	mov	bp,bx						; step 75: xintercept's high word, stored
	mov	dx,bx						; with xtile and yinttile only when a post
	shl	dx,6						; starts (hvw_newcol, hvw_nwt)
	neg	dx
	add	dx,si						; yinttile = xspot-(xtile<<6)
	mov	ch,al						; the wall key: tilehit<<7 | 40h (vertical)
	xor	cl,cl						;  | xtile -- AL is still tilehit, BX xtile
	shr	cx,1
	or	cl,bl
	or	cl,40h
	jmp	HitVertWallA			; step 62: it goes on to nextpix itself


hdoor_t:
	jmp	horizdoor					; step 70: hithoriz's door test's hop
	EVEN
hithoriz:
	mov	[WORD yintercept],ax		; (the door path continues with AX)
	mov	al,[BYTE tilemap+di]		; tilehit = *((byte *)tilemap+yspot);
									; (step 76: stored only by the door path)
	or	al,al						; set flags
	js	hdoor_t						; step 70: a short hop (see hdoor_t)
	mov	di,bx						; ytile = T-(xtile<<6)
	shl	di,6
	neg	di
	add	di,dx
	mov	bx,di						; yintercept's high word (+1 below)
	mov	dx,cx						; xinttile -- step 75: all stored, with
									; BP, only when a post starts
	mov	ch,al						; the wall key: tilehit<<7 | ytile
	xor	cl,cl
	shr	cx,1
	or	cx,di
;
; NEC V30 build (step 70): HitHorizWallA follows, falling through
;
HitHorizWallA:
	PUBLIC	HitHorizWallA				; (public only so profiles can name it)
	mov	si,bp					; xintercept's low word (step 75: BP)
	shr	si,4
	and	si,0fc0h				; SI = texture
hhwy:								; step 71: EB (ytilestep 1) or 3C (-1),
	jmp	SHORT hhw_mirror			; patched by the quadrant code
	inc	bx						; yintercept += TILEGLOBAL (step 75: in BX)
	jmp	hhw_tex
hhw_mirror:
	mov	ax,0fc0h
	sub	ax,si
	mov	si,ax
hhw_tex:
;
; NEC V30 build (step 51): id's test -- lastside, both words of
; lastintercept and lasttilehit, four compares against memory -- is one
; compare of the key AsmRefresh built in CX: tilehit<<7 | side<<6 | tile.
; Tiles are under 64 and tilehit a byte, so the key holds all three
; exactly, never FFFFh; C invalidates it wherever it changes that state.
;
	cmp	cx,[lastkey]
	jne	hhw_nwt				; (a short hop: see hhw_nwt)
	cmp	si,[WORD postsource]
hhwmrg:									; step 97: JMP with LOWWALLS4 (EB for 75)
	jne	SHORT hhw_newcol
wideadd2:								; step 79: pixstep, patched (83 06 iw ib: at +4)
	add	[WORD postwidth],1		; wide scale
	mov	bx,[pixx]
	shl	bx,1
widecp2:								; step 79: wallheight-2*pixstep, patched
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	jmp	nextpix				; step 62: jumped to, not called
hhw_nwt:
	jmp	hhw_newwall			; step 67: the new-wall test's hop
; step 67: the inline height's cache miss, within reach of its test
czi_miss:
	mov	[chhkey],ax
	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
czvyloc:
	sub	ax,1234h				; viewy
czvyhic:
	sbb	dx,1234h
	FIXBYFRACB	czsinsignc,czsinfracc	; dx:ax = gyt
	mov	[chhgylo],ax
	mov	[chhgyhi],dx
	jmp	czi_have
hhw_newcol:
	mov	[WORD xintercept],bp	; step 75: the hit, stored as a post starts
	mov	[WORD xintercept+2],dx
	mov	[xtile],dx
	mov	[WORD yintercept],0
	mov	[WORD yintercept+2],bx
	mov	[ytile],di
; step 67: CalcHeightH inline, no call -- step 68: its cache test first (gyt,
; then gxt: they are independent, and nx = gxt-gyt as before)
	mov	ax,[WORD yintercept+2]
	cmp	ax,[chhkey]
	jne	czi_miss
	mov	ax,[chhgylo]			; dx:ax = gyt, as for the last column
	mov	dx,[chhgyhi]
czi_have:
	push	dx
	push	ax
	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
czvxloc:
	sub	ax,1234h				; viewx, low word (2D iw: at +1)
czvxhic:
	sbb	dx,1234h				; high word (81 DA iw: at +2)
	FIXBYFRACB	czcossignc,czcosfracc	; dx:ax = gxt
	pop	bx
	pop	cx					; cx:bx = gyt
	sub	ax,bx
	sbb	dx,cx
	mov	bx,ax
	mov	cx,dx				; cx:bx = nx = gxt-gyt
czmdhic:
	cmp	cx,1234h			; if (nx < mindist) nx = mindist -- signed (81 F9 iw)
	jg	czi_distok
	jl	czi_clamp
czmdloc:
	cmp	bx,1234h			; (81 FB iw)
	jae	czi_distok
czi_clamp:
czmdlo2c:
	mov	bx,1234h			; (BB iw)
czmdhi2c:
	mov	cx,1234h			; (B9 iw)
czi_distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
czhnloc:
	mov	ax,1234h			; heightnumerator (B8 iw)
czhnhic:
	mov	dx,1234h			; (BA iw)
	idiv	bx
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	push	si						; step 68: ScalePostA inline -- the post
	mov	bx,[postx]				; this column closes
	mov	di,bx
	shl	bx,1
	mov	bp,[wallheight+bx]		; fractional height (low 3 bits frac)
	and	bp,0fff8h				; bp = heightscaler*4
	shr	bp,1
	cmp	bp,[maxscaleshl2]
	jle	czp_hok
	mov	bp,[maxscaleshl2]
czp_hok:
	cmp	bp,[postmin]			; the least wall of the frame (rarely new)
	jb	czp_newmin
czp_minok:
	cmp	bp,[bandlim]
	jb	czp_short				; shorter than the band: ScalePostA's own path
	add	bp,OFFSET fullscalefarcall
	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,[postwidth]			; bx = pixel*8+pixwidth
	mov	al,[mapmasks1-1+bx]		; -1 because no widths of 0
	mov	dx,SC_INDEX+1
	out	dx,al					; set bit mask register
	les	si,[postsource]			; ES:SI = the texture column
	mov	cx,SCREENSEG
	mov	ds,cx					; DS = the screen
	call	[DWORD bp]				; SS:BP -- scale the line of pixels
	mov	al,[ss:mapmasks2-1+bx]
	or	al,al
	jz	czp_done
	inc	di						; a strip that crosses two bytes
	out	dx,al
	call	[DWORD bp]
	mov	al,[ss:mapmasks3-1+bx]
	or	al,al
	jz	czp_done
	inc	di						; three bytes
	out	dx,al
	call	[DWORD bp]
czp_done:
	mov	ax,ss
	mov	ds,ax
	pop	si
	mov	[WORD postsource],si
postw3:								; step 79: pixstep, patched (C7 06 iw iw: at +4)
	mov	[WORD postwidth],1
	mov	ax,[pixx]
	mov	[postx],ax
	jmp	nextpix
czp_newmin:
	mov	[postmin],bp
	jmp	czp_minok
czp_short:
	call	ScalePostA				; (it recomputes; postmin is a least value)
	jmp	czp_done
hhw_drop:						; step 92: as hvw_drop
	cmp	[pixx],0
	je	hhw_first
	call	DropFill
	jmp	hhw_first
hhw_newwall:
	cmp	[cs:wl_skip],0			; a skip before this ray: another wall
	jne	wl_undo
	mov	[WORD xintercept],bp	; step 75: the hit, stored as a post starts
	mov	[WORD xintercept+2],dx
	mov	[xtile],dx
	mov	[WORD yintercept],0
	mov	[WORD yintercept+2],bx
	mov	[ytile],di
	mov	[lastkey],cx
	call	CalcHeightH
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	cmp	[lastside],-1
	je	hhw_drop				; step 92: rare, out of line
	call	ScalePostA
hhw_first:
	mov	[lastside],0
	mov	ax,[ytile]
	cwd
	mov	[WORD lastintercept],ax
	mov	[WORD lastintercept+2],dx
	mov	bx,[lastkey]				; step 76: tilehit, from the wall key
	shr	bx,7
	mov	[lasttilehit],bx
	mov	ax,[pixx]
	mov	[postx],ax
postw4:								; step 79: pixstep, patched (C7 06 iw iw: at +4)
	mov	[WORD postwidth],1
	test	bl,40h
	jz	hhw_plain
	mov	ax,[WORD xintercept+2]	; xtile = xintercept>>TILESHIFT
	mov	[xtile],ax
	mov	di,ax
	shl	di,6
	add	di,[ytile]
	sub	di,[ytilestep]			; tilemap[xtile][ytile-ytilestep]
	test	[BYTE tilemap+di],80h
	jz	hhw_notdoor
	mov	ax,[PMSpriteStart]
	sub	ax,8-2					; DOORWALL+2
	jmp	hhw_getpage
hhw_notdoor:
	and	bx,NOT 40h
hhw_plain:
	shl	bx,1
	mov	ax,[horizwall+bx]
hhw_getpage:
	push	ax
hhwgp:								; step 81: FLATWALLS calls FlatPage here
	call	PM_GetPage
	add	sp,2
	mov	[WORD postsource+2],ax
	mov	[WORD postsource],si
	jmp	nextpix				; step 62: jumped to, not called

;---------------------------------------------------------------------------
;
; next pixel over
;
;---------------------------------------------------------------------------

; (step 69: nextpix and done are just before pixxbx, above)

;===========================================================================

;=============
;
; hit a special horizontal wall, so find which coordinate a door would be
; intersected at, and check to see if the door is open past that point
;
;=============
horizdoor:
	mov	[BYTE tilehit],al			; step 76: the door routines read it
	mov	[xtile],bx					; save off live register variables
	mov	[tsave],dx					; T

	test al,040h      				; both high bits set == pushable wall
	jnz	horizpushwall

	mov	bx,ax
	and	bx,7fh						; strip high bit
	shl	bx,1                        ; index into word width door table

	mov	ax,[WORD cs:hxadd+2]		; xstep, as patched into the loop (NEC V30 build:
	mov	dx,[WORD cs:hxadc+2]		; the rays no longer store it)
	sar	dx,1
	rcr ax,1						; half a step gets to door position

	add	ax,bp						; add half step to current intercept pos
	adc	dx,cx						; CX hold high word of xintercept

	cmp	cx,dx						; is it still in the same tile?
	je	hithmid
;
; midpoint is outside tile, so it hit the side of the wall before a door
;
continuehoriz:
	mov	bx,[xtile]					; reload register variables
	mov	dx,[tsave]
	mov	ax,[WORD yintercept]		; AX = low word again
	jmp	passhoriz					; continue tracing
;
; the trace hit the door plane at pixel position AX, see if the door is
; closed that much
;
hithmid:
	cmp	ax,[doorposition+bx]		; position of leading edge of door
	jb	continuehoriz
;
; draw the door
;
	mov	[WORD xintercept],ax		; save pixel intercept position
	mov	[WORD xintercept+2],cx

	mov	[WORD yintercept],8000h		; intercept in middle of tile
	mov	bp,[xtile]					; ytile = T-(xtile<<6)
	shl	bp,6
	neg	bp
	add	bp,[tsave]
	mov	[WORD yintercept+2],bp

	cmp	[cs:wl_skip],0			; (a skip before: cast it after all)
	jne	wl_undo
	call	FAR HitHorizDoor
	jmp	nextpix

;============
;
; hit a sliding horizontal wall
;
;============

horizpushwall:
	mov	ax,[WORD cs:hxadc+2]		; multiply xstep by pwallmove (0-63)
	mul	[pwallpos]
	mov	bx,ax
	mov	ax,[WORD cs:hxadd+2]
	mul	[pwallpos]
	add	dx,bx

	sar	dx,1						; then divide by 64 to accomplish a
	rcr ax,1						; fixed point multiplication
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1

	add	ax,bp						; add partial step to current intercept
	adc	dx,cx						; CX hold high word of xintercept

	cmp	cx,dx						; is it still in the same tile?
	jne	continuehoriz				; no, it hit the side

;
; draw the pushable wall at the new height
;
	mov	[WORD xintercept],ax		; save pixel intercept position
	mov	[WORD xintercept+2],dx

	mov	bp,[xtile]					; ytile = T-(xtile<<6)
	shl	bp,6
	neg	bp
	add	bp,[tsave]
	mov	[WORD yintercept+2],bp
	mov	[WORD yintercept],0

	cmp	[cs:wl_skip],0			; (a skip before: cast it after all)
	jne	wl_undo
	call	FAR HitHorizPWall
	jmp	nextpix



;===========================================================================

;=============
;
; hit a special vertical wall, so find which coordinate a door would be
; intersected at, and check to see if the door is open past that point
;
;=============
vertdoor:
	mov	[BYTE tilehit],al			; step 76: the door routines read it
	mov	[xtile],bx					; save off live register variables
	mov	[tsave],dx					; T
	mov	dx,bx
	shl	dx,6
	neg	dx
	add	dx,si						; yinttile = xspot-(xtile<<6)
	mov	[WORD yintercept+2],dx

	test al,040h      				; both high bits set == pushable wall
	jnz	vertpushwall

	mov	bx,ax
	and	bx,7fh						; strip high bit
	shl	bx,1                        ; index into word width doorposition

	mov	ax,[WORD cs:vyadd+1]		; ystep, as patched into the loop, less
	mov	dx,[WORD cs:vyadc+2]		; the xtilestep<<6 added to its high word
	sub	dx,[yadj]
	sar	dx,1
	rcr ax,1						; half a step gets to door position

	add	ax,[WORD yintercept]		; add half step to current intercept pos
	adc	dx,[WORD yintercept+2]

	cmp	[WORD yintercept+2],dx		; is it still in the same tile?
	je	hitvmid
;
; midpoint is outside tile, so it hit the side of the wall before a door
;
continuevert:
	mov	bx,[xtile]					; reload register variables
	mov	dx,[tsave]
	mov	ax,[WORD yintercept]		; AX = low word again
	jmp	passvert					; continue tracing
;
; the trace hit the door plane at pixel position AX, see if the door is
; closed that much
;
hitvmid:
	cmp	ax,[doorposition+bx]		; position of leading edge of door
	jb	continuevert
;
; draw the door
;
	mov	[WORD yintercept],ax		; save pixel intercept position
	mov	[WORD xintercept],8000h		; intercept in middle of tile
	mov	ax,[xtile]
	mov	[WORD xintercept+2],ax

	cmp	[cs:wl_skip],0			; (a skip before: cast it after all)
	jne	wl_undo
	call	FAR HitVertDoor
	jmp	nextpix

;============
;
; hit a sliding vertical wall
;
;============

vertpushwall:
	mov	ax,[WORD cs:vyadc+2]		; multiply ystep by pwallmove (0-63)
	sub	ax,[yadj]
	mul	[pwallpos]
	mov	bx,ax
	mov	ax,[WORD cs:vyadd+1]
	mul	[pwallpos]
	add	dx,bx

	sar	dx,1						; then divide by 64 to accomplish a
	rcr ax,1						; fixed point multiplication
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1
	sar	dx,1
	rcr ax,1

	add	ax,[WORD yintercept]		; add partial step to current intercept
	adc	dx,[WORD yintercept+2]

	cmp	[WORD yintercept+2],dx		; is it still in the same tile?
	jne	continuevert				; no, it hit the side

;
; draw the pushable wall at the new height
;
	mov	[WORD yintercept],ax		; save pixel intercept position
	mov	[WORD yintercept+2],dx

	mov	bx,[xtile]
	mov	[WORD xintercept+2],bx
	mov	[WORD xintercept],0

	cmp	[cs:wl_skip],0			; (a skip before: cast it after all)
	jne	wl_undo
	call	FAR HitVertPWall
	jmp	nextpix
		db	0						; (parity, after wl_undo's hooks)



ENDP


;============================
;
; The path-walking AI -- NEC V30 build (step 63), StevenC & Claude
;
; TryWalk and MoveObj (WL_STATE.C), SelectPathDir and T_Path (WL_ACT2.C),
; statement for statement.  Each is a FAR routine for the C and a NEAR body
; with the actor in SI for the others, so T_Path -> SelectPathDir ->
; TryWalk and T_Path -> MoveObj are near calls with no frames.
;
;============================

OB_CLASS		=	4
OB_DISTANCE		=	10
OB_DIR			=	14
OB_SPEED		=	46
FL_SHOOTABLE	=	1
C_INERT			=	2					; classtype
C_DOG			=	6
C_FAKE			=	9
C_GHOST			=	15
C_SPECTRE		=	21
D_NODIR			=	8					; dirtype
ICONARROWS		=	90
AREATILE		=	107
DOOR_ACTION		=	5					; doorobj_t, as the compiler lays it out:
DOOR_SIZE		=	9					; bytes tilex, tiley, an int vertical, a
										; byte lock, the int action, ticcount

;
; boolean TryWalk (objtype *ob)
;
;	CHECKDIAG(x,y): temp = actorat[x][y]; if (temp && (temp<256 ||
;		((objtype *)temp)->flags & FL_SHOOTABLE)) return false;
;	CHECKSIDE(x,y): temp = actorat[x][y]; if (temp) { if (temp<128) return
;		false; if (temp<256) doornum = temp&63; else if (((objtype *)temp)->
;		flags & FL_SHOOTABLE) return false; }
;
;	doornum = -1;
;	if (ob->obclass == inertobj)
;		ob->tilex/tiley step in ob->dir (nothing for nodir)
;	else switch (ob->dir):
;		east, north, west, south: dog or fake: CHECKDIAG, else CHECKSIDE, on
;			the tile ahead; then step
;		the diagonals: CHECKDIAG on (x+dx,y+dy), (x+dx,y), (x,y+dy); then step
;		nodir: return false;  anything else: Quit ("Walk: Bad dir")
;	if (doornum != -1)
;		OpenDoor (doornum), ob->distance = -doornum-1, return true;
;	ob->areanumber = *(mapsegs[0]+farmapylookup[ob->tiley]+ob->tilex)-AREATILE;
;	ob->distance = TILEGLOBAL;  return true;
;
PROC	TryWalk
PUBLIC	TryWalk
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,[bp+6]
	call	TryWalkN
	pop	di
	pop	si
	pop	bp
	ret
ENDP

; SI = the actor; returns AX; keeps SI and BP
PROC	TryWalkN NEAR
	mov	di,-1					; doornum
	mov	bx,[si+OB_DIR]
	cmp	[WORD si+OB_CLASS],C_INERT
	jne	@@check
	cmp	bx,D_NODIR
	jae	@@placed				; the C's switch has no case for these
	jmp	@@step

@@check:
	cmp	bx,D_NODIR
	jb	@@dir
	je	@@false
	call	BadWalkDir			; Quits
@@dir:
	mov	al,[dirdx+bx]
	cbw
	mov	cx,ax					; CX = dx
	mov	al,[dirdy+bx]
	cbw
	mov	dx,ax					; DX = dy
	test	bl,1
	jnz	@@diag
;
; east, north, west, south: the tile ahead
;
	mov	bx,[si+OB_TILEX]
	add	bx,cx
	shl	bx,6
	add	bx,[si+OB_TILEY]
	add	bx,dx
	shl	bx,1
	mov	bx,[actorat+bx]
	or	bx,bx
	jz	@@stepdir
	mov	ax,[si+OB_CLASS]
	cmp	ax,C_DOG
	je	@@cdiag
	cmp	ax,C_FAKE
	je	@@cdiag
	cmp	bx,128					; CHECKSIDE
	jb	@@false
	cmp	bx,256
	jae	@@shoot
	mov	di,bx
	and	di,63					; doornum = temp&63
	jmp	@@stepdir
@@cdiag:
	cmp	bx,256					; CHECKDIAG
	jb	@@false
@@shoot:
	test	[BYTE bx+OB_FLAGS],FL_SHOOTABLE
	jnz	@@false
	jmp	@@stepdir
;
; the diagonals: (x+dx,y+dy), (x+dx,y), (x,y+dy), all CHECKDIAG
;
@@diag:
	mov	bx,[si+OB_TILEX]
	add	bx,cx
	shl	bx,6
	add	bx,[si+OB_TILEY]
	mov	ax,bx					; (x+dx)<<6 + y
	add	bx,dx
	shl	bx,1
	mov	bx,[actorat+bx]
	or	bx,bx
	jz	@@d1
	cmp	bx,256
	jb	@@false
	test	[BYTE bx+OB_FLAGS],FL_SHOOTABLE
	jnz	@@false
@@d1:
	mov	bx,ax
	shl	bx,1
	mov	bx,[actorat+bx]
	or	bx,bx
	jz	@@d2
	cmp	bx,256
	jb	@@false
	test	[BYTE bx+OB_FLAGS],FL_SHOOTABLE
	jnz	@@false
@@d2:
	mov	bx,[si+OB_TILEX]
	shl	bx,6
	add	bx,[si+OB_TILEY]
	add	bx,dx
	shl	bx,1
	mov	bx,[actorat+bx]
	or	bx,bx
	jz	@@stepdir
	cmp	bx,256
	jb	@@false
	test	[BYTE bx+OB_FLAGS],FL_SHOOTABLE
	jnz	@@false
@@stepdir:
	mov	bx,[si+OB_DIR]
@@step:
	mov	al,[dirdx+bx]
	cbw
	add	[si+OB_TILEX],ax
	mov	al,[dirdy+bx]
	cbw
	add	[si+OB_TILEY],ax
@@placed:
	cmp	di,-1
	je	@@area
	push	di
	call	OpenDoor
	add	sp,2
	mov	ax,di
	neg	ax
	dec	ax						; -doornum-1
	cwd
	mov	[si+OB_DISTANCE],ax
	mov	[si+OB_DISTANCE+2],dx
	mov	ax,1
	ret
@@area:
	mov	bx,[si+OB_TILEY]
	shl	bx,1
	mov	bx,[farmapylookup+bx]
	add	bx,[si+OB_TILEX]
	shl	bx,1
	mov	es,[mapsegs]			; plane 0
	mov	al,[es:bx]
	sub	al,AREATILE
	mov	[si+OB_AREANUMBER],al
	mov	[WORD si+OB_DISTANCE],0
	mov	[WORD si+OB_DISTANCE+2],1	; TILEGLOBAL
	mov	ax,1
	ret
@@false:
	xor	ax,ax
	ret
ENDP

;
; void SelectPathDir (objtype *ob)
;
;	spot = MAPSPOT(ob->tilex,ob->tiley,1)-ICONARROWS;	(unsigned)
;	if (spot<8) ob->dir = spot;
;	ob->distance = TILEGLOBAL;
;	if (!TryWalk (ob)) ob->dir = nodir;
;
PROC	SelectPathDir
PUBLIC	SelectPathDir
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,[bp+6]
	call	SelectPathDirN
	pop	di
	pop	si
	pop	bp
	ret
ENDP

PROC	SelectPathDirN NEAR			; SI = the actor; keeps SI and BP
	mov	bx,[si+OB_TILEY]
	shl	bx,1
	mov	bx,[farmapylookup+bx]
	add	bx,[si+OB_TILEX]
	shl	bx,1
	mov	es,[mapsegs+2]			; plane 1
	mov	ax,[es:bx]
	sub	ax,ICONARROWS
	cmp	ax,8
	jae	@@same
	mov	[si+OB_DIR],ax
@@same:
	mov	[WORD si+OB_DISTANCE],0
	mov	[WORD si+OB_DISTANCE+2],1	; TILEGLOBAL
	call	TryWalkN
	or	ax,ax
	jnz	@@ok
	mov	[WORD si+OB_DIR],D_NODIR
@@ok:
	ret
ENDP

;
; void MoveObj (objtype *ob, long move)
;
;	ob->x, ob->y += move in ob->dir (nodir: return; else Quit)
;	if (areabyplayer[ob->areanumber])
;	{
;		deltax = ob->x - player->x;  if outside +-MINACTORDIST goto moveok
;		deltay = ob->y - player->y;  likewise
;		if (ob->obclass == ghostobj || ob->obclass == spectreobj)
;			TakeDamage (tics*2,ob);
;		the move taken back;  return;
;	}
;	moveok: ob->distance -= move;
;
PROC	MoveObj
PUBLIC	MoveObj
	push	bp
	mov	bp,sp
	push	si
	push	di
	mov	si,[bp+6]
	mov	ax,[bp+8]
	mov	dx,[bp+10]
	call	MoveObjN
	pop	di
	pop	si
	pop	bp
	ret
ENDP

PROC	MoveObjN NEAR				; SI = the actor, DX:AX = move; keeps SI, BP
	mov	bx,[si+OB_DIR]
	cmp	bx,D_NODIR
	jb	@@go
	je	@@ret
	call	BadMoveDir			; Quits
@@go:
	mov	cx,ax
	mov	di,dx					; DI:CX = move
	cmp	[dirdx+bx],0
	je	@@noxx
	jl	@@subx
	add	[si+OB_X],cx
	adc	[si+OB_X+2],di
	jmp	@@noxx
@@subx:
	sub	[si+OB_X],cx
	sbb	[si+OB_X+2],di
@@noxx:
	cmp	[dirdy+bx],0
	je	@@noyy
	jl	@@suby
	add	[si+OB_Y],cx
	adc	[si+OB_Y+2],di
	jmp	@@noyy
@@suby:
	sub	[si+OB_Y],cx
	sbb	[si+OB_Y+2],di
@@noyy:
	mov	bl,[si+OB_AREANUMBER]
	xor	bh,bh
	shl	bx,1
	cmp	[areabyplayer+bx],0
	je	@@moveok
	mov	bx,[player]
	mov	ax,[si+OB_X]
	mov	dx,[si+OB_X+2]
	sub	ax,[bx+OB_X]
	sbb	dx,[bx+OB_X+2]			; deltax
	cmp	dx,-1
	jl	@@moveok				; < -MINACTORDIST (FFFF:0000)
	cmp	dx,1
	jl	@@xin
	jg	@@moveok
	or	ax,ax
	jnz	@@moveok				; > MINACTORDIST (0001:0000)
@@xin:
	mov	ax,[si+OB_Y]
	mov	dx,[si+OB_Y+2]
	sub	ax,[bx+OB_Y]
	sbb	dx,[bx+OB_Y+2]			; deltay
	cmp	dx,-1
	jl	@@moveok
	cmp	dx,1
	jl	@@yin
	jg	@@moveok
	or	ax,ax
	jnz	@@moveok
@@yin:
	mov	ax,[si+OB_CLASS]
	cmp	ax,C_GHOST
	je	@@hurt
	cmp	ax,C_SPECTRE
	jne	@@back
@@hurt:
	push	cx
	push	si						; TakeDamage (tics*2,ob)
	mov	ax,[tics]
	shl	ax,1
	push	ax
	call	TakeDamage
	add	sp,4
	pop	cx						; (DI is kept by the C)
@@back:
	mov	bx,[si+OB_DIR]			; back up
	cmp	bx,D_NODIR
	jae	@@ret
	cmp	[dirdx+bx],0
	je	@@bnox
	jl	@@baddx
	sub	[si+OB_X],cx
	sbb	[si+OB_X+2],di
	jmp	@@bnox
@@baddx:
	add	[si+OB_X],cx
	adc	[si+OB_X+2],di
@@bnox:
	cmp	[dirdy+bx],0
	je	@@ret
	jl	@@baddy
	sub	[si+OB_Y],cx
	sbb	[si+OB_Y+2],di
	ret
@@baddy:
	add	[si+OB_Y],cx
	adc	[si+OB_Y+2],di
@@ret:
	ret
@@moveok:
	sub	[si+OB_DISTANCE],cx
	sbb	[si+OB_DISTANCE+2],di
	ret
ENDP

;
; void T_Path (objtype *ob)
;
;	if (SightPlayer (ob)) return;
;	if (ob->dir == nodir) { SelectPathDir (ob); if (ob->dir == nodir) return; }
;	move = ob->speed*tics;
;	while (move)
;	{
;		if (ob->distance < 0)
;		{
;			OpenDoor (-ob->distance-1);
;			if (doorobjlist[-ob->distance-1].action != dr_open) return;
;			ob->distance = TILEGLOBAL;
;		}
;		if (move < ob->distance) { MoveObj (ob,move); break; }
;		if (ob->tilex>MAPSIZE || ob->tiley>MAPSIZE) Quit (...);
;		ob->x = ((long)ob->tilex<<TILESHIFT)+TILEGLOBAL/2;
;		ob->y = ((long)ob->tiley<<TILESHIFT)+TILEGLOBAL/2;
;		move -= ob->distance;
;		SelectPathDir (ob);
;		if (ob->dir == nodir) return;
;	}
;
PROC	T_Path
PUBLIC	T_Path
	push	bp
	mov	bp,sp
	sub	sp,4					; move: [bp-4] low, [bp-2] high
	push	si
	push	di
	mov	si,[bp+6]
	push	si
	call	SightPlayer
	add	sp,2
	or	ax,ax
	jnz	@@ret
	cmp	[WORD si+OB_DIR],D_NODIR
	jne	@@go
	call	SelectPathDirN
	cmp	[WORD si+OB_DIR],D_NODIR
	je	@@ret
@@go:
	mov	ax,[si+OB_SPEED]		; move = speed*tics, the low 32 bits
	mul	[tics]
	mov	[bp-4],ax
	mov	cx,dx
	mov	ax,[si+OB_SPEED+2]
	mul	[tics]
	add	ax,cx
	mov	[bp-2],ax
	jmp	@@test

@@loop:
	cmp	[WORD si+OB_DISTANCE+2],0
	jge	@@notdoor				; distance < 0: waiting for a door
	mov	ax,[si+OB_DISTANCE]
	neg	ax
	dec	ax
	push	ax
	call	OpenDoor
	add	sp,2
	mov	ax,[si+OB_DISTANCE]
	neg	ax
	mov	dx,DOOR_SIZE
	imul	dx
	mov	bx,ax
	cmp	[WORD doorobjlist-DOOR_SIZE+DOOR_ACTION+bx],0	; dr_open
	jne	@@ret
	mov	[WORD si+OB_DISTANCE],0
	mov	[WORD si+OB_DISTANCE+2],1	; TILEGLOBAL
@@notdoor:
	mov	ax,[si+OB_DISTANCE+2]
	cmp	ax,[bp-2]
	jl	@@whole					; distance < move
	jg	@@part
	mov	ax,[si+OB_DISTANCE]
	cmp	ax,[bp-4]
	jbe	@@whole
@@part:
	mov	ax,[bp-4]				; move < distance: MoveObj (ob,move)
	mov	dx,[bp-2]
	call	MoveObjN
	jmp	@@ret
@@whole:
	cmp	[WORD si+OB_TILEX],64
	ja	@@wall
	cmp	[WORD si+OB_TILEY],64
	jbe	@@center
@@wall:
	push	si
	call	TPathHitWall			; Quits
@@center:
	mov	ax,[si+OB_TILEX]
	mov	[WORD si+OB_X],8000h	; tile<<TILESHIFT + TILEGLOBAL/2
	mov	[si+OB_X+2],ax
	mov	ax,[si+OB_TILEY]
	mov	[WORD si+OB_Y],8000h
	mov	[si+OB_Y+2],ax
	mov	ax,[si+OB_DISTANCE]
	sub	[bp-4],ax
	mov	ax,[si+OB_DISTANCE+2]
	sbb	[bp-2],ax
	call	SelectPathDirN
	cmp	[WORD si+OB_DIR],D_NODIR
	je	@@ret
@@test:
	mov	ax,[bp-4]
	or	ax,[bp-2]
	jnz	@@loop
@@ret:
	pop	di
	pop	si
	mov	sp,bp
	pop	bp
	ret
ENDP


;============================
;
; CheckLine (objtype *ob) -- can ob see the player?  (a boolean)
;
; NEC V30 build, StevenC & Claude: WL_STATE.C's line-of-sight trace, called
; by every shooting actor's think routine.  The same two passes -- across
; the x tile boundaries between ob and the player, then across the y ones
; -- with the same fixed-point stepping, the same clamp and the same door
; test, so every actor decides exactly as id's did (a demo would lose sync
; otherwise).  The C's long divide, ((long)delta<<8)/deltafrac clamped to
; +-7FFFh, is one unsigned DIV here, guarded so it cannot overflow: a high
; word at or above the divisor means a quotient over 0FFFFh, which clamps
; anyway.  x*64+y for the tile map is kept as a running offset.
;
;============================

PROC	CheckLine
PUBLIC	CheckLine
	push	bp
	mov	bp,sp
	push	si
	push	di

	mov	si,[bp+6]
	mov	ax,[si+OB_X+1]				; x1 = ob->x>>8, 1/256 tile
	mov	[clx1],ax
	mov	ax,[si+OB_Y+1]				; y1 = ob->y>>8
	mov	[cly1],ax
	mov	si,[player]

;
; across the x tiles
;
	mov	ax,[clx1]
	sar	ax,8						; xt1
	mov	bx,[si+OB_TILEX]			; xt2
	cmp	bx,ax
	jne	@@xgo
	jmp	@@ypass
@@xgo:
	mov	cx,[clx1]
	and	cx,0ffh
	cmp	bx,ax
	jg	@@xpos
	mov	bp,-64						; xstep = -1: partial = x1&0xff
	dec	bx							; xt2 += xstep
	dec	ax							; x = xt1+xstep
	jmp	@@xset
@@xpos:
	neg	cx
	add	cx,256						; xstep = 1: partial = 256-(x1&0xff)
	mov	bp,64
	inc	bx
	inc	ax
@@xset:
	shl	ax,6						; x, as a tile map offset
	shl	bx,6
	mov	[clend],bx
	push	ax
	mov	ax,[plux]
	sub	ax,[clx1]
	jns	@@xdf
	neg	ax
@@xdf:
	mov	bx,ax						; deltafrac = abs(x2-x1)
	mov	ax,[pluy]
	sub	ax,[cly1]					; delta = y2-y1
	call	StepDiv
	mov	di,ax						; ystep
	imul	cx							; ystep*partial
	mov	al,ah						; >>8
	mov	ah,dl
	add	ax,[cly1]
	mov	cx,ax						; yfrac = y1 + (ystep*partial>>8)
	mov	ax,di
	cwd
	sub	ax,dx
	sar	ax,1
	mov	[clhalf],ax					; ystep/2, truncated toward zero as C does
	pop	bx							; x*64

@@xloop:
	mov	ax,cx
	sar	ax,8						; y = yfrac>>8
	add	cx,di						; yfrac += ystep
	mov	si,bx
	add	si,ax
	add	bx,bp						; x += xstep
	mov	al,[BYTE tilemap+si]
	or	al,al
	jnz	@@xhit
@@xnext:
	cmp	bx,[clend]
	jne	@@xloop
	jmp	@@ypass
@@xhit:
	cmp	al,128
	jb	@@false						; a wall
	cmp	al,0C0h						; step 98: a pushwall on the move (0C0h+tile)
	jae	@@false						; blocks: id read doorposition[64+]
	xor	ah,ah
	and	al,7fh						; a door: open far enough?
	mov	si,ax
	shl	si,1
	mov	ax,cx
	sub	ax,[clhalf]					; intercept = yfrac-ystep/2
	cmp	ax,[doorposition+si]
	ja	@@false
	jmp	@@xnext

;
; across the y tiles
;
@@ypass:
	mov	si,[player]
	mov	ax,[cly1]
	sar	ax,8						; yt1
	mov	bx,[si+OB_TILEY]			; yt2
	cmp	bx,ax
	jne	@@ygo
	jmp	@@true
@@ygo:
	mov	cx,[cly1]
	and	cx,0ffh
	cmp	bx,ax
	jg	@@ypos
	mov	bp,-1						; ystep = -1
	dec	bx
	dec	ax
	jmp	@@yset
@@ypos:
	neg	cx
	add	cx,256
	mov	bp,1
	inc	bx
	inc	ax
@@yset:
	mov	[clend],bx
	push	ax
	mov	ax,[pluy]
	sub	ax,[cly1]
	jns	@@ydf
	neg	ax
@@ydf:
	mov	bx,ax						; deltafrac = abs(y2-y1)
	mov	ax,[plux]
	sub	ax,[clx1]					; delta = x2-x1
	call	StepDiv
	mov	di,ax						; xstep
	imul	cx
	mov	al,ah
	mov	ah,dl
	add	ax,[clx1]
	mov	cx,ax						; xfrac
	mov	ax,di
	cwd
	sub	ax,dx
	sar	ax,1
	mov	[clhalf],ax					; xstep/2
	pop	bx							; y

@@yloop:
	mov	ax,cx
	sar	ax,2						; (xfrac>>8)<<6, one shift fewer
	and	al,0c0h
	add	cx,di						; xfrac += xstep
	mov	si,ax
	add	si,bx
	add	bx,bp						; y += ystep
	mov	al,[BYTE tilemap+si]
	or	al,al
	jnz	@@yhit
@@ynext:
	cmp	bx,[clend]
	jne	@@yloop
@@true:
	mov	ax,1
	jmp	@@ret
@@yhit:
	cmp	al,128
	jb	@@false
	cmp	al,0C0h
	jae	@@false
	xor	ah,ah
	and	al,7fh
	mov	si,ax
	shl	si,1
	mov	ax,cx
	sub	ax,[clhalf]					; intercept = xfrac-xstep/2
	cmp	ax,[doorposition+si]
	ja	@@false
	jmp	@@ynext

@@false:
	xor	ax,ax
@@ret:
	pop	di
	pop	si
	pop	bp
	ret
ENDP

;
; StepDiv: AX = ((long)AX<<8)/BX, clamped to -7FFFh..7FFFh, BX > 0.
; Destroys DX and SI.
;
PROC	StepDiv NEAR
	mov	si,ax						; the sign
	or	ax,ax
	jns	@@pos
	neg	ax
@@pos:
	mov	dl,ah						; dx:ax = |delta|<<8
	xor	dh,dh
	mov	ah,al
	xor	al,al
	cmp	dx,bx
	jae	@@clamp						; the quotient would not fit
	div	bx
	cmp	ax,7fffh
	jbe	@@sign
@@clamp:
	mov	ax,7fffh
@@sign:
	or	si,si
	jns	@@done
	neg	ax
@@done:
	ret
ENDP


;============================
;
; DoActors -- for (obj = player;obj;obj = obj->next) DoActor (obj);
;
; NEC V30 build, StevenC & Claude.  PlayLoop's actor loop (step 35), and
; since step 50 WL_PLAY.C's DoActor inside it, statement for statement --
; an actor that is awake cost a far call and a C frame, and a whole-loop
; profile put DoActor at 1.75% once the later demos filled up with enemies:
;
;	if (!ob->active && !areabyplayer[ob->areanumber]) skip;
;	if (!(ob->flags&(FL_NONMARK|FL_NEVERMARK)))
;		actorat[ob->tilex][ob->tiley] = NULL;
;	if (!ob->ticcount)
;		goto think;						(id's code repeats the think block)
;	ob->ticcount -= tics;
;	while (ob->ticcount <= 0)
;	{
;		if (ob->state->action) { action (ob); if (!ob->state) remove; }
;		ob->state = ob->state->next;
;		if (!ob->state) remove;
;		if (!ob->state->tictime) { ob->ticcount = 0; goto think; }
;		ob->ticcount += ob->state->tictime;
;	}
; think:
;	if (ob->state->think) { think (ob); if (!ob->state) remove; }
;	if (ob->flags&FL_NEVERMARK) next;
;	if ((ob->flags&FL_NONMARK) && actorat[ob->tilex][ob->tiley]) next;
;	actorat[ob->tilex][ob->tiley] = ob;
;
; Every field is read from the actor again after a call, as the C did: the
; think and action routines move actors, change states and remove them.
; ob->next is read after the actor is done with, as the C for loop read it.
;
;============================

PROC	DoActors
PUBLIC	DoActors
	push	si
	push	di
	mov	si,[player]
	or	si,si
	jnz	@@loop
;
; NEC V30 build (step 60): @@done and @@next sit above the loop's head, so an
; actor skipped below -- inactive, outside the player's areas: most of them
; -- costs one short jump back, and the walk falls into the next one.
;
@@done:
	pop	di
	pop	si
	ret
@@next:
	mov	si,[si+OB_NEXT]
	or	si,si
	jz	@@done
@@loop:
	cmp	[WORD si+OB_ACTIVE],0
	jne	@@do
	mov	bl,[si+OB_AREANUMBER]
	xor	bh,bh
	shl	bx,1
	cmp	[areabyplayer+bx],0
	je	@@next
@@do:
	test	[BYTE si+OB_FLAGS],FL_NONMARK OR FL_NEVERMARK
	jnz	@@marked
	mov	di,[si+OB_TILEX]
	shl	di,6
	add	di,[si+OB_TILEY]
	shl	di,1
	mov	[actorat+di],0				; actorat[tilex][tiley] = NULL
@@marked:
	cmp	[WORD si+OB_TICCOUNT],0
	je	@@think
	mov	ax,[tics]
	sub	[si+OB_TICCOUNT],ax
@@tloop:
	cmp	[WORD si+OB_TICCOUNT],0
	jg	@@think						; while (ob->ticcount <= 0), signed
	mov	bx,[si+OB_STATE]
	mov	ax,[bx+SS_ACTION]
	or	ax,[bx+SS_ACTION+2]
	jz	@@noaction
	push	si
	call	[DWORD bx+SS_ACTION]
	add	sp,2
	cmp	[WORD si+OB_STATE],0
	je	@@remove
@@noaction:
	mov	bx,[si+OB_STATE]
	mov	bx,[bx+SS_NEXT]
	mov	[si+OB_STATE],bx
	or	bx,bx
	jz	@@remove
	mov	ax,[bx+SS_TICTIME]
	or	ax,ax
	jnz	@@addtic
	mov	[WORD si+OB_TICCOUNT],0
	jmp	@@think
@@addtic:
	add	[si+OB_TICCOUNT],ax
	jmp	@@tloop

@@think:
	mov	bx,[si+OB_STATE]
	mov	ax,[bx+SS_THINK]
	or	ax,[bx+SS_THINK+2]
	jz	@@mark
	push	si
	call	[DWORD bx+SS_THINK]
	add	sp,2
	cmp	[WORD si+OB_STATE],0
	je	@@remove
@@mark:
	test	[BYTE si+OB_FLAGS],FL_NEVERMARK
	jnz	@@next
	mov	di,[si+OB_TILEX]
	shl	di,6
	add	di,[si+OB_TILEY]
	shl	di,1
	test	[BYTE si+OB_FLAGS],FL_NONMARK
	jz	@@setmark
	cmp	[actorat+di],0
	jne	@@next
@@setmark:
	mov	[actorat+di],si				; actorat[tilex][tiley] = ob
	jmp	@@next
@@remove:
	push	si
	call	RemoveObj
	add	sp,2
	jmp	@@next
ENDP



;============================
;
; NEC V30 build (step 81), StevenC & Claude: FLATWALLS -- every wall one
; solid colour, drawn four columns at a time.  See WL_DRAW.C's WallRefresh.
;
;============================

;
; FlatSetup: the first frame with FLATWALLS, after FlatColours (WL_DRAW.C)
; has set each wall page's colour: ScalePostA's entry jumps to FlatPost, and
; the hit routines' page fetches call FlatPage.
;
PROC	FlatSetup FAR
PUBLIC	FlatSetup
	mov	ax,[flatbuf]			; step 84: the columns' buffer, allocated at
	mov	[cs:wcseg],ax			; startup for FLATWALLS only (and locked)
	push	di						; (C's register variable)
	push	ax
	cmp	[solidart],0			; step 84: FLATART -- no artwork, every wall
	je	@@keepart				; its own colour
	push	cs
	pop	es
	mov	di,OFFSET flatart
	mov	cx,FLATPAGES
	xor	al,al
	rep	stosb
@@keepart:
	pop	ax
; step 84: the fill body, built at wcseg:FBODY -- pair k (FMAX-1 down to 0)
; is MOV [DI-(k+1)*80],AL and MOV [DI+k*80],AH, then a RETF.  With LOWVERT
; (step 82) only the even row of each pair is written (half is even: the row
; above, half-1-k, is even when k is odd, the row below when k is even); the
; other is LEA BX,[BX+0], which writes nothing.
	mov	[cs:fr_far+2],ax		; (AX = wcseg)
	mov	es,ax
	mov	di,FBODY
	mov	bx,-80*FMAX				; the row above's displacement, pair FMAX-1
	mov	dx,80*(FMAX-1)			; the row below's
	mov	cx,FMAX-1				; k
@@gen:
	mov	ax,8588h				; 88 85: MOV [DI+d16],AL
	cmp	[lowvert],0
	je	@@up
	test	cl,1
	jnz	@@up
	mov	ax,9F8Dh				; 8D 9F: LEA BX,[BX+0]
	stosw
	xor	ax,ax
	stosw
	jmp	@@down
@@up:
	stosw
	mov	ax,bx
	stosw
@@down:
	mov	ax,0A588h				; 88 A5: MOV [DI+d16],AH
	cmp	[lowvert],0
	je	@@dn
	test	cl,1
	jz	@@dn
	mov	ax,9F8Dh
	stosw
	xor	ax,ax
	stosw
	jmp	@@nextk
@@dn:
	stosw
	mov	ax,dx
	stosw
@@nextk:
	add	bx,80
	sub	dx,80
	dec	cx
	jns	@@gen
	mov	al,0CBh					; RETF
	stosb
	mov	ax,OFFSET FlatPost		; ScalePostA: JMP FlatPost
	sub	ax,OFFSET ScalePostA+3
	mov	[BYTE cs:ScalePostA],0E9h
	mov	[WORD cs:ScalePostA+1],ax
	mov	[WORD cs:hvwgp+1],OFFSET FlatPage	; CALL FAR FlatPage, here
	mov	[WORD cs:hvwgp+3],cs
	mov	[WORD cs:hhwgp+1],OFFSET FlatPage
	mov	[WORD cs:hhwgp+3],cs
	pop	di
	retf
ENDP

;
; FlatColour: a wall page's colour.  C: void FlatColour (int page, int colour).
;
PROC	FlatColour FAR
PUBLIC	FlatColour
	push	bp
	mov	bp,sp
	mov	bx,[bp+6]
	and	bx,FLATPAGES-1
	mov	al,[bp+8]
	mov	[cs:flatcol+bx],al
	pop	bp
	retf
ENDP

;
; FlatPage: a wall page's colour, in place of its segment -- postsource's
; segment carries it to FlatPost.  C: unsigned FlatPage (int page).
;
PROC	FlatPage FAR
PUBLIC	FlatPage
	push	bp
	mov	bp,sp
	mov	bx,[bp+6]
	and	bx,FLATPAGES-1
	mov	al,[cs:flatart+bx]		; step 83: artwork is drawn as it is
	or	al,al
	jne	@@art
	mov	al,[cs:flatcol+bx]
	xor	ah,ah
	pop	bp
	retf
@@art:
	push	si
	push	di
	mov	si,bx					; SI = the page
	push	ax						; its code
	push	si
	call	PM_GetPage
	add	sp,2
	pop	bx
	sub	bl,2
	jb	@@artret				; no twin: as it is
	xor	bh,bh
	mov	di,bx					; DI = k
	mov	bl,[cs:artbase+di]
	mov	dl,[cs:flatcol+bx]		; DL = the twin's flat colour now
	mov	es,ax
	shl	di,1
	mov	bx,[cs:arts0+di]
	cmp	[es:bx],dl
	jne	@@paint
	mov	bx,[cs:arts1+di]
	cmp	[es:bx],dl
	je	@@artret				; painted with it already
@@paint:
	push	di
	push	dx
	mov	bx,di
	shr	bx,1
	mov	bl,[cs:artbase+bx]
	xor	bh,bh
	push	bx
	call	PM_GetPage				; the twin
	add	sp,2
	mov	cx,ax
	push	si
	call	PM_GetPage				; the artwork again (it was used just before
	add	sp,2					; the twin, so it is still in)
	pop	dx
	pop	di
	mov	bx,[cs:artold+di]		; the colour it was painted with, if any
	cmp	bx,0FFFFh
	jne	@@old
	mov	bl,dl
@@old:
	xor	dh,dh
	mov	[cs:artold+di],dx
	push	ds
	mov	ds,cx					; DS = the twin, ES = the artwork
	mov	es,ax
	xor	si,si
	mov	cx,4096
@@px:
	mov	al,[es:si]
	cmp	al,[si]
	je	@@bg					; as the plain wall: background
	cmp	al,bl
	jne	@@nx					; (or the colour it was painted with)
@@bg:
	mov	[es:si],dl
@@nx:
	inc	si
	loop	@@px
	pop	ds
	mov	ax,es
@@artret:
	pop	di
	pop	si
	pop	bp
	retf
ENDP

;
; FlatPost: ScalePostA with FLATWALLS.  Each column of the post gets a word
; in wc: its colour, and above it the half height of the wall, clamped as
; ScalePostA clamps it (scaler 0 is scaler 1, none beyond the view).
; Keeps SI, as ScalePostA does.
;
PROC	FlatPost NEAR
PUBLIC	FlatPost					; public only so profiles can name it
	mov	bx,[postx]
	shl	bx,1
	mov	ax,[wallheight+bx]
	and	ax,0FFF8h
	shr	ax,1
	cmp	ax,[maxscaleshl2]
	jle	@@hok
	mov	ax,[maxscaleshl2]
@@hok:
	cmp	ax,[postmin]			; the frame's least wall, as ScalePostA keeps it
	jae	@@mok
	mov	[postmin],ax
@@mok:
	cmp	[WORD postsource+2],0FFh
	ja	@@tex					; step 83: a segment, not a colour -- artwork
	shr	ax,2
	jnz	@@nz
	inc	ax
@@nz:
	mov	dx,[viewheight]
	shr	dx,1
	cmp	ax,dx
	jbe	@@cc
	mov	ax,dx
@@cc:
	mov	ah,al
	mov	al,[BYTE postsource+2]	; the colour
	mov	di,bx					; wcseg:2x
	mov	cx,[postwidth]
	mov	es,[cs:wcseg]
	rep	stosw
	ret
;
; step 83: artwork, drawn by its compiled scaler as ScalePostA draws it
; (without the band, which FlatRender fills), and its columns marked
;
@@tex:
	push	si
	push	ax						; its scale*4
	mov	bp,ax
	add	bp,OFFSET fullscalefarcall
	mov	di,[postx]
	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,[postwidth]			; bx = pixel*8+pixwidth
	mov	al,[mapmasks1-1+bx]
	mov	dx,SC_INDEX+1
	out	dx,al
	les	si,[postsource]			; ES:SI = the texture column
	mov	cx,SCREENSEG
	mov	ds,cx					; DS = the screen
	call	[DWORD bp]
	mov	al,[ss:mapmasks2-1+bx]
	or	al,al
	jz	@@tdone
	inc	di
	out	dx,al
	call	[DWORD bp]
	mov	al,[ss:mapmasks3-1+bx]
	or	al,al
	jz	@@tdone
	inc	di
	out	dx,al
	call	[DWORD bp]
@@tdone:
	mov	ax,ss
	mov	ds,ax
	pop	ax
	pop	si
	shr	ax,2
	jnz	@@tnz
	inc	ax
@@tnz:
	mov	dx,[viewheight]
	shr	dx,1
	cmp	ax,dx
	jbe	@@tcc
	mov	ax,dx
@@tcc:
	or	al,80h					; drawn already: FlatRender fills its band only
	mov	ah,al
	xor	al,al
	mov	bx,[postx]
	shl	bx,1
	mov	di,bx
	mov	cx,[postwidth]
	mov	es,[cs:wcseg]
	rep	stosw
	ret
ENDP

;
; FlatRender: the walls of the frame, a byte -- four columns -- at a time.
; SI walks wc, DI the byte at the view's middle row; DS is the screen, the
; C's data is reached through SS, and DX stays SC_INDEX+1.
;
PROC	FlatRender FAR
PUBLIC	FlatRender
	push	si
	push	di
	push	bp
	mov	ax,[viewheight]
	shr	ax,1
	mov	cx,80
	mul	cx
	add	ax,[bufferofs]
	mov	di,ax
	mov	ax,[bandhalf]
	mov	[cs:fr_band],ax
	mov	al,[BYTE ceilcolor]
	mov	ah,19h					; the floor, as VGAClearScreen fills it
	mov	[cs:fr_cf],ax
	mov	ax,[viewwidth]
	shr	ax,2
	mov	[cs:fr_groups],ax
	mov	dx,SC_INDEX
	mov	al,2					; the map mask register
	out	dx,al
	inc	dx
	mov	es,[cs:wcseg]		; ES:SI = wc
	xor	si,si
	mov	ax,SCREENSEG
	mov	ds,ax
fr_group:
	mov	al,[es:si+1]			; step 83: artwork in the group?
	or	al,[es:si+3]
	or	al,[es:si+5]
	or	al,[es:si+7]
	js	fr_art
	mov	bl,[es:si+1]			; BL = m, BH = M: the least and most of the four
	mov	bh,bl
	mov	al,[es:si+3]
	cmp	al,bl
	jae	frn3
	mov	bl,al
frn3:
	cmp	al,bh
	jbe	frx3
	mov	bh,al
frx3:
	mov	al,[es:si+5]
	cmp	al,bl
	jae	frn5
	mov	bl,al
frn5:
	cmp	al,bh
	jbe	frx5
	mov	bh,al
frx5:
	mov	al,[es:si+7]
	cmp	al,bl
	jae	frn7
	mov	bl,al
frn7:
	cmp	al,bh
	jbe	frx7
	mov	bh,al
frx7:
	mov	[cs:fr_mm],bx
	mov	al,[es:si]
	cmp	al,[es:si+2]
	jne	fr_mixed
	cmp	al,[es:si+4]
	jne	fr_mixed
	cmp	al,[es:si+6]
	jne	fr_mixed
	mov	ah,al
	mov	[cs:fr_col],ax
	mov	al,0Fh					; one colour: the rows all four cover, at once
	out	dx,al
	mov	ax,[cs:fr_col]
	xor	cx,cx
	xor	bh,bh					; BX = m
	call	FlatFill
	mov	bx,[cs:fr_mm]
	cmp	bl,bh
	je	fr_bandchk				; one height: nothing ragged
	mov	al,bl					; the ragged rows start at row m
	mov	ah,80
	mul	ah
	mov	bp,di
	add	bp,ax
	mov	[cs:fr_dn],bp
	mov	bp,di
	sub	bp,ax
	sub	bp,80
	mov	[cs:fr_up],bp
	mov	cl,[es:si+1]
	sub	cl,[BYTE cs:fr_mm]
	jz	frr0
	mov	al,1
	out	dx,al
	mov	ax,[cs:fr_col]
	call	FlatRows
frr0:
	mov	cl,[es:si+3]
	sub	cl,[BYTE cs:fr_mm]
	jz	frr1
	mov	al,2
	out	dx,al
	mov	ax,[cs:fr_col]
	call	FlatRows
frr1:
	mov	cl,[es:si+5]
	sub	cl,[BYTE cs:fr_mm]
	jz	frr2
	mov	al,4
	out	dx,al
	mov	ax,[cs:fr_col]
	call	FlatRows
frr2:
	mov	cl,[es:si+7]
	sub	cl,[BYTE cs:fr_mm]
	jz	frr3
	mov	al,8
	out	dx,al
	mov	ax,[cs:fr_col]
	call	FlatRows
frr3:
	jmp	fr_bandchk
fr_mixed:								; four colours not one: column by column
	mov	al,1
	out	dx,al
	mov	al,[es:si+0]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+1]
	xor	bh,bh
	call	FlatFill
	mov	al,2
	out	dx,al
	mov	al,[es:si+2]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+3]
	xor	bh,bh
	call	FlatFill
	mov	al,4
	out	dx,al
	mov	al,[es:si+4]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+5]
	xor	bh,bh
	call	FlatFill
	mov	al,8
	out	dx,al
	mov	al,[es:si+6]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+7]
	xor	bh,bh
	call	FlatFill
;
; the band VGAClearScreen left: nothing to do when every wall of the four
; covers it; else ceiling and floor at once beyond the tallest, then each
; column's own
;
fr_bandchk:
	mov	bx,[cs:fr_mm]
	cmp	bl,[BYTE cs:fr_band]
	jae	fr_next
	mov	cl,bh
	xor	ch,ch					; CX = M
	mov	bx,[cs:fr_band]			; BX = B
	cmp	cx,bx
	jae	fr_blim					; M at least B: each column's band ends at B
	mov	al,0Fh
	out	dx,al
	mov	ax,[cs:fr_cf]
	push	cx
	call	FlatFill				; rows M .. B-1, all four
	pop	bx						; each column's band ends at M
fr_blim:
	mov	[cs:fr_lim],bx
	mov	cl,[es:si+1]
	xor	ch,ch
	mov	bx,[cs:fr_lim]
	cmp	cx,bx
	jae	frb0
	mov	al,1
	out	dx,al
	mov	ax,[cs:fr_cf]
	call	FlatFill
frb0:
	mov	cl,[es:si+3]
	xor	ch,ch
	mov	bx,[cs:fr_lim]
	cmp	cx,bx
	jae	frb1
	mov	al,2
	out	dx,al
	mov	ax,[cs:fr_cf]
	call	FlatFill
frb1:
	mov	cl,[es:si+5]
	xor	ch,ch
	mov	bx,[cs:fr_lim]
	cmp	cx,bx
	jae	frb2
	mov	al,4
	out	dx,al
	mov	ax,[cs:fr_cf]
	call	FlatFill
frb2:
	mov	cl,[es:si+7]
	xor	ch,ch
	mov	bx,[cs:fr_lim]
	cmp	cx,bx
	jae	frb3
	mov	al,8
	out	dx,al
	mov	ax,[cs:fr_cf]
	call	FlatFill
frb3:
fr_next:
	inc	di
	add	si,8
	dec	[WORD cs:fr_groups]
	jz	fr_done
	jmp	fr_group
fr_done:
	mov	ax,ss
	mov	ds,ax
	pop	bp
	pop	di
	pop	si
	retf
;
; step 83: a group with artwork -- column by column, each its wall unless
; the scaler drew it, then its band
;
fr_art:
	mov	al,[es:si+1]
	test	al,80h
	jnz	fra0
	mov	al,1
	out	dx,al
	mov	al,[es:si+0]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+1]
	xor	bh,bh
	call	FlatFill
fra0:
	mov	al,1
	out	dx,al
	mov	cl,[es:si+1]
	and	cx,7Fh
	mov	bx,[cs:fr_band]
	mov	ax,[cs:fr_cf]
	call	FlatFill				; rows cc .. B-1, if any
	mov	al,[es:si+3]
	test	al,80h
	jnz	fra1
	mov	al,2
	out	dx,al
	mov	al,[es:si+2]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+3]
	xor	bh,bh
	call	FlatFill
fra1:
	mov	al,2
	out	dx,al
	mov	cl,[es:si+3]
	and	cx,7Fh
	mov	bx,[cs:fr_band]
	mov	ax,[cs:fr_cf]
	call	FlatFill				; rows cc .. B-1, if any
	mov	al,[es:si+5]
	test	al,80h
	jnz	fra2
	mov	al,4
	out	dx,al
	mov	al,[es:si+4]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+5]
	xor	bh,bh
	call	FlatFill
fra2:
	mov	al,4
	out	dx,al
	mov	cl,[es:si+5]
	and	cx,7Fh
	mov	bx,[cs:fr_band]
	mov	ax,[cs:fr_cf]
	call	FlatFill				; rows cc .. B-1, if any
	mov	al,[es:si+7]
	test	al,80h
	jnz	fra3
	mov	al,8
	out	dx,al
	mov	al,[es:si+6]
	mov	ah,al
	xor	cx,cx
	mov	bl,[es:si+7]
	xor	bh,bh
	call	FlatFill
fra3:
	mov	al,8
	out	dx,al
	mov	cl,[es:si+7]
	and	cx,7Fh
	mov	bx,[cs:fr_band]
	mov	ax,[cs:fr_cf]
	call	FlatFill				; rows cc .. B-1, if any
	jmp	fr_next
ENDP

;
; FlatRows: CL rows (1 or more) from fr_up up and fr_dn down, AL above and
; AH below, in the byte the map mask has set.  Uses BX, CX, BP.
;
PROC	FlatRows NEAR
	xor	ch,ch
	mov	bx,[cs:fr_up]
	mov	bp,[cs:fr_dn]
@@row:
	mov	[bx],al
	mov	[ds:bp],ah
	sub	bx,80
	add	bp,80
	loop	@@row
	ret
ENDP

;
; FlatFill: rows lo..hi-1 above and below the centre DI -- AL above, AH
; below -- in the byte at DI with the map mask set.  CX = lo, BX = hi, both
; at most FMAX.  Uses BX, CX, BP.  A RET is patched in after row lo when lo
; is not 0 and taken out again; the body ends in its own.
;
PROC	FlatFill NEAR
PUBLIC	FlatFill					; public only so profiles can name it
	cmp	cx,bx
	jae	@@none
	mov	bp,FMAX
	sub	bp,bx
	shl	bp,3
	add	bp,FBODY				; the pair for row hi-1
	mov	[cs:fr_far],bp
	jcxz	@@all
	mov	bx,FMAX
	sub	bx,cx
	shl	bx,3
	add	bx,FBODY				; the pair for row lo-1: stop there
	mov	cl,[es:bx]				; (step 84: the body is at ES = wcseg)
	mov	[BYTE es:bx],0CBh		; RETF
	call	[DWORD cs:fr_far]
	mov	[es:bx],cl
@@none:
	ret
@@all:
	call	[DWORD cs:fr_far]
	ret
ENDP

fr_far		dw	0,0			; step 84: FlatFill's far call into the body

FLATPAGES	=	128				; wall pages a colour is kept for (WL6 has 106)
flatcol		db	FLATPAGES DUP (0)
LABEL	flatart	BYTE			; steps 83, 84: 0 flat, 1 artwork as it is, 2+k artwork
								; on a flat wall, its twin artbase[k]
	db	0,0,0,0,2,3,4,5,6,7,1,1,8,9,0,0
	db	0,0,10,11,12,13,0,0,0,0,14,15,0,0,1,1
	db	0,0,16,17,0,0,1,1,1,1,1,1,18,19,0,0
	db	0,0,0,0,0,0,20,21,0,0,0,0,0,0,0,0
	db	1,1,0,0,0,0,22,23,0,0,0,0,0,0,0,0
	db	24,25,0,0,26,27,0,0,0,0,0,0,28,29,0,0
	db	30,31,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	db	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
LABEL	artbase	BYTE			; step 84: each painted artwork's plain twin
	db	0,1,2,3,16,15,16,15,22,23,22,23,28,29,32,33
	db	22,23,52,53,78,79,14,15,68,69,82,83,68,69
LABEL	arts0	WORD			; ... two of its background pixels, whose plain
	dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
	dw	0,0,0,0,0,0,0,0,0,0,0,0,0,0
LABEL	arts1	WORD			; colours differ
	dw	1,2,1,10,1,1,1,1,1,1,1,1,1,1,1,2
	dw	1,1,1,1,15,16,1,1,16,16,1,1,16,16
artold		dw	30 DUP (0FFFFh)	; the colour it was painted with, FFFFh none
wcseg		dw	0				; step 84: wc -- each column's colour and its wall's
								; half height, 320 words -- is at wcseg:0 now
fr_mm		dw	0				; the group's least (low) and most half height
fr_col		dw	0
fr_up		dw	0
fr_dn		dw	0
fr_band		dw	0
fr_cf		dw	0
fr_lim		dw	0
fr_groups	dw	0
FMAX		=	80
FBODY		=	640+128*3		; step 84: the body's place in the buffer

;============================
;
; The automap (2026-10-05, StevenC & Claude): TAB shows a map of what has
; been seen, drawn over the 3D view, which is still rendered underneath --
; aiming, FL_VISABLE and the rays' exploring all go on as ever, and the map
; only reads the game.  Never during a demo (WL_DRAW.C and WL_PLAY.C).
;
; A tile is explored when its spotvis byte is set (the rays mark it with
; the frame's vismark; the array is cleared every 255 frames, and
; AutomapCollect folds it into the level's own map, am_seen, first).
;
; Drawn four pixels to a tile: with the map mask on all four planes one
; byte is a tile's row, so a row of the map is a run of bytes, built in
; am_row and copied to each of its four scan lines with REP MOVSB.  Items
; and enemies are a 2x2 dot in their tile; the player a green tile with a
; white dot on the side it faces.  Enemies show when the player has a line
; of sight to them (CheckLine) -- seen or not, the way a map would.
;
;============================

CODESEG

AM_FLOOR	=	237						; dark grey
AM_WALL		=	22						; grey
AM_DOOR		=	123						; cyan
AM_GOLD		=	59						; orange: the gold key's doors
AM_SILVER	=	18						; silver
AM_LIFT		=	212						; brown: the elevator
AM_ITEM		=	71						; yellow
AM_ENEMY	=	32						; red
AM_PLAYER	=	95						; green
AM_FACE		=	15						; white
OB_ANGLE	=	42

am_on		dw	0
am_prev		dw	0
am_demo		dw	0
am_skip		dw	0
am_area		db	64 DUP (0)				; the rooms (areas) the player has entered
am_seen		dd	0						; the level's explored tiles, 64x64
am_cols		dw	0
am_rows		dw	0
am_x0		dw	0
am_y0		dw	0
am_scr		dw	0
am_cy		dw	0
am_row		db	80 DUP (0)
am_dx		db	1,1,0,-1,-1,-1,0,1		; the eight directions, east first,
am_dy		db	0,-1,-1,-1,0,1,1,1		; counterclockwise (north is -y)
am_doorc	db	AM_DOOR,AM_GOLD,AM_SILVER,AM_DOOR,AM_DOOR,AM_LIFT,AM_DOOR,AM_DOOR

;
; void AutomapReset (byte far *seen) -- a level's start: nothing explored
;
PROC	AutomapReset FAR
PUBLIC	AutomapReset
	push	bp
	mov	bp,sp
	push	di
	les	di,[bp+6]
	mov	[WORD cs:am_seen],di
	mov	[WORD cs:am_seen+2],es
	xor	ax,ax
	mov	cx,2048
	cld
	rep	stosw
	mov	ax,cs						; no room entered yet
	mov	es,ax
	mov	di,OFFSET am_area
	xor	ax,ax
	mov	cx,32
	rep	stosw
	pop	di
	pop	bp
	retf
ENDP

;
; void AutomapCollect (void) -- spotvis folded into am_seen (before it is
; cleared)
;
PROC	AutomapCollect FAR
PUBLIC	AutomapCollect
	push	si
	push	di
	les	di,[cs:am_seen]
	mov	ax,es
	or	ax,ax
	jz	@@none
	mov	si,OFFSET spotvis
	mov	cx,2048
	cld
@@w:
	lodsw
	or	[es:di],ax
	add	di,2
	loop	@@w
@@none:
	pop	di
	pop	si
	retf
ENDP

;
; int AutomapKey (int down) -- TAB, edge-triggered: toggles the map
;
PROC	AutomapKey FAR
PUBLIC	AutomapKey
	push	bp
	mov	bp,sp
	mov	ax,[bp+6]
	or	ax,ax
	jz	@@up
	cmp	[cs:am_prev],0
	jne	@@held
	xor	[cs:am_on],1
@@held:
	mov	[cs:am_prev],1
	jmp	@@ret
@@up:
	mov	[cs:am_prev],0
@@ret:
	mov	ax,[cs:am_on]
	pop	bp
	retf
ENDP

;
; int AutomapOn (int demo) -- the map is on (and in a demo only after the
; AUTOMAP switch, which is for showing it: a demo never sees TAB)
;
PROC	AutomapOn FAR
PUBLIC	AutomapOn
	push	bp
	mov	bp,sp
	mov	ax,[cs:am_on]
	cmp	[WORD bp+6],0
	je	@@r
	and	ax,[cs:am_demo]
@@r:
	pop	bp
	retf
ENDP

;
; int AutomapSkip (int demo) -- with the map up (and not in a demo), the 3D
; view under it is rendered one frame in four: 1 on the other three
;
PROC	AutomapSkip FAR
PUBLIC	AutomapSkip
	push	bp
	mov	bp,sp
	call	AmRoom
	xor	ax,ax
	cmp	[WORD bp+6],0
	je	@@play
	cmp	[cs:am_demo],0				; a demo: only with AUTOMAP, for showing
	je	@@r							; and timing it
@@play:
	cmp	[cs:am_on],0
	je	@@r
	inc	[cs:am_skip]
	and	[cs:am_skip],3
	jz	@@r
	inc	ax
@@r:
	pop	bp
	retf
ENDP

;
; void AutomapPickup (void) -- on a frame not rendered, what DrawScaleds would
; have done for items: GetBonus for one the player stands on
;
PROC	AutomapPickup FAR
PUBLIC	AutomapPickup
	push	si
	mov	bx,[player]
	mov	dl,[BYTE bx+OB_TILEX]
	mov	dh,[BYTE bx+OB_TILEY]
	mov	si,OFFSET statobjlist
@@s:
	cmp	si,[laststatobj]
	jae	@@done
	cmp	[WORD si+ST_SHAPENUM],-1
	je	@@n
	test	[BYTE si+ST_FLAGS],FL_BONUS
	jz	@@n
	cmp	[si+ST_TILEX],dl
	jne	@@n
	cmp	[si+ST_TILEY],dh
	jne	@@n
	push	dx
	push	si
	call	GetBonus
	pop	si
	pop	dx
@@n:
	add	si,ST_SIZE
	jmp	@@s
@@done:
	pop	si
	retf
ENDP

;
; void AutomapForce (void) -- the AUTOMAP switch: on from the start, demos too
;
PROC	AutomapForce FAR
PUBLIC	AutomapForce
	mov	[cs:am_on],1
	mov	[cs:am_demo],1
	retf
ENDP

;
; void AutomapDraw (void) -- over the view at bufferofs (already moved to
; the view's corner by ThreeDRefresh), viewwidth x viewheight
;
PROC	AutomapDraw FAR
PUBLIC	AutomapDraw
	push	bp
	push	si
	push	di
	push	es
	mov	ax,[WORD cs:am_seen+2]
	or	ax,ax
	jnz	@@go
	jmp	@@out
@@go:
	mov	ax,[viewwidth]
	shr	ax,2
	mov	[cs:am_cols],ax
	mov	ax,[viewheight]
	shr	ax,2
	mov	[cs:am_rows],ax
	mov	bx,[player]
	mov	ax,[bx+OB_TILEX]			; the player in the middle
	mov	cx,[cs:am_cols]
	shr	cx,1
	sub	ax,cx
	mov	[cs:am_x0],ax
	mov	ax,[bx+OB_TILEY]
	mov	cx,[cs:am_rows]
	shr	cx,1
	sub	ax,cx
	mov	[cs:am_y0],ax
	mov	dx,SC_INDEX					; all four planes: a byte is a tile's row
	mov	ax,0F02h
	out	dx,ax
	mov	ax,[bufferofs]
	mov	[cs:am_scr],ax
	mov	[cs:am_cy],0

@@row:
	les	bx,[cs:am_seen]				; ES:BX the explored map
	mov	ax,[cs:am_y0]
	add	ax,[cs:am_cy]				; y
	mov	di,OFFSET am_row
	mov	cx,[cs:am_cols]
	cmp	ax,63
	jbe	@@yok
@@blank:							; a row off the map
	mov	[BYTE cs:di],0
	inc	di
	loop	@@blank
	jmp	@@blit
@@yok:
	mov	dx,[cs:am_x0]				; x
	mov	si,dx
	shl	si,6
	add	si,ax						; x*64+y: spotvis' and tilemap's order
@@col:
	cmp	dx,63
	ja	@@black
	mov	al,[spotvis+si]
	or	al,[es:bx+si]
	jz	@@unseen
@@seenok:
	mov	al,[BYTE tilemap+si]
	or	al,al
	jz	@@floor
	test	al,80h
	jz	@@wall
	test	al,40h
	jnz	@@wall						; the pushwall on the move
	push	bx							; a door: its lock's colour
	and	ax,3Fh
	mov	bx,ax
	shl	bx,3
	add	bx,ax						; *9
	mov	bl,[doorobjlist+bx+4]
	and	bx,7
	mov	al,[cs:am_doorc+bx]
	pop	bx
	jmp	@@put
@@wall:
	mov	al,AM_WALL
	jmp	@@put
@@floor:
	mov	al,AM_FLOOR
	jmp	@@put
@@unseen:							; a wall nobody has stood by: is it
	mov	al,[BYTE tilemap+si]		; beside explored floor?  (The rays stop
	or	al,al						; at walls, so walls are never marked
	jz	@@black						; themselves.)
@@nb:
	or	dx,dx						; west (x-1)
	jz	@@n2
	mov	al,[spotvis+si-64]
	or	al,[es:bx+si-64]
	jnz	@@seenok
@@n2:
	cmp	dx,63						; east
	jae	@@n3
	mov	al,[spotvis+si+64]
	or	al,[es:bx+si+64]
	jnz	@@seenok
@@n3:
	mov	ax,si						; north and south: y is si's low 6 bits
	and	ax,63
	jz	@@n4
	mov	al,[spotvis+si-1]
	or	al,[es:bx+si-1]
	jnz	@@seenok
	mov	ax,si
	and	ax,63
@@n4:
	cmp	ax,63
	jae	@@black
	mov	al,[spotvis+si+1]
	or	al,[es:bx+si+1]
	jnz	@@seenok
@@black:
	xor	al,al
@@put:
	mov	[cs:di],al
	inc	di
	inc	dx
	add	si,64
	loop	@@col

@@blit:								; the row's four scan lines
	push	ds
	mov	ax,cs
	mov	ds,ax
	mov	ax,SCREENSEG
	mov	es,ax
	mov	di,[cs:am_scr]
	mov	dx,4
	cld
@@scan:
	mov	si,OFFSET am_row
	mov	cx,[cs:am_cols]
	push	di
	rep	movsb
	pop	di
	add	di,80
	dec	dx
	jnz	@@scan
	pop	ds
	add	[cs:am_scr],320
	inc	[cs:am_cy]
	mov	ax,[cs:am_cy]
	cmp	ax,[cs:am_rows]
	jae	@@things
	jmp	@@row

@@things:							; the dots: pixels 1 and 2 of a tile,
	mov	dx,SC_INDEX					; rows 1 and 2
	mov	ax,0602h
	out	dx,ax
	mov	si,OFFSET statobjlist		; items: what can be picked up, seen
@@stat:
	cmp	si,[laststatobj]
	jae	@@actors
	cmp	[WORD si+ST_SHAPENUM],-1
	je	@@snext
	test	[BYTE si+ST_FLAGS],FL_BONUS
	jz	@@snext
	mov	al,[si+ST_TILEX]
	xor	ah,ah
	mov	cl,[si+ST_TILEY]
	xor	ch,ch
	call	AmSeen
	jz	@@snext
	mov	al,[si+ST_TILEX]
	xor	ah,ah
	mov	cl,[si+ST_TILEY]
	xor	ch,ch
	mov	bl,AM_ITEM
	call	AmDot
@@snext:
	add	si,ST_SIZE
	jmp	@@stat

@@actors:							; enemies the player has a line of sight to
	mov	si,[player]
	mov	si,[si+OB_NEXT]
@@act:
	or	si,si
	jz	@@me
	test	[BYTE si+OB_FLAGS],FL_SHOOTABLE
	jz	@@anext
	mov	ax,[si+OB_TILEX]			; off the map's window: not worth asking
	sub	ax,[cs:am_x0]
	cmp	ax,[cs:am_cols]
	jae	@@anext
	mov	ax,[si+OB_TILEY]
	sub	ax,[cs:am_y0]
	cmp	ax,[cs:am_rows]
	jae	@@anext
	mov	bl,[si+OB_AREANUMBER]		; shut off from the player's area
	xor	bh,bh
	shl	bx,1
	cmp	[areabyplayer+bx],0
	je	@@anext
	push	si
	call	CheckLine
	pop	si
	or	ax,ax
	jz	@@anext
	mov	ax,[si+OB_TILEX]
	mov	cx,[si+OB_TILEY]
	mov	bl,AM_ENEMY
	call	AmDot
@@anext:
	mov	si,[si+OB_NEXT]
	jmp	@@act

@@me:								; the player, and the way it faces
	mov	dx,SC_INDEX
	mov	ax,0F02h
	out	dx,ax
	mov	si,[player]
	mov	ax,[si+OB_TILEX]
	mov	cx,[si+OB_TILEY]
	call	AmCell
	jc	@@out
	mov	al,AM_PLAYER
	mov	[es:di],al
	mov	[es:di+80],al
	mov	[es:di+160],al
	mov	[es:di+240],al
	mov	dx,SC_INDEX
	mov	ax,0602h
	out	dx,ax
	mov	ax,[si+OB_ANGLE]			; 0-359, 0 east, counterclockwise
	add	ax,22
	cmp	ax,360
	jb	@@a
	sub	ax,360
@@a:
	xor	dx,dx
	mov	cx,45
	div	cx							; 0-7
	mov	bx,ax
	mov	al,[cs:am_dx+bx]
	cbw
	add	ax,[si+OB_TILEX]
	push	ax
	mov	al,[cs:am_dy+bx]
	cbw
	add	ax,[si+OB_TILEY]
	mov	cx,ax
	pop	ax
	mov	bl,AM_FACE
	call	AmDot
@@out:
	mov	dx,SC_INDEX
	mov	ax,0F02h
	out	dx,ax
	pop	es
	pop	di
	pop	si
	pop	bp
	retf
ENDP

;
; AmRoom (2026-10-05): the room (area) the player stands in, the first time:
; every floor tile of it marked explored in am_seen, from the map's plane 0
; (AREATILE + the area on each of its tiles).  A room once entered is on the
; map whole, the way the SNES version drew it.  Keeps BP.
;
PROC	AmRoom NEAR
	mov	bx,[player]
	or	bx,bx
	jz	@@ret
	mov	bl,[bx+OB_AREANUMBER]
	xor	bh,bh
	cmp	bx,37						; NUMAREAS
	jae	@@ret
	cmp	[cs:am_area+bx],0
	jne	@@ret
	cmp	[WORD cs:am_seen+2],0
	je	@@ret
	mov	[cs:am_area+bx],1
	push	si
	push	di
	push	ds
	push	es
	mov	dx,bx
	add	dx,107						; AREATILE
	mov	es,[mapsegs]				; plane 0, row by row (y*64+x words)
	lds	bx,[cs:am_seen]				; DS:BX the explored map (x*64+y)
	xor	si,si
	xor	ax,ax						; y
@@y:
	mov	di,ax						; x*64+y, x = 0
	mov	cx,64
@@x:
	cmp	[es:si],dx
	jne	@@n
	mov	[BYTE bx+di],1
@@n:
	add	si,2
	add	di,64
	loop	@@x
	inc	ax
	cmp	ax,64
	jb	@@y
	pop	es
	pop	ds
	pop	di
	pop	si
@@ret:
	ret
ENDP

;
; AmSeen: AX, CX a tile -> ZF clear if explored.  Keeps SI.
;
PROC	AmSeen NEAR
	push	si
	mov	si,ax
	shl	si,6
	add	si,cx
	les	bx,[cs:am_seen]
	mov	al,[spotvis+si]
	or	al,[es:bx+si]
	pop	si
	ret
ENDP

;
; AmCell: AX, CX a tile -> ES:DI its top-left byte on the page, CF if it is
; off the map's window.  Keeps SI, BX.
;
PROC	AmCell NEAR
	sub	ax,[cs:am_x0]
	cmp	ax,[cs:am_cols]
	jae	@@off
	sub	cx,[cs:am_y0]
	cmp	cx,[cs:am_rows]
	jae	@@off
	mov	di,cx
	shl	di,2
	add	di,cx						; *5
	shl	di,6						; *320: four scan lines a tile
	add	di,ax
	add	di,[bufferofs]
	mov	ax,SCREENSEG
	mov	es,ax
	clc
	ret
@@off:
	stc
	ret
ENDP

;
; AmDot: AX, CX a tile, BL a colour: its 2x2 dot (the map mask set to 06h)
; Keeps SI.
;
PROC	AmDot NEAR
	push	bx
	call	AmCell
	pop	bx
	jc	@@no
	mov	[es:di+80],bl
	mov	[es:di+160],bl
@@no:
	ret
ENDP

;
; MarkRun (2026-10-05, the automap in BSP mode): the run at AX in wk_runs is
; being drawn: both tiles beside its line, along it, get this frame's mark in
; spotvis, as the rays mark what they cross.  Keeps every register.
;
mr_a	dw	0
mr_b	dw	0

PROC	MarkRun NEAR
	push	ax
	push	bx
	push	cx
	push	dx
	push	si
	push	di
	push	es
	les	si,[cs:wk_runs]
	mov	si,ax
	mov	dl,[BYTE vismark]
	mov	al,[es:si+3]
	xor	ah,ah
	mov	di,ax						; a2
	mov	cl,[es:si+2]
	xor	ch,ch						; a1
	mov	bl,[es:si+1]
	xor	bh,bh						; the line
	mov	al,[es:si]					; of: bit 0, along x
	mov	[cs:mr_a],0					; the tile before the line, and after
	mov	[cs:mr_b],0
	or	bx,bx
	jz	@@na
	inc	[cs:mr_a]
@@na:
	cmp	bx,63
	ja	@@nb
	inc	[cs:mr_b]
@@nb:
	test	al,1
	jnz	@@h
	mov	si,bx						; along y: x = line
	shl	si,6
@@v:
	cmp	cx,di
	jae	@@done
	mov	bx,si
	add	bx,cx
	cmp	[cs:mr_a],0
	je	@@v1
	mov	[spotvis+bx-64],dl
@@v1:
	cmp	[cs:mr_b],0
	je	@@v2
	mov	[spotvis+bx],dl
@@v2:
	inc	cx
	jmp	@@v
@@h:								; along x: y = line
@@hl:
	cmp	cx,di
	jae	@@done
	mov	si,cx
	shl	si,6
	add	si,bx
	cmp	[cs:mr_a],0
	je	@@h1
	mov	[spotvis+si-1],dl
@@h1:
	cmp	[cs:mr_b],0
	je	@@h2
	mov	[spotvis+si],dl
@@h2:
	inc	cx
	jmp	@@hl
@@done:
	pop	es
	pop	di
	pop	si
	pop	dx
	pop	cx
	pop	bx
	pop	ax
	ret
ENDP

END
