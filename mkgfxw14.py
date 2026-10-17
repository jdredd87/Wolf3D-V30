"""Write WOLFSRC/GFXV_W14.H, the graphics header for the shareware 1.4's
VGAGRAPH.WL1 -- StevenC & Claude (Anthropic), 2026-10-16.

    python mkgfxw14.py          (needs the registered and the shareware data
                                 in the two folders below, to check against)

id's GFXV_WL1.H is an older shareware's (556 chunks); 1.4's VGAGRAPH.WL1
has 156.  1.4's data is laid out as the registered game's, plus 12 pictures
for its help screens: GFXV_WL6.H's names with those 12 inserted (named as in
GFXV_WL1.H), one end text instead of six, every number, lump and count
worked out again -- and every picture's width and height compared with its
registered twin's, from both files' own picture tables.
"""
import re, io, os, struct, sys
sys.path.insert(0, r"C:\wolf3d")
src = io.open(r"C:\wolf3d\WOLFSRC\GFXV_WL6.H", "rb").read().decode("latin-1").replace("\r\n", "\n")
body = src[src.index("typedef enum {"):src.index("} graphicnums;")]
names = re.findall(r"^\s*([A-Z0-9_]+)(?:=\d+)?,", body, re.M)
assert names[0] == "H_BJPIC" and names[-1] == "T_ENDART6", names[-3:]
ins = {"H_CASTLEPIC": ["H_KEYBOARDPIC", "H_JOYPIC", "H_HEALPIC", "H_TREASUREPIC", "H_GUNPIC", "H_KEYPIC"],
       "H_BLAZEPIC": ["H_WEAPON1234PIC", "H_WOLFLOGOPIC", "H_VISAPIC", "H_MCPIC", "H_IDLOGOPIC"],
       "H_BOTTOMINFOPIC": ["H_SPEARADPIC"]}
out = []
for n in names:
    if n in ("T_ENDART2", "T_ENDART3", "T_ENDART4", "T_ENDART5", "T_ENDART6"):
        continue
    out.append(n)
    out += ins.get(n, [])
num = {}
v = 3
for n in out:
    if n == "ORDERSCREEN":
        v += 1                      # the 8x8 tiles' chunk, between the pictures and the externs
    num[n] = v
    v += 1
lump_starts = {"H_BJPIC", "C_OPTIONSPIC", "L_GUYPIC", "STATUSBARPIC"}   # where WL6 marks "Lump Start"
wl6_lumps = re.findall(r"^\s*// Lump Start\n\s*([A-Z0-9_]+)", body, re.M)
L = []
L.append("//////////////////////////////////////")
L.append("//")
L.append("// Graphics .H file for the SHAREWARE .WL1, version 1.4")
L.append("// StevenC & Claude (Anthropic), 2026-10-16: id's GFXV_WL1.H is an older")
L.append("// shareware's (556 chunks); 1.4's VGAGRAPH.WL1 has 156.  This is GFXV_WL6.H")
L.append("// with the 12 pictures 1.4's help screens add (named as in id's GFXV_WL1.H;")
L.append("// H_SPEARADPIC is the 256x144 one after H_BOTTOMINFOPIC) and one end text")
L.append("// instead of six -- every picture's size checked against the data's own")
L.append("// picture table.  Chosen by UPLOAD in ID_HEADS.H.")
L.append("//")
L.append("//////////////////////////////////////")
L.append("")
L.append("typedef enum {")
for i, n in enumerate(out):
    if n in wl6_lumps:
        L.append("\t\t// Lump Start")
    if i == 0:
        L.append("\t\t%s=3," % n)
    elif n == "ORDERSCREEN":
        L.append("")
        L.append("\t\t%s=%d," % (n, num[n]))
    else:
        L.append("\t\t%-36s // %d" % (n + ",", num[n]))
