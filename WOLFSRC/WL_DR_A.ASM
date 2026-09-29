	IDEAL
	MODEL	MEDIUM,C
	P186				; NEC V30 build: the V30 runs the 80186 set
	JUMPS				; out-of-range Jcc become Jcc-around-JMP; in-range ones are untouched

SCREENSEG	=	0a000h

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

EXTRN	finetangent:DWORD	; far array, starts at offset 0

EXTRN	HitHorizDoor:FAR
EXTRN	HitVertDoor:FAR
EXTRN	HitHorizPWall:FAR
EXTRN	HitVertPWall:FAR
EXTRN	ScaleShape:FAR
EXTRN	FarScalePost:FAR
EXTRN	PM_GetPage:FAR
EXTRN	GetBonus:FAR
EXTRN	TransformActor:FAR
EXTRN	CalcRotate:FAR
EXTRN	NOLANGUAGE F_LDIV@:FAR		; Borland's signed long divide (H_LDIV.ASM)


DATASEG

EXTRN	viewwidth:WORD

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

EXTRN	xtile:WORD
EXTRN	ytile:WORD
EXTRN	xtilestep:WORD
EXTRN	ytilestep:WORD
EXTRN	xintercept:DWORD
EXTRN	yintercept:DWORD
EXTRN	xstep:DWORD
EXTRN	ystep:DWORD

EXTRN	doorposition:WORD		; table of door position values


EXTRN	pwallpos:WORD			; amound a pushable wall has been moved

CODESEG

;-------------------
;
; xpartialbyystep
;
; multiplies long [ystep] (possibly negative), by word [xpartial] (in BX)
;
; returns dx:ax
; trashes bx,cx,di
;
;-------------------

PROC xpartialbyystep NEAR
;
; setup
;
	mov	ax,[WORD ystep]
	mov	cx,[WORD ystep+2]
	or	cx,cx               ; is ystep negatice?
	jns	@@multpos
;
; multiply negative cx:ax by bx
;
	neg	cx
	neg	ax
	sbb	cx,0

	mul	bx					; fraction*fraction
	mov	di,dx				; di is low word of result
	mov	ax,cx				;
	mul	bx					; units*fraction
	add	ax,di
	adc	dx,0

	neg	dx
	neg	ax
	sbb	dx,0
	ret
;
; multiply positive cx:ax by bx
;
EVEN
@@multpos:
	mul	bx					; fraction*fraction
	mov	di,dx				; di is low word of result
	mov	ax,cx				;
	mul	bx					; units*fraction
	add	ax,di
	adc	dx,0

	ret

ENDP



;-------------------
;
; ypartialbyxstep
;
; multiplies long [xstep] (possibly negative), by word [ypartial] (in BP)
;
; returns dx:ax
; trashes cx,di,bp
;
;-------------------

PROC ypartialbyxstep NEAR
;
; setup
;
	mov	ax,[WORD xstep]
	mov	cx,[WORD xstep+2]
	or	cx,cx               ; is ystep negatice?
	jns	@@multpos
;
; multiply negative cx:ax by bx
;
	neg	cx
	neg	ax
	sbb	cx,0

	mul	bp					; fraction*fraction
	mov	di,dx				; di is low word of result
	mov	ax,cx				;
	mul	bp					; units*fraction
	add	ax,di
	adc	dx,0

	neg	dx
	neg	ax
	sbb	dx,0
	ret
;
; multiply positive cx:ax by bx
;
EVEN
@@multpos:
	mul	bp					; fraction*fraction
	mov	di,dx				; di is low word of result
	mov	ax,cx				;
	mul	bp					; units*fraction
	add	ax,di
	adc	dx,0
	ret

ENDP


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

PROC	CalcHeight
PUBLIC	CalcHeight
	push	si
	push	di

	mov	ax,[WORD xintercept]
	mov	dx,[WORD xintercept+2]
	sub	ax,[WORD viewx]
	sbb	dx,[WORD viewx+2]
	FIXBYFRAC	viewcos			; dx:ax = gxt
	push	dx
	push	ax

	mov	ax,[WORD yintercept]
	mov	dx,[WORD yintercept+2]
	sub	ax,[WORD viewy]
	sbb	dx,[WORD viewy+2]
	FIXBYFRAC	viewsin			; dx:ax = gyt

	pop	bx
	pop	cx					; cx:bx = gxt
	sub	bx,ax
	sbb	cx,dx				; cx:bx = nx = gxt-gyt

	cmp	cx,[WORD mindist+2]	; if (nx < mindist) nx = mindist -- signed
	jg	@@distok
	jl	@@clamp
	cmp	bx,[WORD mindist]
	jae	@@distok
