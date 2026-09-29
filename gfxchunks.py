"""List the chunks of a Wolf3D VGAGRAPH file -- StevenC & Claude, 2026.

    python gfxchunks.py DIR [EXT] [FIRST LAST]

Decodes VGAHEAD/VGADICT/VGAGRAPH.<EXT> (default WL6) the way ID_CA.C does
and prints each chunk's expanded size and first bytes, and whether it looks
like a demo (map byte, word length, zero byte).  Used to find where this
data's demos really are, which is where the GFXV_*.H numbering has to agree
with the data.
"""
import os
import struct
import sys


def huff_expand(src, length, dictn):
    out = bytearray()
    node = 254
    for byte in src:
        for bit in range(8):
            w = dictn[node][(byte >> bit) & 1]
            if w < 256:
                out.append(w)
                node = 254
                if len(out) == length:
                    return bytes(out)
            else:
                node = w - 256
    return bytes(out)


def main():
    a = sys.argv[1:]
    if not a:
        sys.exit(__doc__)
    d = a[0]
    ext = a[1] if len(a) > 1 else "WL6"
    first, last = (int(a[2]), int(a[3])) if len(a) > 3 else (0, 10 ** 6)
    head = open(os.path.join(d, "VGAHEAD." + ext), "rb").read()
    dic = open(os.path.join(d, "VGADICT." + ext), "rb").read()
    gra = open(os.path.join(d, "VGAGRAPH." + ext), "rb").read()
    dictn = [struct.unpack_from("<HH", dic, i * 4) for i in range(255)]
    offs = []
    for i in range(0, len(head), 3):
        v = head[i] | head[i + 1] << 8 | head[i + 2] << 16
        offs.append(None if v == 0xFFFFFF else v)
    n = len(offs) - 1
    print("%d chunks in VGAHEAD.%s" % (n, ext))
    for c in range(max(0, first), min(n, last + 1)):
        if offs[c] is None:
            print("%4d  sparse" % c)
            continue
        nxt = next((o for o in offs[c + 1:] if o is not None), len(gra))
        comp = gra[offs[c]:nxt]
        if len(comp) < 4:
            print("%4d  (%d bytes)" % (c, len(comp)))
            continue
        explen = struct.unpack_from("<L", comp)[0]
        if explen > 200000:
            print("%4d  compressed %d, no length header (tile chunk?)" % (c, len(comp)))
            continue
        data = huff_expand(comp[4:], explen, dictn)
        tag = ""
        if len(data) >= 4:
            mapon, dlen = data[0], struct.unpack_from("<H", data, 1)[0]
            if data[3] == 0 and dlen == len(data) and mapon < 60:
                tag = "  <-- DEMO: map byte %d (floor %d), length %d" % (mapon, mapon + 1, dlen)
        text = data[:24]
        printable = "".join(chr(b) if 32 <= b < 127 else "." for b in text)
        print("%4d  %6d bytes  %s  %s%s" % (c, len(data), text[:12].hex(), printable, tag))


if __name__ == "__main__":
    main()
