; WL_NETA.ASM -- multiplayer: the packet driver's receive callback.
; Written by StevenC and Claude (Anthropic), 2026.  WL_NET.C is the rest.
;
; The driver calls NetRecv twice for every frame that matches one of our
; types, with interrupts off:
;   AX=0, CX = its length: return ES:DI = where to copy it (0:0 = drop it)
;   AX=1, CX = its length: it has been copied
; The frames go into the eight slots of WL_NET.C's netshare (far data),
; whose address NetSetShare puts in the code segment.  Its layout:
;   +0 head (byte), +1 tail (byte), +2 drops (word), +4 len[8] (words),
;   +20 ring[8][1536]
; The main loop takes slot tail&7 while tail != head; this side fills slot
; head&7 and then advances head -- one writer and one reader per index.

.186						; the 80186 set the game is built for
IDEAL
MODEL	MEDIUM

NSLOTS		=	8
SLOTSZ		=	1536
NS_HEAD		=	0
NS_TAIL		=	1
NS_DROPS	=	2
NS_LEN		=	4
NS_RING		=	20

CODESEG

share_off	dw	0
share_seg	dw	0

;
; void NetSetShare (void far *share)
;
PROC	_NetSetShare FAR
PUBLIC	_NetSetShare
	push	bp
	mov		bp,sp
	mov		ax,[bp+6]
	mov		[cs:share_off],ax
	mov		ax,[bp+8]
	mov		[cs:share_seg],ax
	pop		bp
	retf
ENDP

;
; the receiver (far, register interface)
;
PROC	_NetRecv FAR
PUBLIC	_NetRecv
	push	ds
	push	bx
	push	si
	mov		bx,[cs:share_seg]
	mov		ds,bx
	mov		bx,[cs:share_off]
	or		ax,ax
	jnz		@@copied

	cmp		cx,SLOTSZ				; AX=0: room for CX bytes?
	ja		@@drop
	mov		al,[bx+NS_HEAD]
	sub		al,[bx+NS_TAIL]
	cmp		al,NSLOTS
	jae		@@drop					; all eight full
	mov		al,[bx+NS_HEAD]
	and		ax,NSLOTS-1				; AX = the slot
	mov		di,ax
	shl		di,1
	add		di,ax					; slot*3
	shl		di,9					; slot*1536
	add		di,bx
	add		di,NS_RING
	mov		ax,ds
	mov		es,ax
	jmp		SHORT @@out

@@drop:
	inc		[WORD bx+NS_DROPS]
	xor		ax,ax
	mov		es,ax
	xor		di,di
	jmp		SHORT @@out

@@copied:							; AX=1: note the length, publish the slot
	xor		ax,ax
	mov		al,[bx+NS_HEAD]
	and		al,NSLOTS-1
	shl		ax,1
	mov		si,ax
	mov		[bx+NS_LEN+si],cx
	inc		[BYTE bx+NS_HEAD]

@@out:
	pop		si
	pop		bx
	pop		ds
	retf
ENDP

END
