#!/usr/bin/env python3
"""Select exactly one release asset from GitHub API JSON."""
from __future__ import annotations

import json
import re
import sys


def main() -> int:
    if len(sys.argv) != 2:
        return 2
    try:
        pattern = re.compile(sys.argv[1])
        document = json.load(sys.stdin)
        matches = [
            (asset["name"], asset["browser_download_url"])
            for asset in document.get("assets", [])
            if isinstance(asset, dict)
            and isinstance(asset.get("name"), str)
            and isinstance(asset.get("browser_download_url"), str)
            and pattern.search(asset["name"])
        ]
    except (OSError, ValueError, re.error, TypeError, KeyError) as error:
        print(f"invalid GitHub release metadata: {error}", file=sys.stderr)
        return 1
    if len(matches) != 1:
        print(f"asset regex matched {len(matches)} release assets", file=sys.stderr)
        return 1
    print("\t".join(matches[0]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
