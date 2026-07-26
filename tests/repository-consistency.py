#!/usr/bin/env python3
"""Cross-check catalogs, channel manifests, modules, helpers, and owned paths."""
from __future__ import annotations

import csv
import re
import sys
from collections import defaultdict
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
COLUMNS = [
    "id", "display_name", "category", "method", "identifier", "executables",
    "homepage", "source_repository", "license", "needs_root", "network_service",
    "requires_docker", "gui", "update_method", "verification_command", "profile",
    "notes_or_conflicts",
]
CATEGORIES = {
    "base", "network", "web", "ad", "passwords", "exploitation", "cloud",
    "wireless", "reverse-engineering", "forensics", "osint", "containers",
    "wordlists", "desktop",
}
METHODS = {"apt", "pipx", "go", "cargo", "github", "docker", "manual"}
BOOL_COLUMNS = ("needs_root", "network_service", "requires_docker", "gui")
CHANNELS = {
    "pipx": ("pipx-tools.txt", 5),
    "go": ("go-tools.tsv", 4),
    "cargo": ("cargo-tools.tsv", 5),
    "github": ("github-tools.tsv", 7),
    "manual": ("manual-tools.tsv", 4),
}


def rows(path: Path, expected_columns: int) -> list[list[str]]:
    result = []
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line or line.startswith("#"):
            continue
        fields = line.split("\t")
        if fields[0] == "id":
            continue
        if len(fields) != expected_columns:
            raise ValueError(f"{path.relative_to(ROOT)}:{number}: expected {expected_columns} fields, got {len(fields)}")
        result.append(fields)
    return result


def https_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and bool(parsed.netloc) and not any(character.isspace() for character in value)


