"""k9.py OUT.K9 SEQ -- a K9INJ script (k9inj.asm) from a key sequence, the
notation of keys37.py: NAME:ms (a key held that long; NAME+NAME for several
at once), wait:ms, text=WORDS:ms (typed).  Bytes are scancode set 1, as the
keyboard controller hands them on; times in BIOS ticks (18.2 a second).
StevenC & Claude (Anthropic), 2026-10-22."""
import struct
import sys

SC = {"esc": 0x01, "1": 0x02, "2": 0x03, "3": 0x04, "4": 0x05, "5": 0x06, "6": 0x07, "7": 0x08, "8": 0x09,
      "9": 0x0A, "0": 0x0B, "bs": 0x0E, "tab": 0x0F, "enter": 0x1C, "ctrl": 0x1D, "lshift": 0x2A,
      "alt": 0x38, "space": 0x39, "up": 0x48, "down": 0x50, "left": 0x4B, "right": 0x4D,
      "f1": 0x3B, "f2": 0x3C, "f3": 0x3D, "f4": 0x3E, "f5": 0x3F, "f6": 0x40, "f7": 0x41,
      "f8": 0x42, "f9": 0x43, "f10": 0x44}
for ch, code in zip("qwertyuiop", range(0x10, 0x1A)):
    SC[ch] = code
for ch, code in zip("asdfghjkl", range(0x1E, 0x27)):
    SC[ch] = code
for ch, code in zip("zxcvbnm", range(0x2C, 0x33)):
    SC[ch] = code


def ticks(ms):
    return max(1, int(round(ms * 18.2065 / 1000)))


def compile_seq(seq):
    out = []                    # (wait ticks before, byte)
    wait = 2

    def send(byte):
        nonlocal wait
        out.append((wait, byte))
        wait = 0

    for item in seq.split(","):
        name, ms = item.rsplit(":", 1)
        ms = int(ms)
        if name == "wait":
            wait += ticks(ms)
        elif name.startswith("text="):
            for ch in name[5:].lower():
                k = SC["space"] if ch == " " else SC[ch]
                send(k)
                wait = 2
                send(k | 0x80)
                wait = 2
            wait += ticks(ms)
        else:
            keys = [SC[n] for n in name.split("+")]
            for k in keys:
                send(k)
                wait = 1
            wait = ticks(ms)
            for k in reversed(keys):
                send(k | 0x80)
                wait = 1
            wait = 2
    return out


def main():
    path, seq = sys.argv[1], sys.argv[2]
    entries = compile_seq(seq)
    b = b"".join(struct.pack("<HB", w, k) for w, k in entries) + b"\xff\xff"
    assert len(b) <= 6000, "too long for K9INJ"
    open(path, "wb").write(b)
    total = sum(w for w, _ in entries)
    print("%s: %d bytes, %d keys, %.1f s" % (path, len(b), len(entries), total / 18.2065))


if __name__ == "__main__":
    main()
