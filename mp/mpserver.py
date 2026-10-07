"""The multiplayer server, in Python -- the reference.  StevenC & Claude, 2026.

    python mp/mpserver.py [--players 4] [--bots 0] [--map 0] [--skill 2]
                          [--mode coop|dm] [--ff on|off] [--noenemies]
                          [--fraglimit N] [--timelimit MIN]
                          [--port 31992] [--bind 0.0.0.0] [--steps N] [--once]
                          [--drop-after 30] [--record M50.DEM] [--drop 0.0] [--quiet]

It keeps the clock and passes controls along; it knows nothing of the game.
MULTIPLAYER.md, "Protocol, version 1", is what it speaks.

It runs by itself, and people come and go (StevenC, 2026-10-07: "once a
server runs, people can join and leave as needed").  --players is the number
of slots, four at most.  The game starts the moment the first player has
loaded the level; anyone else who joins while it runs gets every step from
the first, plays them fast to catch up, and is let into the game -- the
other machines see the player arrive -- once caught up.  A slot is free
again when its player leaves (ESC, Y), or when its machine has not been
heard from for --drop-after seconds (30: a V30 loading a floor is quiet for
ten or so); the server tells it so.  A player who finds every slot taken is
told the server is full.  When the last player has gone the game is over;
the server waits for the next one, who starts a new game -- or, with --once,
stops.  --steps N stops it after N steps (for tests).

A slot's presence is in every step: an empty slot's 3 bytes are 0, -128,
-128 (mpproto.ABSENT), which no player's controls ever are.  Every machine
plays every step, so every machine sees a player arrive or leave at the same
step.

--bots N of the slots are the server's own, the last ones, in the game from
the first step: they play gendemo.py's structured random input (runs, turns,
strafes, fire, use), so two machines can try a four-player game.  They cannot
aim: the server does not run the game.

The rules go to every machine in WELCOME and START (MULTIPLAYER.md, "Modes
and rules"): --mode coop (the default) or dm (deathmatch); --ff off turns
friendly fire off in co-op (on by default, as DOOM's); --noenemies spawns
no enemies; --fraglimit and --timelimit end a deathmatch level.

SYNCs are compared step by step -- the first machine to report a step sets
its sum, and any other that differs is told DESYNC -- so a machine that
joined late is checked against the ones that played those steps live.

--record writes each game, when it ends, as an Mn.DEM for TIMEDEMO MGEN.
--drop P throws away that fraction of packets each way, for testing.  On
Windows the port needs an inbound firewall rule (UDP 31992, local subnet).
"""
import os
import random
import socket
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import mpproto as P                 # noqa: E402
sys.path.insert(0, os.path.join(HERE, ".."))
import gendemo                      # noqa: E402  (the bots' input)

RULE_DM, RULE_NOFF, RULE_NOENEMIES = 1, 2, 4
CAUGHT_UP = 4                       # steps behind the newest: let it in
JOIN_SILENT = 60                    # seconds: a join that never loaded