@@clamp:
	mov	bx,[WORD mindist]
	mov	cx,[WORD mindist+2]
@@distok:
	mov	bl,bh				; bx = bits 8-23 of nx, the word at nx+1
	mov	bh,cl
	mov	ax,[WORD heightnumerator]
	mov	dx,[WORD heightnumerator+2]
	idiv	bx

	pop	di
	pop	si
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
	jmp	@@test

; Laid out for the V30: an object not seen this frame -- nearly all of them
; -- falls straight through to the next; only a seen one jumps out.
	EVEN
@@loop:
	mov	bx,[si+ST_VISSPOT]			; (both tests are pure: order is free)
@@mark:
	cmp	[BYTE bx],0					; (the 0 is vismark, patched above)
	je	@@seenstat
@@next:
	add	si,ST_SIZE
@@test:
	cmp	si,[laststatobj]
	jne	@@loop
	jmp	@@statdone

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
	or	ax,ax
	jz	@@notbonus
	test	[BYTE si+ST_FLAGS],FL_BONUS
	jz	@@notbonus
	push	si
	call	GetBonus
	add	sp,2
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
; HitVertWall / HitHorizWall
;
; NEC V30 build, StevenC & Claude: WL_DRAW.C's two wall-hit routines,
; which AsmRefresh calls once per ray.  In C each was a far call with a
; frame and its state compared through memory; here they are NEAR calls
; from the ray loop.  Every register is free at the call -- AsmRefresh has
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
	cmp	[xtilestep],-1
	jne	@@tex
	mov	ax,0fc0h
	sub	ax,si
	mov	si,ax
	inc	[WORD xintercept+2]		; xintercept += TILEGLOBAL
@@tex:
	cmp	[lastside],1
	jne	@@newwall
	mov	ax,[xtile]
	cwd							; lastintercept is a long
	cmp	ax,[WORD lastintercept]
	jne	@@newwall
	cmp	dx,[WORD lastintercept+2]
	jne	@@newwall
	mov	ax,[tilehit]
	cmp	ax,[lasttilehit]
	jne	@@newwall
	cmp	si,[WORD postsource]
	jne	@@newcol
	inc	[postwidth]				; wide scale
	mov	bx,[pixx]
	shl	bx,1
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	ret
@@newcol:
	call	CalcHeight
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	call	FarScalePost
	mov	[WORD postsource],si
	mov	[postwidth],1
	mov	ax,[pixx]
	mov	[postx],ax
	ret
@@newwall:
	call	CalcHeight
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	cmp	[lastside],-1
	je	@@first
	call	FarScalePost
@@first:
	mov	[lastside],1
	mov	ax,[xtile]
	cwd
	mov	[WORD lastintercept],ax
	mov	[WORD lastintercept+2],dx
	mov	bx,[tilehit]
	mov	[lasttilehit],bx
	mov	ax,[pixx]
	mov	[postx],ax
	mov	[postwidth],1
	test	bl,40h
	jz	@@plain
	mov	ax,[WORD yintercept+2]	; ytile = yintercept>>TILESHIFT
	mov	[ytile],ax
	mov	di,[xtile]
	sub	di,[xtilestep]
	shl	di,6
	add	di,ax
	test	[BYTE tilemap+di],80h
	jz	@@notdoor
	mov	ax,[PMSpriteStart]
	sub	ax,8-3					; DOORWALL+3
	jmp	@@getpage
@@notdoor:
	and	bx,NOT 40h
@@plain:
	shl	bx,1
	mov	ax,[vertwall+bx]
@@getpage:
	push	ax
	call	PM_GetPage
	add	sp,2
	mov	[WORD postsource+2],ax
	mov	[WORD postsource],si
	ret
ENDP


PROC	HitHorizWallA NEAR
PUBLIC	HitHorizWallA				; public only so profiles can name it
	mov	si,[WORD xintercept]
	shr	si,4
	and	si,0fc0h				; SI = texture
	cmp	[ytilestep],-1
	jne	@@mirror
	inc	[WORD yintercept+2]		; yintercept += TILEGLOBAL
	jmp	@@tex
@@mirror:
	mov	ax,0fc0h
	sub	ax,si
	mov	si,ax
