"""Build MKBJ, the players-as-BJ maker -- StevenC & Claude (Anthropic), 2026-10-23.

    python mp/mkmkbj.py     -> mp/build/mkbj/mkbj.exe   (DOS, the plain 8086)
                               mp/build/mkbjw/mkbjw.exe (Windows, 32-bit)

One source, mp/mkbj.pas, with FPC's i8086-msdos cross-compiler (small
model) and its own i386-win32 compiler.  It writes what mp/mkbj.py writes,
byte for byte.
"""
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TARGETS = [(["-Tmsdos", "-Pi8086", "-WmSmall"], os.path.join("build", "mkbj"), "mkbj.exe"),
           (["-Twin32"], os.path.join("build", "mkbjw"), "mkbjw.exe")]


def main():
    ok = True
    for flags, out_dir, name in TARGETS:
        os.makedirs(os.path.join(HERE, out_dir), exist_ok=True)
        cmd = ["fpc"] + flags + ["-O2", "-FE" + out_dir, "-FU" + out_dir, "-o" + name, "mkbj.pas"]
        r = subprocess.run(cmd, cwd=HERE, capture_output=True, text=True)
        exe = os.path.join(HERE, out_dir, name)
        out = [l for l in (r.stdout + r.stderr).splitlines()
               if not l.startswith(("Free Pascal", "Copyright", "Target OS", "Compiling", "Assembling"))]
        print("\n".join(out))
        if r.returncode or not os.path.exists(exe):
            print("build FAILED:", name)
            ok = False
        else:
            print("built:", exe, os.path.getsize(exe), "bytes")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
