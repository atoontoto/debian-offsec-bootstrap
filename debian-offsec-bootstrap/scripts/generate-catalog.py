#!/usr/bin/env python3
"""Generate docs/TOOL_CATALOG.md from manifests/tool-catalog.tsv."""
from __future__ import annotations
import argparse
import csv
from pathlib import Path


def render(catalog: Path) -> str:
    rows = list(csv.DictReader(catalog.open(encoding="utf-8", newline=""), delimiter="\t"))
    lines = ["# Curated Tool Catalog", "", f"This generated catalog contains **{len(rows)} tools**. Edit `manifests/tool-catalog.tsv`, not this file.", "", "| Tool | Category | Method | Profile | Executables | License |", "|---|---|---|---|---|---|"]
    for row in rows:
        values = [row[k].replace("|", "\\|") for k in ("display_name", "category", "method", "profile", "executables", "license")]
        lines.append("| " + " | ".join(values) + " |")
    lines.extend(["", "Every tool remains governed by its own upstream license. Inclusion does not relicense or redistribute third-party software.", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, default=Path("manifests/tool-catalog.tsv"))
    parser.add_argument("--output", type=Path, default=Path("docs/TOOL_CATALOG.md"))
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    content = render(args.catalog)
    if args.check:
        return 0 if args.output.exists() and args.output.read_text(encoding="utf-8") == content else 1
    args.output.write_text(content, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
