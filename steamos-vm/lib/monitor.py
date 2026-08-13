#!/usr/bin/env python3
"""Send one command to QEMU's monitor and print what it says.

This is the human monitor (HMP), not QMP: the machine is started with
`-monitor unix:...`, and commands are the ones you would type at the `(qemu)`
prompt — `screendump out.png -f png`, `info block`, `system_powerdown`.

    monitor.py <socket> <command>
"""

import socket
import sys
import time


def send(path: str, command: str, settle: float = 1.0) -> str:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(10)
        s.connect(path)
        time.sleep(0.2)
        try:
            s.recv(65536)  # the banner
        except socket.timeout:
            pass
        s.sendall(command.encode() + b"\n")
        # Commands that write a file return before the file is complete, so give
        # the monitor a moment rather than racing whoever reads it next.
        time.sleep(settle)
        out = b""
        try:
            while True:
                chunk = s.recv(65536)
                if not chunk:
                    break
                out += chunk
                if out.rstrip().endswith(b"(qemu)"):
                    break
        except socket.timeout:
            pass
        return out.decode(errors="replace")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    print(send(sys.argv[1], sys.argv[2]), end="")
