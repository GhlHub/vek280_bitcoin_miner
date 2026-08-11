#!/usr/bin/env python3
"""Minimal Stratum v1 mock pool with an intentionally easy target.

The server accepts one miner connection, sends subscribe/authorize responses,
programs an all-ones target with mining.set_target, emits one synthetic job, and
logs the first mining.submit it receives.
"""

from __future__ import annotations

import argparse
import json
import socket
import time
from pathlib import Path


def send_line(conn: socket.socket, log, obj: dict) -> None:
    line = json.dumps(obj, separators=(",", ":")) + "\n"
    log.write(f"TX: {line}")
    log.flush()
    conn.sendall(line.encode("ascii"))


def recv_line(conn: socket.socket, log, timeout_s: float) -> str | None:
    conn.settimeout(timeout_s)
    data = bytearray()
    try:
        while True:
            chunk = conn.recv(1)
            if not chunk:
                return None
            if chunk == b"\n":
                line = data.decode("ascii", errors="replace")
                log.write(f"RX: {line}\n")
                log.flush()
                return line
            if chunk != b"\r":
                data.extend(chunk)
    except socket.timeout:
        return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=3334)
    parser.add_argument("--log", required=True)
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--target", default=("0" * 7) + ("f" * 57))
    args = parser.parse_args()

    log_path = Path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    with log_path.open("w", encoding="utf-8") as log:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
            server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            server.bind((args.host, args.port))
            server.listen(1)
            server.settimeout(args.timeout)
            log.write(f"LISTEN: {args.host}:{args.port}\n")
            log.flush()

            conn, addr = server.accept()
            with conn:
                log.write(f"ACCEPT: {addr[0]}:{addr[1]}\n")
                log.flush()

                first = recv_line(conn, log, 5.0)
                second = recv_line(conn, log, 5.0)
                if first is None or second is None:
                    log.write("FAIL: did not receive subscribe and authorize\n")
                    return 1

                send_line(
                    conn,
                    log,
                    {
                        "id": 1,
                        "result": [[["mining.notify", "easy-test"]], "abcd1234", 8],
                        "error": None,
                    },
                )
                send_line(
                    conn,
                    log,
                    {
                        "id": None,
                        "method": "mining.set_target",
                        "params": [args.target],
                    },
                )
                send_line(conn, log, {"id": 2, "result": True, "error": None})

                ntime = f"{int(time.time()) & 0xFFFFFFFF:08x}"
                send_line(
                    conn,
                    log,
                    {
                        "id": None,
                        "method": "mining.notify",
                        "params": [
                            "easy0001",
                            "00" * 32,
                            "01000000",
                            "",
                            [],
                            "20000000",
                            "207fffff",
                            ntime,
                            True,
                        ],
                    },
                )

                deadline = time.monotonic() + args.timeout
                while time.monotonic() < deadline:
                    line = recv_line(conn, log, max(0.1, deadline - time.monotonic()))
                    if line is None:
                        continue
                    if '"method":"mining.submit"' in line:
                        send_line(conn, log, {"id": 4, "result": True, "error": None})
                        log.write("PASS: received mining.submit\n")
                        return 0

                log.write("FAIL: timed out waiting for mining.submit\n")
                return 1


if __name__ == "__main__":
    raise SystemExit(main())
