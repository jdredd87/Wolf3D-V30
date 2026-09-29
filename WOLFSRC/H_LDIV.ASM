;[]-----------------------------------------------------------------[]
;|      H_LDIV.ASM -- long division routine                          |
;|                                                                   |
;|      C/C++ Run Time Library        Version 4.0                    |
;|                                                                   |
;|      Copyright (c) 1987, 1991 by Borland International Inc.       |
;|      All Rights Reserved.                                         |
;[]-----------------------------------------------------------------[]
.model medium
	INCLUDE RULES.ASI
.186    ;NEC V30 build: 386 only inside the patched block below

_TEXT   segment public byte 'CODE'
	assume  cs:_TEXT
	public  LDIV@
	public  F_LDIV@
	public  N_LDIV@
	public  LUDIV@
	public  F_LUDIV@
		public  N_LUDIV@
	public  LMOD@
	public  F_LMOD@
		public  N_LMOD@
	public  LUMOD@
	public  F_LUMOD@
		public  N_LUMOD@

N_LDIV@:
		pop     cx                      ;fix up far return
		push    cs
		push    cx
LDIV@:
F_LDIV@:
	xor     cx,cx                   ; signed divide
	jmp     short common

;       JAB
;
;       If we're using a 386 or better, the two instructions above get patched
;               to be NOP's (4 of them). So, instead of using the looping code,
;               we use the 386's long divide instruction.
;
;       The stack after setting up the stack frame:
;               12[bp]: divisor (high word)
;               10[bp]: divisor (low word)
;                8[bp]: dividend (high word)
;                6[bp]: dividend (low word)
;                4[bp]: return CS
;                2[bp]: return IP
;                0[bp]: previous BP
;
	IDEAL
	P386

	push bp
	mov     bp,sp   ;Save BP, and set it equal to stack

	mov     eax,[DWORD PTR bp+6]
	cdq
	idiv [DWORD PTR bp+10]
	mov     edx,eax
	shr     edx,16

	pop     bp              ;Restore BP
	retf    8       ;Return to original caller

	P186
	MASM

N_LUDIV@:
		pop     cx                      ;fix up far return
		push    cs
		push    cx
LUDIV@:
F_LUDIV@:
	mov     cx,1                    ; unsigned divide
	jmp     short common

N_LMOD@:
		pop     cx                      ;fix up far return
		push    cs
		push    cx
LMOD@:
F_LMOD@:
	mov     cx,2                    ; signed remainder
	jmp     short   common

N_LUMOD@:
		pop     cx                      ;fix up far return
		push    cs
		push    cx
LUMOD@:
F_LUMOD@:
	mov     cx,3                    ; unsigned remainder

;
;       di now contains a two bit control value.  The low order
;       bit (test mask of 1) is on if the operation is unsigned,
;       signed otherwise.  The next bit (test mask of 2) is on if
;       the operation returns the remainder, quotient otherwise.
;
common:
	push    bp
	push    si
	push    di
	mov     bp,sp                   ; set up frame
	mov     di,cx
;
;       dividend is pushed last, therefore the first in the args
;       divisor next.
;
	mov     ax,10[bp]               ; get the first low word
	mov     dx,12[bp]               ; get the first high word
	mov     bx,14[bp]               ; get the second low word
	mov     cx,16[bp]               ; get the second high word

	or      cx,cx
	jnz     slow@ldiv               ; both high words are zero

	or      dx,dx
	jz      go@quick

	or      bx,bx
	jnz     slow@ldiv               ; else cx:bx == 0: force a zero divide
go@quick:                               ; (a near JMP: the V30 fast path below
	jmp     quick@ldiv              ; put quick@ldiv out of short range)
					; we don't expect this to actually
					; work

slow@ldiv:

	test    di,1                    ; signed divide?
	jnz     positive                ; no: skip
;
;               Signed division should be done.  Convert negative
;               values to positive and do an unsigned division.
;               Store the sign value in the next higher bit of
;               di (test mask of 4).  Thus when we are done, testing
;               that bit will determine the sign of the result.
;
	or      dx,dx                   ; test sign of dividend
	jns     onepos
	neg     dx
	neg     ax
	sbb     dx,0                    ; negate dividend
	or      di,0Ch
