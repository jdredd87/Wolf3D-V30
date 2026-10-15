"""to8086.py -- an 8086/8088 copy of the source tree.  StevenC & Claude, 2026-10-14.

    python to8086.py [SRC] [DST]        default WOLFSRC -> stage/src8086

The game is built for the 80186 set (a NEC V20/V30, an 80186/188, or any 286
or later) and refuses an Intel 8086/8088: on those, a 186 instruction is not
an error but something else, and the machine crashes.  This writes a copy of
the source that an 8086 can run -- the same game, the same picture -- and
leaves the source itself alone, so the V30 build is untouched:

  * every shift or rotate by a count of 2 or more (an 80186 instruction)
    becomes that many shifts by 1, in the assembler and in the C files'
    inline assembly.  The result and CF are the same; OF is undefined after
    a shift of more than 1 on any CPU, and nothing here reads it;
  * PUSHA / POPA become their eight pushes and pops, with POPA's skipped SP
    slot popped into BX first -- the same stack layout, and no flags
    touched, as POPA touches none;
  * VL_SetPalette's REP OUTSB (its fast path, ID_VL.C's inline assembly)
    becomes LODSB / OUT / LOOP: the same 768 bytes to the same port;
  * the page manager's one three-operand IMUL (x 18) becomes shifts and an
    add, keeping DX:AX, which the loop is still using;
  * the C compiler loses -1 (80186 code), so it emits 8086 code;
  * every assembler file's .186/P186 becomes .8086/P8086, so TASM itself
    refuses any 186 instruction this script missed -- a missed one is a
    build error, not a crash on someone's 8088.  A P386 block is left
    exactly as it is: H_LDIV's runs only on a 386, checked at run time;
  * C0.ASM's start-up check lets every CPU in.

`python w3dbuild.py build8086` runs this and builds the copy on the 486, in
C:\\W3D8, and the EXE comes back as WOLFSRC\\WOLF3D8.EXE.

Proven 2026-10-14: built from v30-8086 b262ef4, WOLF3D8.EXE (290,478 bytes)
gave id's own renderer's checksums over the whole attract loop on the 486
and on the Pentium II (`ab.py --full`, 5,386 frames).  TASM assembled every
file under P8086, and BCC without -1 refused the one 186 instruction this
script first missed (VL_SetPalette's REP OUTSB) -- the two checks that stand
in for the 8088 nobody here has.  On the V30 (2026-10-15) it played demo 0
in 738 ticks against WOLF3DV's 722 from the same source: 2.3% slower, and
pixel-identical there too.
"""
import os
import re
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "WOLFSRC")
DST = sys.argv[2] if len(sys.argv) > 2 else os.path.join(HERE, "stage", "src8086")

SHIFT = re.compile(r"^(?P<lead>\s*(?:(?:asm)\s+)?)(?P<label>[@\w]+:\s*)?(?P<op>shl|shr|sar|sal|rol|ror|rcl|rcr)"
                   r"(?P<sp>\s+)(?P<dst>[^,;/]+?),\s*(?P<n>[0-9][0-9a-fA-F]*[hH]?)\b(?P<rest>.*)$", re.I)
counts = {"shift": 0, "pusha": 0, "popa": 0, "imul": 0, "outs": 0, "cpu": 0, "cfg": 0, "check": 0}


def num(s):
    s = s.strip()
    return int(s[:-1], 16) if s[-1] in "hH" else int(s)


def shifts(line, is_c):
    m = SHIFT.match(line)
    if not m:
        return None
    n = num(m.group("n"))
    if n < 2:
        return None
    lead, label, op, sp, dst, rest = (m.group("lead"), m.group("label") or "", m.group("op"),
                                      m.group("sp"), m.group("dst").rstrip(), m.group("rest"))
    if is_c and not lead.strip().lower().startswith("asm"):
        return None                     # only inline assembly in a C file
    counts["shift"] += 1
    out = [lead + label + op + sp + dst + ",1" + rest]
    more = lead if (is_c or lead) else "	"          # a label at column 0: indent the rest
    for _ in range(n - 1):
        out.append(more + op + sp + dst + ",1")
    return out


