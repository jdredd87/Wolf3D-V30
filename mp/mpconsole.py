"""The multiplayer server's console -- StevenC & Claude, 2026-10-12/13.

Commands typed into the server's window while it runs (StevenC: "do we have
options inside it? to kick users, send messages, change levels or episodes
... make it a full fledged server to control everything?").  The second half
(say, a kick's reason, pause, map and the limits in play, scores) needs the
WOLF3DM of 2026-10-13 or later on every machine.

    help                     this list
    status                   the game, and every slot: who, where from, how far
                             behind, inputs, how long since last heard
    say TEXT                 a message on every player's screen, as SERVER
    scores                   every player's frags and deaths, as the game has them
    kick N [reason]          slot N (1-4) out of the game; its screen says why
    ban N | ban ADDRESS      kick, and refuse that address from now on
    unban ADDRESS | bans     ... and back again; the list
    end [reason]             end the game for everyone; the server waits for
                             the next one (or stops, with --once)
    pause | resume           hold the game for everyone, and let it go on
    map E L | map N          everyone to that floor now (the tally first);
                             Spear of Destiny: map 1 L, L 1-21, or N 0-20
    nextfloor                everyone to the next floor now
    timelimit MIN | fraglimit N   change the game's limit now (0: none)
    next                     the settings the next game starts with
    next map E L | next map N    episode and floor (N = (E-1)*10 + L-1)
    next mode coop|dm|tdm|ctf    next skill 0-3   next bots N
    next timelimit MIN       next fraglimit N    next itemrespawn SECS
    next enemies on|off      next ff on|off
    quiet on|off             the log's lines off, or on again
    quit                     end the game and stop the server

"next" settings take effect when the next game starts -- at once if none is
running -- since every machine in a game must be playing the same rules.
map, nextfloor and the limits in play are events at a step the server
names: every machine, and anyone who joins later and replays, applies them
at that same step -- in a floor's tally too (2026-10-14): map then picks the
floor the tally leads to, and nextfloor has nothing to do.  A recording
(--record) replays one floor, so it is cut where map or nextfloor ended it.

Lines are read on a thread of their own and carried out by the server's own
loop (Console.poll), between packets, so nothing here races the game.  With
no console -- input from a pipe that ends, or none -- it simply does nothing.

The same commands come from anywhere on this PC through the control port
(2026-10-14): 127.0.0.1:31999 unless --control says otherwise (0: none), a
command a datagram, the console's answer sent back -- `python mp/mpctl.py
say hello`.  So a server started in the background, with no window to type
in, can still be run.  Loopback only.
"""
import queue
import socket
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
        self.ctl = None                 # the control port's socket
        self.answer = None              # a control command's answer, being gathered

    # ---- input, on its own thread

    def control(self, port):
        """Listen for console lines on 127.0.0.1:port."""
        if not port:
            return
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.bind(("127.0.0.1", port))
        except OSError as e:              # another server has it: carry on without
            self.say("no control port %d (%s) -- the console window only" % (port, e))
            s.close()
            return
        s.setblocking(False)
        self.ctl = s
        self.say("control port 127.0.0.1:%d -- python mp/mpctl.py COMMAND" % port)

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
        """Carry out whatever has been typed, or sent to the control port.
        Returns False on quit."""
        while self.ctl is not None:
            try:
                data, addr = self.ctl.recvfrom(1024)
            except (BlockingIOError, ConnectionResetError, OSError):
                break
            line = data.decode("latin-1", "replace").strip()
            self.answer = []
            go = self.do(line) if line else True
            reply = "\n".join(self.answer) or "(done)"
            self.answer = None
            try:
                self.ctl.sendto(reply.encode("latin-1", "replace")[:8000], addr)
            except OSError:
                pass
            if not go:
                return False
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
        if "mode" in p:                         # tdm, ctf: deathmatch with teams
            dm = p["mode"] != "coop"
            rules = (rules | self.RULE_DM) if dm else (rules & ~self.RULE_DM)
            s.rules2 = {"tdm": 1, "ctf": 3}.get(p["mode"], 0)
            if "itemrespawn" not in p:          # each mode's default, as at start-up:
                p["itemrespawn"] = 30 if dm else 0  # 30 s, or never
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
        if self.answer is not None:     # a control command's: send it back too
            self.answer.append(text)

    def settings(self):
        s = self.s
        r = s.rules
        parts = ["map %d (%s)" % (s.map, self.P.map_name(s.map, s.data())), s.mode_name(),
                 "skill %d" % s.skill, "bots %d" % s.bots,
                 "enemies %s" % ("off" if r & self.RULE_NOENEMIES else "on"),
                 "ff %s" % ("off" if r & self.RULE_NOFF else "on"),
                 "items back %s" % ("after %d s" % ((r >> 3) * 5) if r >> 3 else "never")]
        if s.minutes:
            parts.append("timelimit %d" % s.minutes)
        if s.frags:
            parts.append("fraglimit %d" % s.frags)
        for k, v in sorted(getattr(s, "live", {}).items()):
            parts.append("%s %s in this game" % (k, v or "none"))
        if getattr(s, "paused", False):
            parts.append("PAUSED")
        if getattr(s, "waitfor", None) is not None:
            parts.append("WAITING for %s to catch up" % s.who(s.waitfor))
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
                if self.answer is not None:
                    self.answer.append(HELP)
            elif cmd in ("status", "players", "st"):
                self.status()
            elif cmd == "kick":
                i = self.slot(rest[0]) if rest else None
                if i is None:
                    self.say("kick: no person in slot %s" % (rest[0] if rest else "?"))
                else:
                    why = " ".join(rest[1:])
                    s.leave(i, "was kicked from the console (%s)" % (why or "no reason given"),
                            P.BYE_KICKED, why)
            elif cmd == "say":
                if not rest:
                    self.say("say: what?")
                else:
                    s.say_all(line.split(None, 1)[1][:60])
            elif cmd == "scores":
                self.scores()
            elif cmd in ("pause", "resume"):
                if s.state != "play":
                    self.say("%s: no game is running" % cmd)
                elif not s.pause(cmd == "pause"):
                    self.say("already %s" % ("paused" if s.paused else "going"))
            elif cmd in ("map", "nextfloor", "timelimit", "fraglimit"):
                self.now(cmd, rest)
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
                        s.leave(k, "was banned from the console", P.BYE_KICKED,
                                "banned from this server")
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
            self.pending["map"] = self.map_number(w[1:])
        elif what == "mode":
            if w[1].lower() not in ("dm", "coop", "tdm", "ctf"):
                raise ValueError("coop, dm, tdm or ctf")
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

    def map_number(self, w):
        data = self.s.data()            # the players' data: Spear's floors are 0-20
        if len(w) >= 2:
            return self.P.map_from(int(w[0]), int(w[1]), data)
        n = int(w[0])
        if not 0 <= n <= self.P.map_max(data):
            raise ValueError("map 0-%d" % self.P.map_max(data))
        return n

    def now(self, cmd, w):
        """map, nextfloor and the limits, in the game being played."""
        s, P = self.s, self.P
        if s.state != "play":
            self.say("%s: no game is running -- for the next one, next %s" % (cmd, cmd))
            return
        if cmd == "map":
            n = self.map_number(w)
            at = s.event(P.EV_MAP, n)
            what = "everyone to map %d (%s)" % (n, P.map_name(n, s.data()))
        elif cmd == "nextfloor":
            at = s.event(P.EV_NEXTFLOOR)
            what = "everyone to the next floor"
        else:
            v = int(w[0])
            if not 0 <= v <= 65535:
                raise ValueError("0-65535")
            at = s.event(P.EV_TIMELIMIT if cmd == "timelimit" else P.EV_FRAGLIMIT, v)
            s.live[cmd] = v
            what = "%s %s" % (cmd, v or "none")
        if s.paused:
            what += " (when the game goes on)"
        self.say("%s, at step %d" % (what, at))
        s.log("console: %s at step %d" % (what, at))

    def scores(self):
        s = self.s
        if s.scores is None:
            self.say("scores: none yet -- the players send theirs every 50 steps")
            return
        step, sc = s.scores
        self.say("scores at step %d:" % step)
        for i, sl in enumerate(s.slots):
            if sl is not None:
                f, d = sc[i] if i < len(sc) else (0, 0)
                self.say("  P%d  %-16s %4d frags  %4d deaths" % (i + 1, sl.name, f, d))

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
                if sl.ready and not sl.present and sl.played is not None and newest >= sl.played:
                    behind += ", %d to play" % (newest - sl.played)
                self.say("  P%d  %-16s %s:%d  %s, has step %s%s, %d inputs, heard %.1f s ago"
                         % (i + 1, sl.name, sl.addr[0], sl.addr[1], state, have, behind, sl.inputs,
                            now - sl.heard))
        for k, w in enumerate(getattr(s, "watchers", [])):     # NET WATCH (2026-10-17)
            if w:
                self.say("  W%d  %-16s %s:%d  watching, has step %s" % (k + 1, w.name, w.addr[0], w.addr[1],
                         "none" if w.have == P.NOBODY else w.have))
        if self.pending:
            self.say("next game: " + ", ".join("%s %s" % kv for kv in sorted(self.pending.items())))