@@tex:
	cmp	[lastside],0
	jne	@@newwall
	mov	ax,[ytile]
	cwd
	cmp	ax,[WORD lastintercept]
	jne	@@newwall
	cmp	dx,[WORD lastintercept+2]
	jne	@@newwall
	mov	ax,[tilehit]
	cmp	ax,[lasttilehit]
	jne	@@newwall
	cmp	si,[WORD postsource]
	jne	@@newcol
	inc	[postwidth]				; wide scale
	mov	bx,[pixx]
	shl	bx,1
	mov	ax,[wallheight+bx-2]
	mov	[wallheight+bx],ax
	ret
@@newcol:
	call	CalcHeight
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	call	FarScalePost
	mov	[WORD postsource],si
	mov	[postwidth],1
	mov	ax,[pixx]
	mov	[postx],ax
	ret
@@newwall:
	call	CalcHeight
	mov	bx,[pixx]
	shl	bx,1
	mov	[wallheight+bx],ax
	cmp	[lastside],-1
	je	@@first
	call	FarScalePost
@@first:
	mov	[lastside],0
	mov	ax,[ytile]
	cwd
	mov	[WORD lastintercept],ax
	mov	[WORD lastintercept+2],dx
	mov	bx,[tilehit]
	mov	[lasttilehit],bx
	mov	ax,[pixx]
	mov	[postx],ax
	mov	[postwidth],1
	test	bl,40h
	jz	@@plain
	mov	ax,[WORD xintercept+2]	; xtile = xintercept>>TILESHIFT
	mov	[xtile],ax
	mov	di,ax
	shl	di,6
	add	di,[ytile]
	sub	di,[ytilestep]			; tilemap[xtile][ytile-ytilestep]
	test	[BYTE tilemap+di],80h
	jz	@@notdoor
	mov	ax,[PMSpriteStart]
	sub	ax,8-2					; DOORWALL+2
	jmp	@@getpage
@@notdoor:
	and	bx,NOT 40h
@@plain:
	shl	bx,1
	mov	ax,[horizwall+bx]
@@getpage:
	push	ax
	call	PM_GetPage
	add	sp,2
	mov	[WORD postsource+2],ax
	mov	[WORD postsource],si
	ret
ENDP


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
	je	@@seen
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
	push	si
	call	TransformActor
	add	sp,2
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

	mov	[pixx],0
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
pixxloop:
	mov	ax,SEG finetangent
	mov	es,ax
	mov	cx,[midangle]			; center of view area
	mov	bx,[pixx]
	shl	bx,1
	add	cx,[pixelangle+bx]		; delta for this pixel
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
	mov	[xtilestep],1			; xtilestep = 1
	mov	[ytilestep],-1			; ytilestep = -1
	mov	[BYTE cs:horizop],OP_JGE	; patch a jge in
	mov	[BYTE cs:vertop],OP_JLE		; patch a jle in
	mov	[BYTE cs:vxtileop],OP_INCBX	; xtile += xtilestep
	mov	[BYTE cs:hytileop],OP_DECBP	; ytile += ytilestep
	mov	bx,DEG90-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	dx,[es:bx+2]
	mov	[WORD xstep],ax
	mov	[WORD cs:hxadd+4],ax	; patch xstep into the core loop
	mov	[WORD cs:hxadc+2],dx
	mov	[WORD xstep+2],dx		; xstep = finetangent[DEG90-1-angle]
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	dx,[es:bx+2]
	neg	dx
	neg	ax
	sbb	dx,0
	mov	[WORD ystep],ax
	mov	[WORD cs:vyadd+1],ax	; patch ystep into the core loop
	mov	[WORD cs:vyadc+2],dx
	mov	[WORD ystep+2],dx		; ystep = -finetangent[angle]

	mov	bx,[xpartialup]			; xpartial = xpartialup
	mov	bp,[ypartialdown]		; ypartial = ypartialdown
	jmp	initvars

not90:
	cmp	cx,DEG180
	jge	not180
