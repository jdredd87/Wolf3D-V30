"""The multiplayer server's console -- StevenC & Claude, 2026-10-12.

Commands typed into the server's window while it runs (StevenC: "do we have
options inside it? to kick users, send messages, change levels or episodes
... make it a full fledged server to control everything?").  This is the
first half, the server's own: nothing in it needs a new game build.

    help                     this list
    status                   the game, and every slot: who, where from, how far
                             behind, inputs, how long since last heard
    kick N [reason]          slot N (1-4) out of the game; its machine is told
    ban N | ban ADDRESS      kick, and refuse that address from now on
    unban ADDRESS | bans     ... and back again; the list
    end [reason]             end the game for everyone; the server waits for
                             the next one (or stops, with --once)
    next                     the settings the next game starts with
    next map E L | next map N    episode and floor (N = (E-1)*10 + L-1)
    next mode dm|coop        next skill 0-3      next bots N
    next timelimit MIN       next fraglimit N    next itemrespawn SECS
    next enemies on|off      next ff on|off
    quiet on|off             the log's lines off, or on again
    quit                     end the game and stop the server

"next" settings take effect when the next game starts -- at once if none is
running -- since every machine in a game must be playing the same rules.

Lines are read on a thread of their own and carried out by the server's own
loop (Console.poll), between packets, so nothing here races the game.  With
no console -- input from a pipe that ends, or none -- it simply does nothing.
"""
import queue
import sys
import threading
import time

HELP = __doc__[__doc__.index("    help"):__doc__.index('"next" settings')].rstrip()