L.append("\t\tENUMEND")
L.append("\t     } graphicnums;")
L.append("")
L.append("//")
L.append("// Data LUMPs")
L.append("//")
def lump(name, a, b):
    L.append("#define %s_LUMP_START\t\t%d" % (name, num[a]))
    L.append("#define %s_LUMP_END\t\t\t%d" % (name, num[b]))
    L.append("")
# the WL6 lumps, by their first and last names
tail = src[src.index("// Data LUMPs"):]
for m in re.finditer(r"#define (\w+)_LUMP_START\s+(\d+)\n#define \1_LUMP_END\s+(\d+)", tail):
    nm, a, b = m.group(1), int(m.group(2)), int(m.group(3))
    first, last = names[a - 3], names[b - 3]
    if last == "H_BOTTOMINFOPIC":
        last = "H_SPEARADPIC"
    lump(nm, first, last)
npics = num["GETPSYCHEDPIC"] - 2
tile8 = num["GETPSYCHEDPIC"] + 1
nchunks = num["T_ENDART1"] + 1
L.append("")
L.append("//")
L.append("// Amount of each data item")
L.append("//")
for k, v in [("NUMCHUNKS", nchunks), ("NUMFONT", 2), ("NUMFONTM", 0), ("NUMPICS", npics), ("NUMPICM", 0),
             ("NUMSPRITES", 0), ("NUMTILE8", 72), ("NUMTILE8M", 0), ("NUMTILE16", 0), ("NUMTILE16M", 0),
             ("NUMTILE32", 0), ("NUMTILE32M", 0), ("NUMEXTERNS", nchunks - tile8 - 1)]:
    L.append("#define %-12s %d" % (k, v))
L.append("//")
L.append("// File offsets for data items")
L.append("//")
L.append("#define STRUCTPIC    0")
L.append("")
for k, v in [("STARTFONT", 1), ("STARTFONTM", 3), ("STARTPICS", 3), ("STARTPICM", tile8), ("STARTSPRITES", tile8),
             ("STARTTILE8", tile8), ("STARTTILE8M", tile8 + 1), ("STARTTILE16", tile8 + 1), ("STARTTILE16M", tile8 + 1),
             ("STARTTILE32", tile8 + 1), ("STARTTILE32M", tile8 + 1), ("STARTEXTERNS", tile8 + 1)]:
    L.append("#define %-12s %d" % (k, v))
L.append("")
L.append("//")
L.append("// Thank you for using IGRAB!")
L.append("//")
L.append("")
io.open(r"C:\wolf3d\WOLFSRC\GFXV_W14.H", "wb").write("\r\n".join(L).encode("latin-1"))
print("chunks", nchunks, "pics", npics, "tile8", tile8, "ORDERSCREEN", num["ORDERSCREEN"], "T_DEMO0", num["T_DEMO0"], "T_ENDART1", num["T_ENDART1"])
# check against the data: every picture's size in the same place as its WL6 twin
from gfxchunks import huff_expand
def pictable(d, ext):
    head = open(os.path.join(d, "VGAHEAD." + ext), "rb").read(); dic = open(os.path.join(d, "VGADICT." + ext), "rb").read()
    g = open(os.path.join(d, "VGAGRAPH." + ext), "rb").read()
    dn = [struct.unpack_from("<HH", dic, i * 4) for i in range(255)]
    o0 = int.from_bytes(head[0:3], "little"); o1 = int.from_bytes(head[3:6], "little")
    ln = struct.unpack_from("<I", g, o0)[0]; pt = huff_expand(g[o0 + 4:o1], ln, dn)
    return [struct.unpack_from("<hh", pt, i * 4) for i in range(ln // 4)], len(head) // 3 - 1
reg, _ = pictable(r"C:\Software\86Box\Software\wolf3d", "WL6")
sw, swn = pictable(r"C:\Software\86Box\Software\wolf3d-sw", "WL1")
assert swn == nchunks and len(sw) == npics, (swn, len(sw))
bad = [n for i, n in enumerate(names) if n.endswith("PIC") and reg[i] != sw[num[n] - 3]]
print("pictures whose size differs from WL6's twin:", bad or "none")
