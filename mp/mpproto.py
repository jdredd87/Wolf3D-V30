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
# PAUSED (2026-10-13): the server's console paused the game (1) or let it go
# on (0).  No steps come while it is paused; this says why, and keeps the
# players' "No word from the server" box away
PAUSED = 14
# DISCOVER / INFO (2026-10-17): LAN discovery.  A game broadcasts DISCOVER
# (and its build) on the port; every server answers INFO -- what it is
# playing, and who -- to the address it came from
DISCOVER, INFO = 15, 16
NAMES = {HELLO: "HELLO", WELCOME: "WELCOME", START: "START", INPUT: "INPUT", STEPS: "STEPS",
         SYNC: "SYNC", DESYNC: "DESYNC", BYE: "BYE", CHAT: "CHAT", CHATMSG: "CHATMSG",
         PLAYERS: "NAMES", HANG: "HANG", PAUSED: "PAUSED", DISCOVER: "DISCOVER", INFO: "INFO"}
# the server's events (2026-10-13), in STEPS' tail: each at a step, so every
# machine -- and every joiner, replaying -- applies it at the same one
EV_NEXTFLOOR, EV_MAP, EV_TIMELIMIT, EV_FRAGLIMIT = 1, 2, 4, 5
SERVER_SLOT = 0xFF              # CHATMSG from the server itself (its console's say)
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


def welcome(slot, players, mapnum, skill, rules, frags=0, minutes=0, joinstep=0):
    """joinstep (2026-10-14): the step the machine joins at -- its slot's
    presence before it belonged to whoever held the slot then"""
    return head(WELCOME) + struct.pack("<6BHHI", slot, players, mapnum, skill, rules, 0, frags, minutes,
                                       joinstep)


def un_welcome(b):
    slot, players, mapnum, skill, rules, _, frags, minutes = struct.unpack_from("<6BHH", b)
    return dict(slot=slot, players=players, map=mapnum, skill=skill, rules=rules, frags=frags, minutes=minutes)


def start(players, mapnum, skill, rules, starts, rules2=0):
    """rules2, after the starts (2026-10-17): 1 teams (Gold P1+P3, Silver
    P2+P4), 2 capture the flag (with 1).  A game older than it stops reading
    at the starts, and one that finds no byte there takes 0."""
    out = head(START) + bytes([players, mapnum, skill, rules])
    for s in starts:
        out += bytes(s)
    return out + bytes([rules2])


def un_start(b):
    players, mapnum, skill, rules = b[:4]
    starts = [tuple(b[4 + 4 * i:8 + 4 * i]) for i in range(players)]
    rules2 = b[4 + 4 * players] if len(b) > 4 + 4 * players else 0
    return dict(players=players, map=mapnum, skill=skill, rules=rules, starts=starts, rules2=rules2)


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


def steps(first, players, rows, events=(), newest=None):
    """rows: a list of `players*3`-byte steps.  events: (step, event,
    argument) for steps among these -- a tail the game reads since
    2026-10-13 (a count, then 7 bytes each); an older game ignores it.
    newest (2026-10-17): the server's newest step, after the events (a
    count of 0 first if there are none) -- how far a joiner has to go."""
    out = head(STEPS) + struct.pack("<IBB", first, len(rows), players) + b"".join(rows)
    events = list(events)[:20]
    if events or newest is not None:
        out += bytes([len(events)]) + b"".join(struct.pack("<IBH", s, e, a & 0xFFFF)
                                               for s, e, a in events)
    if newest is not None:
        out += struct.pack("<I", newest & 0xFFFFFFFF)
    return out


def un_steps(b):
    first, count, players = struct.unpack_from("<IBB", b)
    n = 3 * players
    rows = [bytes(b[6 + i * n:6 + (i + 1) * n]) for i in range(count)]
    return first, players, rows


def un_steps_events(b):
    """STEPS' tail: [(step, event, argument)]."""
    first, count, players = struct.unpack_from("<IBB", b)
    off = 6 + count * 3 * players
    if len(b) <= off:
        return []
    return [struct.unpack_from("<IBH", b, off + 1 + 7 * i) for i in range(b[off])
            if len(b) >= off + 1 + 7 * (i + 1)]


def sync(slot, step, total):
    return head(SYNC) + struct.pack("<BBII", slot, 0, step, total & 0xFFFFFFFF)


def un_sync(b):
    slot, _, step, total = struct.unpack_from("<BBII", b)
    return slot, step, total


def un_sync_scores(b):
    """Since 2026-10-13 a SYNC ends in every slot's frags and deaths, as
    that machine has them -- [(frags, deaths)] x 4, or None from an older one."""
    if len(b) < 10 + 16:
        return None
    v = struct.unpack_from("<8h", b, 10)
    return [(v[2 * i], v[2 * i + 1]) for i in range(4)]


def desync(step, mask):
    return head(DESYNC) + struct.pack("<IB", step, mask)


def un_desync(b):
    return struct.unpack_from("<IB", b)


# BYE's reason (since 2026-10-07; a client older than that ignores it).
# BYE_KICKED (2026-10-13) is followed by its reason's length and text
BYE_END, BYE_FULL, BYE_BUILD, BYE_DROPPED, BYE_KICKED = 0, 1, 2, 3, 4

# a slot nobody is in, in a step: 0, -128, -128 -- id's PollControls clamps a
# turn or a move to +-100 a tic, so no player's controls are ever this
ABSENT = bytes([0, 0x80, 0x80])


def bye(slot, reason=BYE_END, text=""):
    out = head(BYE) + bytes([slot, reason])
    if reason == BYE_KICKED:
        t = text.encode("latin-1", "replace")[:40]
        out += bytes([len(t)]) + t
    return out


def un_bye(b):
    return b[0], (b[1] if len(b) >= 2 else BYE_END)


def discover(build):
    return head(DISCOVER) + struct.pack("<I", build)


def info(playing, slots, people, bots, watchers, mapnum, skill, rules, rules2, step, build, name, names):
    """INFO: state (0 waiting, 1 playing), slots, people in, bots, spectators,
    map, skill, rules, rules2, pad, step (u32), the build being played (u32,
    0: none yet), the server's name (16), every slot's name (4 x 16)."""
    out = head(INFO) + bytes([playing, slots, people, bots, watchers, mapnum, skill, rules, rules2, 0])
    out += struct.pack("<II", step & 0xFFFFFFFF, build & 0xFFFFFFFF)
    out += name.encode("latin-1", "replace")[:16].ljust(16, b"\0")
    for k in range(4):
        n = names[k] if k < len(names) else ""
        out += n.encode("latin-1", "replace")[:16].ljust(16, b"\0")
    return out


def un_info(b):
    v = struct.unpack_from("<10BII", b)
    name = b[18:34].split(b"\0")[0].decode("latin-1")
    names = [b[34 + 16 * k:50 + 16 * k].split(b"\0")[0].decode("latin-1") for k in range(4)]
    return dict(playing=v[0], slots=v[1], people=v[2], bots=v[3], watchers=v[4], map=v[5], skill=v[6],
                rules=v[7], rules2=v[8], step=v[10], build=v[11], name=name, names=names)


def paused(on, slot=0):
    """on: 0 going again, 1 the console paused it, 2 (2026-10-17) everyone
    waits for a joiner to catch up -- slot, the one waited for, follows.  A
    game older than 2 takes it as 1."""
    return head(PAUSED) + bytes([int(on), slot])


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
