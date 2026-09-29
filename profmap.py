"""Turn PROF.BIN from `WOLF3DV TIMEDEMO PROFILE` into per-function and
per-module time, using the link map.  StevenC & Claude, 2026.

    python profmap.py PROF.BIN WOLFSRC\\WOLF3DV.MAP [--top N] [--buckets N]

The sampler records ((CS - loadseg) * 16 + IP) >> shift, which is the address
space the map is written in, so a bucket's samples belong to the public
symbol at or below it.  Static functions have no public of their own and
are charged to the public before them -- the module totals are exact.
"""
import bisect
import re
import struct
import sys


def load_prof(path):
    d = open(path, "rb").read()
    if d[:4] != b"WPRF":
        sys.exit("%s: not a PROF.BIN" % path)
    shift, count = struct.unpack_from("<HH", d, 4)
    other = struct.unpack_from("<3L", d, 8)
    buckets = struct.unpack_from("<%dL" % count, d, 20)
    return shift, other, buckets


def load_map(path):
    segs, pubs = [], []
    mode = None
    for line in open(path, errors="replace"):
        if "Start  Stop   Length Name" in line:
            mode = "segs"
            continue
        if "Publics by Value" in line:
            mode = "pubs"
            continue
        if "Detailed map" in line or "Publics by Name" in line:
            mode = None
            continue
        if mode == "segs":
            m = re.match(r"\s*([0-9A-F]{5})H\s+([0-9A-F]{5})H\s+([0-9A-F]{5})H\s+(\S+)\s+(\S+)", line)
            if m:
                segs.append((int(m[1], 16), int(m[1], 16) + int(m[3], 16), m[4], m[5]))
        elif mode == "pubs":
            m = re.match(r"\s*([0-9A-F]{4}):([0-9A-F]{4})\s+(?:idle\s+)?(\S+)\s*$", line)
            if m and "Abs" not in line:
                seg = int(m[1], 16)
                pubs.append((seg * 16 + int(m[2], 16), m[3], seg))
    # A public counts only if it lies inside a real segment whose frame is its
    # own segment value.  The 8087 emulator's fix-up constants (FIARQQ,
    # FJCRQQ, __floatconvert) are listed as 0000:xxxx numbers, not code, and
    # would otherwise steal the samples of whatever function they land in.
    frames = [(s >> 4, s, e) for s, e, _, _ in segs]
    kept = sorted((addr, name) for addr, name, seg in pubs
                  if any(f == seg and s <= addr < e for f, s, e in frames))
    return segs, kept


def main():
    argv = sys.argv[1:]
    opts = {"--top": 30, "--buckets": 0}
    for o in opts:
        if o in argv:
            i = argv.index(o)
            opts[o] = int(argv[i + 1])
            del argv[i:i + 2]
    top, nbuckets = opts["--top"], opts["--buckets"]
    args = argv
    if len(args) != 2:
        sys.exit(__doc__)
    shift, other, buckets = load_prof(args[0])
    segs, pubs = load_map(args[1])
    addrs = [a for a, _ in pubs]

    total = sum(buckets) + sum(other)
    if not total:
        sys.exit("no samples")
    per_fn, per_seg = {}, {}
    for i, n in enumerate(buckets):
        if not n:
            continue
        addr = i << shift
        j = bisect.bisect_right(addrs, addr) - 1
        fn = pubs[j][1] if j >= 0 else "?"
        per_fn[fn] = per_fn.get(fn, 0) + n
        seg = next((s[2] for s in segs if s[0] <= addr < s[1] and s[3] == "CODE"), "(not code)")
        per_seg[seg] = per_seg.get(seg, 0) + n
    per_seg["(heap: compiled scalers)"] = other[1]
    per_seg["(below program: DOS/TSRs)"] = other[0]
    per_seg["(ROM / BIOS)"] = other[2]

    print("%d samples, %d-byte buckets" % (total, 1 << shift))
    print("\nby module")
    for k, v in sorted(per_seg.items(), key=lambda kv: -kv[1]):
        if v:
            print("  %6.2f%%  %7d  %s" % (100.0 * v / total, v, k))
    print("\nby function (public at or below the sample)")
    for k, v in sorted(per_fn.items(), key=lambda kv: -kv[1])[:top]:
        print("  %6.2f%%  %7d  %s" % (100.0 * v / total, v, k))

    if nbuckets:
        print("\nhottest %d-byte buckets (function+offset -- read against a listing)" % (1 << shift))
        hot = sorted(((n, i) for i, n in enumerate(buckets) if n), reverse=True)[:nbuckets]
        for n, i in hot:
            addr = i << shift
            j = bisect.bisect_right(addrs, addr) - 1
            fn, base = (pubs[j][1], pubs[j][0]) if j >= 0 else ("?", 0)
            print("  %6.2f%%  %6d  %05X  %s+%X" % (100.0 * n / total, n, addr, fn, addr - base))


if __name__ == "__main__":
    main()
