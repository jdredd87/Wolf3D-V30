; ID_PM_A.ASM -- the page manager's LRU search in assembly, for the NEC V30
; StevenC & Claude, 2026
;
; PML_GiveLRUPage scans every page in VSWAP -- 663 of them in WL6 -- for the
; unlocked page, resident in EMS or main memory, with the oldest lastHit.
; It runs whenever a page has to be brought in and the cache is full, and
; with XMS (XMSSC on the V30) and a small main-memory cache that is often:
; profiled at 6% of the frame once the cache fell to 32 pages.  The C loop
; did it with a far pointer and a 32-bit compare per page.
;
; PML_FindLRU returns exactly what the C loop found, or -1:
;
;	last = MAXLONG, lru = -1
;	for each page i, in order:
;		if (lastHit < last			(unsigned: lastHit is a longword)
;		 && (emsPage != -1 || mainPage != -1)
;		 && locked == pml_Unlocked
;		 && !(mainonly && mainPage == -1))
;			last = lastHit, lru = i
;
; A strict < keeps the FIRST page among equal lastHits, as the C does.
; ID_PM.C keeps PML_GiveLRUPage, which calls this and still Quits on -1.

	IDEAL
	MODEL	MEDIUM,C
	P186

DATASEG

EXTRN	PMPages:DWORD				; PageListStruct far *
EXTRN	ChunksInFile:WORD

; PageListStruct: offset dd, length dw, xmsPage dw, locked dw (enum),
;                 emsPage dw, mainPage dw, lastHit dd -- 18 bytes
P_LOCKED	=	8
P_EMSPAGE	=	10
P_MAINPAGE	=	12
P_LASTHIT	=	14
P_SIZE		=	18

CODESEG

PROC	PML_FindLRU
PUBLIC	PML_FindLRU
ARG		mainonly:WORD
	push	si
	push	di

	les	di,[PMPages]
	mov	cx,[ChunksInFile]
	mov	ax,0FFFFh
	mov	dx,07FFFh				; last = MAXLONG
	mov	bx,-1					; lru
	xor	si,si					; i
	jcxz	@@done
	cmp	[mainonly],0
	jne	@@mainloop

;
; any page in EMS or main memory
;
; The four conditions are independent, so they are tested cheapest-to-reject
; first: most of the 663 pages are in neither EMS nor main memory, and are
; turned away by the residency test before their lastHit is read.
;
	EVEN
@@anyloop:
	cmp	[WORD es:di+P_EMSPAGE],-1
	jne	@@anyres
	cmp	[WORD es:di+P_MAINPAGE],-1
	je	@@anynext				; not resident
@@anyres:
	cmp	[es:di+P_LASTHIT+2],dx
	ja	@@anynext
	jb	@@anytime
	cmp	[es:di+P_LASTHIT],ax
	jae	@@anynext
@@anytime:						; lastHit < last
	cmp	[WORD es:di+P_LOCKED],0
	jne	@@anynext
	mov	ax,[es:di+P_LASTHIT]
	mov	dx,[es:di+P_LASTHIT+2]
	mov	bx,si
@@anynext:
	add	di,P_SIZE
	inc	si
	loop	@@anyloop
	jmp	@@done

;
; main memory pages only
;
	EVEN
@@mainloop:
	cmp	[WORD es:di+P_MAINPAGE],-1
	je	@@mainnext				; mainonly: must be in main memory
	cmp	[es:di+P_LASTHIT+2],dx
	ja	@@mainnext
	jb	@@maintime
	cmp	[es:di+P_LASTHIT],ax
	jae	@@mainnext
@@maintime:
	cmp	[WORD es:di+P_LOCKED],0
	jne	@@mainnext
	mov	ax,[es:di+P_LASTHIT]
	mov	dx,[es:di+P_LASTHIT+2]
	mov	bx,si
@@mainnext:
	add	di,P_SIZE
	inc	si
	loop	@@mainloop

@@done:
	mov	ax,bx
	pop	di
	pop	si
	ret
ENDP

	END
