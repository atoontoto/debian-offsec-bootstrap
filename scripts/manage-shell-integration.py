#!/usr/bin/env python3
"""Atomically add or remove the exact managed shell-alias block."""
from __future__ import annotations

import argparse
import os
import stat
import tempfile
from pathlib import Path

MARKER = "# debian-offsec-bootstrap (remove this line and the next to disable)"


def managed_line(shell: str) -> str:
    return f'[[ -r "$HOME/.offsec-aliases.{shell}" ]] && source "$HOME/.offsec-aliases.{shell}"'


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("add", "remove"))
    parser.add_argument("shell", choices=("bash", "zsh"))
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    metadata = args.path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"refusing unsafe shell configuration: {args.path}")
    original = args.path.read_text(encoding="utf-8")
    line = managed_line(args.shell)
    lines = original.splitlines(keepends=True)
    pairs = sum(
        1 for position in range(len(lines) - 1)
        if lines[position].rstrip("\r\n") == MARKER and lines[position + 1].rstrip("\r\n") == line
    )
    marker_count = sum(1 for entry in lines if entry.rstrip("\r\n") == MARKER)
    if marker_count != pairs:
        raise SystemExit("refusing an incomplete or modified managed shell block")
    if args.action == "add" and pairs == 1:
        return 0
    filtered: list[str] = []
    index = 0
    while index < len(lines):
        if lines[index].rstrip("\r\n") == MARKER and index + 1 < len(lines) and lines[index + 1].rstrip("\r\n") == line:
            if filtered and filtered[-1] in {"\n", "\r\n"}:
                filtered.pop()
            index += 2
            continue
        filtered.append(lines[index])
        index += 1
    content = "".join(filtered)
    if args.action == "add":
        if content and not content.endswith("\n"):
            content += "\n"
        content += f"\n{MARKER}\n{line}\n"
    if content == original:
        return 0
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{args.path.name}.offsec-", dir=args.path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary_name, stat.S_IMODE(metadata.st_mode))
        os.replace(temporary_name, args.path)
    finally:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
