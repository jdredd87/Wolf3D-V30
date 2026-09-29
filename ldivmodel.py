"""Exact 16-bit model of H_LDIV.ASM's V30 fast path -- StevenC & Claude, 2026.

Checks the unsigned 32/32 core (the part after signs are removed) against
Python's own division, over edge cases and random operands.  Every step
mirrors one instruction group of the assembly: 16-bit registers, DIV that
must not overflow (asserted), shifts through CL.

    python ldivmodel.py [N]      N random cases per class (default 200000)
"""
import random
import sys

M16 = 0xFFFF


def div16(dx, ax, d):
    """DIV r16: DX:AX / d -> (AX quotient, DX remainder); overflow is a trap."""
    n = (dx << 16) | ax
    q, r = divmod(n, d)
    assert d != 0 and q <= M16, "DIV overflow %08X / %04X" % (n, d)
    return q, r


def fast_udivmod(u, v):
    """The assembly's path from `positive:` on; returns (quotient, remainder)."""
    dx, ax = u >> 16, u & M16
    cx, bx = v >> 16, v & M16
    if cx == 0:                       # divisor < 65536: two DIVs
        si = ax
        qh, r1 = div16(0, dx, bx)
        ql, r = div16(r1, si, bx)
        return (qh << 16) | ql, r
    # save u, v
    ulo, uhi, vlo, vhi = ax, dx, bx, cx
    si = 0                            # n = nlz16(vhi), normalising v
    while not (cx & 0x8000):
        carry = bx >> 15
        bx = (bx << 1) & M16
        cx = ((cx << 1) | carry) & M16
        si += 1
    ax = ((dx & 1) << 15) | (ax >> 1)  # u1 = u >> 1
    dx = dx >> 1
    ax, _ = div16(dx, ax, cx)          # q1
    cl = 15 - si
    ax = ax >> cl                      # q0 = q1 >> (15-n)
    if ax:
        ax -= 1
    si = ax
    p = (((si * vhi) & M16) << 16) + si * vlo   # low word of q0*vhi, plus q0*vlo
    p &= 0xFFFFFFFF
    r = (((uhi << 16) | ulo) - p) & 0xFFFFFFFF
    v32 = (vhi << 16) | vlo
    if r >= v32:
        r = (r - v32) & 0xFFFFFFFF
        si += 1
    return si, r


def check(u, v):
    q, r = fast_udivmod(u, v)
    eq, er = divmod(u, v)
    if (q, r) != (eq, er):
        raise SystemExit("MISMATCH u=%08X v=%08X got q=%X r=%X want q=%X r=%X" % (u, v, q, r, eq, er))


def main():
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200000
    edges = [1, 2, 3, 0x7FFF, 0x8000, 0x8001, 0xFFFF, 0x10000, 0x10001, 0x1FFFF,
             0x7FFFFFFF, 0x80000000, 0x80000001, 0xFFFFFFFE, 0xFFFFFFFF,
             0xFFFF0000, 0x0000FFFF, 0x12345678, 0x00010000]
    count = 0
    # the slow path is only reached with a nonzero divisor and not both high words 0
    for u in edges + [0]:
        for v in edges:
            if (u >> 16) == 0 and (v >> 16) == 0:
                continue          # Borland's own quick@ldiv takes these
            check(u, v)
            count += 1
    rnd = random.Random(1992)
    for _ in range(n):            # divisor >= 65536, all sizes of dividend
        v = rnd.randrange(0x10000, 1 << 32)
        u = rnd.randrange(0, 1 << rnd.randrange(1, 33))
        check(u, v)
        check(rnd.randrange(0, 1 << 32), v)
        count += 2
    for _ in range(n):            # divisor < 65536, dividend >= 65536
        v = rnd.randrange(1, 0x10000)
        u = rnd.randrange(0x10000, 1 << 32)
        check(u, v)
        count += 1
    for _ in range(n):            # the Wolf3D shape: ny*scale / nx, both near 2^16..2^31
        v = rnd.randrange(0x5800, 1 << 31)
        u = rnd.randrange(0, 1 << 31)
        if (u >> 16) or (v >> 16):
            check(u, v)
            count += 1
    for k in range(16, 32):       # every normalisation shift, boundary divisors
        for v in ((1 << k), (1 << k) + 1, (2 << k) - 1):
            for u in ((1 << 32) - 1, v * 3 - 1, v * 3, v - 1, v, (v << 1) - 1):
                u &= 0xFFFFFFFF
                check(u, v)
                count += 1
    print("OK: %d divisions, quotient and remainder exact" % count)


if __name__ == "__main__":
    main()
