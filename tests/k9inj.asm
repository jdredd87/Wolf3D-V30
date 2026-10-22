; K9INJ.COM  --  keys for a DOS program that reads the keyboard itself
; StevenC & Claude (Anthropic), 2026-10-22.
;
;   K9INJ file.K9   load a script and go resident: from the next timer tick
;                   its key bytes go to the keyboard controller, each at its
;                   time, as if typed
;   K9INJ /T        test the controller here: one key (Q) put in and looked
;                   for at the DOS prompt.  rc 0 it came, 1 it did not
;   K9INJ /S        how far the script is: bytes sent, waits that ran out
;   K9INJ /U        unhook and free
;
; Wolfenstein reads the keyboard hardware itself (its own INT 9 reads port
; 60h), so DOS Bridge's KINJ, which answers INT 16h, cannot reach it.  An AT
; keyboard controller can: command D2h puts a byte in its output buffer as if
; the keyboard had sent it, and raises IRQ 1 -- the game's own INT 9 reads it,
; exactly as a key.  So a byte goes in from the BIOS timer tick (INT 1Ch: the
; game chains its timer to the BIOS's at 18.2 a second), one a tick at most,
; never while the last is unread, and every wait on the controller is bounded
; -- a controller that never answers costs a missed key, not a hung machine.
; Bytes are scancode set 1, as the controller hands them to the system (make
; codes, and break codes with bit 7): 48h is Up as Wolfenstein reads it.
;
; An XT (the V30) has no such controller: there is nothing to send D2h to.
;
; The script (tests/k9.py makes it): entries of a word, the ticks to wait
; before, and a byte to send; a wait of FFFFh ends it.

cpu 8086
org 100h

MAXS    equ     6000                    ; script bytes (2,000 entries)

start:  jmp     init

; ---------------------------------------------------------------------------
;  resident
; ---------------------------------------------------------------------------
sig     db      'K9INJ1'
old1c   dd      0
active  db      0
pos     dw      0                       ; the entry next to send
count   dw      0                       ; ticks to wait before it
sent    dw      0
fails   dw      0                       ; controller waits that ran out
script  times MAXS db 0FFh

; AL to the controller's output buffer (D2h); carry set if it never was ready
kbsend:
        mov     ah,al
        mov     cx,0FFFFh
.ob:    in      al,64h                  ; the last byte read?  (output buffer empty)
        test    al,1
        jz      .ib
        loop    .ob
        jmp     .fail
.ib:    mov     cx,0FFFFh
.ib1:   in      al,64h                  ; ready for a command?  (input buffer empty)
        test    al,2
        jz      .cmd
        loop    .ib1
        jmp     .fail
.cmd:   mov     al,0D2h                 ; write keyboard output buffer
        out     64h,al
        mov     cx,0FFFFh
.ib2:   in      al,64h
        test    al,2
        jz      .dat
        loop    .ib2
        jmp     .fail
.dat:   mov     al,ah
        out     60h,al
        clc
        ret
.fail:  stc
        ret

int1c:  push    ax
        push    bx
        push    cx
        push    si
        push    ds
        push    cs
        pop     ds
        cmp     byte [active],0
        je      .chain
        cmp     word [count],0
        je      .send
        dec     word [count]
        jmp     .chain
.send:  mov     si,[pos]
        mov     al,[script+si+2]
        call    kbsend
        jnc     .ok
        inc     word [fails]
        jmp     .chain                  ; try again next tick
.ok:    inc     word [sent]
        add     si,3
        mov     [pos],si
        mov     bx,[script+si]          ; the next one's wait
        cmp     bx,0FFFFh
        jne     .next
        mov     byte [active],0         ; the end
        jmp     .chain
.next:  mov     [count],bx
.chain: pop     ds
        pop     si
        pop     cx
        pop     bx
        pop     ax
        jmp     far [cs:old1c]
resend:

; ---------------------------------------------------------------------------
;  transient
; ---------------------------------------------------------------------------
init:   mov     si,81h
.skip:  lodsb
        cmp     al,' '
        je      .skip
        cmp     al,13
        je      usage
        cmp     al,'/'
        jne     load
        lodsb
        and     al,0DFh
        cmp     al,'T'
        je      test
        cmp     al,'S'
        je      status
        cmp     al,'U'
        je      unload
usage:  mov     dx,msg_use
        jmp     sayexit

; the resident copy, if there is one: ES = its segment, ZF set when found
find:   mov     ax,351Ch
        int     21h                     ; ES:BX = INT 1Ch
        mov     di,sig
        mov     si,sig
        mov     cx,6
        repe    cmpsb
        ret

; --- /T: one Q put in at the prompt, and looked for through the BIOS ---
test:   mov     ah,1
        int     16h
        jz      .clean
        xor     ah,ah                   ; empty the BIOS buffer first
        int     16h
        jmp     test
.clean: mov     al,10h                  ; Q down
        call    kbsend
        jc      .no
        call    pause
        mov     al,90h                  ; Q up
        call    kbsend
        jc      .no
        call    pause
        mov     ah,1
        int     16h
        jz      .no
        xor     ah,ah
        int     16h
        cmp     ah,10h
        jne     .no
        mov     dx,msg_ok
        mov     ah,9
        int     21h
        mov     ax,4C00h
        int     21h
.no:    mov     dx,msg_no
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h

pause:  push    cx                      ; two BIOS ticks
        push    es
        xor     ax,ax
        mov     es,ax
        mov     ax,[es:46Ch]
        add     ax,2
.w:     cmp     ax,[es:46Ch]
        ja      .w
        pop     es
        pop     cx
        ret

; --- /S ---
status: call    find
        je      .there
        mov     dx,msg_none
        jmp     sayexit
.there: mov     ax,[es:sent]
        mov     di,num_sent
        call    dec5
        mov     ax,[es:fails]
        mov     di,num_fail
        call    dec5
        mov     al,'Y'
        cmp     byte [es:active],0
        jne     .act
        mov     al,'N'
.act:   mov     [num_act],al
        mov     dx,msg_stat
        jmp     sayexit

; AX as five digits at DS:DI
dec5:   mov     cx,5
        add     di,4
        mov     bx,10
.d:     xor     dx,dx
        div     bx
        add     dl,'0'
        mov     [di],dl
        dec     di
        loop    .d
        ret

; --- /U ---
unload: call    find
        je      .ours
        mov     dx,msg_none
        jmp     sayexit
.ours:  push    ds
        lds     dx,[es:old1c]
        mov     ax,251Ch
        int     21h
        pop     ds
        mov     ax,[es:2Ch]             ; its environment, then itself
        push    es
        mov     es,ax
        mov     ah,49h
        int     21h
        pop     es
        mov     ah,49h
        int     21h
        mov     dx,msg_gone
        jmp     sayexit

; --- load: the script, then resident ---
load:   dec     si                      ; the file name, to its end
        mov     dx,si
.end:   lodsb
        cmp     al,' '
        je      .z
        cmp     al,13
        jne     .end
.z:     mov     byte [si-1],0
        call    find
        jne     .new
        mov     dx,msg_already
        jmp     sayexit
.new:   push    cs
        pop     es
        mov     ax,3D00h
        int     21h
        jc      .bad
        mov     bx,ax
        mov     ah,3Fh
        mov     cx,MAXS
        mov     dx,script
        int     21h
        jc      .bad
        mov     ah,3Eh
        int     21h
        mov     ax,[script]
        cmp     ax,0FFFFh
        je      .bad
        mov     [count],ax
        mov     word [pos],0
        mov     byte [active],1
        mov     ax,351Ch
        int     21h
        mov     [old1c],bx
        mov     [old1c+2],es
        mov     dx,int1c
        mov     ax,251Ch
        int     21h
        mov     dx,msg_on
        mov     ah,9
        int     21h
        mov     dx,(resend - start + 100h + 15) / 16
        mov     ax,3100h
        int     21h
.bad:   mov     dx,msg_bad
sayexit:
        mov     ah,9
        int     21h
        mov     ax,4C00h
        int     21h

msg_use     db  'K9INJ file.K9 | /T | /S | /U  -- StevenC & Claude',13,10,'$'
msg_ok      db  'K9INJ: the controller takes D2h -- a key came through',13,10,'$'
msg_no      db  'K9INJ: no key came through D2h',13,10,'$'
msg_none    db  'K9INJ: not resident',13,10,'$'
msg_already db  'K9INJ: already resident (K9INJ /U first)',13,10,'$'
msg_gone    db  'K9INJ: unhooked and freed',13,10,'$'
msg_on      db  'K9INJ: resident, the script running',13,10,'$'
msg_bad     db  'K9INJ: cannot read that script',13,10,'$'
msg_stat    db  'K9INJ: sent '
num_sent    db  '00000, waits run out '
num_fail    db  '00000, running '
num_act     db  '?',13,10,'$'