class Console:
    def __init__(self, server, P, rule_dm, rule_noff, rule_noenemies):
        self.s = server
        self.P = P
        self.RULE_DM, self.RULE_NOFF, self.RULE_NOENEMIES = rule_dm, rule_noff, rule_noenemies
        self.lines = queue.Queue()
        self.pending = {}               # "next" settings, for the next game
        self.banned = set()

    # ---- input, on its own thread

    def start(self, stream=None):
        stream = stream or sys.stdin
        if stream is None:
            return
        t = threading.Thread(target=self._read, args=(stream,), daemon=True)
        t.start()

    def _read(self, stream):
        try:
            for line in stream:
                self.lines.put(line.strip())
        except (OSError, ValueError):
            pass

    # ---- the server's loop calls these

    def poll(self):
        """Carry out whatever has been typed.  Returns False on quit."""
        while True:
            try:
                line = self.lines.get_nowait()
            except queue.Empty:
                return True
            if line and not self.do(line):
                return False

    def refused(self, addr):
        """A HELLO from a banned address?"""
        return addr[0] in self.banned

    def apply_next(self):
        """The pending "next" settings, now: no game is running."""
        s, P = self.s, self.P
        if not self.pending:
            return
        p, self.pending = self.pending, {}
        if "map" in p:
            s.map = p["map"]
        if "skill" in p:
            s.skill = p["skill"]
        rules = s.rules & 7
        if "mode" in p:
            rules = (rules | self.RULE_DM) if p["mode"] == "dm" else (rules & ~self.RULE_DM)
            if "itemrespawn" not in p:          # each mode's default, as at start-up:
                p["itemrespawn"] = 30 if p["mode"] == "dm" else 0   # 30 s, or never
        if "enemies" in p:
            rules = (rules & ~self.RULE_NOENEMIES) if p["enemies"] else (rules | self.RULE_NOENEMIES)
        if "ff" in p:
            rules = (rules & ~self.RULE_NOFF) if p["ff"] else (rules | self.RULE_NOFF)
        respawn = p.get("itemrespawn", (s.rules >> 3) * 5)
        s.respawn = respawn
        s.rules = (rules & 7) | P.respawn_bits(respawn)
        if "timelimit" in p:
            s.minutes = p["timelimit"]
        if "fraglimit" in p:
            s.frags = p["fraglimit"]
        if "bots" in p:
            n = max(0, min(s.players - 1, p["bots"]))
            if any(s.slots[k] and not s.slots[k].bot for k in range(s.players - n, s.players)):
                self.say("bots: a person is in a slot the bots would take -- left at %d" % s.bots)
            else:
                for k in range(s.players):
                    if s.slots[k] and s.slots[k].bot:
                        s.slots[k] = None
                s.bots, s.humans = n, s.players - n
                for k in range(s.bots):
                    s.slots[s.humans + k] = s.new_bot(k)
        self.say("now: " + self.settings())

    # ---- the commands

    def say(self, text):
        print("[console] " + text, flush=True)

    def settings(self):
        s = self.s
        r = s.rules
        e, l = s.map // 10 + 1, s.map % 10 + 1
        parts = ["map %d (E%dL%d)" % (s.map, e, l), "deathmatch" if r & self.RULE_DM else "co-op",
                 "skill %d" % s.skill, "bots %d" % s.bots,
                 "enemies %s" % ("off" if r & self.RULE_NOENEMIES else "on"),
                 "ff %s" % ("off" if r & self.RULE_NOFF else "on"),
                 "items back %s" % ("after %d s" % ((r >> 3) * 5) if r >> 3 else "never")]
        if s.minutes:
            parts.append("timelimit %d" % s.minutes)
        if s.frags:
            parts.append("fraglimit %d" % s.frags)
        return ", ".join(parts)

    def slot(self, word):
        try:
            i = int(word) - 1
        except ValueError:
            return None
        if 0 <= i < self.s.players and self.s.slots[i] and not self.s.slots[i].bot:
            return i
        return None

    def do(self, line):
        s, P = self.s, self.P
        w = line.split()
        cmd, rest = w[0].lower(), w[1:]
        try:
            if cmd in ("help", "?"):
                print(HELP, flush=True)
            elif cmd in ("status", "players", "st"):
                self.status()
            elif cmd == "kick":
                i = self.slot(rest[0]) if rest else None
                if i is None:
                    self.say("kick: no person in slot %s" % (rest[0] if rest else "?"))
                else:
                    why = " ".join(rest[1:]) or "kicked"
                    s.leave(i, "was kicked from the console (%s)" % why, P.BYE_DROPPED)
            elif cmd == "ban":
                if not rest:
                    self.say("ban: a slot (1-4) or an address")
                    return True
                i = self.slot(rest[0])
                addr = s.slots[i].addr[0] if i is not None else rest[0]
                self.banned.add(addr)
                self.say("banned %s" % addr)
                for k in s.people():
                    if s.slots[k].addr[0] == addr:
                        s.leave(k, "was banned from the console", P.BYE_DROPPED)
            elif cmd == "unban":
                if rest and rest[0] in self.banned:
                    self.banned.discard(rest[0])
                    self.say("unbanned %s" % rest[0])
                else:
                    self.say("unban: not banned: %s" % (rest[0] if rest else "?"))
            elif cmd == "bans":
                self.say("banned: %s" % (", ".join(sorted(self.banned)) or "nobody"))
            elif cmd == "end":
                if s.state != "play":
                    self.say("end: no game is running")
                else:
                    for k in range(3):
                        for i in s.people():
                            s.send(P.bye(i, P.BYE_END), s.slots[i].addr)
                    for i in s.people():
                        s.slots[i] = None
                    try:
                        s.game_over("ended from the console" + (" (%s)" % " ".join(rest) if rest else ""))
                    except StopIteration:
                        return False
            elif cmd == "next":
                self.next(rest)
            elif cmd == "quiet":
                s.quiet = bool(rest) and rest[0].lower() == "on"
                self.say("log %s" % ("off" if s.quiet else "on"))
            elif cmd in ("quit", "exit"):
                self.say("stopping")
                return False
            else:
                self.say("unknown: %s -- try help" % cmd)
        except (IndexError, ValueError) as e:
            self.say("%s: %s -- try help" % (cmd, e))
        return True

    def next(self, w):
        if not w:
            self.say("now: " + self.settings())
            if self.pending:
                self.say("next game: " + ", ".join("%s %s" % kv for kv in sorted(self.pending.items())))
            return
        what = w[0].lower()
        if what == "map":
            if len(w) >= 3:
                e, l = int(w[1]), int(w[2])
                if not (1 <= e <= 6 and 1 <= l <= 10):
                    raise ValueError("episode 1-6, floor 1-10")
                n = (e - 1) * 10 + (l - 1)
            else:
                n = int(w[1])
                if not 0 <= n <= 59:
                    raise ValueError("map 0-59")
            self.pending["map"] = n
        elif what == "mode":
            if w[1].lower() not in ("dm", "coop"):
                raise ValueError("dm or coop")
            self.pending["mode"] = w[1].lower()
        elif what in ("skill", "bots", "timelimit", "fraglimit", "itemrespawn"):
            v = int(w[1])
            if v < 0 or (what == "skill" and v > 3) or (what == "itemrespawn" and v > 155):
                raise ValueError("out of range")
            self.pending[what] = v
        elif what in ("enemies", "ff"):
            if w[1].lower() not in ("on", "off"):
                raise ValueError("on or off")
            self.pending[what] = w[1].lower() == "on"
        else:
            raise ValueError("next what?")
        if self.s.state != "play":
            self.apply_next()
        else:
            self.say("next game: %s %s" % (what, " ".join(w[1:])))

    def status(self):
        s, P = self.s, self.P
        now = time.perf_counter()
        if s.state == "play":
            took = now - s.started_at
            self.say("playing: step %d, %d:%02d in; %s" % (len(s.history), took // 60, took % 60, self.settings()))
        else:
            self.say("waiting for players; %s" % self.settings())
        newest = len(s.history) - 1
        for i, sl in enumerate(s.slots):
            if sl is None:
                self.say("  P%d  (empty)" % (i + 1))
            elif sl.bot:
                self.say("  P%d  %-16s the server's bot" % (i + 1, sl.name))
            else:
                have = "none" if sl.have == P.NOBODY else sl.have
                behind = "" if sl.have == P.NOBODY or newest < 0 else ", %d behind" % max(0, newest - sl.have)
                state = "in the game" if sl.present else ("catching up" if sl.ready else "loading")
                self.say("  P%d  %-16s %s:%d  %s, has step %s%s, %d inputs, heard %.1f s ago"
                         % (i + 1, sl.name, sl.addr[0], sl.addr[1], state, have, behind, sl.inputs,
                            now - sl.heard))
        if self.pending:
            self.say("next game: " + ", ".join("%s %s" % kv for kv in sorted(self.pending.items())))
