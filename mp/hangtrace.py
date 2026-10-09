"""hangtrace.py -- a stack trace out of a hang watchdog's report.  StevenC &
Claude (Anthropic), 2026-10-09.

A test build from mp/huntbot.py (WL_NET.C's HANGDUMP) reports a game whose
loop has stopped for 20 s: to the server, which keeps it in
stage/hang-<address>.log, and into the machine's C:\\WOLF3D\\HANG.LOG.
The report holds 384 bytes of the stack as the watchdog found it -- every
frame from the BIOS tick down to the stuck code -- and the address NetSend
was loaded at.  With the build's map (compiled -y, linked /l: it has line
numbers) and its EXE, every word that is a return address becomes a source
line:

    python mp/hangtrace.py stage/hang-192.168.50.67.log
    python mp/hangtrace.py HANG.LOG --map stage/WOLF3DT.MAP --exe stage/WOLF3DT.EXE

Two kinds of frame are found, both checked against the code itself:
  * INTERRUPTED -- IP, CS and FLAGS as an interrupt pushes them, with
    interrupts on: where the processor was when the tick came.  The last
    one into the game's own code is the stuck place;
  * called from -- a far return address whose bytes before it are a far
    call: the chain that led there.
Every report in the file is traced, oldest first; --last takes only the
newest.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


class Map:
    def __init__(self, path):
        text = open(path, encoding="latin-1").read().splitlines()
        self.segs = []                  # (start, stop, name) of CODE, linear
        self.pubs = []                  # (linear, name)
        self.lines = []                 # (linear, file, line)
        self.byname = {}                # name -> (seg, off)
        mode = None
        src = None
        for ln in text:
            m = re.match(r"\s*([0-9A-F]{5})H ([0-9A-F]{5})H [0-9A-F]{5}H (\S+)\s+(\S+)", ln)
            if m and mode is None:
                if m.group(4) == "CODE":
                    self.segs.append((int(m.group(1), 16), int(m.group(2), 16) + 1, m.group(3)))
                continue
            if "Publics by Value" in ln:
                mode = "pubs"
                continue
            if "Publics by Name" in ln:
                mode = "names"
                continue
            m = re.match(r"Line numbers for \S+?\((\S+)\)", ln)
            if m:
                mode, src = "lines", m.group(1)
                continue
            if mode in ("pubs", "names"):
                m = re.match(r"\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:idle\s+|Abs\s+)?(\S+)", ln)
                if m:
                    seg, off = int(m.group(1), 16), int(m.group(2), 16)
                    if mode == "pubs":
                        self.pubs.append((seg * 16 + off, m.group(3)))
                    self.byname[m.group(3)] = (seg, off)
            elif mode == "lines":
                for n, seg, off in re.findall(r"(\d+) ([0-9A-F]{4}):([0-9A-F]{4})", ln):
                    self.lines.append((int(seg, 16) * 16 + int(off, 16), src, int(n)))
        self.pubs.sort()
        self.lines.sort()

    def code(self, lin):
        for a, b, name in self.segs:
            if a <= lin < b:
                return name
        return None

    def where(self, lin):
        seg = self.code(lin)
        pub = None
        for a, name in self.pubs:
            if a > lin:
                break
            pub = name
        best = None
        lo = [s for s in self.segs if s[2] == seg]
        for a, f, n in self.lines:
            if a > lin:
                break
            if lo and lo[0][0] <= a < lo[0][1]:
                best = (f, n)
        here = "%s:%d" % best if best else "?"
        return "%-14s %-22s (after public %s)" % (seg, here, pub)


def far_call_before(img, lin):
    """The bytes before a return address are a far call (or push cs + near call)."""
    if lin < 5 or lin > len(img):
        return False
    if img[lin - 5] == 0x9A:
        return True
    for k, mods in ((2, (0,)), (3, (1,)), (4, (2, 0))):
        if img[lin - k] == 0xFF:
            modrm = img[lin - k + 1]
            mod, reg, rm = modrm >> 6, (modrm >> 3) & 7, modrm & 7
            if reg == 3 and mod in mods:
                if k == 2 and rm == 6:
                    continue
                if k == 4 and mod == 0 and rm != 6:
                    continue
                return True
    return img[lin - 3] == 0xE8 and img[lin - 4] == 0x0E


def reports(path):
    """Each STUCK report's lines, oldest first."""
    out, cur = [], None
    for ln in open(path, encoding="latin-1").read().replace("\r", "").split("\n"):
        if "STUCK" in ln:
            cur = [ln]
            out.append(cur)
        elif cur is not None:
            if ln.startswith("==") or not ln.strip():
                cur = None
            else:
                cur.append(ln)
    return out


def trace(rep, mp, img):
    print(rep[0])
    info = " ".join(rep[1:3])
    v = dict((k, (int(a, 16), int(b, 16))) for k, a, b in
             re.findall(r"(netsend|ss:sp|pktdrv|int21|int13) ([0-9A-F]{4}):([0-9A-F]{4})", info))
    words = [int(w, 16) for ln in rep[rep.index("stack:") + 1:] for w in ln.split()] \
        if "stack:" in rep else []
    ms, mo = mp.byname["_NetSend"]
    rs, ro = v["netsend"]
    base = rs - ms
    if ro != mo:
        print("  ! NetSend's offset %04X is not the map's %04X: wrong map for this EXE?" % (ro, mo))
    others = {v[k][0]: name for k, name in (("pktdrv", "the packet driver"), ("int21", "DOS"),
                                            ("int13", "the disk BIOS")) if k in v}
    print("  loaded at %04X; stack at %04X:%04X, %d words" % (base, v["ss:sp"][0], v["ss:sp"][1],
                                                            len(words)))
    for i in range(len(words) - 1):
        off, seg = words[i], words[i + 1]
        lin = (seg - base) * 16 + off
        inside = 0 <= lin < len(img) and mp.code(lin)
        flags = words[i + 2] if i + 2 < len(words) else 0
        intr = (flags & 0x0202) == 0x0202 and not flags & 0x0028
        if inside and intr and not far_call_before(img, lin):
            print("  [%3d] INTERRUPTED at %04X:%04X  %s" % (i, seg, off, mp.where(lin)))
        elif inside and far_call_before(img, lin):
            print("  [%3d] called from    %04X:%04X  %s" % (i, seg, off, mp.where(lin)))
        elif intr and seg in others:
            print("  [%3d] INTERRUPTED at %04X:%04X  in %s" % (i, seg, off, others[seg]))
    print()


def main():
    files = [a for a in sys.argv[1:] if not a.startswith("--") and
             sys.argv[sys.argv.index(a) - 1] not in ("--map", "--exe")]
    if not files:
        print(__doc__)
        return 1
    mp = Map(arg("--map", os.path.join(ROOT, "stage", "WOLF3DT.MAP")))
    exe = open(arg("--exe", os.path.join(ROOT, "stage", "WOLF3DT.EXE")), "rb").read()
    img = exe[int.from_bytes(exe[8:10], "little") * 16:]
    reps = reports(files[0])
    if not reps:
        print("no STUCK report in", files[0])
        return 1
    for rep in reps[-1:] if "--last" in sys.argv else reps:
        trace(rep, mp, img)
    return 0


if __name__ == "__main__":
    sys.exit(main())
