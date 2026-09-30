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
	JUMPS

EXTRN	PML_GetPageC:FAR			; ID_PM.C: id's PM_GetPage

DATASEG

EXTRN	PMPages:DWORD				; PageListStruct far *
EXTRN	ChunksInFile:WORD
EXTRN	EMSPagesUsed:WORD
EXTRN	mainOwner:WORD				; int[PMMaxMainMem]: the page in each main block
EXTRN	MainMemPages:WORD			; memptr[PMMaxMainMem]: segments
EXTRN	PMFrameCount:DWORD
PMMAXMAIN	=	100				; PMMaxMainMem (ID_PM.H)
lrubase		dw	0

; PageListStruct: offset dd, length dw, xmsPage dw, locked dw (enum),
;                 emsPage dw, mainPage dw, lastHit dd -- 18 bytes
P_LOCKED	=	8
P_EMSPAGE	=	10
P_MAINPAGE	=	12
P_LASTHIT	=	14
P_SIZE		=	18

CODESEG


;============================
;
; PM_GetPage (int pagenum) -- step 58
;
; The C's result exactly when the page is in main memory:
;
;	if (pagenum < ChunksInFile && PMPages[pagenum].mainPage != -1
;	 && (result = MainMemPages[PMPages[pagenum].mainPage]))
;	{
;		PMPages[pagenum].lastHit = PMFrameCount;
;		return result;
;	}
;
; and otherwise id's routine, reached with the caller's frame as it was.
;
;============================

PROC	PM_GetPage
PUBLIC	PM_GetPage
	push	bp
	mov	bp,sp
	mov	bx,[bp+6]				; pagenum
	cmp	bx,[ChunksInFile]
	jae	@@slow					; unsigned, as the C compares it (and Quits)
	mov	ax,bx
	shl	ax,3
	add	ax,bx
	shl	ax,1					; pagenum*18
	les	bx,[PMPages]
	add	bx,ax					; ES:BX = &PMPages[pagenum]
	mov	ax,[es:bx+P_MAINPAGE]
	cmp	ax,-1
	je	@@slow					; not in main memory
	mov	dx,bx
	mov	bx,ax
	shl	bx,1
	mov	ax,[MainMemPages+bx]
	or	ax,ax
	jz	@@slow
	mov	bx,dx
	mov	dx,[WORD PMFrameCount]
	mov	[WORD es:bx+P_LASTHIT],dx
	mov	dx,[WORD PMFrameCount+2]
	mov	[WORD es:bx+P_LASTHIT+2],dx
	pop	bp
	ret
@@slow:
	pop	bp
	jmp	PML_GetPageC
ENDP


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
	or	cx,cx
	jz	@@done				; (no JCXZ: too far now, and JUMPS cannot stretch it)
;
; NEC V30 build (step 45): with nothing in EMS -- XMS, the default -- the
; candidates are exactly the pages in main memory, so walk its 100 slots
; through mainOwner instead of all 663 pages.  The slots are not in page
; order, so the minimum is taken over (lastHit, page number): the same
; page id's scan finds first.  A page whose lastHit equals the starting
; MAXLONG is never taken, as id's strict < never took it.
;
	cmp	[EMSPagesUsed],0
	jne	@@scan
	mov	[lrubase],di
	mov	cx,PMMAXMAIN
	xor	si,si
	EVEN
@@oloop:
	mov	di,[mainOwner+si]
	inc	di
	jz	@@onext						; a free slot
	imul	di,[mainOwner+si],P_SIZE
	add	di,[lrubase]
	cmp	[es:di+P_LASTHIT+2],dx
	ja	@@onext
	jb	@@ocand
	cmp	[es:di+P_LASTHIT],ax
	ja	@@onext
	jb	@@ocand
	cmp	bx,-1						; equal lastHit: the lower page wins
	je	@@onext
	cmp	[mainOwner+si],bx
	jae	@@onext
@@ocand:
	cmp	[WORD es:di+P_LOCKED],0
	jne	@@onext
	mov	ax,[es:di+P_LASTHIT]
	mov	dx,[es:di+P_LASTHIT+2]
	mov	bx,[mainOwner+si]
@@onext:
	add	si,2
	loop	@@oloop
	jmp	@@done

@@scan:
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
