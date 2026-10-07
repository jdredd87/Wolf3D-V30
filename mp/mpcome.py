"""Comings and goings, for testing a running game -- StevenC & Claude, 2026.

    python mp/mpcome.py [--server 127.0.0.1] [--port 31992] SCRIPT...

A scripted player that does not play: it sends INPUT (gendemo.py's random
input) and keeps the steps it is sent, so the real machines in the game see
it come and go -- every one of them must do the same at the same step, and
their SYNCs say whether they did.  It sends no SYNC of its own (it has no
game to sum).  SCRIPT is a list of timed actions, seconds from the start:

    join@20      say HELLO (a new socket: a new machine) and stay
    leave@60     ESC, Y: BYE
    quiet@100    stop sending anything, as a machine that crashed
    knock@40     a separate HELLO that only reports the answer: WELCOME, or
                 BYE and its reason (full, another build)
    end@180      stop

It prints what happens, and each BYE's reason.
"""
import os
import random
import socket
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import mpproto as P                 # noqa: E402
import gendemo                      # noqa: E402

BUILD = 0x12345678
REASON = {P.BYE_END: "the end", P.BYE_FULL: "the server is full",
          P.BYE_BUILD: "another build", P.BYE_DROPPED: "dropped (not heard from)"}


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


T0 = time.perf_counter()


def log(*a):
    print("[%7.2f]" % (time.perf_counter() - T0), *a, flush=True)


class Player:
    def __init__(self, server, name):
        self.server = server
        self.name = name
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", 0))
        self.sock.setblocking(False)
        self.slot = None
        self.started = False
        self.have = -1
        self.rows = {}
        self.seq = 0
        self.quiet = False
        self.over = False
        self.inputs = iter(gendemo.inputs(random.Random(77), 10 ** 5))
        self.next_hello = 0
        self.next_input = 0

    def send(self, data):
        if not self.quiet:
            self.sock.sendto(data, self.server)

    def pump(self, now):
        while True:
            try:
                data, _ = self.sock.recvfrom(4096)
            except (BlockingIOError, ConnectionResetError):
                break
            kind, b = P.parse(data)
            if kind == P.WELCOME and self.slot is None:
                self.slot = P.un_welcome(b)["slot"]
                log("%s: WELCOME, slot P%d" % (self.name, self.slot + 1))
            elif kind == P.START and not self.started:
                self.started = True
                log("%s: START" % self.name)
            elif kind == P.STEPS:
                first, players, rows = P.un_steps(b)
                for k, r in enumerate(rows):
                    self.rows[first + k] = r
                while self.have + 1 in self.rows:
                    self.have += 1
            elif kind == P.BYE and not self.over:
                slot, reason = P.un_bye(b)
                self.over = True
                log("%s: BYE -- %s" % (self.name, REASON.get(reason, reason)))
        if self.over or self.quiet:
            return
        if self.slot is None and now >= self.next_hello:
            self.next_hello = now + 0.5
            self.send(P.hello(self.name, BUILD))
        if self.started and now >= self.next_input:
            self.next_input = now + 2 / 70
            b, x, y = next(self.inputs)
            self.seq += 1
            have = self.have if self.have >= 0 else P.NOBODY
            self.send(P.inp(self.slot, b, x - 256 if x > 127 else x, y - 256 if y > 127 else y,
                            self.seq, have, have))

    def bye(self):
        for k in range(3):
            self.send(P.bye(self.slot if self.slot is not None else 0xFF))
        self.over = True


def main():
    server = (arg("--server", "127.0.0.1"), int(arg("--port", P.PORT)))
    script = []
    for a in sys.argv[1:]:
        if "@" in a:
            what, when = a.split("@")
            script.append((float(when), what))
    script.sort()
    players = []
    me = None
    n = 0
    while script or any(not p.over for p in players):
        now = time.perf_counter() - T0
        while script and script[0][0] <= now:
            _, what = script.pop(0)
            if what == "join":
                n += 1
                me = Player(server, "COMER%d" % n)
                players.append(me)
                log("%s: HELLO" % me.name)
            elif what == "leave" and me:
                log("%s: leaving (BYE)" % me.name)
                me.bye()
            elif what == "quiet" and me:
                log("%s: going quiet" % me.name)
                me.quiet = True
            elif what == "knock":
                n += 1
                k = Player(server, "KNOCK%d" % n)
                players.append(k)
                log("%s: HELLO" % k.name)
            elif what == "end":
                script = []
                for p in players:
                    p.over = True
        for p in players:
            p.pump(now)
            if p.name.startswith("KNOCK") and p.slot is not None and not p.over:
                log("%s: let in -- leaving again" % p.name)
                p.bye()
        time.sleep(0.005)
    log("done")


if __name__ == "__main__":
    main()
