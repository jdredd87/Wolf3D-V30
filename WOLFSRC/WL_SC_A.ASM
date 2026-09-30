; WL_SC_A.ASM -- ScaleShape in assembly, for the NEC V30 build
; StevenC & Claude, 2026
;
; WL_SCALE.C's ScaleShape walks a sprite's source columns, left from the
; centre and then right, and calls ScaleLine for each span that is wide
; enough and not hidden behind a nearer wall.  Profiled on the V30 it was
; 10% of the frame, nearly all of it loop overhead: for a distant sprite
; most of the 64 columns scale to zero width and draw nothing, and the C
; loop reloaded srcx, the width table's segment and the command pointer
; from the stack and stored slinewidth for every one of them.
;
; Here srcx, slinex, slinewidth, stopx and height live in registers and
; the width table stays in ES, so a skipped column is a few register
; instructions.  The arithmetic is the C routine's exactly -- the same
; signed and unsigned comparisons, the same 16-bit wrap of srcx if a shape
; ever had leftpix 0 -- and the command pointer is not walked alongside
; srcx but computed when it is needed: in both halves it is
; dataofs[srcx-leftpix].
;
; It sits in WL_SCALE_TEXT, WL_SCALE.C's own code segment.  ScaleSpan, below,
; is WL_SCALE.C's ScaleLine and the glue that called it, in one routine.
;
; Registers in the loops:
;	SI	srcx			DI	slinex			DX	slinewidth
;	CX	stopx			BP	height			ES	comptable (scaler)

	IDEAL
	MODEL	MEDIUM,C
	P186
	JUMPS						; long conditional jumps become Jcc-around-JMP

DATASEG

EXTRN	PMSpriteStart:WORD
EXTRN	scaledirectory:WORD			; t_compscale _seg *[] -- segments
EXTRN	maxscale:WORD
EXTRN	viewwidth:WORD
EXTRN	wallheight:WORD
EXTRN	slinex:WORD
EXTRN	slinewidth:WORD
EXTRN	linecmds:DWORD
EXTRN	linescale:DWORD
EXTRN	bufferofs:WORD
EXTRN	mapmasks1:BYTE
EXTRN	mapmasks2:BYTE
EXTRN	mapmasks3:BYTE
EXTRN	mask1:BYTE
EXTRN	mask2:BYTE
EXTRN	mask3:BYTE

shapeseg	dw	?					; segment of this shape's page
leftpix		dw	?
rightpix	dw	?
xcent		dw	?
onemask		db	1,2,4,8				; step 54: mapmasks1[pixel][0], a width of 1

WIDTHS		=	130					; offset of t_compscale.width[]
DATAOFS		=	4					; offset of t_compshape.dataofs[]
SC_INDEX	=	3C4h
SCREENSEG	=	0A000h
OP_RETF		=	0CBh


SEGMENT	WL_SCALE_TEXT WORD PUBLIC 'CODE'	; WORD, so EVEN below is a real even address
	ASSUME	cs:WL_SCALE_TEXT, ds:DGROUP

EXTRN	PM_GetPage:FAR


;============================
;
; ScaleSpan
;
; Draw one span of a shape: the source column srcx (SI) scaled into the
; screen columns slinex (DI) to slinex+slinewidth-1 (DX), through the
; compiled scaler whose segment is in ES.  Keeps every register but AX and
; BX, and returns with DS = SS.
;
; This was WL_SCALE.C's ScaleLine and CallScaleLine, which handed it the
; span through slinex, slinewidth and linecmds -- two stores and four reloads
; and a C frame per span.  Here the span stays in registers, the one-byte
; case (every span of a distant sprite) is decided by one table lookup, and
; the post loop tests at the bottom.  The work is ScaleLine's exactly: the
; same masks from the same tables, the same RETF patch and the same calls.
;
; While a scaler runs, the shape is in ES and the screen in DS (see
; BuildCompScale); the scalers change only AL.
;
;	CX	the scaler's segment	BP	the column's post list
;	DX	SCREENSEG (one byte), the map mask port (two and three)
;	AH	the byte the RETF replaced
;
;============================