;----------
;
; 90-179 degree arc
;
;----------
	mov	ax,-1
	mov	[xtilestep],ax			; xtilestep = -1
	mov	[ytilestep],ax			; ytilestep = -1
	mov	[BYTE cs:horizop],OP_JLE	; patch a jle in
	mov	[BYTE cs:vertop],OP_JLE		; patch a jle in
	mov	[BYTE cs:vxtileop],OP_DECBX	; xtile += xtilestep
	mov	[BYTE cs:hytileop],OP_DECBP	; ytile += ytilestep

	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG90*4]
	mov	dx,[es:bx+2-DEG90*4]
	neg	dx
	neg	ax
	sbb	dx,0
	mov	[WORD xstep],ax
	mov	[WORD cs:hxadd+4],ax	; patch xstep into the core loop
	mov	[WORD cs:hxadc+2],dx
	mov	[WORD xstep+2],dx		; xstep = -finetangent[angle-DEG90]
	mov	bx,DEG180-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	dx,[es:bx+2]
	neg	dx
	neg	ax
	sbb	dx,0
	mov	[WORD ystep],ax
	mov	[WORD cs:vyadd+1],ax	; patch ystep into the core loop
	mov	[WORD cs:vyadc+2],dx
	mov	[WORD ystep+2],dx		; ystep = -finetangent[DEG180-1-angle]

	mov	bx,[xpartialdown]		; xpartial = xpartialdown
	mov	bp,[ypartialdown]		; ypartial = ypartialdown
	jmp	initvars

not180:
	cmp	cx,DEG270
	jge	not270
;----------
;
; 180-269 degree arc
;
;----------
	mov	[xtilestep],-1			; xtilestep = -1
	mov	[ytilestep],1			; ytilestep = 1
	mov	[BYTE cs:horizop],OP_JLE	; patch a jle in
	mov	[BYTE cs:vertop],OP_JGE		; patch a jge in
	mov	[BYTE cs:vxtileop],OP_DECBX	; xtile += xtilestep
	mov	[BYTE cs:hytileop],OP_INCBP	; ytile += ytilestep

	mov	bx,DEG270-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	dx,[es:bx+2]
	neg	dx
	neg	ax
	sbb	dx,0
	mov	[WORD xstep],ax
	mov	[WORD cs:hxadd+4],ax	; patch xstep into the core loop
	mov	[WORD cs:hxadc+2],dx
	mov	[WORD xstep+2],dx		; xstep = -finetangent[DEG270-1-angle]
	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG180*4]
	mov	dx,[es:bx+2-DEG180*4]
	mov	[WORD ystep],ax
	mov	[WORD cs:vyadd+1],ax	; patch ystep into the core loop
	mov	[WORD cs:vyadc+2],dx
	mov	[WORD ystep+2],dx		; ystep = finetangent[angle-DEG180]

	mov	bx,[xpartialdown]		; xpartial = xpartialdown
	mov	bp,[ypartialup]			; ypartial = ypartialup
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
	mov	ax,1
	mov	[xtilestep],ax			; xtilestep = 1
	mov	[ytilestep],ax			; ytilestep = 1
	mov	[BYTE cs:horizop],OP_JGE	; patch a jge in
	mov	[BYTE cs:vertop],OP_JGE		; patch a jge in
	mov	[BYTE cs:vxtileop],OP_INCBX	; xtile += xtilestep
	mov	[BYTE cs:hytileop],OP_INCBP	; ytile += ytilestep

	mov	bx,cx
	shl	bx,2
	mov	ax,[es:bx-DEG270*4]
	mov	dx,[es:bx+2-DEG270*4]
	mov	[WORD xstep],ax
	mov	[WORD cs:hxadd+4],ax	; patch xstep into the core loop
	mov	[WORD cs:hxadc+2],dx
	mov	[WORD xstep+2],dx		; xstep = finetangent[angle-DEG270]
	mov	bx,DEG360-1
	sub	bx,cx
	shl	bx,2
	mov	ax,[es:bx]
	mov	dx,[es:bx+2]
	mov	[WORD ystep],ax
	mov	[WORD cs:vyadd+1],ax	; patch ystep into the core loop
	mov	[WORD cs:vyadc+2],dx
	mov	[WORD ystep+2],dx		; ystep = finetangent[DEG360-1-angle]

	mov	bx,[xpartialup]			; xpartial = xpartialup
	mov	bp,[ypartialup]			; ypartial = ypartialup
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
;---------------------------------------------------------------------------
initvars:
;	xpartialbyystep, inlined (NEC V30 build: one call and return fewer a ray)
	mov	ax,[WORD ystep]
	mov	cx,[WORD ystep+2]
	or	cx,cx
	jns	@@ixpos
	neg	cx
	neg	ax
	sbb	cx,0
	mul	bx
	mov	di,dx
	mov	ax,cx
	mul	bx
	add	ax,di
	adc	dx,0
	neg	dx
	neg	ax
	sbb	dx,0
	jmp	@@ixdone
