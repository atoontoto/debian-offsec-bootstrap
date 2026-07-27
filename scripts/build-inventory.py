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


def executable_state(executable: str) -> dict[str, str | bool | None]:
    path = shutil.which(executable)
    version = None
    if path:
        try:
            result = subprocess.run([path, "--version"], text=True, capture_output=True, timeout=3, check=False)
            lines = (result.stdout or result.stderr).splitlines()
            version = lines[0][:300] if lines else "present"
        except (OSError, subprocess.TimeoutExpired):
            version = "present"
    return {"name": executable, "installed": path is not None, "path": path, "version": version}


def channel_metadata(catalog: Path) -> dict[str, dict[str, object]]:
    manifests = catalog.parent
    metadata: dict[str, dict[str, object]] = {}
    go_manifest = manifests / "go-tools.tsv"
    if go_manifest.exists():
        for line in go_manifest.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            tool_id, module, version, _ = line.split("\t")
            metadata[tool_id] = {"pinned_version": version, "release_source": f"{module}@{version}"}
    github_manifest = manifests / "github-tools.tsv"
    if github_manifest.exists():
        for line in github_manifest.read_text(encoding="utf-8").splitlines():
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) == 7:
                tool_id, repo, tag, _, checksum, _, _ = fields
            elif len(fields) == 10:
                tool_id, _, repo, tag, _, _, checksum, _, _, _ = fields
            else:
                continue
            entry = metadata.setdefault(tool_id, {
                "pinned_version": tag,
                "release_source": f"https://github.com/{repo}/releases/tag/{tag}",
                "checksum_sources": [],
            })
            sources = entry.setdefault("checksum_sources", [])
            if checksum not in sources:
                sources.append(checksum)
    return metadata


def verified_github_state(path: Path | None) -> dict[str, dict[str, str]]:
    state: dict[str, dict[str, str]] = {}
    if not path or not path.is_file():
        return state
    for line in path.read_text(encoding="utf-8").splitlines():
        fields = line.split("\t")
        if len(fields) >= 3:
            state[fields[0]] = {"version": fields[1], "release_source": fields[2]}
    return state


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--profile", choices=("core", "standard", "full"), required=True)
    parser.add_argument("--category")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--owner", required=True)
    parser.add_argument("--github-state", type=Path)
    args = parser.parse_args()
    tools = []
    metadata = channel_metadata(args.catalog)
    github_state = verified_github_state(args.github_state)
    with args.catalog.open(encoding="utf-8", newline="") as stream:
        for row in csv.DictReader(stream, delimiter="\t"):
            if not included(args.profile, row["profile"]):
                continue
            if args.category and row["category"] != args.category:
                continue
            executable_states = [executable_state(name) for name in row["executables"].split(",")]
            installed_count = sum(bool(state["installed"]) for state in executable_states)
            tool = {
                "id": row["id"], "display_name": row["display_name"],
                "category": row["category"], "method": row["method"],
                "identifier": row["identifier"], "installed": installed_count == len(executable_states),
                "partial": 0 < installed_count < len(executable_states),
                "path": executable_states[0]["path"], "version": executable_states[0]["version"],
                "executables": executable_states,
            }
            tool.update(metadata.get(row["id"], {}))
            if row["method"] == "github":
                state = github_state.get(row["id"])
                tool["verified_source"] = bool(
                    state and state["version"] == tool.get("pinned_version")
                    and state["release_source"] == tool.get("release_source")
                )
            tools.append(tool)
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
