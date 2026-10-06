"""Read Wolfenstein 3-D's art out of the player's own WL6 files -- the
sprites in VSWAP.WL6 and the pictures in VGAGRAPH.WL6 -- for building the
multiplayer player sprites.  StevenC & Claude, 2026.

Nothing read here is ever written into this repository: id's art stays in
id's files, and what is built from it is built on the player's machine.

    from wl6art import Art
    art = Art(r"C:\\WOLF3D")          # the folder with the *.WL6 files
    img = art.sprite("SPR_BJ_W1")     # 64x64 PIL image, palette, 255 = clear
    img = art.pic(43)                 # a VGAGRAPH picture by chunk number
"""
import os
import re
import struct

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "WOLFSRC")
CLEAR = 255                     # transparent in a sprite image (palette 255
                                # is never drawn by a sprite: magenta-free)


def gamepal(path=os.path.join(HERE, "..", "stage", "GAMEPAL.PAL")):
    p = open(path, "rb").read()[:768]
    if max(p) < 64:             # VGA DAC values, 0-63
        p = bytes(min(255, c * 4) for c in p)
    return list(p)


def sprite_names():
    """The sprite enum of WL_DEF.H, in order, for Wolf3D (not Spear)."""
    t = open(os.path.join(SRC, "WL_DEF.H"), errors="replace").read()
    t = t[t.index("SPR_DEMO"):]
    t = t[:t.index("};")]
    names, skip = [], []
    for line in t.splitlines():
        s = line.strip()
        if s.startswith("#ifdef SPEAR"):
            skip.append(True)
        elif s.startswith("#ifndef SPEAR"):
            skip.append(False)
        elif s.startswith("#else"):
            skip[-1] = not skip[-1]
        elif s.startswith("#endif"):
            skip.pop()
        elif not any(skip):
            names += re.findall(r"SPR_\w+", re.sub(r"//.*", "", s))
    return names


class Art:
    def __init__(self, folder):
        self.folder = folder
        self.pal = gamepal()
        self.names = sprite_names()
        d = open(os.path.join(folder, "VSWAP.WL6"), "rb").read()
        n, self.sprstart, _ = struct.unpack_from("<3H", d, 0)
        self.offs = struct.unpack_from("<%dI" % n, d, 6)
        self.lens = struct.unpack_from("<%dH" % n, d, 6 + 4 * n)
        self.vswap = d
        self._vga = None

    def blank(self, w=64, h=64):
        img = Image.new("P", (w, h), CLEAR)
        img.putpalette(self.pal)
        return img

    def sprite(self, name):
        k = self.names.index(name) if isinstance(name, str) else name
        o = self.offs[self.sprstart + k]
        c = self.vswap[o:o + self.lens[self.sprstart + k]]
        left, right = struct.unpack_from("<2H", c, 0)
        img = self.blank()
        px = img.load()
        for i, x in enumerate(range(left, right + 1)):
            p = struct.unpack_from("<H", c, 4 + 2 * i)[0]
            while True:
                end = struct.unpack_from("<H", c, p)[0]
                if end == 0:
                    break
                corr = struct.unpack_from("<h", c, p + 2)[0]
                start = struct.unpack_from("<H", c, p + 4)[0]
                for y in range(start // 2, end // 2):
                    px[x, y] = c[corr + y]
                p += 6
        return img

    def _vgagraph(self):
        if self._vga:
            return self._vga
        f = lambda n: open(os.path.join(self.folder, n), "rb").read()
        head = f("VGAHEAD.WL6")
        offs = [int.from_bytes(head[i:i + 3], "little") for i in range(0, len(head) - 2, 3)]
        dic = f("VGADICT.WL6")
        nodes = [struct.unpack_from("<2H", dic, 4 * i) for i in range(255)]
        g = f("VGAGRAPH.WL6")

        def chunk(n):                   # id's Huffman, as CAL_HuffExpand
            o = offs[n]
            size = struct.unpack_from("<I", g, o)[0]
            out, node, bit, pos = bytearray(), 254, 1, o + 4
            while len(out) < size:
                v = nodes[node][1 if g[pos] & bit else 0]
                bit <<= 1
                if bit == 256:
                    pos, bit = pos + 1, 1
                if v < 256:
                    out.append(v)
                    node = 254
                else:
                    node = v - 256
            return bytes(out)
        self._vga = (chunk, chunk(0))
        return self._vga

    def pic(self, num, startpics=3):
        """A VGAGRAPH picture by chunk number (GFXV_WL6.H): four planes."""
        chunk, table = self._vgagraph()
        w, h = struct.unpack_from("<2H", table, 4 * (num - startpics))
        data = chunk(num)
        img = Image.new("P", (w, h))
        img.putpalette(self.pal)
        px = img.load()
        q = w // 4
        for y in range(h):
            for x in range(w):
                px[x, y] = data[(x % 4) * q * h + y * q + x // 4]
        return img


def sheet(images, cols, scale=3, gap=2, pal=None):
    """Lay images out in a grid, for looking at."""
    w = max(i.width for i in images)
    h = max(i.height for i in images)
    rows = (len(images) + cols - 1) // cols
    s = Image.new("P", (cols * (w + gap), rows * (h + gap)), CLEAR)
    s.putpalette(pal or images[0].getpalette())
    for k, img in enumerate(images):
        s.paste(img, ((k % cols) * (w + gap), (k // cols) * (h + gap)))
    return s.resize((s.width * scale, s.height * scale), Image.NEAREST)
