#!/usr/bin/env python3
"""Generate the reviewable inventory of custom Neovim behavior."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "CUSTOMIZATIONS.md"
MANIFEST = ROOT / "tests/customizations.json"
CONFIG_FILES = [ROOT / "init.lua", *sorted((ROOT / "lua/config").glob("*.lua"))]


def display(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def location(path: Path, offset: int) -> str:
    line = path.read_text().count("\n", 0, offset) + 1
    return f"`{display(path)}:{line}`"


def inventory() -> str:
    manifest = json.loads(MANIFEST.read_text())
    plugins: list[tuple[str, str]] = []
    options: list[tuple[str, str, str]] = []
    mappings: list[tuple[str, str, str, str]] = []
    autocmds: list[tuple[str, str]] = []

    for path in CONFIG_FILES:
        source = path.read_text()
        for match in re.finditer(r"\{\s*src\s*=\s*'https://github\.com/([^']+)'", source):
            plugins.append((match.group(1), location(path, match.start())))
        for match in re.finditer(r"(?m)^\s*vim\.(?:o|g|opt)\.([A-Za-z0-9_]+)\s*=\s*(?!=)([^\n]+)", source):
            value = match.group(2).split("--", 1)[0].strip()
            options.append((match.group(1), f"`{value}`", location(path, match.start())))
        for match in re.finditer(
            r"vim\.keymap\.set\(\s*(['\"])([^'\"]+)\1\s*,\s*(['\"])([^'\"]+)\3[\s\S]{0,500}?desc\s*=\s*(['\"])(.*?)\5",
            source,
        ):
            key = match.group(4)
            if not key.endswith('<leader>'):
                mappings.append((match.group(2), key, match.group(6), location(path, match.start())))
        for match in re.finditer(r"nvim_create_autocmd\(\s*('(?:[^']+)'|\{[^}]+\})\s*,", source):
            autocmds.append((match.group(1).strip(), location(path, match.start())))

    declared_plugins = set(manifest["plugins"])
    discovered_plugins = {name for name, _ in plugins}
    if declared_plugins != discovered_plugins:
        raise ValueError(f"plugin manifest drift: declared={sorted(declared_plugins)} discovered={sorted(discovered_plugins)}")

    configured_options = {name for name, _, _ in options}
    declared_options = set(manifest["options"]) | {"mapleader", "maplocalleader", "listchars"}
    if configured_options != declared_options:
        raise ValueError(f"option manifest drift: declared={sorted(declared_options)} discovered={sorted(configured_options)}")

    literal_mappings = {(mode, key) for mode, key, _, _ in mappings if key not in {"q", "<CR>"}}
    declared_mappings = {(mode, key) for mode, entries in manifest["keymaps"].items() for key in entries}
    missing_mappings = literal_mappings - declared_mappings
    if missing_mappings:
        raise ValueError(f"keymap manifest drift: add {sorted(missing_mappings)}")
    mapping_locations = {(mode, key): where for mode, key, _, where in mappings}
    recorded_mappings = [
        (mode, key, description, mapping_locations.get((mode, key), "generated in configuration"))
        for mode, entries in manifest["keymaps"].items()
        for key, description in entries.items()
    ]

    discovered_events = set()
    for expression, _ in autocmds:
        discovered_events.update(re.findall(r"'([^']+)'", expression))
    if discovered_events != set(manifest["autocmd_events"]):
        raise ValueError(
            f"autocmd manifest drift: declared={sorted(manifest['autocmd_events'])} discovered={sorted(discovered_events)}"
        )
    for test in manifest["behaviors"]:
        if not (ROOT / test).is_file():
            raise ValueError(f"behavioral test does not exist: {test}")

    rows = [
        "# Customization record",
        "",
        "> Generated from the executable `tests/customizations.json` manifest by `make customizations`;",
        "> do not edit by hand. CI fails when configuration, tests, and this record drift apart.",
        "",
        "## Plugins",
        "",
        "| Repository | Runtime module | Declared at |",
        "| --- | --- | --- |",
        *[f"| `{name}` | `{manifest['plugins'][name]}` | {where} |" for name, where in plugins],
        "",
        "## Editor and global settings",
        "",
        "| Setting | Configured value | Declared at |",
        "| --- | --- | --- |",
        *[f"| `{name}` | {value} | {where} |" for name, value, where in options],
        "",
        "## Keymaps",
        "",
        "Mappings with literal modes and keys are listed; generated mappings are exercised by their feature tests.",
        "",
        "| Mode | Key | Purpose | Declared at |",
        "| --- | --- | --- | --- |",
        *[f"| `{mode}` | `{key.replace('|', '&#124;')}` | {desc} | {where} |"
          for mode, key, desc, where in recorded_mappings],
        "",
        "## Automation",
        "",
        "| Event expression | Declared at |",
        "| --- | --- |",
        *[f"| `{event}` | {where} |" for event, where in autocmds],
        "",
        "## Behavioral coverage",
        "",
        "| Area | Executable record |",
        "| --- | --- |",
        *[f"| {description} | `{test}` |" for test, description in manifest["behaviors"].items()],
        "",
    ]
    return "\n".join(rows)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the committed record is stale")
    args = parser.parse_args()
    generated = inventory()
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_text() != generated:
            print("CUSTOMIZATIONS.md is stale; run `make customizations` and commit the result.")
            return 1
        print("Customization record is current.")
        return 0
    OUTPUT.write_text(generated)
    print(f"Updated {display(OUTPUT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
