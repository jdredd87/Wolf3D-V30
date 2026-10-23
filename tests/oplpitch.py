"""oplpitch.py -- the title music, the V30's PicoMEM AdLib against the
Windows OPL2, after opltempo.py: the two 20 s segments lined up within one
phrase, then
  * pitch: the long-term spectrum's strongest peaks in each, matched, in cents;
  * the notes: each 100 ms's pitch classes (12, C to B), correlated over time;
  * the sound: the spectrum's shape, octave by octave, in dB against its total.
Needs NumPy (a throwaway venv is enough).  StevenC & Claude, 2026-10-23."""
import os
import numpy as np

D = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "stage", "tests", "opl")
RATE = 22050


def load(name):
    return np.fromfile(os.path.join(D, name), dtype="<i2").astype(np.float64)


v, w = load("v30-20.raw"), load("w37-20.raw")


def env(a, hop=110):
    n = len(a) // hop
    return np.abs(a[:n * hop]).reshape(n, hop).mean(1)


ev, ew = env(v), env(w)
ev, ew = (ev - ev.mean()) / ev.std(), (ew - ew.mean()) / ew.std()
L = 15 * RATE // 110
best = max(((np.dot(ev[k:k + L], ew[:L]) / L, k) for k in range(0, 3600 // 5)), key=lambda t: t[0])
shift = best[1] * 110
print("lined up: the V30 %.3f s into its segment (r %.2f)" % (shift / RATE, best[0]))
n = 15 * RATE
v, w = v[shift:shift + n], w[:n]

# the long-term spectrum and its peaks
N, H = 8192, 2048
win = np.hanning(N)


def spec(a):
    frames = [a[i:i + N] * win for i in range(0, len(a) - N, H)]
    return np.array([np.abs(np.fft.rfft(f)) for f in frames])


sv, sw = spec(v), spec(w)
freqs = np.fft.rfftfreq(N, 1 / RATE)


def peaks(lt, k=12):
    m = (freqs > 60) & (freqs < 3000)
    idx = [i for i in range(2, len(lt) - 2) if m[i] and lt[i] > lt[i - 1] and lt[i] >= lt[i + 1]
           and lt[i] > lt[i - 2] and lt[i] >= lt[i + 2]]
    idx = sorted(idx, key=lambda i: -lt[i])[:k]
    out = []
    for i in idx:                       # parabolic: the peak between bins
        a, b, c = np.log(lt[i - 1]), np.log(lt[i]), np.log(lt[i + 1])
        out.append((freqs[i] + 0.5 * (a - c) / (a - 2 * b + c) * (freqs[1] - freqs[0]), lt[i]))
    return out


lv, lw = sv.mean(0), sw.mean(0)
pv, pw = peaks(lv), peaks(lw)
print("\nthe strongest notes (Hz): Windows -> the V30's nearest, in cents")
cents = []
for f, _ in sorted(pw):
    g = min(pv, key=lambda p: abs(np.log2(p[0] / f)))[0]
    c = 1200 * np.log2(g / f)
    if abs(c) < 50:
        cents.append(c)
    print("  %8.2f  %8.2f  %+6.1f" % (f, g, c))
if cents:
    print("pitch: the V30 %+.1f cents from Windows on average (%d notes matched)" % (np.mean(cents), len(cents)))

# the notes over time: pitch classes per 100 ms
def chroma(a):
    n2, h2 = 4096, 2205
    out = []
    fr = np.fft.rfftfreq(n2, 1 / RATE)
    ok = (fr > 60) & (fr < 4000)
    pc = np.round(12 * np.log2(fr[ok] / 440.0)).astype(int) % 12
    for i in range(0, len(a) - n2, h2):
        s = np.abs(np.fft.rfft(a[i:i + n2] * np.hanning(n2)))[ok]
        c = np.bincount(pc, weights=s, minlength=12)
        out.append(c / (np.linalg.norm(c) or 1))
    return np.array(out)


cv, cw = chroma(v), chroma(w)
m = min(len(cv), len(cw))
r = np.mean([np.dot(cv[i], cw[i]) for i in range(m)])
rs = np.mean([np.dot(cv[i], cw[(i + 17) % m]) for i in range(m)])
print("\nthe notes, 100 ms at a time: similarity %.3f (the same with Windows 1.7 s off: %.3f)" % (r, rs))

# the sound: each octave's share of the spectrum, dB
print("\neach octave's share of the sound (dB against its total): V30, Windows")
for lo in (62.5, 125, 250, 500, 1000, 2000, 4000, 8000):
    band = (freqs >= lo) & (freqs < 2 * lo)
    a = 10 * np.log10((lv[band] ** 2).sum() / (lv ** 2).sum())
    b = 10 * np.log10((lw[band] ** 2).sum() / (lw ** 2).sum())
    print("  %5d-%5d Hz  %6.1f  %6.1f   %+5.1f" % (lo, 2 * lo, a, b, a - b))
