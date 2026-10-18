"""profline.py -- PROF.BIN to source LINES, not functions: the samples of a
profiling build whose map carries line numbers (mp/profbuild.py's).  A
static function is charged to the public before it by profmap.py; here
every sample lands on its own line.  StevenC & Claude (Anthropic),
2026-10-17.

    python mp/profline.py PROF.BIN stage/WOLF3DP.MAP [--top 40] [--file wl_mp.c]

A 16-byte bucket's samples go to the line whose code starts at or below it.
"""
import bisect
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
from profmap import load_prof           # noqa: E402

ROOT = os.path.join(HERE, "..", "WOLFSRC")


def load_lines(path):
    lines = []                          # (linear address, file, line)
    cur = None
    for raw in open(path, errors="replace"):
        m = re.match(r"Line numbers for \S+\((\S+)\) segment", raw)
        if m:
            cur = m.group(1)
            continue
        if cur and raw.strip() and not re.match(r"\s*\d+ [0-9A-F]{4}:[0-9A-F]{4}", raw):
            if not raw.startswith(" "):
                cur = None
            continue
        if cur:
            for n, seg, off in re.findall(r"(\d+) ([0-9A-F]{4}):([0-9A-F]{4})", raw):
                lines.append((int(seg, 16) * 16 + int(off, 16), cur, int(n)))
    lines.sort()
    return lines


def main():
    argv = sys.argv[1:]
    top = 40
    only = None
    if "--top" in argv:
        i = argv.index("--top")
        top = int(argv[i + 1])
        del argv[i:i + 2]
    if "--file" in argv:
        i = argv.index("--file")
        only = argv[i + 1].lower()
        del argv[i:i + 2]
    shift, other, buckets = load_prof(argv[0])
    lines = load_lines(argv[1])
    addrs = [a for a, _, _ in lines]
    total = sum(buckets) + sum(other)
    per = {}
    for i, n in enumerate(buckets):
        if not n:
            continue
        a = i << shift
        k = bisect.bisect_right(addrs, a) - 1
        if k < 0:
            continue
        _, f, ln = lines[k]
        per[(f, ln)] = per.get((f, ln), 0) + n
    files = {}
    for (f, ln), n in per.items():
        files[f] = files.get(f, 0) + n
    print("%d samples; by file (where line numbers are known):" % total)
    for f, n in sorted(files.items(), key=lambda x: -x[1])[:12]:
        print("  %6.2f%%  %s" % (100.0 * n / total, f))
    src = {}
    print("\nby line:")
    for (f, ln), n in sorted(per.items(), key=lambda x: -x[1]):
        if only and f.lower() != only:
            continue
        if f not in src:
            p = os.path.join(ROOT, f.upper())
            src[f] = open(p, encoding="latin-1").read().split("\n") if os.path.exists(p) else []
        text = src[f][ln - 1].strip() if 0 < ln <= len(src[f]) else ""
        print("  %6.2f%%  %s:%d  %s" % (100.0 * n / total, f, ln, text[:90]))
        top -= 1
        if not top:
            break


if __name__ == "__main__":
    main()