PROC	ScaleSpan NEAR
	push	si
	push	di
	push	dx
	push	cx
	push	bp

	mov	cx,es					; CX = the scaler
	mov	bx,si
	sub	bx,[leftpix]
	shl	bx,1
	mov	es,[shapeseg]			; ES = the shape
	mov	bp,[es:bx+DATAOFS]		; its post list for srcx

	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	shl	bx,3
	add	bx,dx					; bx = pixel*8+width
	mov	al,[mapmasks2-1+bx]		; -1 because a width of 1 is first
	or	al,al
	jnz	@@multi					; more than one byte

	mov	al,[mapmasks1-1+bx]
	mov	dx,SC_INDEX+1
	out	dx,al					; set map mask register
	mov	dx,SCREENSEG
	mov	ds,cx					; DS = the scaler
	mov	bx,[es:bp]				; table location of the rtl to patch
	or	bx,bx
	jz	@@done					; 0 ends the post list

	EVEN
@@spost:
	mov	bx,[bx]
	mov	ah,[bx]					; save old value
	mov	[BYTE bx],OP_RETF		; patch a RETF in
	mov	si,[es:bp+4]			; table location of entry spot
	mov	si,[si]
	mov	[WORD ss:linescale],si	; call here to start scaling
	mov	si,[es:bp+2]			; corrected top of shape for this post
	add	bp,6					; next post
	mov	ds,dx					; DS = the screen
	call	[DWORD ss:linescale]	; scale the post
	mov	ds,cx					; DS = the scaler
	mov	[bx],ah					; unpatch the RETF
	mov	bx,[es:bp]
	or	bx,bx
	jnz	@@spost

@@done:
	mov	ax,ss
	mov	ds,ax
	mov	es,cx					; ES = the scaler again, for the caller
	pop	bp
	pop	cx
	pop	dx
	pop	di
	pop	si
	ret

;
; two and three bytes: the masks in mask1..mask3, DX the map mask port
;
@@multi:
	mov	[mask2],al
	mov	al,[mapmasks1-1+bx]
	mov	[mask1],al
	mov	al,[mapmasks3-1+bx]
	mov	[mask3],al
	mov	dx,SC_INDEX+1
	mov	ds,cx					; DS = the scaler
	or	al,al
	jnz	@@triple

	mov	bx,[es:bp]
	or	bx,bx
	jz	@@done
@@dpost:
	mov	bx,[bx]
	mov	ah,[bx]
	mov	[BYTE bx],OP_RETF
	mov	si,[es:bp+4]
	mov	si,[si]
	mov	[WORD ss:linescale],si
	mov	si,[es:bp+2]
	add	bp,6
	push	SCREENSEG
	pop	ds						; DS = the screen
	mov	al,[ss:mask1]
	out	dx,al
	call	[DWORD ss:linescale]
	inc	di
	mov	al,[ss:mask2]
	out	dx,al
	call	[DWORD ss:linescale]
	dec	di
	mov	ds,cx
	mov	[bx],ah
	mov	bx,[es:bp]
	or	bx,bx
	jnz	@@dpost
	jmp	@@done

@@triple:
	mov	bx,[es:bp]
	or	bx,bx
	jz	@@done
@@tpost:
	mov	bx,[bx]
	mov	ah,[bx]
	mov	[BYTE bx],OP_RETF
	mov	si,[es:bp+4]
	mov	si,[si]
	mov	[WORD ss:linescale],si
	mov	si,[es:bp+2]
	add	bp,6
	push	SCREENSEG
	pop	ds
	mov	al,[ss:mask1]
	out	dx,al
	call	[DWORD ss:linescale]
	inc	di
	mov	al,[ss:mask2]
	out	dx,al
	call	[DWORD ss:linescale]
	inc	di
	mov	al,[ss:mask3]
	out	dx,al
	call	[DWORD ss:linescale]
	dec	di
	dec	di
	mov	ds,cx
	mov	[bx],ah
	mov	bx,[es:bp]
	or	bx,bx
	jnz	@@tpost
	jmp	@@done
ENDP


;============================
;
; ScaleShape (int xcenter, int shapenum, unsigned height)
;
;============================

PROC	ScaleShape FAR
PUBLIC	ScaleShape
	push	bp
	mov	bp,sp
	push	si
	push	di

;
; shape = PM_GetSpritePage (shapenum) -- first, as the C does, before the
; scale is checked
;
	mov	ax,[PMSpriteStart]
	add	ax,[bp+8]				; shapenum
	push	ax
	call	PM_GetPage
	add	sp,2
	mov	[shapeseg],ax
	mov	[WORD linecmds+2],ax	; seg of shape

	mov	di,[bp+6]				; slinex = xcenter
	mov	[xcent],di
	mov	bp,[bp+10]				; height, in BP from here on

	mov	bx,bp
	shr	bx,3					; scale = height>>3
	jnz	@@scaleok
	jmp	@@ret					; too far away
