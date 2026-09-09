#!/usr/bin/env python3
"""Fail when declared configuration is missing from the executable spec."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = ROOT / "tests/config_spec.json"
CONFIG_FILES = [ROOT / "init.lua", *sorted((ROOT / "lua/config").glob("*.lua"))]


def fail(kind: str, expected: set, actual: set) -> None:
    if expected != actual:
        raise SystemExit(
            f"{kind} spec drift:\n  expected: {sorted(expected)}\n  configured: {sorted(actual)}"
        )


def main() -> None:
    spec = json.loads(SPEC.read_text())
    source = "\n".join(path.read_text() for path in CONFIG_FILES)

    plugins = set(re.findall(r"\{\s*src\s*=\s*'https://github\.com/([^']+)'", source))
    fail("plugin", set(spec["plugins"]), plugins)

    options = set(
        re.findall(r"(?m)^\s*vim\.(?:o|g|opt)\.([A-Za-z0-9_]+)\s*=\s*(?!=)", source)
    )
    expected_options = set(spec["options"]) | {"mapleader", "maplocalleader", "listchars"}
    fail("option", expected_options, options)

    mappings = {
        (mode, key)
        for _, mode, _, key in re.findall(
            r"vim\.keymap\.set\(\s*(['\"])([^'\"]+)\1\s*,\s*(['\"])([^'\"]+)\3",
            source,
        )
        if key not in {"q", "<CR>"} and not key.endswith("<leader>")
    }
    expected_mappings = {
        (mode, key) for mode, entries in spec["keymaps"].items() for key in entries
    }
    unexpected_mappings = mappings - expected_mappings
    if unexpected_mappings:
        raise SystemExit(f"keymap spec drift; add: {sorted(unexpected_mappings)}")

    event_expressions = re.findall(
        r"nvim_create_autocmd\(\s*('(?:[^']+)'|\{[^}]+\})\s*,", source
    )
    events = {event for expression in event_expressions for event in re.findall(r"'([^']+)'", expression)}
    fail("autocmd", set(spec["autocmd_events"]), events)

    missing_tests = [test for test in spec["behaviors"] if not (ROOT / test).is_file()]
    if missing_tests:
        raise SystemExit(f"behavioral tests do not exist: {missing_tests}")

    print("Configuration declarations match tests/config_spec.json.")


if __name__ == "__main__":
    main()
