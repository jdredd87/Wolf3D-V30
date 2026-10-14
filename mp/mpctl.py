"""Send a command to a running Wolf3D server's console -- StevenC & Claude, 2026-10-14.

    python mp/mpctl.py status
    python mp/mpctl.py say Ten minutes to go
    python mp/mpctl.py --port 31998 pause

The server listens for these on 127.0.0.1 (port 31999 unless started with
--control), so this works only on the PC the server runs on.  Any console
command works -- `python mp/mpctl.py help` lists them -- and what the
console says back is printed.  Exit code 0 when the server answered, 1 if
nothing did within --wait seconds (3).
"""
import socket
import sys


def main(argv):
    port, wait = 31999, 3.0
    args = list(argv)
    if "--port" in args:
        i = args.index("--port")
        port = int(args[i + 1])
        del args[i:i + 2]
    if "--wait" in args:
        i = args.index("--wait")
        wait = float(args[i + 1])
        del args[i:i + 2]
    if not args:
        print(__doc__.strip())
        return 1
    line = " ".join(args)
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.settimeout(wait)
    s.sendto(line.encode("latin-1", "replace"), ("127.0.0.1", port))
    try:
        data, _ = s.recvfrom(16384)
    except (socket.timeout, ConnectionResetError):
        print("no answer from a server on 127.0.0.1:%d" % port)
        return 1
    print(data.decode("latin-1", "replace"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