@@scaleok:
	cmp	bx,[maxscale]			; unsigned: scale is unsigned
	jbe	@@scaleok2
	jmp	@@ret					; too close
@@scaleok2:
	shl	bx,1
	mov	ax,[scaledirectory+bx]
	mov	[WORD linescale+2],ax	; seg of far call
	mov	es,[shapeseg]
	mov	cx,[es:0]				; stopx = shape->leftpix
	mov	[leftpix],cx
	mov	bx,[es:2]
	mov	[rightpix],bx
	mov	es,ax					; ES = comptable from here on

;----------------------------------------------------------------------------
;
; scale to the left (from pixel 31 to shape->leftpix)
;
;	while ( --srcx >= stopx && slinex > 0 )
;
;----------------------------------------------------------------------------

	mov	si,32
	EVEN
@@lloop:
	dec	si
	cmp	si,cx
	jb	@@lend_t				; unsigned, as srcx and stopx are
	or	di,di
	jle	@@lend_t				; slinex > 0, signed
	mov	bx,si
	shl	bx,1
	mov	dx,[es:bx+WIDTHS]		; slinewidth = comptable->width[srcx]
	or	dx,dx
	jz	@@lloop
	cmp	dx,1
	jne	@@lmulti

	dec	di						; one pixel: slinex--
	cmp	di,[viewwidth]
	jge	@@lloop
	mov	bx,di
	shl	bx,1
	cmp	[wallheight+bx],bp
	jae	@@lloop					; obscured by a closer wall
	jmp	@@l1draw				; step 54: drawn below, then back to @@lloop
;
; NEC V30 build: TASM's JUMPS turns a conditional jump that cannot reach
; into "jump the other way over a JMP", so a branch that is normally NOT
; taken became one that always is -- two taken jumps a column in each loop
; here.  These short hops keep the common path falling through.
;
@@lend_t:
	jmp	@@lend

@@lmulti:
	cmp	di,[viewwidth]
	jle	@@lonscreen
	sub	di,dx					; slinex -= slinewidth
	mov	dx,[viewwidth]
	sub	dx,di					; slinewidth = viewwidth-slinex
	cmp	dx,1
	jl	@@lloop					; still off the right side
	jmp	@@lvis
@@lonscreen:
	cmp	dx,di
	jle	@@lsub
	mov	dx,di					; slinewidth = slinex
@@lsub:
	sub	di,dx					; slinex -= slinewidth

@@lvis:
	mov	bx,di
	shl	bx,1
	cmp	[wallheight+bx],bp
	jae	@@lnotleft				; left edge hidden
	add	bx,dx
	add	bx,dx
	sub	bx,2					; wallheight[slinex+slinewidth-1]
	cmp	[wallheight+bx],bp
	jb	@@ldraw					; both edges visible
@@lshrink:						; while (right edge hidden) slinewidth--
	dec	dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@lshrink
@@ldraw:
	call	ScaleSpan
@@lagain:
	jmp	@@lloop

@@lnotleft:
	mov	ax,bx
	add	bx,dx
	add	bx,dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@lagain				; totally obscured
	mov	bx,ax
@@lgrow:						; while (left edge hidden) slinex++, slinewidth--
	inc	di
	dec	dx
	add	bx,2
	cmp	[wallheight+bx],bp
	jae	@@lgrow
	call	ScaleSpan
										; break: the rest of the shape is gone
@@lend:

;----------------------------------------------------------------------------
;
; scale to the right
;
;	while ( ++srcx <= stopx && (slinex+=slinewidth) < viewwidth )
;
;----------------------------------------------------------------------------

	mov	di,[xcent]				; slinex = xcenter
	mov	cx,[rightpix]			; stopx = shape->rightpix
	mov	si,31
	mov	ax,[leftpix]
	cmp	ax,31
	jb	@@rstart				; leftpix < 31: srcx = 31
	mov	si,ax
	dec	si						; else srcx = leftpix-1
@@rstart:
	xor	dx,dx					; slinewidth = 0

	EVEN
