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
SLOTSZ		=	1024
NS_HEAD		=	0
NS_TAIL		=	1
NS_DROPS	=	2
NS_LEN		=	4
NS_RING		=	20

DATASEG

EXTRN	_player:WORD				; the player in the globals (MPSwapIn/Out)
EXTRN	_gamestate:WORD
EXTRN	_controlx:WORD
EXTRN	_controly:WORD
EXTRN	_buttonstate:WORD
EXTRN	_buttonheld:WORD
EXTRN	_running:WORD
EXTRN	_thrustspeed:WORD
EXTRN	_plux:WORD
EXTRN	_pluy:WORD
EXTRN	_anglefrac:WORD
EXTRN	_gotgatgun:WORD
EXTRN	_LastAttacker:WORD
EXTRN	_playerxmove:WORD
EXTRN	_playerymove:WORD

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
	shl		di,10					; slot*1024
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

;
; unsigned NetSum (void far *p, unsigned len, unsigned sum): the Internet
; checksum's one's-complement sum (RFC 1071) of len bytes, added on to sum --
; both read as big-endian (network order) words, so a pseudo-header's sum
; chains into its datagram's.  The words are added little-endian with the
; carry each time, and the bytes swapped at the end, which comes to the same
; sum.  StevenC & Claude (Anthropic), 2026-10-23: the game's datagrams carry
; a UDP checksum now, and the ones it is sent are checked -- a PicoMEM 2
; garbles a frame sent straight after another, and with no checksum the
; garbage was taken as a player's packet (P3's chat line, 2026-10-22)
;
PROC	_NetSum FAR
PUBLIC	_NetSum
	push	bp
	mov		bp,sp
	push	ds
	push	si
	lds		si,[bp+6]				; p
	mov		cx,[bp+10]				; len
	mov		dx,[bp+12]				; sum
	xchg	dl,dh					; ... little-endian, as the words are added
	shr		cx,1					; words; CF = an odd byte at the end
	pushf
	clc
	jcxz	@@odd
@@word:
	lodsw
	adc		dx,ax
	loop	@@word					; (LOOP keeps the carry)
	adc		dx,0
	adc		dx,0					; (the end-around carry can carry once more)
@@odd:
	popf
	jnc		@@done
	lodsb							; the last byte: the high half of a big-
	xor		ah,ah					; endian word, the low half of ours
	add		dx,ax
	adc		dx,0
	adc		dx,0
@@done:
	xchg	dl,dh					; back to big-endian
	mov		ax,dx
	pop		si
	pop		ds
	pop		bp
	retf
ENDP

