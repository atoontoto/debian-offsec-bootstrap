#!/usr/bin/env python3
"""Regression tests for traversal and special-entry archive rejection."""
from __future__ import annotations

import io
import stat
import subprocess
import sys
import tarfile
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts/validate-archive.py"


def accepted(path: Path) -> bool:
    return subprocess.run([sys.executable, str(VALIDATOR), str(path)], capture_output=True, check=False).returncode == 0


def tar_with(path: Path, member: tarfile.TarInfo) -> None:
    with tarfile.open(path, "w") as archive:
        if member.isfile():
            data = b"content"
            member.size = len(data)
            archive.addfile(member, io.BytesIO(data))
        else:
            archive.addfile(member)


def main() -> int:
    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        safe = root / "safe.tar"
        tar_with(safe, tarfile.TarInfo("directory/file.txt"))
        assert accepted(safe)

        for name, member_type, link in (
            ("symlink", tarfile.SYMTYPE, "../../outside"),
            ("hardlink", tarfile.LNKTYPE, "../../outside"),
            ("fifo", tarfile.FIFOTYPE, ""),
            ("device", tarfile.CHRTYPE, ""),
        ):
            member = tarfile.TarInfo("directory/entry")
            member.type = member_type
            member.linkname = link
            archive = root / f"{name}.tar"
            tar_with(archive, member)
            assert not accepted(archive), name

        traversal = root / "traversal.zip"
        with zipfile.ZipFile(traversal, "w") as archive:
            archive.writestr("..\\outside", "bad")
        assert not accepted(traversal)

        symlink = root / "symlink.zip"
        info = zipfile.ZipInfo("link")
        info.create_system = 3
        info.external_attr = (stat.S_IFLNK | 0o777) << 16
        with zipfile.ZipFile(symlink, "w") as archive:
            archive.writestr(info, "../../outside")
        assert not accepted(symlink)

        collision = root / "collision.zip"
        with zipfile.ZipFile(collision, "w") as archive:
            archive.writestr("parent", "file")
            archive.writestr("parent/child", "bad")
        assert not accepted(collision)
    print("Archive safety tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
