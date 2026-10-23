"""opltempo.py -- the title music's tempo in each of oplrec.py's recordings,
on its own: where each one's music starts, and the length of its repeating
phrase (the envelope's autocorrelation), so nothing depends on lining the
two recordings up.  Then 20 s of each from its music's start, as WAV, and
one spectrogram above the other.  StevenC & Claude (Anthropic), 2026-10-23."""
import array
import os
import subprocess

D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "opl")
RATE = 22050
HOP = 110                                   # 5 ms


def load(name, stereo):
    a = array.array("h")
    a.frombytes(open(os.path.join(D, name), "rb").read())
    if stereo:
        a = array.array("h", ((a[i] + a[i + 1]) // 2 for i in range(0, len(a) - 1, 2)))
    return a


def envelope(a):
    return [sum(abs(v) for v in a[i:i + HOP]) / HOP for i in range(0, len(a) - HOP, HOP)]


def start(f, channels):
    """Where the music starts, in 5 ms steps: the end of the recording's
    silence with 2 s of sound after it (ffmpeg's silencedetect, -40 dB) --
    the V30's has its signon's quiet and a click in it -- or 0."""
    import re
    r = subprocess.run(["ffmpeg", "-hide_banner", "-f", "s16le", "-ar", str(RATE), "-ac", str(channels),
                        "-i", os.path.join(D, f), "-af", "silencedetect=n=-40dB:d=0.5", "-f", "null", "-"],
                       capture_output=True, text=True)
    starts = [float(x) for x in re.findall(r"silence_start: ([0-9.]+)", r.stderr)]
    ends = [float(x) for x in re.findall(r"silence_end: ([0-9.]+)", r.stderr)]
    # the end of a silence with at least 2 s of sound after it (a click is
    # not the music: the V30's signon has one)
    for i, end in enumerate(ends):
        nxt = starts[i + 1] if i + 1 < len(starts) else 1e9
        if nxt - end >= 2.0:
            return int(end * RATE / HOP)
    return 0


def period(e, s, secs=20, lo=2.5, hi=5.0):     # (wider finds the phrase twice over)
    """The repeating phrase's length (s): the envelope's autocorrelation peak."""
    seg = e[s:s + secs * RATE // HOP]
    m = sum(seg) / len(seg)
    seg = [x - m for x in seg]
    n = len(seg)
    best = (-1e30, 0)
    for lag in range(int(lo * RATE / HOP), int(hi * RATE / HOP)):
        c = sum(seg[t] * seg[t + lag] for t in range(n - lag)) / (n - lag)
        best = max(best, (c, lag))
    # refine to a fraction of a hop: the parabola through the peak and its neighbours
    lag = best[1]

    def ac(l):
        return sum(seg[t] * seg[t + l] for t in range(n - l)) / (n - l)
    y0, y1, y2 = ac(lag - 1), ac(lag), ac(lag + 1)
    d = 0.5 * (y0 - y2) / (y0 - 2 * y1 + y2) if (y0 - 2 * y1 + y2) else 0
    return (lag + d) * HOP / RATE


res = {}
for name, f, st in (("V30 (PicoMEM AdLib)", "v30.raw", False), ("Windows (OPL2 in C)", "w37.raw", True)):
    a = load(f, st)
    e = envelope(a)
    s = start(f, 2 if st else 1)
    p = period(e, s)
    res[f] = (a, s, p)
    print("%-20s music from %5.2f s; its phrase %.3f s" % (name, s * HOP / RATE, p))
pv, pw = res["v30.raw"][2], res["w37.raw"][2]
print("the V30 plays %.2f%% %s than Windows" % (abs(100 * (pv - pw) / pw), "slower" if pv > pw else "faster"))
for f, tag in (("v30.raw", "v30"), ("w37.raw", "w37")):
    a, s, _ = res[f]
    seg = a[s * HOP:s * HOP + 20 * RATE]
    raw = os.path.join(D, tag + "-20.raw")
    open(raw, "wb").write(seg.tobytes())
    for args, out in ((["-lavfi", "showspectrumpic=s=1200x400:scale=log:fscale=log:legend=0:color=intensity"],
                       tag + "-spec20.png"), ([], tag + "-20.wav")):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE), "-ac", "1", "-i", raw]
                       + args + [os.path.join(D, out)], check=True)
print("20 s from each one's start:", os.path.join(D, "v30-20.wav"), os.path.join(D, "w37-20.wav"))