def main() -> int:
    errors: list[str] = []
    catalog_path = ROOT / "manifests/tool-catalog.tsv"
    with catalog_path.open(encoding="utf-8", newline="") as stream:
        reader = csv.DictReader(stream, delimiter="\t")
        if reader.fieldnames != COLUMNS:
            errors.append("tool catalog header does not match the 17-column schema")
        catalog_rows = list(reader)

    by_id: dict[str, dict[str, str]] = {}
    executables: dict[str, list[dict[str, str]]] = defaultdict(list)
    for number, row in enumerate(catalog_rows, 2):
        tool_id = row.get("id", "")
        if not re.fullmatch(r"[a-z0-9][a-z0-9._+-]*", tool_id):
            errors.append(f"tool-catalog.tsv:{number}: invalid id {tool_id!r}")
        if tool_id in by_id:
            errors.append(f"duplicate catalog id: {tool_id}")
        by_id[tool_id] = row
        if row.get("category") not in CATEGORIES:
            errors.append(f"{tool_id}: unknown category {row.get('category')!r}")
        if row.get("method") not in METHODS:
            errors.append(f"{tool_id}: unknown method {row.get('method')!r}")
        if row.get("profile") not in {"core", "standard", "full", "optional"}:
            errors.append(f"{tool_id}: invalid profile {row.get('profile')!r}")
        for column in BOOL_COLUMNS:
            if row.get(column) not in {"true", "false", "optional"}:
                errors.append(f"{tool_id}: invalid {column} value {row.get(column)!r}")
        if not row.get("identifier") or not row.get("executables"):
            errors.append(f"{tool_id}: identifier and executables are required")
        if not https_url(row.get("source_repository", "")) and row.get("source_repository") != "-":
            errors.append(f"{tool_id}: source repository must be HTTPS or '-'")
        for executable in row.get("executables", "").split(","):
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", executable):
                errors.append(f"{tool_id}: unsafe executable name {executable!r}")
            executables[executable].append(row)

    for executable, owners in executables.items():
        if len(owners) > 1 and not any(re.search(r"overlay|conflict|alternative", row["notes_or_conflicts"], re.I) for row in owners):
            errors.append(f"duplicate executable lacks a documented conflict: {executable}")

    seen_channel_ids: dict[str, str] = {}
    for method, (filename, width) in CHANNELS.items():
        try:
            channel_rows = rows(ROOT / "manifests" / filename, width)
        except ValueError as error:
            errors.append(str(error))
            continue
        local_ids: set[str] = set()
        for fields in channel_rows:
            tool_id = fields[0]
            if tool_id in local_ids:
                errors.append(f"duplicate {method} manifest id: {tool_id}")
            local_ids.add(tool_id)
            if tool_id in seen_channel_ids:
                errors.append(f"channel id {tool_id} occurs in both {seen_channel_ids[tool_id]} and {method}")
            seen_channel_ids[tool_id] = method
            if tool_id not in by_id:
                errors.append(f"{method} manifest id is absent from catalog: {tool_id}")
            elif by_id[tool_id]["method"] != method:
                errors.append(f"{tool_id}: catalog method {by_id[tool_id]['method']} disagrees with {method} manifest")
            if method == "manual" and not https_url(fields[1]):
                errors.append(f"{tool_id}: manual URL must use HTTPS")
        expected = {tool_id for tool_id, row in by_id.items() if row["method"] == method}
        for tool_id in sorted(expected - local_ids):
            errors.append(f"catalog {tool_id} lacks its {method} channel entry")

    apt_lines = [line.split("#", 1)[0].strip() for line in (ROOT / "manifests/apt-packages.txt").read_text(encoding="utf-8").splitlines()]
    apt_packages = [line for line in apt_lines if line]
    if len(apt_packages) != len(set(apt_packages)):
        errors.append("apt-packages.txt contains duplicate package identifiers")

    try:
        resources = rows(ROOT / "manifests/git-resources.tsv", 4)
    except ValueError as error:
        errors.append(str(error))
        resources = []
    resource_ids: set[str] = set()
    resource_links: set[str] = set()
    for resource_id, url, commit, link in resources:
        if resource_id in resource_ids or link in resource_links:
            errors.append(f"duplicate managed Git resource id or link: {resource_id}/{link}")
        resource_ids.add(resource_id); resource_links.add(link)
        if not https_url(url) or not url.endswith(".git"):
            errors.append(f"{resource_id}: managed Git URL must be HTTPS and end in .git")
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            errors.append(f"{resource_id}: managed Git resource is not pinned to a full commit")

    required_modules = {category if category != "ad" else "active-directory" for category in CATEGORIES - {"desktop", "wordlists"}}
    for module in sorted(required_modules | {"desktop", "wordlists"}):
        if not (ROOT / "modules" / f"{module}.sh").is_file():
            errors.append(f"missing category module: modules/{module}.sh")

    owned_paths = [line for line in (ROOT / "manifests/owned-paths.txt").read_text(encoding="utf-8").splitlines() if line and not line.startswith("#")]
    if len(owned_paths) != len(set(owned_paths)):
        errors.append("owned-paths.txt contains duplicates")
    if any(not path.startswith("/") or path in {"/", "/opt", "/usr", "/var", "/home"} for path in owned_paths):
        errors.append("owned-paths.txt contains an unsafe path")
    service = (ROOT / "systemd/debian-offsec-bootstrap-update.service").read_text(encoding="utf-8")
    if "ExecStart=/usr/local/bin/offsec-update --non-interactive" not in service:
        errors.append("systemd update service must use the custom-root-aware helper")
    helper_names = {Path(path).name for path in owned_paths if path.startswith("/usr/local/bin/")}
    for desktop_path in (ROOT / "desktop").glob("*.desktop"):
        values: dict[str, str] = {}
        for line in desktop_path.read_text(encoding="utf-8").splitlines():
            if "=" in line and not line.startswith("#"):
                key, value = line.split("=", 1)
                values[key] = value
        for required_key in ("Type", "Name", "Exec", "Terminal", "Categories"):
            if not values.get(required_key):
                errors.append(f"{desktop_path.name}: missing desktop key {required_key}")
        command = values.get("Exec", "").split(maxsplit=1)[0]
        if command not in helper_names | {"xdg-open"}:
            errors.append(f"{desktop_path.name}: Exec references an unmanaged command: {command}")

    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if ".git" in relative.parts or relative.parts[:2] == ("tests", "tmp") or path.name in {"local.conf", "installed.conf"}:
            continue
        if path.is_file() and path.suffix in {".sh", ".py", ".tsv", ".txt", ".conf", ".yml", ".md", ".desktop", ".service", ".timer"}:
            if path.read_bytes() and not path.read_bytes().endswith(b"\n"):
                errors.append(f"file lacks a final newline: {relative}")

    if errors:
        for error in errors:
            print(f"consistency error: {error}", file=sys.stderr)
        return 1
    print(f"Repository consistency validated across {len(catalog_rows)} catalog entries and {len(seen_channel_ids)} channel entries.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
