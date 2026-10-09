"""The multiplayer protocol, version 1 -- packing and unpacking.  StevenC &
Claude, 2026.  MULTIPLAYER.md ("Protocol, version 1") is the specification;
mpserver.py and mpfake.py use this, and the DOS sides must match it.
"""
import struct

PORT = 31992
VERSION = 1
HELLO, WELCOME, START, INPUT, STEPS, SYNC, DESYNC, BYE, CHAT, CHATMSG, PLAYERS = range(1, 12)
# HANG (2026-10-09): only a TEST build sends it (mp/huntbot.py's, WL_NET.C's
# HANGDUMP) -- a text report from its hang watchdog, for the server to keep
HANG = 12
NAMES = {HELLO: "HELLO", WELCOME: "WELCOME", START: "START", INPUT: "INPUT", STEPS: "STEPS",
         SYNC: "SYNC", DESYNC: "DESYNC", BYE: "BYE", CHAT: "CHAT", CHATMSG: "CHATMSG",
         PLAYERS: "NAMES", HANG: "HANG"}
STEPS_MAX = 64                  # steps in one STEPS packet
# (the game's receive slots are 1024 bytes: 4 players x 3 x STEPS_MAX + 52 must fit)
STEP_SECONDS = 4 / 70           # DEMOTICS of the 70 Hz clock
SYNC_EVERY = 50                 # steps between SYNCs
NOBODY = 0xFFFFFFFF             # `have` before the first step


def head(kind):
    return b"WM" + bytes([VERSION, kind])


def parse(data):
    """(type, body) -- or (None, None) for anything not ours."""
    if len(data) < 4 or data[:2] != b"WM" or data[2] != VERSION:
        return None, None
    return data[3], data[4:]


def hello(name, build, want=0xFF):
    return head(HELLO) + name.encode("latin-1")[:16].ljust(16, b"\0") + struct.pack("<IB", build, want)


def un_hello(b):
    name = b[:16].split(b"\0")[0].decode("latin-1")
    build, want = struct.unpack_from("<IB", b, 16)
    return name, build, want


def welcome(slot, players, mapnum, skill, rules, frags=0, minutes=0):
    return head(WELCOME) + struct.pack("<6BHH", slot, players, mapnum, skill, rules, 0, frags, minutes)


def un_welcome(b):
    slot, players, mapnum, skill, rules, _, frags, minutes = struct.unpack_from("<6BHH", b)
    return dict(slot=slot, players=players, map=mapnum, skill=skill, rules=rules, frags=frags, minutes=minutes)


def start(players, mapnum, skill, rules, starts):
    out = head(START) + bytes([players, mapnum, skill, rules])
    for s in starts:
        out += bytes(s)
    return out


def un_start(b):
    players, mapnum, skill, rules = b[:4]
    starts = [tuple(b[4 + 4 * i:8 + 4 * i]) for i in range(players)]
    return dict(players=players, map=mapnum, skill=skill, rules=rules, starts=starts)


def inp(slot, buttons, turn, move, seq, have, played=None):
    out = head(INPUT) + struct.pack("<BBbbHI", slot, buttons, turn, move, seq & 0xFFFF, have & 0xFFFFFFFF)
    if played is not None:          # since 2026-10-07: how far it has PLAYED
        out += struct.pack("<I", played & 0xFFFFFFFF)
    return out


def un_inp(b):
    """(slot, buttons, turn, move, seq, have, played) -- played None from a
    client older than 2026-10-07, which does not send it."""
    v = struct.unpack_from("<BBbbHI", b)
    played = struct.unpack_from("<I", b, 10)[0] if len(b) >= 14 else None
    return v + (played,)


def steps(first, players, rows):
    """rows: a list of `players*3`-byte steps."""
    return head(STEPS) + struct.pack("<IBB", first, len(rows), players) + b"".join(rows)


def un_steps(b):
    first, count, players = struct.unpack_from("<IBB", b)
    n = 3 * players
    rows = [bytes(b[6 + i * n:6 + (i + 1) * n]) for i in range(count)]
    return first, players, rows


def sync(slot, step, total):
    return head(SYNC) + struct.pack("<BBII", slot, 0, step, total & 0xFFFFFFFF)


def un_sync(b):
    slot, _, step, total = struct.unpack_from("<BBII", b)
    return slot, step, total


def desync(step, mask):
    return head(DESYNC) + struct.pack("<IB", step, mask)


def un_desync(b):
    return struct.unpack_from("<IB", b)


# BYE's reason (since 2026-10-07; a client older than that ignores it)
BYE_END, BYE_FULL, BYE_BUILD, BYE_DROPPED = 0, 1, 2, 3

# a slot nobody is in, in a step: 0, -128, -128 -- id's PollControls clamps a
# turn or a move to +-100 a tic, so no player's controls are ever this
ABSENT = bytes([0, 0x80, 0x80])


def bye(slot, reason=BYE_END):
    return head(BYE) + bytes([slot, reason])


def un_bye(b):
    return b[0], (b[1] if len(b) >= 2 else BYE_END)


def chat(slot, number, text, kind=CHAT):
    t = text.encode("latin-1")[:60]
    return head(kind) + bytes([slot, number & 0xFF, len(t)]) + t


def un_chat(b):
    slot, number, n = b[:3]
    return slot, number, b[3:3 + n].decode("latin-1")


def names(names):
    """NAMES (type 11, since 2026-10-08): every slot's name, "" for an
    empty one -- 16 bytes each, NUL-padded."""
    out = head(PLAYERS) + bytes([len(names)])
    for n in names:
        out += n.encode("latin-1")[:16].ljust(16, b"\0")
    return out


def un_names(b):
    return [b[1 + 16 * i:17 + 16 * i].split(b"\0")[0].decode("latin-1") for i in range(b[0])]


# the rules' bits 3-7 (since 2026-10-08): items come back after 5 s times this
def respawn_bits(seconds):
    return max(0, min(31, (int(seconds) + 2) // 5)) << 3


def seq_newer(a, b):
    """Is 16-bit sequence number a after b (wrapping)?"""
    return a != b and ((a - b) & 0xFFFF) < 0x8000