def arg(name, default, kind=str):
    return kind(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default


class Slot:
    def __init__(self, addr, name, build):
        self.addr, self.name, self.build = addr, name, build
        self.controls = b"\0\0\0"
        self.seq = None
        self.have = P.NOBODY        # the newest step it holds with none missing
        self.played = None          # the newest step it has played (None: no word)
        self.ready = False          # its level is loaded
        self.present = False        # in the game: its controls are in the steps
        self.inputs = 0
        self.heard = time.perf_counter()
        self.bot = None             # a bot: its input, a step at a time
        self.sent_first = self.sent_last = None     # the last STEPS sent it
        self.sent_at = 0


class Server:
    def __init__(self):
        self.players = max(1, min(4, arg("--players", 4, int)))
        self.map = arg("--map", 0, int)
        self.skill = arg("--skill", 2, int)
        self.bots = max(0, min(self.players - 1, arg("--bots", 0, int)))
        self.humans = self.players - self.bots
        self.rules = arg("--rules", 0, int)
        if arg("--mode", "coop") == "dm":
            self.rules |= RULE_DM
        if arg("--ff", "on") == "off":
            self.rules |= RULE_NOFF
        if "--noenemies" in sys.argv:
            self.rules |= RULE_NOENEMIES
        self.frags = arg("--fraglimit", 0, int)
        self.minutes = arg("--timelimit", 0, int)
        self.limit = arg("--steps", 0, int)
        self.once = "--once" in sys.argv
        self.drop_after = arg("--drop-after", 30, float)
        self.record = arg("--record", "")
        self.drop = arg("--drop", 0.0, float)
        self.quiet = "--quiet" in sys.argv
        self.rnd = random.Random(1992)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((arg("--bind", "0.0.0.0"), arg("--port", P.PORT, int)))
        self.sock.settimeout(0.005)
        self.slots = [None] * self.players     # the bots take the last: reset()
        self.games = 0
        self.stats = dict(sent=0, recv=0, dropped=0)
        self.desyncs = 0
        self.reset()

    def new_bot(self, k):
        b = Slot(None, "BOT%d" % (k + 1), 0)
        b.bot = iter(gendemo.inputs(random.Random(4242 + k), 10 ** 6))  # 16 hours
        b.seed = 4242 + k
        b.ready = b.present = True
        return b

    def reset(self):
        """No game: waiting for a first player."""
        self.state = "wait"
        self.history = []           # every step: players*3 bytes
        self.sums = {}              # step -> (sum, slot) as first reported
        self.started_at = None
        self.next_start = 0
        for k in range(self.bots):              # a new game's bots play anew
            self.slots[self.humans + k] = self.new_bot(k)

    def log(self, *a):
        if not self.quiet:
            print("[%7.2f]" % (time.perf_counter() - T0), *a, flush=True)

    def send(self, data, addr):
        if self.drop and self.rnd.random() < self.drop:
            self.stats["dropped"] += 1
            return
        try:
            self.sock.sendto(data, addr)
        except OSError:
            pass
        self.stats["sent"] += 1

    def slot_of(self, addr):
        for i, s in enumerate(self.slots):
            if s and not s.bot and s.addr == addr:
                return i
        return None

    def people(self):
        return [i for i, s in enumerate(self.slots) if s and not s.bot]

    def who(self, i):
        s = self.slots[i]
        return "P%d %s" % (i + 1, s.name if s else "")

    # ---- coming and going

    def join(self, addr, name, build):
        free = [k for k in range(self.humans) if self.slots[k] is None]
        if not free:
            self.log("refused %s from %s:%d: the server is full" % (name, addr[0], addr[1]))
            self.send(P.bye(0xFF, P.BYE_FULL), addr)
            return None
        others = [self.slots[k].build for k in self.people()]
        if others and build != others[0]:
            self.log("refused %s: build %08X, not %08X" % (name, build, others[0]))
            self.send(P.bye(0xFF, P.BYE_BUILD), addr)
            return None
        i = free[0]
        self.slots[i] = Slot(addr, name, build)
        self.log("%s joined from %s:%d (build %08X)%s" % (self.who(i), addr[0], addr[1], build,
                 "" if self.state == "wait" else ", into a game at step %d" % len(self.history)))
        return i

    def leave(self, i, why, reason=None):
        s = self.slots[i]
        if reason is not None:
            for k in range(3):                  # UDP: it may be lost
                self.send(P.bye(i, reason), s.addr)
        self.log("%s %s (%d inputs, had step %s)" % (self.who(i), why, s.inputs,
                 "none" if s.have == P.NOBODY else s.have))
        self.slots[i] = None
        if self.state == "play" and not self.people():
            self.game_over("everyone has left")

    def game_over(self, why):
        n = len(self.history)
        took = time.perf_counter() - self.started_at if self.started_at else 0
        self.log("game over, %s: %d steps in %.1f s (%.2f a second)"
                 % (why, n, took, n / took if took else 0))
        self.write_record()
        self.games += 1
        self.reset()
        if self.once:
            raise StopIteration
        self.log("waiting for players")

    # ---- packets

    def handle(self, data, addr):
        kind, b = P.parse(data)
        if kind is None:
            return
        if self.drop and self.rnd.random() < self.drop:
            self.stats["dropped"] += 1
            return
        self.stats["recv"] += 1
        i = self.slot_of(addr)
        if i is not None:
            self.slots[i].heard = time.perf_counter()
        if kind == P.HELLO:
            name, build, want = P.un_hello(b)
            if i is not None and self.slots[i].ready:
                # a machine that is in the game says HELLO again: it was
                # restarted.  Its old self leaves; it joins anew
                self.leave(i, "is back (restarted)")
                i = None
            if i is None:
                i = self.join(addr, name, build)
                if i is None:
                    return
            self.send(P.welcome(i, self.players, self.map, self.skill, self.rules,
                                self.frags, self.minutes), addr)
            self.send(self.start_packet(), addr)
            return
        if i is None:
            if kind == P.INPUT:                 # from a slot already let go:
                self.send(P.bye(0xFF, P.BYE_DROPPED), addr)     # say so again
            return
        s = self.slots[i]
        if kind == P.INPUT:
            slot, buttons, turn, move, seq, have, played = P.un_inp(b)
            if not s.ready:
                s.ready = True
                if self.state == "wait":
                    self.state = "play"
                    self.started_at = time.perf_counter()
                    self.tick = self.started_at
                    self.log("%s has loaded the level: the game starts" % self.who(i))
                else:
                    self.log("%s has loaded the level: catching up from step 0 of %d"
                             % (self.who(i), len(self.history)))
            if s.seq is None or P.seq_newer(seq, s.seq):
                s.seq = seq
                s.controls = bytes([buttons, turn & 0xFF, move & 0xFF])
            if have != P.NOBODY and (s.have == P.NOBODY or have > s.have):
                s.have = have
            if played is not None:
                s.played = None if played == P.NOBODY else played
            s.inputs += 1
        elif kind == P.SYNC:
            slot, step, total = P.un_sync(b)
            first = self.sums.get(step)
            if first is None:
                self.sums[step] = (total, i)
            elif first[0] != total:
                self.desyncs += 1
                self.log("DESYNC at step %d: %s has %08X, %s had %08X"
                         % (step, self.who(i), total, self.who(first[1]) if self.slots[first[1]] else
                            "P%d" % (first[1] + 1), first[0]))
                self.send(P.desync(step, 1 << i), s.addr)
        elif kind == P.BYE:
            self.leave(i, "left")
        elif kind == P.CHAT:
            slot, number, text = P.un_chat(b)
            self.log("%s says: %s" % (self.who(i), text))
            for k in self.people():
                self.send(P.chat(i, number, text, P.CHATMSG), self.slots[k].addr)

    def start_packet(self):
        return P.start(self.players, self.map, self.skill, self.rules, [(0, 0, 0, 0)] * self.players)

    # ---- the clock

    def step(self):
        newest = len(self.history) - 1
        row = b""
        for i, s in enumerate(self.slots):
            if s is None:
                row += P.ABSENT
            elif s.bot:
                c = next(s.bot, None)
                if c is None:           # 16 hours of play used up: more of it
                    s.seed += 1000
                    s.bot = iter(gendemo.inputs(random.Random(s.seed), 10 ** 6))
                    c = next(s.bot)
                row += bytes(c)
            else:
                if not s.present and s.ready:
                    # a player is let in once caught up: it has played (or,
                    # from an older client, holds) all but the last few steps
                    done = s.played if s.played is not None else (
                        None if s.have == P.NOBODY else s.have)
                    if newest < 0 or (done is not None and done >= newest - CAUGHT_UP):
                        s.present = True
                        if newest >= 0:
                            self.log("%s is in the game at step %d" % (self.who(i), newest + 1))
                row += s.controls if s.present else P.ABSENT
        self.history.append(row)
        newest += 1
        for i in self.people():
            s = self.slots[i]
            if not s.ready:
                continue
            # from the first step it lacks: a machine that fell behind (a
            # level loading on a V30, or one joining late) catches up
            # STEPS_MAX at a time
            first = 0 if s.have == P.NOBODY else s.have + 1
            last = min(newest, first + P.STEPS_MAX - 1)
            if first > newest:
                continue
            # a machine busy catching up says what it has only now and then:
            # the same steps again at most 4 times a second (each copy cost a
            # V30 catching up its time to take in, 17 a second)
            now = time.perf_counter()
            if first == s.sent_first and last == s.sent_last and now - s.sent_at < 0.25:
                continue
            s.sent_first, s.sent_last, s.sent_at = first, last, now
            self.send(P.steps(first, self.players, self.history[first:last + 1]), s.addr)

    def run(self):
        self.log("listening on UDP %d: %d slots (%d for people, %d bots), map %d, rules %d"
                 % (self.sock.getsockname()[1], self.players, self.humans, self.bots, self.map, self.rules))
        try:
            while True:
                now = time.perf_counter()
                if now >= self.next_start:      # START again to any still loading
                    self.next_start = now + 0.5
                    for i in self.people():
                        if not self.slots[i].ready:
                            self.send(self.start_packet(), self.slots[i].addr)
                for i in self.people():         # machines gone quiet
                    s = self.slots[i]
                    quiet = now - s.heard
                    if s.ready and quiet > self.drop_after:
                        self.leave(i, "was not heard from for %d s: its slot is free" % quiet,
                                   P.BYE_DROPPED)
                    elif not s.ready and quiet > JOIN_SILENT:
                        self.leave(i, "never loaded the level: its slot is free")
                if self.state == "play":
                    while now >= self.tick:
                        self.step()
                        self.tick += P.STEP_SECONDS
                        if self.limit and len(self.history) >= self.limit:
                            raise StopIteration
                try:
                    data, addr = self.sock.recvfrom(2048)
                    self.handle(data, addr)
                except socket.timeout:
                    pass
                except ConnectionResetError:
                    pass                # Windows: an ICMP port-unreachable
        except (KeyboardInterrupt, StopIteration):
            pass
        for k in range(5):              # UDP: one BYE lost left a V30 waiting
            for i in self.people():     # for steps that never came
                self.send(P.bye(i, P.BYE_END), self.slots[i].addr)
            time.sleep(0.05)
        self.finish()

    def finish(self):
        if self.state == "play":
            n = len(self.history)
            took = time.perf_counter() - self.started_at if self.started_at else 0
            self.log("ended: %d steps in %.1f s (%.2f a second); packets sent %d, received %d, dropped %d; %d desyncs"
                     % (n, took, n / took if took else 0, self.stats["sent"], self.stats["recv"],
                        self.stats["dropped"], self.desyncs))
            for i, s in enumerate(self.slots):
                if s:
                    self.log("  %s: %d inputs, had step %s" % (self.who(i), s.inputs,
                             "none" if s.have == P.NOBODY else s.have))
            self.write_record()
        else:
            self.log("ended with no game running; packets sent %d, received %d; %d desyncs"
                     % (self.stats["sent"], self.stats["recv"], self.desyncs))

    def write_record(self):
        n = len(self.history)
        if not self.record or not n:
            return
        per = 3 * self.players
        frames = min(n, (65535 - 4) // per)
        body = b"".join(self.history[:frames])
        demo = bytes([self.map]) + struct.pack("<H", 4 + per * frames) + b"\0" + body
        # P1's start's 4th byte: the skill + 1 (0 = id's demos' own, hard)
        # P2's start's 4th byte: the rules
        starts = bytes([0, 0, 0, self.skill + 1])
        if self.players > 1:
            starts += bytes([0, 0, 0, self.rules]) + bytes(4 * (self.players - 2))
        data = b"M" + bytes([self.players]) + starts + demo
        name = self.record
        if self.games:                  # a second game on: M50.DEM, M50B.DEM ...
            base, ext = os.path.splitext(self.record)
            name = base + chr(ord("A") + self.games) + ext
        open(name, "wb").write(data)
        self.log("recorded %d steps as %s" % (frames, name))


T0 = time.perf_counter()
if __name__ == "__main__":
    Server().run()