onepos:
	or      cx,cx                   ; test sign of divisor
	jns     positive
	neg     cx
	neg     bx
	sbb     cx,0                    ; negate divisor
	xor     di,4
positive:
;
;	NEC V30 build, StevenC & Claude: the V30's DIV instruction is fast, so
;	the 32-step shift-and-subtract loop Borland used here is replaced by
;	hardware division.  Every result is the loop's: DX:AX and CX:BX are
;	already non-negative here, the control bits in DI say what the caller
;	wants, and the code below leaves the quotient in DX:AX and the
;	remainder in DI:SI, exactly where the loop left them, for Borland's
;	own tail to pick the one wanted and fix its sign.  (A zero divisor
;	never gets here: the entry code sends it to quick@ldiv's DIV.)
;
;	divisor < 65536    two DIVs, high word then low word
;	divisor >= 65536   Hacker's Delight 9-5, doubleword division: normalise
;	                   the divisor to 16 bits, one DIV of the dividend/2 for
;	                   an estimate that is exact or one high, one multiply
;	                   back to correct it.  ldivmodel.py checks this, step
;	                   for step, against exact division.
;
	push    di                      ; save the flags, as the loop did
	or      cx,cx
	jnz     big@ldiv

	mov     si,ax                   ; divisor fits a word
	mov     ax,dx
	xor     dx,dx
	div     bx                      ; AX = high word of quotient, DX = carry
	mov     di,ax
	mov     ax,si
	div     bx                      ; AX = low word, DX = remainder
	mov     si,dx
	mov     dx,di                   ; quotient DX:AX
	xor     di,di                   ; remainder DI:SI
	jmp     short tail@ldiv

big@ldiv:
	push    dx                      ; u high
	push    ax                      ; u low
	push    cx                      ; v high
	push    bx                      ; v low
	xor     si,si                   ; n = leading zeros of v's high word
norm@ldiv:
	or      cx,cx
	js      normed@ldiv
	shl     bx,1
	rcl     cx,1                    ; CX = v1 = (v << n) >> 16
	inc     si
	jmp     short norm@ldiv
normed@ldiv:
	shr     dx,1
	rcr     ax,1                    ; u1 = u >> 1: high word < 8000h <= v1
	div     cx                      ; AX = q1
	mov     cx,15
	sub     cx,si
	shr     ax,cl                   ; q0 = q1 >> (15-n)
	or      ax,ax
	jz      q0@ldiv
	dec     ax                      ; q0 = q0-1 unless zero
q0@ldiv:
	mov     si,ax                   ; SI = q0
	pop     bx                      ; v low
	pop     cx                      ; v high
	mul     cx                      ; q0 * v high (fits a word: q0*v <= u)
	mov     di,ax
	mov     ax,si
	mul     bx                      ; q0 * v low
	add     dx,di                   ; DX:AX = q0 * v
	pop     di                      ; u low
	sub     di,ax
	mov     ax,di
	pop     di                      ; u high
	sbb     di,dx                   ; DI:AX = r = u - q0*v
	cmp     di,cx
	jb      done@ldiv
	ja      fix@ldiv
	cmp     ax,bx
	jb      done@ldiv
fix@ldiv:
	sub     ax,bx                   ; r >= v: the estimate was one low
	sbb     di,cx
	inc     si
done@ldiv:
	xchg    ax,si                   ; AX = quotient, SI = remainder low
	xor     dx,dx                   ; quotient < 65536 here
tail@ldiv:
;
;       When the division is done the four registers look like:
;
;       |     di     |     si     |     dx     |     ax     |
;       |        remainder        |         quotient        |
;
	pop     bx                      ; get control bits
	test    bx,2                    ; remainder?
	jz      usequo
	mov     ax,si
	mov     dx,di                   ; use remainder
	shr     bx,1                    ; shift in the remainder sign bit
usequo:
	test    bx,4                    ; needs negative
	jz      finish
	neg     dx
	neg     ax
	sbb     dx,0                    ; negate
finish:
	pop     di
	pop     si
	pop     bp
	retf    8

quick@ldiv:
	div     bx                      ; unsigned divide
					; DX = remainder AX = quotient
	test    di,2                    ; want remainder?
	jz      quick@quo
		xchg    ax,dx

quick@quo:

	xor     dx,dx
		jmp     short finish

_TEXT   ends
	end
