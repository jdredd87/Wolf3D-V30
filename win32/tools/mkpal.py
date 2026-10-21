"""mkpal.py -- src/w32pal.c from id's GAMEPAL.OBJ (WOLFSRC/OBJ): the game's
palette, which id linked into the EXE rather than shipping as data -- as id's
symbol gamepal (InitRedShifts reads 768 bytes from &gamepal).  The OMF
object's LEDATA records hold its 768 bytes (red, green, blue: 0-63 each).
StevenC & Claude (Anthropic), 2026-10-21.    python win32/tools/mkpal.py"""
import os
HERE = os.path.dirname(os.path.abspath(__file__))
d = open(os.path.join(HERE, "..", "..", "WOLFSRC", "OBJ", "GAMEPAL.OBJ"), "rb").read()
i, data = 0, bytearray()
while i < len(d):
    t, n = d[i], d[i + 1] | (d[i + 2] << 8)
    body = d[i + 3:i + 3 + n - 1]
    if t in (0xA0, 0xA1):                   # LEDATA: segment, offset, bytes
        off = body[1] | (body[2] << 8)
        chunk = body[3:]
        if len(data) < off + len(chunk):
            data.extend(b"\0" * (off + len(chunk) - len(data)))
        data[off:off + len(chunk)] = chunk
    i += 3 + n
assert len(data) == 768
rows = ["\t" + ",".join("%2d" % v for v in data[k:k + 24]) + "," for k in range(0, 768, 24)]
open(os.path.join(HERE, "..", "src", "w32pal.c"), "w").write(
    "/* w32pal.c -- id's game palette (WOLFSRC/OBJ/GAMEPAL.OBJ), by tools/mkpal.py */\n"
    "unsigned char gamepal[768] = {\n%s\n};\n" % "\n".join(rows))
print("w32pal.c: 768 bytes")
