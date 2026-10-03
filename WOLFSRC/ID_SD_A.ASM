;
;	ID_SD_A.ASM
;	Id Sound Manager assembly stuff

	.186				; NEC V30 build: the V30 runs the 80186 set
	IDEAL
	MODEL	MEDIUM,C
	JUMPS

	INCLUDE 'ID_SD.EQU'

DEBUG	=	0

	EXTRN	SDL_DigitizedDone:FAR

;============================================================================

DATASEG

mlogon		dw	0					; MUSICLOG (TIMEDEMO): hash the sequencer's writes
mlogn		dw	0
mlogsum		dw	0
mlogstart	dw	0
	PUBLIC	mlogon
	PUBLIC	mlogn
	PUBLIC	mlogsum
	PUBLIC	mlogstart

sqQuiet		dw	0					; ticks certainly without a music event:
	PUBLIC	sqQuiet					;  see SDL_t0FastAsmService
alDelayAddr	dw	6					; alOut's waits, in status-port reads:
alDelayData	dw	35					; id's counts until SDL_TimeOPL runs
	PUBLIC	alDelayAddr
	PUBLIC	alDelayData

	EXTRN	sqActive:WORD
	EXTRN	ssSample:DWORD
	EXTRN	ssLengthLeft:WORD
	EXTRN	ssControl:WORD
	EXTRN	ssStatus:WORD
	EXTRN	ssData:WORD
	EXTRN	ssOn:BYTE
	EXTRN	ssOff:BYTE

	EXTRN	pcSound:DWORD
	EXTRN	pcLengthLeft:WORD
	EXTRN	pcLastSample:BYTE
	EXTRN	pcSoundLookup:WORD

	EXTRN	alSound:DWORD
	EXTRN	alBlock:WORD
	EXTRN	alLengthLeft:WORD
	EXTRN	alTimeCount:DWORD

	EXTRN	sqHack:DWORD
	EXTRN	sqHackPtr:DWORD
	EXTRN	sqHackLen:WORD
	EXTRN	sqHackSeqLen:WORD
	EXTRN	sqHackTime:DWORD

	EXTRN	HackCount:WORD
	EXTRN	TimeCount:WORD
	EXTRN	LocalTime:WORD

	EXTRN	TimerCount:WORD
	EXTRN	TimerDivisor:WORD
	EXTRN	t0OldService:DWORD

	EXTRN	SoundMode:WORD
	EXTRN	DigiMode:WORD

	EXTRN	SoundNumber:WORD
	EXTRN	SoundPriority:WORD