def convert_asm(name, text):
    nl = "\r\n" if "\r\n" in text else "\n"
    lines = text.replace("\r\n", "\n").split("\n")
    out = []
    in386 = False                       # inside a P386 block: 386 code, gated at run time
    for line in lines:
        code = line.split(";")[0]
        low = code.strip().lower()
        if re.match(r"^\s*(\.386|p386)\b", code, re.I):
            in386 = True
        elif re.match(r"^\s*(\.186|p186|\.8086|p8086)\b", code, re.I):
            in386 = False
        if in386:
            out.append(line)
            continue
        if re.match(r"^\s*(\.186|p186)\b", code, re.I):
            out.append(re.sub(r"(\.186|P186)", lambda m: ".8086" if m.group(1).startswith(".") else "P8086",
                              line, count=1, flags=re.I))
            counts["cpu"] += 1
            continue
        if low == "pusha":
            ind = line[:len(line) - len(line.lstrip())]
            out += [ind + r for r in ("push\tax", "push\tcx", "push\tdx", "push\tbx", "push\tsp",
                                      "push\tbp", "push\tsi", "push\tdi\t; 8086: pusha")]
            counts["pusha"] += 1
            continue
        if low == "popa":
            ind = line[:len(line) - len(line.lstrip())]
            out += [ind + r for r in ("pop\tdi", "pop\tsi", "pop\tbp", "pop\tbx\t; (pusha's SP)",
                                      "pop\tbx", "pop\tdx", "pop\tcx", "pop\tax\t; 8086: popa")]
            counts["popa"] += 1
            continue
        if re.match(r"^\s*imul\s+di\s*,\s*\[mainOwner\+si\]\s*,\s*P_SIZE\s*$", code, re.I):
            assert "P_SIZE\t\t=\t18" in text, "P_SIZE is not 18 any more"
            ind = line[:len(line) - len(line.lstrip())]
            out += [ind + r for r in ("push\tbx\t\t\t\t; 8086: imul di,[mainOwner+si],18",
                                      "mov\tdi,[mainOwner+si]", "shl\tdi,1", "mov\tbx,di",
                                      "shl\tdi,1", "shl\tdi,1", "shl\tdi,1", "add\tdi,bx", "pop\tbx")]
            counts["imul"] += 1
            continue
        if name.upper() == "C0.ASM" and re.match(r"^\s*jns\s+@@Have286", code, re.I):
            out.append(re.sub(r"jns", "jmp", line, count=1, flags=re.I) + "\t; 8086 build: every CPU")
            counts["check"] += 1
            continue
        r = shifts(line, False)
        out += r if r else [line]
    return nl.join(out)


REPOUTS = re.compile(r"^(?P<lead>\s*asm\s+)rep\s+outsb\b(?P<rest>.*)$", re.I)


def convert_c(text):
    nl = "\r\n" if "\r\n" in text else "\n"
    out = []
    for line in text.replace("\r\n", "\n").split("\n"):
        m = REPOUTS.match(line)
        if m:                           # REP OUTSB (186): the same bytes to the same port
            counts["outs"] += 1
            lab = "outs8086_%d" % counts["outs"]
            out += [lab + ":\t\t\t\t\t\t// 8086: rep outsb",
                    m.group("lead") + "lodsb",
                    m.group("lead") + "out\tdx,al",
                    m.group("lead") + "loop\t" + lab]
            continue
        r = shifts(line, True)
        out += r if r else [line]
    return nl.join(out)


def main():
    if os.path.isdir(DST):
        shutil.rmtree(DST)
    shutil.copytree(SRC, DST)
    for root, _, files in os.walk(DST):
        for f in files:
            p = os.path.join(root, f)
            ext = os.path.splitext(f)[1].upper()
            if ext not in (".ASM", ".C") and f.upper() != "TURBOC.CFG":
                continue
            text = open(p, encoding="latin-1", newline="").read()
            if f.upper() == "TURBOC.CFG":
                new = re.sub(r"(?m)^-1\r?\n", "", text)
                if new != text:
                    counts["cfg"] += 1
            elif ext == ".ASM":
                new = convert_asm(f, text)
            else:
                new = convert_c(text)
            if new != text:
                open(p, "w", encoding="latin-1", newline="").write(new)
    print("8086 copy in %s: %s" % (DST, ", ".join("%s %d" % kv for kv in counts.items())))


if __name__ == "__main__":
    main()