@@ixpos:
	mul	bx
	mov	di,dx
	mov	ax,cx
	mul	bx
	add	ax,di
	adc	dx,0
@@ixdone:
	add	ax,[WORD viewy]
	adc	dx,[WORD viewy+2]
	mov	[WORD yintercept],ax
	mov	[WORD yintercept+2],dx

	mov	si,[focaltx]
	add	si,[xtilestep]
	mov	[xtile],si					; xtile = focaltx+xtilestep
	shl	si,6
	add	si,dx						; xspot = (xtile<<6) + yinttile


;	ypartialbyxstep, inlined
	mov	ax,[WORD xstep]
	mov	cx,[WORD xstep+2]
	or	cx,cx
	jns	@@iypos
	neg	cx
	neg	ax
	sbb	cx,0
	mul	bp
	mov	di,dx
	mov	ax,cx
	mul	bp
	add	ax,di
	adc	dx,0
	neg	dx
	neg	ax
	sbb	dx,0
	jmp	@@iydone
@@iypos:
	mul	bp
	mov	di,dx
	mov	ax,cx
	mul	bp
	add	ax,di
	adc	dx,0
@@iydone:
	add	ax,[WORD viewx]
	adc	dx,[WORD viewx+2]
	mov	[WORD xintercept],ax
	mov	cx,dx

	mov	bx,[focalty]
	add	bx,[ytilestep]
	mov	bp,bx						; ytile = focalty+ytilestep
	mov	di,dx
	shl	di,6
	add	di,bx						; yspot = (xinttile<<6) + ytile

	mov	bx,[xtile]
	mov	dx,[WORD yintercept+2]
	mov	ax,SCREENSEG
	mov	es,ax						; faster than mov es,[screenseg]
	mov	ax,[WORD yintercept]		; NEC V30 build: AX = low word of yintercept


;---------------------------------------------------------------------------
;
; trace along this angle until we hit a wall
;
; CORE LOOP!
;
; All variables are killed when a wall is hit
;
; AX : scratch
; BX : xtile
; CX : high word of xintercept
; DX : high word of yintercept
; AX : low word of yintercept -- NEC V30 build, StevenC & Claude: kept in
;      AX while tracing instead of added to in memory every vertical step;
;      stored back first thing at every hit, reloaded at every continue
; SI : xspot (yinttile<<6)+xtile (index into tilemap and spotvis)
; DI : yspot (xinttile<<6)+ytile (index into tilemap and spotvis)
; BP : ytile
; ES : screenseg
;
;---------------------------------------------------------------------------

;-----------
;
; check intersections with vertical walls
;
;-----------

	EVEN
vertcheck:
	cmp	dx,bp
vertop:								; 0x7e = jle (ytilestep==-1)
	jle	horizentry					; 0x7d = jge (ytilestep==1)
vertentry:
	test [BYTE tilemap+si],0ffh		; tilehit = *((byte *)tilemap+xspot);
	jnz	hitvert
passvert:
vspotop:
	mov	[BYTE spotvis+si],1			; = vismark, patched in at +4 per frame
;
; NEC V30 build, StevenC & Claude: the three steps below are patched in per
; ray by the quadrant code above, as id already patches vertop/horizop, so a
; tile step no longer reads xtilestep and both words of ystep from memory.
; The 1234h placeholders force the full imm16 encodings being patched.
;
vxtileop:
	inc	bx							; xtile+=xtilestep: INC BX or DEC BX
vyadd:
	add	ax,1234h					; yintercept += ystep (low word at +1, in AX)
vyadc:
	adc	dx,1234h					; (high word at +2)
	mov	si,bx
	shl	si,6
	add	si,dx						; xspot = (xtile<<6)+yinttile
	jmp	vertcheck

	EVEN
hitvert:
	mov	[WORD yintercept],ax		; the low word back to memory first
	mov	al,[BYTE tilemap+si]		; tilehit = *((byte *)tilemap+xspot);
	mov	[BYTE tilehit],al
	or	al,al						; set flags
	jns	notvertdoor
	jmp	vertdoor
notvertdoor:
	mov	[WORD xintercept],0
	mov	[WORD xintercept+2],bx
	mov	[xtile],bx
	mov	[WORD yintercept+2],dx
	mov	[ytile],dx
	call	HitVertWallA			; NEAR, WL_DR_A.ASM (was the far C routine)
	jmp nextpix


