#!/usr/bin/env python3
"""Validate APT identifiers against an official Debian Packages.xz index."""
from __future__ import annotations
import argparse
import csv
import lzma
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("index", type=Path, help="Trixie binary-amd64 Packages.xz")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    packages: set[str] = set()
    with lzma.open(args.index, "rt", encoding="utf-8", errors="replace") as stream:
        for line in stream:
            if line.startswith("Package: "):
                packages.add(line.removeprefix("Package: ").strip())
    foundation = {
        clean for line in (args.root / "manifests/apt-packages.txt").read_text(encoding="utf-8").splitlines()
        if (clean := line.split("#", 1)[0].strip())
    }
    with (args.root / "manifests/tool-catalog.tsv").open(encoding="utf-8", newline="") as stream:
        catalog = {row["identifier"] for row in csv.DictReader(stream, delimiter="\t") if row["method"] == "apt"}
    missing_foundation = sorted(foundation - packages)
    missing_catalog = sorted(catalog - packages)
    if missing_foundation or missing_catalog:
        print(f"missing foundation packages: {missing_foundation}")
        print(f"missing catalog packages: {missing_catalog}")
        return 1
    print(f"Validated {len(foundation)} foundation and {len(catalog)} unique catalog APT identifiers against {len(packages)} indexed packages.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
