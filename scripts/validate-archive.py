#!/usr/bin/env python3
"""Reject archive layouts that can escape or confuse a clean extraction root."""
from __future__ import annotations

import argparse
import stat
import tarfile
import zipfile
from pathlib import Path, PurePosixPath


def normalized_name(raw: str) -> str:
    name = raw.replace("\\", "/")
    path = PurePosixPath(name)
    if not name or name.startswith("/") or path.is_absolute():
        raise ValueError(f"absolute or empty archive path: {raw!r}")
    if path.parts and path.parts[0].endswith(":"):
        raise ValueError(f"drive-qualified archive path: {raw!r}")
    if any(part in ("", ".", "..") for part in path.parts):
        raise ValueError(f"ambiguous or traversing archive path: {raw!r}")
    return str(path)


def validate_layout(entries: list[tuple[str, bool]]) -> None:
    seen: dict[str, bool] = {}
    for raw_name, is_directory in entries:
        name = normalized_name(raw_name.rstrip("/") if is_directory else raw_name)
        if name in seen:
            raise ValueError(f"duplicate archive path: {name!r}")
        parent = PurePosixPath(name).parent
        while str(parent) != ".":
            parent_name = str(parent)
            if parent_name in seen and not seen[parent_name]:
                raise ValueError(f"archive file used as a parent: {parent_name!r}")
            parent = parent.parent
        seen[name] = is_directory


def validate_zip(path: Path) -> None:
    entries: list[tuple[str, bool]] = []
    with zipfile.ZipFile(path) as archive:
        for item in archive.infolist():
            if item.flag_bits & 0x1:
                raise ValueError(f"encrypted ZIP entry: {item.filename!r}")
            mode = item.external_attr >> 16
            file_type = stat.S_IFMT(mode)
            if file_type and not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise ValueError(f"unsupported ZIP entry type: {item.filename!r}")
            entries.append((item.filename, item.is_dir()))
    validate_layout(entries)


def validate_tar(path: Path) -> None:
    entries: list[tuple[str, bool]] = []
    with tarfile.open(path, mode="r:*") as archive:
        for item in archive.getmembers():
            if not (item.isfile() or item.isdir()):
                raise ValueError(f"unsupported TAR entry type: {item.name!r}")
            entries.append((item.name, item.isdir()))
    validate_layout(entries)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    try:
        if args.archive.name.endswith(".zip"):
            validate_zip(args.archive)
        else:
            validate_tar(args.archive)
    except (OSError, ValueError, tarfile.TarError, zipfile.BadZipFile) as error:
        print(f"unsafe archive: {error}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