@@rloop:
	inc	si
	cmp	si,cx
	ja	@@done_t				; unsigned
	add	di,dx					; slinex += slinewidth
	cmp	di,[viewwidth]
	jge	@@done_t				; signed
	mov	bx,si
	shl	bx,1
	mov	dx,[es:bx+WIDTHS]
	or	dx,dx
	jz	@@rloop
	cmp	dx,1
	jne	@@rmulti

	or	di,di					; one pixel
	jl	@@rloop					; slinex >= 0
	mov	bx,di
	shl	bx,1
	cmp	[wallheight+bx],bp
	jae	@@rloop
	jmp	@@r1draw				; step 54: drawn below, then back to @@rloop
@@done_t:
	jmp	@@done

@@rmulti:
	or	di,di
	jge	@@ronscreen
	mov	ax,di
	neg	ax
	cmp	dx,ax
	jle	@@rloop					; still off the left edge (signed)
	add	dx,di					; slinewidth += slinex
	xor	di,di					; slinex = 0
	jmp	@@rvis
@@ronscreen:
	mov	ax,di
	add	ax,dx
	cmp	ax,[viewwidth]
	jle	@@rvis
	mov	dx,[viewwidth]
	sub	dx,di					; slinewidth = viewwidth-slinex

@@rvis:
	mov	bx,di
	shl	bx,1
	cmp	[wallheight+bx],bp
	jae	@@rnotleft
	add	bx,dx
	add	bx,dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jb	@@rdraw					; both edges visible
@@rshrink:
	dec	dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@rshrink
	call	ScaleSpan
	jmp	@@done					; break: the rest of the shape is gone
@@rdraw:
	call	ScaleSpan
@@ragain:
	jmp	@@rloop

@@rnotleft:
	mov	ax,bx
	add	bx,dx
	add	bx,dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@ragain				; totally obscured
	mov	bx,ax
@@rgrow:
	inc	di
	dec	dx
	add	bx,2
	cmp	[wallheight+bx],bp
	jae	@@rgrow
	call	ScaleSpan
	jmp	@@rloop

@@done:
	mov	[slinex],di				; leave the globals as the C left them
	mov	[slinewidth],dx
@@ret:
	pop	di
	pop	si
	pop	bp
	ret

;
; NEC V30 build (step 54), StevenC & Claude: a one-pixel span -- nearly every
; span of a sprite that is not close -- drawn here rather than through
; ScaleSpan.  The work is ScaleSpan's exactly, for a width of 1: one byte,
; its map mask 1<<pixel, and every post of the column.  Out of line, so the
; loops' short branches keep their reach (see step 38); the right loop's
; slinewidth is 1 again on the way back, as ScaleSpan kept it.
;
@@l1draw:
	push	si
	push	di
	push	cx
	push	bp
	mov	cx,es					; CX = the scaler
	mov	bx,si
	sub	bx,[leftpix]
	shl	bx,1
	mov	es,[shapeseg]			; ES = the shape
	mov	bp,[es:bx+DATAOFS]		; its post list for srcx
	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	mov	al,[onemask+bx]
	mov	dx,SC_INDEX+1
	out	dx,al					; set map mask register
	mov	dx,SCREENSEG
	mov	ds,cx					; DS = the scaler
	mov	bx,[es:bp]				; table location of the rtl to patch
	or	bx,bx
	jz	@@l1done				; 0 ends the post list
	EVEN
@@l1post:
	mov	bx,[bx]
	mov	ah,[bx]					; save old value
	mov	[BYTE bx],OP_RETF		; patch a RETF in
	mov	si,[es:bp+4]			; table location of entry spot
	mov	si,[si]
	mov	[WORD ss:linescale],si	; call here to start scaling
	mov	si,[es:bp+2]			; corrected top of shape for this post
	add	bp,6					; next post
	mov	ds,dx					; DS = the screen
	call	[DWORD ss:linescale]	; scale the post
	mov	ds,cx					; DS = the scaler
	mov	[bx],ah					; unpatch the RETF
	mov	bx,[es:bp]
	or	bx,bx
	jnz	@@l1post
@@l1done:
	mov	ax,ss
	mov	ds,ax
	mov	es,cx					; ES = the scaler again
	pop	bp
	pop	cx
	pop	di
	pop	si
	jmp	@@lloop

