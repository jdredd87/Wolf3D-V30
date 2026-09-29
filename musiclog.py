"""Add the TIMEDEMO MUSICLOG check to a WOLFSRC tree -- StevenC & Claude, 2026.

    python musiclog.py [WOLFSRC dir]

MUSICLOG hashes the first 1,000 AdLib register writes the music sequencer
makes, each with its register, its value and the timer tick it happened on
(counted from the song's start), and TIMEDEMO prints the hash.  Two builds
whose hashes match played the same music, note for note and tick for tick --
which is how changes to the sound code are checked, since a picture checksum
cannot see them.  The patch is applied here rather than committed on its own
so it can go onto an older tree (id's interrupt code) for the reference.
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "WOLFSRC")
os.chdir(root)
NL = "\r\n"


def crlf(s):
    return s.replace("\r\n", "\n").replace("\n", NL)


def edit(path, old, new):
    t = open(path, "rb").read().decode("latin-1")
    old, new = crlf(old), crlf(new)
    if new in t:
        print(path, "already patched")
        return
    assert t.count(old) == 1, (path, t.count(old), old[:70])
    open(path, "wb").write(t.replace(old, new).encode("latin-1"))
    print("patched", path)


# ---- the ISR: hash each sequencer write ------------------------------------------------
t = open("ID_SD_A.ASM", "rb").read().decode("latin-1")
if "mlogsum" not in t:
    i = t.index(NL + "DATASEG" + NL) + len(NL + "DATASEG" + NL)
    t = t[:i] + crlf("""
mlogon		dw	0					; MUSICLOG (TIMEDEMO): hash the sequencer's writes
mlogn		dw	0
mlogsum		dw	0
mlogstart	dw	0
	PUBLIC	mlogon
	PUBLIC	mlogn
	PUBLIC	mlogsum
	PUBLIC	mlogstart
""") + t[i:]
    old = "\tmov\tax,[es:di]\t\t\t\t\t\t; Get register/value pair" + NL
    assert t.count(old) >= 1, "sequencer read"
    new = old + crlf("""	cmp	[mlogon],0					; MUSICLOG: hash register, value and tick
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
""")
    # only the fast (700 Hz music) service's sequencer loop
    p = t.index("PROC\tSDL_t0FastAsmService")
    q = t.index("ENDP", p)
    seg = t[p:q]
    assert seg.count(old) == 1
    t = t[:p] + seg.replace(old, new) + t[q:]
    open("ID_SD_A.ASM", "wb").write(t.encode("latin-1"))
    print("patched ID_SD_A.ASM")

# ---- where the song starts ------------------------------------------------------------------
edit("ID_SD.C", """		sqHackTime = 0;
		alTimeCount = 0;
""", """		sqHackTime = 0;
		alTimeCount = 0;
		{
		extern word mlogstart;			// MUSICLOG: ticks count from here
		mlogstart = HackCount;
		}
""")

# ---- TIMEDEMO: switch and report ------------------------------------------------------------
edit("WL_MAIN.C", "\ttdcrc = MS_CheckParm (\"crc\");\t// checksum the view every 50 frames\n",
     "\ttdcrc = MS_CheckParm (\"crc\");\t// checksum the view every 50 frames\n"
     "\t{\n"
     "\textern word mlogon;\n"
     "\tmlogon = MS_CheckParm (\"musiclog\");\t// hash the music's first 1000 writes\n"
     "\t}\n")
edit("WL_MAIN.C", "\tif (profiling)\n\t\tprintf (\"PROFILE: %lu samples in PROF.BIN\\n\",samples);\n",
     "\tif (profiling)\n\t\tprintf (\"PROFILE: %lu samples in PROF.BIN\\n\",samples);\n"
     "\t{\n"
     "\textern word mlogon,mlogn,mlogsum;\n"
     "\tif (mlogon)\n"
     "\t\tprintf (\"music log: %u writes, hash %04X\\n\",mlogn,mlogsum);\n"
     "\t}\n")
