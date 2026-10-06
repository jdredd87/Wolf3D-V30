"""The multiplayer server, in Python -- the reference.  StevenC & Claude, 2026.

    python mp/mpserver.py [--players 2] [--map 0] [--skill 2] [--rules 0]
                          [--port 31992] [--bind 0.0.0.0] [--steps N]
                          [--record M50.DEM] [--drop 0.0] [--quiet]

It keeps the clock and passes controls along; it knows nothing of the game.
MULTIPLAYER.md, "Protocol, version 1", is what it speaks.  Players join with
HELLO; when --players have joined it sends START, and once every one of them
has sent INPUT (its level is loaded) it steps 17.5 times a second, never
waiting: each step is every player's newest controls, and each client gets
STEPS with every step after the one it last had (up to 64), so a lost packet
or a slow machine just catches up.  SYNCs are compared and a DESYNC sent if
two games part.  At the end -- --steps reached, Ctrl-C, or everyone gone --
the match is written as an Mn.DEM (--record), for TIMEDEMO MGEN.

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


def arg(name, default, kind=str):
    return kind(sys.argv[sys.argv.index(name) + 1]) if name in sys.argv else default


class Slot:
    def __init__(self, addr, name, build):
        self.addr, self.name, self.build = addr, name, build
        self.controls = b"\0\0\0"
        self.seq = None
        self.have = P.NOBODY
        self.ready = False
        self.gone = False
        self.inputs = 0


class Server:
    def __init__(self):
        self.players = arg("--players", 2, int)
        self.map = arg("--map", 0, int)
        self.skill = arg("--skill", 2, int)
        self.rules = arg("--rules", 0, int)
        self.limit = arg("--steps", 0, int)
        self.record = arg("--record", "")
        self.drop = arg("--drop", 0.0, float)
        self.quiet = "--quiet" in sys.argv
        self.rnd = random.Random(1992)
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind((arg("--bind", "0.0.0.0"), arg("--port", P.PORT, int)))
        self.sock.settimeout(0.005)
        self.slots = []
        self.history = []           # every step: players*3 bytes
        self.syncs = {}             # step -> {slot: sum}
        self.desyncs = []
        self.state = "join"
        self.started_at = None
        self.next_start = 0
        self.stats = dict(sent=0, recv=0, dropped=0)

    def log(self, *a):
        if not self.quiet:
            print("[%7.2f]" % (time.perf_counter() - T0), *a, flush=True)

    def send(self, data, addr):
        if self.drop and self.rnd.random() < self.drop:
            self.stats["dropped"] += 1
            return
        self.sock.sendto(data, addr)
        self.stats["sent"] += 1

    def slot_of(self, addr):
        for i, s in enumerate(self.slots):
            if s.addr == addr:
                return i
        return None

    def handle(self, data, addr):
        kind, b = P.parse(data)
        if kind is None:
            return
        if self.drop and self.rnd.random() < self.drop:
            self.stats["dropped"] += 1
            return
        self.stats["recv"] += 1
        i = self.slot_of(addr)
        if kind == P.HELLO:
            name, build, want = P.un_hello(b)
            if i is None:
                if self.state != "join" or len(self.slots) >= self.players:
                    self.send(P.bye(0xFF), addr)
                    return
                if self.slots and build != self.slots[0].build:
                    self.log("refused %s: build %08X, not %08X" % (name, build, self.slots[0].build))
                    self.send(P.bye(0xFF), addr)
                    return
                self.slots.append(Slot(addr, name, build))
                i = len(self.slots) - 1
                self.log("P%d joined: %s from %s:%d (build %08X)" % (i + 1, name, addr[0], addr[1], build))
            self.send(P.welcome(i, self.players, self.map, self.skill, self.rules), addr)
            if len(self.slots) == self.players and self.state == "join":
                self.state = "start"
                self.log("all %d here: START" % self.players)
        elif i is None:
            return
        elif kind == P.INPUT:
            s = self.slots[i]
            slot, buttons, turn, move, seq, have = P.un_inp(b)
            if self.state == "start" and not s.ready:
                s.ready = True
                self.log("P%d ready" % (i + 1))
            if s.seq is None or P.seq_newer(seq, s.seq):
                s.seq = seq
                s.controls = bytes([buttons, turn & 0xFF, move & 0xFF])
            if have != P.NOBODY and (s.have == P.NOBODY or have > s.have):
                s.have = have
            s.inputs += 1
        elif kind == P.SYNC:
            slot, step, total = P.un_sync(b)
            got = self.syncs.setdefault(step, {})
            got[i] = total
            live = [k for k, s in enumerate(self.slots) if not s.gone]
            if all(k in got for k in live):
                first = got[live[0]]
                mask = sum(1 << k for k in live if got[k] != first)
                if mask:
                    self.desyncs.append((step, mask))
                    self.log("DESYNC at step %d: %s" % (step, " ".join("P%d=%08X" % (k + 1, got[k]) for k in live)))
                    for s in self.slots:
                        self.send(P.desync(step, mask), s.addr)
                del self.syncs[step]
        elif kind == P.BYE:
            self.slots[i].gone = True
            self.slots[i].controls = b"\0\0\0"
            self.log("P%d left" % (i + 1))
        elif kind == P.CHAT:
            slot, number, text = P.un_chat(b)
            self.log("P%d says: %s" % (i + 1, text))
            for s in self.slots:
                if not s.gone:
                    self.send(P.chat(i, number, text, P.CHATMSG), s.addr)

    def step(self):
        row = b"".join(s.controls for s in self.slots)
        self.history.append(row)
        newest = len(self.history) - 1
        for s in self.slots:
            if s.gone:
                continue
            first = 0 if s.have == P.NOBODY else s.have + 1
            first = max(first, newest - P.STEPS_MAX + 1)
            if first <= newest:
                self.send(P.steps(first, self.players, self.history[first:newest + 1]), s.addr)

    def run(self):
        self.log("listening on UDP %d for %d players, map %d" % (self.sock.getsockname()[1], self.players, self.map))
        tick = None
        try:
            while True:
                now = time.perf_counter()
                if self.state == "start" and now >= self.next_start:
                    self.next_start = now + 0.5
                    for s in self.slots:
                        self.send(P.start(self.players, self.map, self.skill, self.rules,
                                          [(0, 0, 0, 0)] * self.players), s.addr)
                    if all(s.ready for s in self.slots):
                        self.state = "play"
                        self.started_at = now
                        tick = now
                        self.log("everyone ready: stepping")
                if self.state == "play":
                    while now >= tick:
                        self.step()
                        tick += P.STEP_SECONDS
                        if self.limit and len(self.history) >= self.limit:
                            raise StopIteration
                    if self.slots and all(s.gone for s in self.slots):
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
        for s in self.slots:
            if not s.gone:
                self.send(P.bye(0xFF), s.addr)
        self.finish()

    def finish(self):
        n = len(self.history)
        took = time.perf_counter() - self.started_at if self.started_at else 0
        self.log("ended: %d steps in %.1f s (%.2f a second); packets sent %d, received %d, dropped %d; %d desyncs"
                 % (n, took, n / took if took else 0, self.stats["sent"], self.stats["recv"],
                    self.stats["dropped"], len(self.desyncs)))
        for i, s in enumerate(self.slots):
            self.log("  P%d %s: %d inputs, had step %s" % (i + 1, s.name, s.inputs,
                                                         "none" if s.have == P.NOBODY else s.have))
        if self.record and n:
            per = 3 * self.players
            frames = min(n, (65535 - 4) // per)
            body = b"".join(self.history[:frames])
            demo = bytes([self.map]) + struct.pack("<H", 4 + per * frames) + b"\0" + body
            data = b"M" + bytes([self.players]) + bytes(4 * self.players) + demo
            open(self.record, "wb").write(data)
            self.log("recorded %d steps as %s" % (frames, self.record))


T0 = time.perf_counter()
if __name__ == "__main__":
    Server().run()