;
; The text over the view, in assembly -- NEC V30 build, StevenC & Claude
; (Anthropic), 2026-10-23.  WL_MP.C's Text1 drew a letter's column at a time
; here and did the rest in C: the clip test, the glyph's address, the
; registers saved, the map mask, the next column -- per column, nearly twice
; what the rows themselves cost (a replay's profile on the V30: text 17% of
; its time, 9.6% of it that C).  Now one call a line of text does it all.
; fontstruct: height (word), location[256] (words), width[256] (bytes); the
; font is the start of its own segment (the memory manager's blocks are).
;
FONT_LOC	=	2
FONT_WIDTH	=	514

;
; unsigned long MPTextSum (char far *s, unsigned fontseg, unsigned r): the
; string's width in pixels (the low word) and r*33 + each letter, a letter
; at a time (the high) -- Text1's measuring pass
;
PROC	_MPTextSum FAR
PUBLIC	_MPTextSum
	push	bp
	mov		bp,sp
	push	si
	push	ds
	les		si,[bp+6]				; ES:SI = the string
	mov		ds,[bp+10]				; DS = the font
	mov		dx,[bp+12]				; r
	xor		cx,cx					; the width
	xor		bh,bh
@@letter:
	mov		bl,[es:si]
	inc		si
	or		bl,bl
	jz		@@end
	mov		al,[bx+FONT_WIDTH]
	xor		ah,ah
	add		cx,ax
	mov		ax,dx					; r = r*33 + the letter
	add		dx,dx
	add		dx,dx
	add		dx,dx
	add		dx,dx
	add		dx,dx
	add		dx,ax
	add		dx,bx
	jmp		@@letter
@@end:
	mov		ax,cx
	pop		ds
	pop		si
	pop		bp
	retf
ENDP

;
; void MPTextDraw (byte far *dest, char far *s, unsigned fontseg, int x,
;	int cx0, int cx1, unsigned n, unsigned r0, unsigned step, unsigned color)
; the string, column by column from dest (the column of x on its page): each
; glyph's n rows from its row r0, step bytes apart on the page, in color
; wherever the font has a pixel; a column only when cx0 <= x < cx1.  Then
; every plane's mask back on.
;
PROC	_MPTextDraw FAR
PUBLIC	_MPTextDraw
	push	bp
	mov		bp,sp
	sub		sp,8					; [bp-2] the plane's mask, [bp-4] the glyph's
	push	si						; width, [bp-6] its columns to go, [bp-8]
	push	di						; the column's first byte in the font
	push	ds
	mov		ax,[bp+16]				; x
	mov		cl,al
	and		cl,3
	mov		al,1
	shl		al,cl
	mov		[BYTE bp-2],al
	mov		dx,03C4h				; the sequencer's map mask: its index once
	mov		al,2
	out		dx,al
	les		di,[bp+6]				; ES:DI = the column's first byte on the page
	mov		ds,[bp+14]				; DS = the font
@@letter:
	push	ds
	lds		bx,[bp+10]				; the next letter
	mov		bl,[bx]
	pop		ds
	inc		[WORD bp+10]
	xor		bh,bh
	or		bl,bl
	jz		@@end
	mov		al,[bx+FONT_WIDTH]		; its width
	xor		ah,ah
	mov		[bp-4],ax
	mov		[bp-6],ax
	add		bx,bx
	mov		si,[bx+FONT_LOC]		; its first column ...
	mov		ax,[bp+24]
	mul		[WORD bp-4]				; ... from row r0: r0 * the width on
	add		si,ax
	mov		[bp-8],si
@@column:
	cmp		[WORD bp-6],0
	je		@@letter
	dec		[WORD bp-6]
	mov		ax,[bp+16]				; in the clip?
	cmp		ax,[bp+18]
	jl		@@next
	cmp		ax,[bp+20]
	jge		@@next
	mov		dx,03C5h
	mov		al,[bp-2]
	out		dx,al					; this column's plane
	mov		si,[bp-8]
	push	di
	mov		cx,[bp+22]				; n rows
	mov		bx,[bp-4]				; a font row is the glyph's width on
	mov		dx,[bp+26]				; a page row is step on
	mov		al,[bp+28]				; the colour
	jcxz	@@drawn
@@row:
	cmp		[BYTE si],0
	je		@@skip
	mov		[es:di],al
@@skip:
	add		si,bx
	add		di,dx
	loop	@@row
@@drawn:
	pop		di
@@next:
	inc		[WORD bp+16]			; x
	inc		[WORD bp-8]				; the glyph's next column
	shl		[BYTE bp-2],1
	cmp		[BYTE bp-2],16
	jne		@@column
	mov		[BYTE bp-2],1			; plane 0 again, a byte on
	inc		di
	jmp		@@column
@@end:
	mov		dx,03C4h
	mov		ax,0F02h				; every plane
	out		dx,ax
	pop		ds
	pop		di
	pop		si
	mov		sp,bp
	pop		bp
	retf
ENDP

;
; NEC V30 build, StevenC & Claude (2026-10-07): a player's context, in and
; out -- WL_MP.C's Save and Load, which every enemy's think pays for (its
; target's context goes in first).  The fields in mpctx_t's order: ob,
; gs (gswords words), controlx, controly, buttonstate[8], buttonheld[8],
; running, thrustspeed, plux, pluy, anglefrac, gotgatgun, LastAttacker,
; playerxmove, playerymove.  WL_MP.C's Init checks mpctx_t has that layout.
;
; void MPSwapOut (void far *ctx, unsigned gswords): the globals -> ctx
;
PROC	_MPSwapOut FAR
PUBLIC	_MPSwapOut
	push	bp
	mov		bp,sp
	push	si
	push	di
	les		di,[bp+6]
	mov		dx,[bp+10]
	cld
	mov		ax,[_player]
	stosw
	mov		si,OFFSET _gamestate
	mov		cx,dx
	rep		movsw
	mov		ax,[_controlx]
	stosw
	mov		ax,[_controly]
	stosw
	mov		si,OFFSET _buttonstate
	mov		cx,8
	rep		movsw
	mov		si,OFFSET _buttonheld
	mov		cx,8
	rep		movsw
	mov		ax,[_running]
	stosw
	mov		si,OFFSET _thrustspeed
	movsw
	movsw
	mov		ax,[_plux]
	stosw
	mov		ax,[_pluy]
	stosw
	mov		ax,[_anglefrac]
	stosw
	mov		ax,[_gotgatgun]
	stosw
	mov		ax,[_LastAttacker]
	stosw
	mov		si,OFFSET _playerxmove
	movsw
	movsw
	mov		si,OFFSET _playerymove
	movsw
	movsw
	pop		di
	pop		si
	pop		bp
	retf
ENDP

;
; void MPSwapIn (void far *ctx, unsigned gswords): ctx -> the globals
;
PROC	_MPSwapIn FAR
PUBLIC	_MPSwapIn
	push	bp
	mov		bp,sp
	push	si
	push	di
	push	ds
	mov		dx,[bp+10]
	mov		ax,ds
	mov		es,ax					; ES: DGROUP, the globals
	lds		si,[bp+6]				; DS:SI: the context
	cld
	lodsw
	mov		[es:_player],ax
	mov		di,OFFSET _gamestate
	mov		cx,dx
	rep		movsw
	lodsw
	mov		[es:_controlx],ax
	lodsw
	mov		[es:_controly],ax
	mov		di,OFFSET _buttonstate
	mov		cx,8
	rep		movsw
	mov		di,OFFSET _buttonheld
	mov		cx,8
	rep		movsw
	lodsw
	mov		[es:_running],ax
	mov		di,OFFSET _thrustspeed
	movsw
	movsw
	lodsw
	mov		[es:_plux],ax
	lodsw
	mov		[es:_pluy],ax
	lodsw
	mov		[es:_anglefrac],ax
	lodsw
	mov		[es:_gotgatgun],ax
	lodsw
	mov		[es:_LastAttacker],ax
	mov		di,OFFSET _playerxmove
	movsw
	movsw
	mov		di,OFFSET _playerymove
	movsw
	movsw
	pop		ds
	pop		di
	pop		si
	pop		bp
	retf
ENDP

IFDEF HANGDUMP
;
; TEST builds only (mp/huntbot.py defines HANGDUMP): the hang watchdog's
; INT 8 entry, in front of id's timer service and of DOS's.  DOS (STACKS=)
; moves the BIOS tick onto a stack of its own, so by INT 1Ch, where the
; watchdog runs, the game's stack is out of sight.  Here, first, its SS:SP
; is noted -- the IP, CS and FLAGS of whatever the tick stopped are at
; SP+4 -- and the tick goes on to id's service exactly as before.
; StevenC & Claude (Anthropic), 2026-10-09.
;
DATASEG

PUBLIC	_hang8ss, _hang8sp
_hang8ss	dw	0
_hang8sp	dw	0

CODESEG

hang8next	dd	0

PROC	_Hang8 FAR
PUBLIC	_Hang8
	push	ds
	push	ax
	mov		ax,@data
	mov		ds,ax
	mov		[_hang8ss],ss
	mov		[_hang8sp],sp
	pop		ax
	pop		ds
	jmp		[DWORD PTR cs:hang8next]
ENDP

;
; void HangNext8 (void interrupt (*isr)(void)) -- where Hang8 goes on to.
; Both words at once: a tick between them would jump to half of each
;
PROC	_HangNext8 FAR
PUBLIC	_HangNext8
	push	bp
	mov		bp,sp
	pushf
	cli
	mov		ax,[bp+6]
	mov		[WORD PTR cs:hang8next],ax
	mov		ax,[bp+8]
	mov		[WORD PTR cs:hang8next+2],ax
	popf
	pop		bp
	retf
ENDP
ENDIF

END
