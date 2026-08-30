#!/usr/bin/env python3
"""Read the SAR 16-bit schematic hierarchy through the Virtuoso bridge."""

from __future__ import annotations

import argparse
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.schematic.reader import read_schematic


LIBRARY = "12bit_50M_SAR"
TOP_CELL = "test_16bit5MSAR_ideal"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--max-depth", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=90)
    queue: deque[tuple[str, int]] = deque([(TOP_CELL, 0)])
    visited: set[str] = set()
    hierarchy: dict[str, object] = {}
    failures: dict[str, str] = {}

    while queue:
        cell, depth = queue.popleft()
        if cell in visited:
            continue
        visited.add(cell)
        print(f"Reading {LIBRARY}/{cell}/schematic at depth {depth}...", flush=True)
        try:
            data = read_schematic(
                client,
                LIBRARY,
                cell,
                include_positions=False,
            )
        except Exception as exc:  # Preserve a complete audit trail.
            failures[cell] = f"{type(exc).__name__}: {exc}"
            continue

        refs = sorted(
            {
                str(inst.get("cell", ""))
                for inst in data.get("instances", [])
                if inst.get("lib") == LIBRARY and inst.get("cell")
            }
        )
        hierarchy[cell] = {
            "depth": depth,
            "instances": data.get("instances", []),
            "nets": data.get("nets", {}),
            "pins": data.get("pins", {}),
            "notes": data.get("notes", []),
            "same_library_references": refs,
        }
        if depth < args.max_depth:
            for ref in refs:
                if ref not in visited:
                    queue.append((ref, depth + 1))

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "read_only_oa",
        "library": LIBRARY,
        "top_cell": TOP_CELL,
        "max_depth": args.max_depth,
        "read_cells": sorted(hierarchy),
        "read_cell_count": len(hierarchy),
        "failures": failures,
        "hierarchy": hierarchy,
    }
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {args.output}: {len(hierarchy)} cells read, "
        f"{len(failures)} unavailable views."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
