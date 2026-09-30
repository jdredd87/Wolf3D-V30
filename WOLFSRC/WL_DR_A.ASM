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
	jne	hvw_newcol
	inc	[postwidth]				; wide scale
	mov	bx,[pixx]
	shl	bx,1
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
	mov	[postwidth],1
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
	je	hvw_first
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
	mov	[postwidth],1
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
	push	[WORD ttnx+2]				; LDIV@ (dividend, divisor): divisor first
	push	[WORD ttnx]
	push	di
	push	si
	call	F_LDIV@						; pops its own arguments
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
	push	[WORD ttnx+2]				; LDIV@ (dividend, divisor): divisor first
	push	[WORD ttnx]
	push	di
	push	si
	call	F_LDIV@						; pops its own arguments
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
	EVEN
nextpix:
	mov	bx,[pixx]
	inc	bx
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
	jle	horizentry					; 0x7d = jge (ytilestep==1)
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
	jg	vertentry

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
	jl	horizentry					; on xtilestep): 0x7f = jg, 0x7c = jl
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
	jne	hhw_newcol
	inc	[postwidth]				; wide scale
	mov	bx,[pixx]
	shl	bx,1
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
	mov	[postwidth],1
	mov	ax,[pixx]
	mov	[postx],ax
	jmp	nextpix
czp_newmin:
	mov	[postmin],bp
	jmp	czp_minok
czp_short:
	call	ScalePostA				; (it recomputes; postmin is a least value)
	jmp	czp_done
hhw_newwall:
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
	je	hhw_first
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
	mov	[postwidth],1
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

	call	FAR HitVertPWall
	jmp	nextpix



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


END