;-----------
;
; check intersections with horizontal walls
;
;-----------
	EVEN
horizcheck:
	cmp	cx,bx
horizop:							; 0x7e = jle (xtilestep==-1)
	jle	vertentry					; 0x7d = jge (xtilestep==1)
horizentry:
	test [BYTE tilemap+di],0ffh		; tilehit = *((byte *)tilemap+yspot);
	jnz	hithoriz
passhoriz:
hspotop:
	mov	[BYTE spotvis+di],1			; = vismark, patched in at +4 per frame
hytileop:
	inc	bp							; ytile+=ytilestep: INC BP or DEC BP, patched
hxadd:
	add	[WORD xintercept],1234h		; xintercept += xstep (low word at +4)
hxadc:
	adc	cx,1234h					; (high word at +2)
	mov	di,cx
	shl	di,6
	add	di,bp						; yspot = (xinttile<<6)+ytile
	jmp	horizcheck

	EVEN
hithoriz:
	mov	[WORD yintercept],ax		; the low word back to memory first
	mov	al,[BYTE tilemap+di]		; tilehit = *((byte *)tilemap+yspot);
	mov	[BYTE tilehit],al
	or	al,al						; set flags
	js	horizdoor
	mov	[WORD xintercept+2],cx
	mov	[xtile],cx
	mov	[WORD yintercept],0
	mov	[WORD yintercept+2],bp
	mov	[ytile],bp
	call	HitHorizWallA			; NEAR, WL_DR_A.ASM (was the far C routine)
	jmp nextpix

;---------------------------------------------------------------------------
;
; next pixel over
;
;---------------------------------------------------------------------------

nextpix:
	mov	ax,[pixx]
	inc	ax
	mov	[pixx],ax
	cmp	ax,[viewwidth]
	jge	done
	jmp	pixxloop
done:
	pop	bp
	pop	di
	pop	si
	retf

;===========================================================================

;=============
;
; hit a special horizontal wall, so find which coordinate a door would be
; intersected at, and check to see if the door is open past that point
;
;=============
horizdoor:
	mov	[xtile],bx					; save off live register variables
	mov	[WORD yintercept+2],dx

	test al,040h      				; both high bits set == pushable wall
	jnz	horizpushwall

	mov	bx,ax
	and	bx,7fh						; strip high bit
	shl	bx,1                        ; index into word width door table

	mov	ax,[WORD xstep]
	mov	dx,[WORD xstep+2]
	sar	dx,1
	rcr ax,1						; half a step gets to door position

	add	ax,[WORD xintercept]		; add half step to current intercept pos
	adc	dx,cx						; CX hold high word of xintercept

	cmp	cx,dx						; is it still in the same tile?
	je	hithmid
;
; midpoint is outside tile, so it hit the side of the wall before a door
;
continuehoriz:
	mov	bx,[xtile]					; reload register variables
	mov	dx,[WORD yintercept+2]
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
	mov	[WORD yintercept+2],bp

	call	FAR HitHorizDoor
	jmp	nextpix

;============
;
; hit a sliding horizontal wall
;
;============

horizpushwall:
	mov	ax,[WORD xstep+2]			; multiply xstep by pwallmove (0-63)
	mul	[pwallpos]
	mov	bx,ax
	mov	ax,[WORD xstep]
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

	add	ax,[WORD xintercept]		; add partial step to current intercept
	adc	dx,cx						; CX hold high word of xintercept

	cmp	cx,dx						; is it still in the same tile?
	jne	continuehoriz				; no, it hit the side

;
; draw the pushable wall at the new height
;
	mov	[WORD xintercept],ax		; save pixel intercept position
	mov	[WORD xintercept+2],dx

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
	mov	[xtile],bx					; save off live register variables
	mov	[WORD yintercept+2],dx

	test al,040h      				; both high bits set == pushable wall
	jnz	vertpushwall

	mov	bx,ax
	and	bx,7fh						; strip high bit
	shl	bx,1                        ; index into word width doorposition

	mov	ax,[WORD ystep]
	mov	dx,[WORD ystep+2]
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
	mov	dx,[WORD yintercept+2]
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
	mov	ax,[WORD ystep+2]			; multiply ystep by pwallmove (0-63)
	mul	[pwallpos]
	mov	bx,ax
	mov	ax,[WORD ystep]
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


END


