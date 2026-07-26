#!/usr/bin/env python3
"""PTY regressions for visible, isolated confirmation prompts."""
from __future__ import annotations

import os
import select
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

if os.name != "posix":
    print("SKIP: PTY prompt tests require a POSIX host.")
    raise SystemExit(77)

import fcntl  # noqa: E402
import pty  # noqa: E402
import termios  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def spawn(script: str, shell: str = "bash") -> tuple[subprocess.Popen[bytes], int]:
    master, slave = pty.openpty()
    attributes = termios.tcgetattr(slave)
    attributes[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, attributes)

    def controlling_terminal() -> None:
        os.setsid()
        fcntl.ioctl(slave, termios.TIOCSCTTY, 0)

    process = subprocess.Popen(
        [shell, "-f", "-i", "-c", script] if shell == "zsh" else [shell, "-c", script],
        cwd=ROOT, stdin=slave, stdout=slave, stderr=slave,
        preexec_fn=controlling_terminal, close_fds=True,
    )
    os.close(slave)
    return process, master


def read_until(master: int, marker: bytes, timeout: float = 5.0) -> bytes:
    output = bytearray()
    deadline = time.monotonic() + timeout
    while marker not in output and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                output.extend(os.read(master, 4096))
            except OSError:
                break
    assert marker in output, output.decode(errors="replace")
    return bytes(output)


def finish(process: subprocess.Popen[bytes], master: int, initial: bytes = b"") -> tuple[int, bytes]:
    output = bytearray(initial)
    deadline = time.monotonic() + 5
    while process.poll() is None and time.monotonic() < deadline:
        ready, _, _ = select.select([master], [], [], 0.1)
        if ready:
            try:
                output.extend(os.read(master, 4096))
            except OSError:
                break
    process.wait(timeout=2)
    while True:
        try:
            ready, _, _ = select.select([master], [], [], 0)
            if not ready:
                break
            output.extend(os.read(master, 4096))
        except OSError:
            break
    os.close(master)
    return process.returncode, bytes(output)


def confirmation(answer: bytes) -> tuple[int, bytes]:
    script = "source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=false; if confirm 'Question?'; then exit 0; else exit $?; fi"
    process, master = spawn(script)
    before = read_until(master, b"Question? [y/N] ")
    os.write(master, answer + b"\n")
    status, output = finish(process, master, before)
    assert output.count(b"Question? [y/N] ") == 1
    assert b"Question? [y/N] \r\n" in output
    return status, output


def main() -> int:
    for answer in (b"y", b"Y", b"yes"):
        assert confirmation(answer)[0] == 0
    for answer in (b"", b"n", b"invalid"):
        assert confirmation(answer)[0] == 1

    process, master = spawn("source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=false; confirm 'EOF?'")
    read_until(master, b"EOF? [y/N] ")
    os.close(master)
    assert process.wait(timeout=2) != 0

    with tempfile.TemporaryDirectory() as temporary:
        log = Path(temporary) / "session.log"
        events = Path(temporary) / "events.jsonl"
        script = f"source lib/logging.sh; source lib/common.sh; trap cleanup_common EXIT; start_logging {log!s} {events!s} test; if confirm 'Logged?'; then printf 'accepted\\n'; else exit $?; fi"
        process, master = spawn(script)
        before = read_until(master, b"Logged? [y/N] ")
        os.write(master, b"y\n")
        status, output = finish(process, master, before)
        assert status == 0 and output.count(b"Logged? [y/N] ") == 1
        content = log.read_text(encoding="utf-8")
        assert "accepted" in content and "Logged?" not in content and "\ny\n" not in content

    script = "source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=false; if confirm First; then confirm Second; else exit $?; fi"
    process, master = spawn(script)
    first = read_until(master, b"First [y/N] ")
    os.write(master, b"y\n")
    second = read_until(master, b"Second [y/N] ")
    os.write(master, b"n\n")
    status, output = finish(process, master, first + second)
    assert status == 1 and output.count(b"First [y/N] ") == 1 and output.count(b"Second [y/N] ") == 1

    no_tty = subprocess.run(
        ["bash", "-c", "source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=false; confirm NoTTY"],
        cwd=ROOT, stdin=subprocess.DEVNULL, capture_output=True, timeout=3, check=False,
    )
    assert no_tty.returncode == 2 and b"no controlling terminal" in no_tty.stderr
    noninteractive = subprocess.run(
        ["bash", "-c", "source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=true; confirm Never"],
        cwd=ROOT, input=b"y\n", capture_output=True, timeout=3, check=False,
    )
    assert noninteractive.returncode == 1 and b"Never" not in noninteractive.stdout + noninteractive.stderr
    if shutil.which("zsh"):
        child = "source lib/logging.sh; source lib/common.sh; NON_INTERACTIVE=false; confirm ZshLaunch"
        process, master = spawn(f"bash -c {shlex.quote(child)}", shell="zsh")
        before = read_until(master, b"ZshLaunch [y/N] ")
        os.write(master, b"n\n")
        status, output = finish(process, master, before)
        assert status != 0 and not output.rstrip(b"\r\n").endswith(b"%")
    print("PTY prompt tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
