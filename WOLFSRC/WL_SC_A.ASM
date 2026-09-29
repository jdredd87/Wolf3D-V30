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
; It sits in WL_SCALE_TEXT, WL_SCALE.C's own code segment, because
; ScaleLine is a NEAR function there.  ScaleLine keeps SI, DI and BP and
; returns with DS = SS; it destroys AX, BX, CX, DX and ES.
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

shapeseg	dw	?					; segment of this shape's page
leftpix		dw	?
rightpix	dw	?
xcent		dw	?

WIDTHS		=	130					; offset of t_compscale.width[]
DATAOFS		=	4					; offset of t_compshape.dataofs[]


SEGMENT	WL_SCALE_TEXT BYTE PUBLIC 'CODE'
	ASSUME	cs:WL_SCALE_TEXT, ds:DGROUP

EXTRN	ScaleLine:NEAR				; WL_SCALE.C, same segment
EXTRN	PM_GetPage:FAR


;============================
;
; CallScaleLine
;
; Hand ScaleLine the current span: slinex, slinewidth and the column's
; command list, dataofs[srcx-leftpix] in the shape.
;
;============================

PROC	CallScaleLine NEAR
	mov	[slinex],di
	mov	[slinewidth],dx
	mov	bx,si
	sub	bx,[leftpix]
	shl	bx,1
	push	es
	mov	es,[shapeseg]
	mov	ax,[es:bx+DATAOFS]
	mov	[WORD linecmds],ax
	push	cx
	push	dx
	call	ScaleLine
	pop	dx
	pop	cx
	pop	es
	ret
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
@@lloop:
	dec	si
	cmp	si,cx
	jb	@@lend					; unsigned, as srcx and stopx are
	or	di,di
	jle	@@lend					; slinex > 0, signed
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
	call	CallScaleLine
	jmp	@@lloop

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
	call	CallScaleLine
	jmp	@@lloop

@@lnotleft:
	mov	ax,bx
	add	bx,dx
	add	bx,dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@lloop					; totally obscured
	mov	bx,ax
@@lgrow:						; while (left edge hidden) slinex++, slinewidth--
	inc	di
	dec	dx
	add	bx,2
	cmp	[wallheight+bx],bp
	jae	@@lgrow
	call	CallScaleLine
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

@@rloop:
	inc	si
	cmp	si,cx
	ja	@@done					; unsigned
	add	di,dx					; slinex += slinewidth
	cmp	di,[viewwidth]
	jge	@@done					; signed
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
	call	CallScaleLine
	jmp	@@rloop

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
	call	CallScaleLine
	jmp	@@done					; break: the rest of the shape is gone
@@rdraw:
	call	CallScaleLine
	jmp	@@rloop

@@rnotleft:
	mov	ax,bx
	add	bx,dx
	add	bx,dx
	sub	bx,2
	cmp	[wallheight+bx],bp
	jae	@@rloop					; totally obscured
	mov	bx,ax
@@rgrow:
	inc	di
	dec	dx
	add	bx,2
	cmp	[wallheight+bx],bp
	jae	@@rgrow
	call	CallScaleLine
	jmp	@@rloop

@@done:
	mov	[slinex],di				; leave the globals as the C left them
	mov	[slinewidth],dx
@@ret:
	pop	di
	pop	si
	pop	bp
	ret
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
	call	CallScaleLine
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
@@rloop:
	inc	si
	cmp	si,cx
	ja	@@done
	mov	bx,si
	shl	bx,1
	mov	dx,[es:bx+WIDTHS]
	or	dx,dx
	jz	@@rloop
	call	CallScaleLine
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
