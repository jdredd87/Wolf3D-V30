"""Build the multiplayer player sprites -- BJ, in every direction, gun in
hand -- from the SS's frames in the player's own VSWAP.WL6.  StevenC &
Claude, 2026.  A DRAFT: this first version writes preview sheets only.

    python mp/mkbj.py WL6FOLDER        previews into stage/mp/

The SS has the full set a DOOM-style player needs -- 8 standing views,
4 walking frames in 8 views, 3 firing, 2 pain, 3 dying and a body -- with
his gun in every one (DOOM's players also carry one gun whatever they
use).  The conversion:

* his cap becomes BJ's hair: down each column from the head's top, the
  cap's blues (and its black band) mapped by brightness onto the
  palette's orange ramp -- stopping at the first pixel that is not cap,
  and at an eye (a blue pixel with skin either side: the cap's brim sits
  right on the eyes in the front views);
* his uniform -- the blue ramp 140-159, used by nothing else on him --
  is left in that ramp in the built sprite, so the game can translate it
  per player at draw time (DOOM's colour translation); the previews show
  it as BJ's own grey and in four player colours;
* his gun, face, boots and harness are kept.

id's pixels are never written into the repository: everything here is
built from the player's own data, on their machine.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wl6art import Art, CLEAR, sheet        # noqa: E402

STAGE = os.path.join(HERE, "..", "stage", "mp")
UNIFORM = list(range(140, 160))     # the SS blue ramp, bright to dark: his
                                    # uniform and nothing else he wears
NAVY = (227, 228, 232)              # near-black blues: boots and shadow, as
                                    # on BJ's own sprite -- kept
# the game palette's ramps, bright to dark
HAIR = list(range(56, 64))          # orange: BJ's hair (his own is 59, 61)
RAMPS = {                           # the four players, in order (StevenC)
    "grey": list(range(18, 31)),    # 1: BJ's own outfit (20-31), a shade lighter
    "green": list(range(97, 112)),  # 2
    "red": list(range(33, 48)),     # 3
    "brown": list(range(208, 224)), # 4
}
CAPROWS = 8                         # at most, from the head's top


def blueness(pal, i):
    r, g, b = pal[3 * i:3 * i + 3]
    return b if (r < 40 and g < 40) else 0


def frames(art):
    """The SS frames a player needs, in the order the game will use."""
    n = []
    n += ["SPR_SS_S_%d" % r for r in range(1, 9)]
    for w in range(1, 5):
        n += ["SPR_SS_W%d_%d" % (w, r) for r in range(1, 9)]
    n += ["SPR_SS_PAIN_1", "SPR_SS_PAIN_2", "SPR_SS_DIE_1", "SPR_SS_DIE_2",
          "SPR_SS_DIE_3", "SPR_SS_DEAD", "SPR_SS_SHOOT1", "SPR_SS_SHOOT2",
          "SPR_SS_SHOOT3"]
    return n


def convert(art, img, hair):
    """SS -> BJ: the cap to hair.  The uniform stays in the blue ramp."""
    pal = art.pal
    out = img.copy()
    px = out.load()
    ys = [y for y in range(64) for x in range(64) if px[x, y] != CLEAR]
    if not ys:
        return out
    top = min(ys)
    bluemax = max(blueness(pal, i) for i in UNIFORM)
    # down each column from the head's top, through the cap, stopping at the
    # first pixel that is not cap (skin, hair) -- so the eyes, blue too and
    # only a row or two below, are left alone
    skin = lambda c: 192 <= c <= 223
    for x in range(64):
        for y in range(top, min(64, top + CAPROWS)):
            c = px[x, y]
            if c == CLEAR:
                continue
            if not (c in UNIFORM or c in NAVY or c == 0):
                break
            if 0 < x < 63 and skin(px[x - 1, y]) and skin(px[x + 1, y]):
                break               # an eye: blue between skin
            # bright blue -> bright orange, dark (and the black band) -> dark
            t = blueness(pal, c) / bluemax if c else 0
            px[x, y] = hair[min(len(hair) - 1, int((1 - t) * len(hair)))]
    return out


def translate(img, table):
    out = img.copy()
    out.putdata([table[p] for p in img.getdata()])
    out.putpalette(img.getpalette())
    return out


def table_to(pal, targets):
    """A 256-byte translation: the uniform ramp onto targets, by brightness."""
    t = list(range(256))
    n = len(UNIFORM) - 1
    for k, i in enumerate(UNIFORM):
        t[i] = targets[round(k * (len(targets) - 1) / n)]
    return t


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else r"C:\WOLF3D"
    art = Art(folder)
    pal = art.pal
    os.makedirs(STAGE, exist_ok=True)
    built = [convert(art, art.sprite(n), HAIR) for n in frames(art)]
    for name, targets in RAMPS.items():
        tab = table_to(pal, targets)
        sheet([translate(b, tab) for b in built], 8).save(os.path.join(STAGE, "bj_%s.png" % name))
    # each colour: standing, two walking views, the back, a firing frame
    pick = [built[0], built[8 + 1], built[16 + 2], built[4], built[47]]
    sheet([translate(b, table_to(pal, t)) for t in RAMPS.values() for b in pick],
          len(pick)).save(os.path.join(STAGE, "bj_colours.png"))
    print("previews in", os.path.abspath(STAGE))


if __name__ == "__main__":
    main()