@@r1draw:
	push	si
	push	di
	push	cx
	push	bp
	mov	cx,es					; CX = the scaler
	mov	bx,si
	sub	bx,[leftpix]
	shl	bx,1
	mov	es,[shapeseg]			; ES = the shape
	mov	bp,[es:bx+DATAOFS]		; its post list for srcx
	mov	bx,di
	shr	di,2					; X in bytes
	add	di,[bufferofs]
	and	bx,3
	mov	al,[onemask+bx]
	mov	dx,SC_INDEX+1
	out	dx,al					; set map mask register
	mov	dx,SCREENSEG
	mov	ds,cx					; DS = the scaler
	mov	bx,[es:bp]				; table location of the rtl to patch
	or	bx,bx
	jz	@@r1done				; 0 ends the post list
	EVEN
@@r1post:
	mov	bx,[bx]
	mov	ah,[bx]					; save old value
	mov	[BYTE bx],OP_RETF		; patch a RETF in
	mov	si,[es:bp+4]			; table location of entry spot
	mov	si,[si]
	mov	[WORD ss:linescale],si	; call here to start scaling
	mov	si,[es:bp+2]			; corrected top of shape for this post
	add	bp,6					; next post
	mov	ds,dx					; DS = the screen
	call	[DWORD ss:linescale]	; scale the post
	mov	ds,cx					; DS = the scaler
	mov	[bx],ah					; unpatch the RETF
	mov	bx,[es:bp]
	or	bx,bx
	jnz	@@r1post
@@r1done:
	mov	ax,ss
	mov	ds,ax
	mov	es,cx					; ES = the scaler again
	pop	bp
	pop	cx
	pop	di
	pop	si
	mov	dx,1					; slinewidth
	jmp	@@rloop
ENDP


;============================
;
; SimpleScaleShape (int xcenter, int shapenum, unsigned height)
;
; NEC V30 build, StevenC & Claude: WL_SCALE.C's unclipped scaler, used for
; the player's weapon every frame.  The same column walk as ScaleShape
; without the wall tests; note the right half moves slinex AFTER drawing,
; and scale is height>>1 with no range check -- both as in the C:
;
;	srcx = 32; slinex = xcenter; stopx = shape->leftpix;
;	while ( --srcx >=stopx )
;		if ( (slinewidth = comptable->width[srcx]) )
;			slinex -= slinewidth, ScaleLine ();
;	slinex = xcenter; stopx = shape->rightpix;
;	srcx = shape->leftpix<31 ? 31 : shape->leftpix-1;
;	slinewidth = 0;
;	while ( ++srcx <= stopx )
;		if ( (slinewidth = comptable->width[srcx]) )
;			ScaleLine (), slinex+=slinewidth;
;
;============================

PROC	SimpleScaleShape FAR
PUBLIC	SimpleScaleShape
	push	bp
	mov	bp,sp
	push	si
	push	di

	mov	ax,[PMSpriteStart]
	add	ax,[bp+8]				; shapenum
	push	ax
	call	PM_GetPage
	add	sp,2
	mov	[shapeseg],ax
	mov	[WORD linecmds+2],ax

	mov	di,[bp+6]				; slinex = xcenter
	mov	[xcent],di
	mov	bx,[bp+10]
	shr	bx,1					; scale = height>>1
	shl	bx,1
	mov	ax,[scaledirectory+bx]
	mov	[WORD linescale+2],ax
	mov	es,[shapeseg]
	mov	cx,[es:0]				; stopx = shape->leftpix
	mov	[leftpix],cx
	mov	bx,[es:2]
	mov	[rightpix],bx
	mov	es,ax					; ES = comptable

	mov	si,32
	EVEN
@@lloop:
	dec	si
	cmp	si,cx
	jb	@@lend					; unsigned
	mov	bx,si
	shl	bx,1
	mov	dx,[es:bx+WIDTHS]
	or	dx,dx
	jz	@@lloop
	sub	di,dx					; slinex -= slinewidth
	call	ScaleSpan
	jmp	@@lloop
@@lend:

	mov	di,[xcent]
	mov	cx,[rightpix]
	mov	si,31
	mov	ax,[leftpix]
	cmp	ax,31
	jb	@@rstart
	mov	si,ax
	dec	si
@@rstart:
	xor	dx,dx					; slinewidth = 0
	EVEN
@@rloop:
	inc	si
	cmp	si,cx
	ja	@@done
	mov	bx,si
	shl	bx,1
	mov	dx,[es:bx+WIDTHS]
	or	dx,dx
	jz	@@rloop
	call	ScaleSpan
	add	di,dx					; slinex += slinewidth, after drawing
	jmp	@@rloop

@@done:
	mov	[slinex],di
	mov	[slinewidth],dx
	pop	di
	pop	si
	pop	bp
	ret
ENDP

ENDS

	END
