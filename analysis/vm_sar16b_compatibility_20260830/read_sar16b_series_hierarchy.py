#!/usr/bin/env python3
"""Read the live SAR_16B_5M cross-library schematic hierarchy."""

from __future__ import annotations

import argparse
import json
from collections import deque
from datetime import datetime, timezone
from pathlib import Path

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.schematic.reader import read_schematic


DEFAULT_LIBRARY = "SAR_16B_5M_TB"
DEFAULT_TOP_CELL = "TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6"
PROJECT_LIBRARIES = {
    "SAR_16B_5M_CORE",
    "SAR_16B_5M_EXP",
    "SAR_16B_5M_TB",
}


def design_key(library: str, cell: str) -> str:
    return f"{library}/{cell}"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--library", default=DEFAULT_LIBRARY)
    parser.add_argument("--cell", default=DEFAULT_TOP_CELL)
    parser.add_argument("--max-depth", type=int, default=10)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=120)
    queue: deque[tuple[str, str, int]] = deque([(args.library, args.cell, 0)])
    visited: set[tuple[str, str]] = set()
    hierarchy: dict[str, object] = {}
    failures: dict[str, str] = {}

    while queue:
        library, cell, depth = queue.popleft()
        design = (library, cell)
        if design in visited:
            continue
        visited.add(design)
        key = design_key(library, cell)
        print(f"Reading {key}/schematic at depth {depth}...", flush=True)

        try:
            data = read_schematic(
                client,
                library,
                cell,
                include_positions=False,
            )
        except Exception as exc:
            failures[key] = f"{type(exc).__name__}: {exc}"
            continue

        references = sorted(
            {
                (str(inst.get("lib", "")), str(inst.get("cell", "")))
                for inst in data.get("instances", [])
                if inst.get("lib") in PROJECT_LIBRARIES and inst.get("cell")
            }
        )
        hierarchy[key] = {
            "library": library,
            "cell": cell,
            "depth": depth,
            "instances": data.get("instances", []),
            "nets": data.get("nets", {}),
            "pins": data.get("pins", {}),
            "notes": data.get("notes", []),
            "project_references": [
                design_key(ref_library, ref_cell)
                for ref_library, ref_cell in references
            ],
        }

        if depth < args.max_depth:
            for ref_library, ref_cell in references:
                ref_design = (ref_library, ref_cell)
                if ref_design not in visited:
                    queue.append((ref_library, ref_cell, depth + 1))

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "read_only_oa",
        "top_library": args.library,
        "top_cell": args.cell,
        "max_depth": args.max_depth,
        "read_designs": sorted(hierarchy),
        "read_design_count": len(hierarchy),
        "failures": failures,
        "hierarchy": hierarchy,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(
        f"Wrote {args.output}: {len(hierarchy)} designs read, "
        f"{len(failures)} unavailable views."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