count_time	dw	?
fxdown		dw	5					; NEC V30 build: ticks to the next effects tick,
								; counting down (id's count_fx counted up to 5)

pcdtab	db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b,00b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b
		db	10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b,10b


;============================================================================

CODESEG

MyDS	dw	?

pcindicate	dw	?
extreme		dw	?

	PROC	SDL_SetDS
	PUBLIC	SDL_SetDS

	mov	ax,ds
	mov	[cs:MyDS],ds
	ret

	ENDP

;
;	COMMONSTART
;	Macro used for common prefix code
;
	MACRO	COMMONSTART
	IF DEBUG
	push dx
	push ax
	mov	dx,STATUS_REGISTER_1
	in	al,dx
	mov	dx,ATR_INDEX
	mov	al,ATR_OVERSCAN
	out	dx,al
	mov	al,4	; red
	out	dx,al
	ENDIF

	push ds
	push ax

	mov	ds,[cs:MyDS]
	inc	[HackCount]
	ENDM

;
;	DOFX
;	Macro used to do the sound effects code
;
	MACRO	DOFX
	les	di,[pcSound]				; PC sound effects
	mov	ax,es
	or	ax,di
	jz	@@nopc						; nil pointer - no PC sound effect going

	mov	bl,[es:di]					; Get the byte
	inc	[WORD PTR pcSound]			; Increment pointer
	cmp	[pcLastSample],bl			; Is this sample the same as last?
	jz	@@pcsame					; Yep - don't do anything
	mov	[pcLastSample],bl			; No, save it for next time

	or	bl,bl
	jz	@@pcoff						; If 0, turn sounds off
	xor	bh,bh
	shl	bx,1
	mov	bx,[pcSoundLookup+bx]		; Use byte as index into frequency table

	mov	al,0b6h						; Write to channel 2 (speaker) timer
	out	pcTAccess,al
	mov	al,bl
	out	pcTimer,al					; Low byte
	mov	al,bh
	out	pcTimer,al					; High byte

	in	al,pcSpeaker				; Turn the speaker & gate on
	or	al,3
	out	pcSpeaker,al

	jmp @@pcsame

@@pcoff:
	in	al,pcSpeaker  				; Turn the speaker & gate off
	and	al,0fch						; ~3
	out	pcSpeaker,al

@@pcsame:
	dec	[pcLengthLeft]				; Decrement length
	jnz	@@nopc						; If not 0, we're not done with the sound

	mov	ax,0
	mov	[WORD PTR pcSound],ax		; Zero the pointer
	mov	[WORD PTR pcSound + 2],ax
	mov	[SoundNumber],ax    		; Indicate no sound
	mov	[SoundPriority],ax			;  with no priority

	in	al,pcSpeaker  				; Turn the speaker off
	and	al,0fdh						; ~2
	out	pcSpeaker,al
@@nopc:

	les	di,[alSound]				; AdLib sound effects
	mov	ax,es
	or	ax,di
	jz	@@noal						; nil pointer - no AdLib effect going

	xor	ah,ah
	mov	al,[es:di]
	or	al,al
	jz	@@aldone

	CALL alOut C,alFreqL,ax
	mov	ax,[alBlock]

@@aldone:
	CALL alOut C,alFreqH,ax
	inc	[WORD PTR alSound]
	dec	[alLengthLeft]
	jnz	@@noal

	mov	ax,0
	mov	[WORD PTR alSound],ax		; Zero the pointer
	mov	[WORD PTR alSound + 2],ax
	mov	[SoundNumber],ax    		; Indicate no sound
	mov	[SoundPriority],ax			;  with no priority
	CALL alOut C,alFreqH,ax			; Turn off the sound
@@noal:

	ENDM

;
;
;
	MACRO	TIME
	cmp	[count_time],2
	jb	@@notime
	add	[LocalTime],1
	adc	[LocalTime+2],0
	add	[TimeCount],1
	adc	[TimeCount+2],0
	mov	[count_time],0
@@notime:
	ENDM

;
;	COMMONEND
;	Macro used for common suffix code
;
	MACRO	COMMONEND
@@fullexit:
	pop	es
	popa

@@nosave:
	mov	ax,[TimerDivisor]
	add	[TimerCount],ax
	jc	@@chain					; NEC V30 build: the usual case falls through

	mov	al,20h
	out	20h,al

@@out:
	pop	ax
	pop	ds

	IF DEBUG
	mov	dx,STATUS_REGISTER_1
	in	al,dx
	mov	dx,ATR_INDEX
	mov	al,ATR_OVERSCAN
	out	dx,al
	mov	al,3	; blue
	out	dx,al
	mov	al,20h	; normal
	out	dx,al
	pop	ax
	pop	dx
	ENDIF

	iret

@@chain:
	pushf
	call [t0OldService]
	jmp	@@out
	ENDM

;
;	SDL_IndicatePC
;
	PROC	SDL_IndicatePC on:WORD
	PUBLIC	SDL_IndicatePC

	mov	ax,[on]
	mov	[cs:pcindicate],ax
	ret

	ENDP

;
;	SDL_t0ExtremeAsmService
;	Timer 0 ISR 7000Hz interrupts
;
	PROC	SDL_t0ExtremeAsmService
	PUBLIC	SDL_t0ExtremeAsmService

	push ax
	mov	al,[BYTE PTR cs:pcindicate]
	or	al,al
	jz	@@done

	push ds
	push es
	pusha

	mov	ds,[cs:MyDS]

	les	di,[pcSound]
	mov	ax,es
	or	ax,di
	jz	@@donereg					; nil pointer

	mov	bl,[es:di]					; Get the byte
	inc	[WORD PTR pcSound]			; Increment pointer

	and	bl,11100000b				; Nuke some of the precision (DEBUG - do this in the table)

	xor	bh,bh
	mov	ah,[pcdtab+bx]				; Translate the byte

	in	al,pcSpeaker
	and	al,11111100b
	or	al,ah
	out	pcSpeaker,al

	dec	[pcLengthLeft]
	jnz	@@donereg

	mov	[WORD PTR pcSound],0		; We're done with this sample
	mov	[WORD PTR pcSound+2],0

	in	al,pcSpeaker
	and	al,11111100b
	out	pcSpeaker,al

	call SDL_DigitizedDone

@@donereg:
	popa
	pop	es
	pop	ds

@@done:
	inc	[cs:extreme]
	cmp	[cs:extreme],10
	jae	@@tofast

	mov	al,20h
	out	20h,al
	pop	ax
	iret

@@tofast:
	mov	[cs:extreme],0
	pop	ax

;	jmp	SDL_t0FastAsmService			; Drops through to SDL_t0FastAsmService

	ENDP

;
;	SDL_t0FastAsmService
;	Timer 0 ISR for 700Hz interrupts
;
	PROC	SDL_t0FastAsmService
	PUBLIC	SDL_t0FastAsmService

	COMMONSTART

	dec	[fxdown]						; Time to do PC/AdLib effects & time?
	jz	@@dofull

;
; NEC V30 build, StevenC & Claude: sqQuiet is how many coming ticks are
; certain to have no music event -- set by the full service below, and
; cleared by every C routine that changes the sequencer or starts a sample.
; On such a tick there is nothing to do but what the full service would do
; there: alTimeCount++.
;
	mov	ax,[sqQuiet]
	or	ax,ax
	jz	@@notquiet
	dec	ax
	mov	[sqQuiet],ax
	inc	[WORD PTR alTimeCount]		; alTimeCount++: its high word carries once
	jz	@@qcarry					; in 65536 ticks
@@qexit:
;
; NEC V30 build: a quiet tick leaves from here, not through a jump to the
; shared exit: the BIOS chain test and the end of interrupt, inline.
;
	mov	ax,[TimerDivisor]
	add	[TimerCount],ax
	jc	@@qchain
	mov	al,20h
	out	20h,al
	pop	ax
	pop	ds
	iret
@@qchain:
	pushf
	call [t0OldService]
	pop	ax
	pop	ds
	iret
@@qcarry:
	inc	[WORD PTR alTimeCount+2]
	jmp	@@qexit
@@notquiet:

	mov	ax,[WORD PTR ssSample]			; Is there a sample for the Sound Src?
	or	ax,[WORD PTR ssSample+2]
	jnz	@@dofull

	mov	ax,[sqActive]					; Is the sequencer active?
	or	ax,ax
	jz	@@nosave

;
; NEC V30 build, StevenC & Claude: with music playing, id took the full
; service -- PUSHA, ES, the sequencer walk, POPA -- on every one of 700
; ticks a second, though on nearly all of them no music event is due and
; all it changes is alTimeCount.  That was ~100 us a tick on the V30, 5.8%
; of a frame.  So test the same condition the sequencer loop tests, with
; id's own comparison (high word, then low word), and when nothing is due
; do just what the full service would have done: alTimeCount++.  Effects
; ticks, samples, events due and the end of the song all still go the full
; way, and the music keeps its 700 Hz timing.
;
	mov	ax,[sqHackLen]
	or	ax,ax
	jz	@@dofull						; end of the song: restart it there
	mov	ax,[WORD PTR sqHackTime+2]
	cmp	ax,[WORD PTR alTimeCount+2]
	ja	@@notdue
	mov	ax,[WORD PTR sqHackTime]
	cmp	ax,[WORD PTR alTimeCount]
	jbe	@@dofull						; an event is due
@@notdue:
	inc	[WORD PTR alTimeCount]
	jnz	@@qexit
	jmp	@@qcarry

@@dofull:
	pusha
	push es

	cmp	[fxdown],0
	jne	@@nofx
	mov	[fxdown],5
	DOFX

	inc	[count_time]
	TIME
@@nofx:

	mov	ax,[sqActive]
	or	ax,ax
	jz	@@nosq

	mov	ax,[sqHackLen]
	or	ax,ax
	jz	@@sqdone

	les	di,[sqHackPtr]
@@sqloop:
	mov	ax,[WORD PTR sqHackTime+2]
	cmp	ax,[WORD PTR alTimeCount+2]
	ja	@@sqdone
	mov	ax,[WORD PTR sqHackTime]
	cmp	ax,[WORD PTR alTimeCount]
	ja	@@sqdone

	mov	ax,[es:di+2]					; Get time to next event
	add	ax,[WORD PTR alTimeCount]
	mov	[WORD PTR sqHackTime],ax
	mov	ax,[WORD PTR alTimeCount+2]
	adc	ax,0
	mov	[WORD PTR sqHackTime+2],ax

	mov	ax,[es:di]						; Get register/value pair
	cmp	[mlogon],0					; MUSICLOG: hash register, value and tick
	je	@@nolog
	cmp	[mlogn],1000
	jae	@@nolog
	inc	[mlogn]
	mov	cx,[mlogsum]
	mov	dx,cx
	shl	cx,1
	shl	cx,1
	shl	cx,1
	shl	cx,1
	shl	cx,1
	add	cx,dx						; hash*33
	add	cx,ax						; + register and value
	mov	dx,[HackCount]
	sub	dx,[mlogstart]
	add	cx,dx						; + tick since the song started
	mov	[mlogsum],cx
@@nolog:
	xor	bh,bh
	mov	bl,ah
	xor	ah,ah
	CALL alOut C,ax,bx

	add	di,4
	mov	[WORD PTR sqHackPtr],di

	sub	[sqHackLen],4
	jnz	@@sqloop

@@sqdone:
	add	[WORD PTR alTimeCount],1
	adc	[WORD PTR alTimeCount+2],0
	mov	ax,[sqHackLen]
	or	ax,ax
	jnz	@@nosq

	mov	ax,[WORD PTR sqHack]		; Copy pointer
	mov	[WORD PTR sqHackPtr],ax
	mov	ax,[WORD PTR sqHack+2]
	mov	[WORD PTR sqHackPtr+2],ax

	mov	ax,[sqHackSeqLen]			; Copy length
	mov	[sqHackLen],ax

	mov	ax,0
	mov	[WORD PTR alTimeCount],ax	; Reset time counts
	mov	[WORD PTR alTimeCount+2],ax
	mov	[WORD PTR sqHackTime],ax
	mov	[WORD PTR sqHackTime+2],ax
@@nosq:
;
; How many coming ticks are certain to be quiet?  Only counted when the high
; words of sqHackTime and alTimeCount agree and no sample is playing: then
; id's test -- high word, then low word -- first finds the event due when
; alTimeCount's low word reaches sqHackTime's, sqHackTime-alTimeCount ticks
; from now, and the low word cannot wrap before that.  Anything else is 0,
; which leaves every tick to the full test.
;
	mov	[sqQuiet],0
	mov	ax,[sqActive]
	or	ax,ax
	jz	@@qdone
	mov	ax,[sqHackLen]
	or	ax,ax
	jz	@@qdone
	mov	ax,[WORD PTR ssSample]
	or	ax,[WORD PTR ssSample+2]
	jnz	@@qdone
	mov	ax,[WORD PTR sqHackTime+2]
	cmp	ax,[WORD PTR alTimeCount+2]
	jne	@@qdone
	mov	ax,[WORD PTR sqHackTime]
	sub	ax,[WORD PTR alTimeCount]
	jbe	@@qdone
	mov	[sqQuiet],ax
@@qdone:

	les	di,[ssSample]			; Get pointer to Sound Source sample
	mov	ax,es
	or	ax,di
	jz	@@ssdone				; If nil, skip this

@@ssloop:
	mov	dx,[ssStatus]			; Check to see if FIFO has any empty slots
	in	al,dx
	test al,40h
	jnz	@@ssdone				; Nope - don't push any more data out

	mov	dx,[ssData]
	mov	al,[es:di]				; al = *ssSample
	out	dx,al					; Pump the value out

	mov	dx,[ssControl]			; Pulse printer select
	mov	al,[ssOff]
	out	dx,al
	push ax
	pop	ax
	mov	al,[ssOn]
	out	dx,al

	push ax						; Delay a short while
	pop	ax

	inc	di
	mov	[WORD PTR ssSample],di	; ssSample++

	dec	[ssLengthLeft]
	jnz @@ssloop

	mov	[WORD PTR ssSample],0	; We're done with this sample
	mov	[WORD PTR ssSample+2],0

	call SDL_DigitizedDone
@@ssdone:

	COMMONEND

	ENDP

;
;	SDL_t0SlowAsmService
;	Timer 0 ISR for 140Hz interrupts
;
	PROC	SDL_t0SlowAsmService
	PUBLIC	SDL_t0SlowAsmService

	IF DEBUG
	push dx
	push ax
	mov	dx,STATUS_REGISTER_1
	in	al,dx
	mov	dx,ATR_INDEX
	mov	al,ATR_OVERSCAN
	out	dx,al
	mov	al,4	; red
	out	dx,al
	ENDIF

	push ds
	push ax

	mov	ds,[cs:MyDS]

	inc	[count_time]
	TIME

	mov	ax,[WORD PTR pcSound]		; Is there a PC sound effect going?
	or	ax,[WORD PTR pcSound+2]
	jnz	@@dofull

	mov	ax,[WORD PTR alSound]		; Is there an AdLib sound effect going?
	or	ax,[WORD PTR alSound+2]
	jz	@@nosave

@@dofull:
	pusha
	push es

	DOFX

	COMMONEND

	ENDP

	
;============================
;
; alOut (byte n, byte b) -- put b in AdLib register n
;
; NEC V30 build, StevenC & Claude: was C in ID_SD.C.  An OPL2 needs 3.3 us
; after its address is written and 23 us after its data, and id waited by
; reading the status port 6 and 35 times -- counts for a 1990 AT.  On this
; V30 an IN takes ~4 us whatever the port, so every register write waited
; ~170 us, and music cost 6% of the frame.  The two counts are now
; alDelayAddr and alDelayData, which SD_Startup calibrates against the BIOS
; clock (SDL_TimeOPL) to the chip's figures plus half again -- right on a
; slow machine and on a fast one.  Until then they are id's 6 and 35.
; The interrupt handling is id's: off from the address write to the data
; write, back on for the long wait.
;
;============================

PROC	alOut
PUBLIC	alOut
ARG		n:WORD, b:WORD
	mov	bl,[BYTE n]				; the register shadow: a write of the value
	cmp	bl,20h					; a register already holds changes nothing on
	jb	@@write					; an OPL2 (a note starts on key-on going 0 to
	xor	bh,bh					; 1, not on a rewrite), so it is skipped --
	shl	bx,1					; with its 13 port accesses.  Below 20h (test,
	mov	al,[BYTE b]				; timers, IRQ reset) every write counts and
	xor	ah,ah					; is made.  0FFFFh: never written
	add	[WORD cs:alWrites],1
	adc	[WORD cs:alWrites+2],0
	cmp	[cs:alShadow+bx],ax
	je	@@same
	mov	[cs:alShadow+bx],ax
@@write:
	pushf
	cli
	mov	dx,388h
	mov	al,[BYTE n]
	out	dx,al
	mov	cx,[alDelayAddr]
	jcxz	@@naddr					; FASTOPL: no wait at all
@@waddr:
	in	al,dx
	loop	@@waddr
@@naddr:
	inc	dx
	mov	al,[BYTE b]
	out	dx,al
	popf
	dec	dx
	mov	cx,[alDelayData]
	jcxz	@@ndata
@@wdata:
	in	al,dx
	loop	@@wdata
@@ndata:
	ret
@@same:
	add	[WORD cs:alSkipped],1
	adc	[WORD cs:alSkipped+2],0
	ret
ENDP

;
; long ALStat (int which) -- TIMEDEMO's count of register writes at 20h and
; up: 0 all of them, 1 those the shadow skipped
;
PROC	ALStat
PUBLIC	ALStat
ARG		which:WORD
	mov	ax,[WORD cs:alWrites]
	mov	dx,[WORD cs:alWrites+2]
	cmp	[which],0
	je	@@r
	mov	ax,[WORD cs:alSkipped]
	mov	dx,[WORD cs:alSkipped+2]
@@r:
	ret
ENDP

alWrites	dd	0
alSkipped	dd	0
alShadow	dw	256 DUP (0FFFFh)	; each register's last value, in the code
								; segment: DGROUP has no room

END
