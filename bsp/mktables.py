"""BSP proof of concept, the tables -- StevenC & Claude, 2026.

    python mktables.py         -> TABLES.DAT

The projection both halves of BSPTEST use: 240 columns, Wolf's focal
distance (0xAF00) and view width (0x10000 global units), so a column's
angle offset from the centre (pixelangle, tenths of a degree), 1.14 sines
and 16.16 tangents at 3600 angles, and scale16 -- sixteenths of a column
per unit of side over depth.  Not id's own pixelangle rounding: both the
walk and the BSP use these, so they agree with each other.
"""
import math
import struct

k = (65536.0 / 240) / 44800.0                      # tan step per column
pix = [int(round(math.atan((119.5 - i) * k) * 1800 / math.pi)) for i in range(240)]
sin14 = [int(round(math.sin(a * math.pi / 1800) * 16384)) for a in range(3600)]
tan16 = []
for a in range(3600):
    v = int(round(math.tan(a * math.pi / 1800) * 65536))
    tan16.append(max(-0x7F000000, min(0x7F000000, v)))
scale16 = int(round(16 / k))
data = (b"WTAB" + struct.pack("<H", scale16) + struct.pack("<240h", *pix)
        + struct.pack("<3600h", *sin14) + struct.pack("<3600l", *tan16))
open("TABLES.DAT", "wb").write(data)
print("scale16", scale16, "pixelangle", pix[0], pix[239], "bytes", len(data))
