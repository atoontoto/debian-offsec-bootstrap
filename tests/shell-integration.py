#!/usr/bin/env python3
"""Regression tests for atomic, idempotent shell integration edits."""
from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EDITOR = ROOT / "scripts/manage-shell-integration.py"


def run(*arguments: str) -> None:
    subprocess.run([sys.executable, str(EDITOR), *arguments], check=True)


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        shellrc = Path(temporary) / ".bashrc"
        original = "export SAFE=value\n# similar but unmanaged text\n"
        shellrc.write_text(original, encoding="utf-8")
        os.chmod(shellrc, 0o640)
        run("add", "bash", str(shellrc))
        once = shellrc.read_bytes()
        run("add", "bash", str(shellrc))
        assert shellrc.read_bytes() == once
        assert once.count(b"# debian-offsec-bootstrap") == 1
        if os.name == "posix":
            assert shellrc.stat().st_mode & 0o777 == 0o640
        run("remove", "bash", str(shellrc))
        assert shellrc.read_text(encoding="utf-8") == original

        target = Path(temporary) / "target"
        target.write_text("safe\n", encoding="utf-8")
        link = Path(temporary) / "link"
        try:
            link.symlink_to(target)
        except OSError:
            pass
        else:
            result = subprocess.run([sys.executable, str(EDITOR), "add", "bash", str(link)], check=False)
            assert result.returncode != 0 and target.read_text(encoding="utf-8") == "safe\n"
    print("Shell integration tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
