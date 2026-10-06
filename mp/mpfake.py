"""Fake players for the multiplayer server -- StevenC & Claude, 2026.

    python mp/mpfake.py [--server 127.0.0.1] [--port 31992] [--fps 5,30,70,17]
                        [--load 4,1,1,2] [--loss 0.05] [--corrupt K] [--out FILE]

One fake player per --fps entry, all in this process, each on its own
socket, speaking MULTIPLAYER.md's protocol: HELLO, wait for WELCOME and
START, "load" for --load seconds, then at its own frame rate send INPUT
(gendemo.py's structured random input, its own seed) and keep every STEPS
row it is given.  They play nothing -- the sum each sends in SYNC is a CRC
of the steps it holds, so two fakes agree exactly when the server gave them
the same steps.  --loss drops that fraction of what each receives and sends;
--corrupt K makes player K alter its copy of step 100, to prove a DESYNC is
caught.  At the end (the server's BYE) every fake's steps are compared with
each other and, with --out, saved (one row per line, hex) for checking
against the server's record.
"""
import os
import random
import select
import socket
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, ".."))
import mpproto as P                 # noqa: E402
import gendemo                      # noqa: E402

BUILD = 0x12345678


def arg(name, default):
    return sys.argv[sys.argv.index(name) + 1] if name in sys.argv else default


class Fake:
    def __init__(self, k, fps, load, loss, server, corrupt):
        self.k, self.fps, self.load, self.loss = k, fps, load, loss
        self.server = server
        self.corrupt = corrupt
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", 0))
        self.sock.setblocking(False)
        self.rnd = random.Random(500 + k)
        self.inputs = gendemo.inputs(random.Random(77 + k), 20000)
        self.slot = None
        self.state = "hello"
        self.rows = {}
        self.have = -1
        self.seq = 0
        self.frame = 0
        self.next = 0.0
        self.loaded_at = None
        self.synced = 0
        self.desyncs = []
        self.chats = []
        self.done = False
        self.stats = dict(steps_pkts=0, dup_rows=0)

    def send(self, data):
        if self.rnd.random() < self.loss:
            return
        try:
            self.sock.sendto(data, self.server)
        except OSError:
            pass

    def receive(self, data):
        if self.rnd.random() < self.loss:
            return
        kind, b = P.parse(data)
        if kind == P.WELCOME and self.slot is None:
            self.slot = P.un_welcome(b)["slot"]
            self.state = "welcome"
        elif kind == P.START and self.state == "welcome":
            self.state = "loading"
            self.loaded_at = time.perf_counter() + self.load
        elif kind == P.STEPS:
            first, players, rows = P.un_steps(b)
            self.stats["steps_pkts"] += 1
            for i, r in enumerate(rows):
                n = first + i
                if n in self.rows:
                    self.stats["dup_rows"] += 1
                    continue
                if n == 100 and self.corrupt == self.k:
                    r = bytes([r[0] ^ 1]) + r[1:]
                self.rows[n] = r
            while self.have + 1 in self.rows:
                self.have += 1
            while self.synced + P.SYNC_EVERY <= self.have + 1:
                self.synced += P.SYNC_EVERY
                crc = 0
                for n in range(self.synced):
                    crc = zlib.crc32(self.rows[n], crc)
                self.send(P.sync(self.slot, self.synced, crc))
        elif kind == P.DESYNC:
            self.desyncs.append(P.un_desync(b))
        elif kind == P.CHATMSG:
            self.chats.append(P.un_chat(b))
        elif kind == P.BYE:
            self.done = True

    def tick(self, now):
        if self.done or now < self.next:
            return
        if self.state in ("hello",):
            self.send(P.hello("FAKE%d" % (self.k + 1), BUILD))
            self.next = now + 0.5
        elif self.state == "loading" and now >= self.loaded_at:
            self.state = "play"
        if self.state == "play":
            b, x, y = self.inputs[self.frame % len(self.inputs)]
            self.frame += 1
            self.seq += 1
            self.send(P.inp(self.slot, b, x - 256 if x > 127 else x, y - 256 if y > 127 else y,
                            self.seq, self.have if self.have >= 0 else P.NOBODY))
            if self.frame == 30 and self.k == 0:
                self.send(P.chat(self.slot, 1, "door's over here"))
            self.next = now + 1.0 / self.fps


def main():
    server = (arg("--server", "127.0.0.1"), int(arg("--port", P.PORT)))
    fps = [float(x) for x in arg("--fps", "5,30,70,17").split(",")]
    load = [float(x) for x in arg("--load", ",".join("1" for _ in fps)).split(",")]
    loss = float(arg("--loss", "0"))
    corrupt = int(arg("--corrupt", "-1"))
    fakes = [Fake(k, fps[k], load[k], loss, server, corrupt) for k in range(len(fps))]
    deadline = time.perf_counter() + float(arg("--timeout", "300"))
    while not all(f.done for f in fakes) and time.perf_counter() < deadline:
        r, _, _ = select.select([f.sock for f in fakes], [], [], 0.002)
        for f in fakes:
            if f.sock in r:
                while True:
                    try:
                        data, _ = f.sock.recvfrom(4096)
                    except (BlockingIOError, ConnectionResetError):
                        break
                    f.receive(data)
        now = time.perf_counter()
        for f in fakes:
            f.tick(now)
    ok = True
    common = min(f.have for f in fakes) + 1
    ref = [fakes[0].rows[n] for n in range(common)]
    for f in fakes:
        mine = [f.rows[n] for n in range(common)]
        same = mine == ref
        ok &= same or corrupt >= 0
        print("FAKE%d (slot %s, %g fps): %d steps, %d STEPS packets, %d repeated rows, "
              "desyncs %s, chat %s, %s" % (f.k + 1, f.slot, f.fps, f.have + 1, f.stats["steps_pkts"],
                                           f.stats["dup_rows"], f.desyncs, f.chats,
                                           "same steps as FAKE1" if same else "STEPS DIFFER"))
    if "--out" in sys.argv:
        open(arg("--out", ""), "w").write("\n".join(r.hex() for r in ref) + "\n")
    print("%d common steps; %s" % (common, "all agree" if ok else "DISAGREE"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
