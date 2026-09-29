; ID_VL.ASM

	IDEAL
	MODEL	MEDIUM,C

	INCLUDE	'ID_VL.EQU'

SCREENSEG	=	0a000h

UPDATEWIDE	=	20
UPDATEHIGH	=	13

	DATASEG


EXTRN	bufferofs			:WORD
EXTRN	displayofs			:WORD
EXTRN	ylookup				:WORD
EXTRN	linewidth			:WORD
EXTRN	blockstarts			:WORD	;offsets from drawofs for each update block

EXTRN	update				:BYTE

; FizzleFade's state, set up by ID_VH.C for FizzleStep below
EXTRN	fzcount				:WORD	; pixels to try this frame
EXTRN	fzsource			:WORD
EXTRN	fzdelta				:WORD	; dest-source
EXTRN	fzwidth				:WORD
EXTRN	fzheight			:WORD
EXTRN	fzdone				:WORD	; set when the sequence is complete
EXTRN	fzrnd				:DWORD	; the 17-bit random sequence

fzmasks		db	1,2,4,8

	CODESEG


;=================
;
; VH_UpdateScreen
;
;=================

PROC	VH_UpdateScreen
PUBLIC	VH_UpdateScreen
USES	si,di

	mov	dx,SC_INDEX
	mov	ax,SC_MAPMASK+15*256
	out	dx,ax

	mov dx,GC_INDEX
	mov al,GC_MODE
	out dx,al

	inc dx
	in	al,dx
	and al,252
	or	al,1
	out dx,al

	mov	bx,UPDATEWIDE*UPDATEHIGH-1		; bx is the tile number
	mov	dx,[linewidth]

;
; see if the tile needs to be copied
;
@@checktile:
	test	[update+bx],1
	jnz	@@copytile
@@next:
	dec	bx
	jns	@@checktile

;
; done
;
	mov dx,GC_INDEX+1
	in	al,dx
	and al,NOT 3
	or	al,0
	out dx,al
	ret

;
; copy a tile
;
@@copytile:
	mov	[update+bx],0
	shl	bx,1
	mov	si,[blockstarts+bx]
	shr	bx,1
	mov	di,si
	add	si,[bufferofs]
	add	di,[displayofs]

	mov	ax,SCREENSEG
	mov	ds,ax

REPT	16
	mov	al,[si]
	mov	[di],al
	mov	al,[si+1]
	mov	[di+1],al
	mov	al,[si+2]
	mov	[di+2],al
	mov	al,[si+3]
	mov	[di+3],al
	add	si,dx
	add	di,dx
ENDM

	mov	ax,ss
	mov	ds,ax
	jmp	@@next

ENDP


	;=================
;
; FizzleStep
;
; NEC V30 build, StevenC & Claude: the inner loop of ID_VH.C's FizzleFade,
; which took over six seconds per level start on the V30 in C.  The same
; 17-bit sequence, the same pixel copies in the same order, and the same
; end test -- which id makes only after a pixel that was on screen.  For
; each of fzcount steps:
;
;	y = (low byte of rnd) - 1		x = the next 9 bits
;	advance rnd: shift right, xor 12000h if a 1 fell out
;	if (x <= width && y <= height)
;		copy the pixel at source+ylookup[y]+x/4 in plane x&3 to +delta
;		if (rnd == 1) done
;
; rnd is AX (low word) and SI (its one high bit).
;
;=================

PROC	FizzleStep
PUBLIC	FizzleStep
	push	si
	push	di
	push	bp

	mov	ax,SCREENSEG		; screenseg is always A000h in VGA mode
	mov	es,ax
	mov	cx,[fzcount]
	mov	ax,[WORD fzrnd]
	mov	si,[WORD fzrnd+2]
	or	cx,cx
	jz	@@out

@@pix:
	mov	bl,al
	dec	bl
	xor	bh,bh				; BX = y
	mov	dx,si
	mov	dh,dl
	mov	dl,ah				; DX = x (9 bits)
	mov	bp,dx

	shr	si,1				; advance the sequence
	rcr	ax,1
	jnc	@@noxor
	xor	si,1
	xor	ax,2000h
@@noxor:
	cmp	bp,[fzwidth]
	ja	@@next				; off to the right
	cmp	bx,[fzheight]
	ja	@@next				; off the bottom

	shl	bx,1
	mov	di,[ylookup+bx]
	add	di,[fzsource]
	mov	bx,bp
	shr	bx,1
	shr	bx,1
	add	di,bx				; drawofs = source+ylookup[y]+(x>>2)

	and	bp,3				; plane
	push	ax
	mov	dx,GC_INDEX
	mov	ax,bp
	mov	ah,al
	mov	al,GC_READMAP
	out	dx,ax				; read from that plane
	mov	dx,SC_INDEX
	mov	ah,[fzmasks+bp]
	mov	al,SC_MAPMASK
	out	dx,ax				; write to it only
	mov	al,[es:di]
	add	di,[fzdelta]
	mov	[es:di],al			; copy the pixel
	pop	ax

	cmp	ax,1				; whole sequence done?
	jne	@@next
	or	si,si
	jne	@@next
	mov	[fzdone],1
	jmp	@@out

@@next:
	dec	cx
	jz	@@out
	jmp	@@pix

@@out:
	mov	[WORD fzrnd],ax
	mov	[WORD fzrnd+2],si
	pop	bp
	pop	di
	pop	si
	ret
ENDP

END
