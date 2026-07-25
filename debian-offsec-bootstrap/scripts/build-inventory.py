#!/usr/bin/env python3
"""Build a redaction-safe inventory from the single source-of-truth catalog."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import shutil
import subprocess
from pathlib import Path


def included(selected: str, membership: str) -> bool:
    return membership == "core" if selected == "core" else membership in ({"core", "standard"} if selected == "standard" else {"core", "standard", "full"})


def version_for(executables: str) -> tuple[str | None, str | None]:
    for executable in executables.split(","):
        path = shutil.which(executable)
        if not path:
            continue
        try:
            result = subprocess.run([path, "--version"], text=True, capture_output=True, timeout=3, check=False)
            line = (result.stdout or result.stderr).splitlines()
            version = line[0][:300] if line else "present"
        except (OSError, subprocess.TimeoutExpired):
            version = "present"
        return path, version
    return None, None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--profile", choices=("core", "standard", "full"), required=True)
    parser.add_argument("--category")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--owner", required=True)
    args = parser.parse_args()
    tools = []
    with args.catalog.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            if not included(args.profile, row["profile"]):
                continue
            if args.category and row["category"] != args.category:
                continue
            path, version = version_for(row["executables"])
            tools.append({
                "id": row["id"], "display_name": row["display_name"],
                "category": row["category"], "method": row["method"],
                "identifier": row["identifier"], "installed": path is not None,
                "path": path, "version": version,
            })
    document = {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "profile": args.profile, "owner": args.owner,
        "platform": {"os": "Debian", "target_version": "13", "architecture": "amd64"},
        "tools": tools,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_suffix(args.output.suffix + f".tmp.{os.getpid()}")
    temporary.write_text(json.dumps(document, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
