#!/usr/bin/env python3
"""Create a read-only inventory of the live VM SAR_16B_5M design series."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import sys
from datetime import datetime, timezone
from pathlib import Path

VM_REMOTE = Path(r"D:\ReedZhao\vm-remote")
if str(VM_REMOTE) not in sys.path:
    sys.path.insert(0, str(VM_REMOTE))

from vm_base import VMConnection  # noqa: E402


LIBRARY_PATHS = {
    "SAR_16B_5M_CORE": "/home/meow/IC/SAR_16B_5M_CORE",
    "SAR_16B_5M_EXP": "/home/meow/IC/SAR_16B_5M_EXP",
    "SAR_16B_5M_TB": "/home/meow/IC/SAR_16B_5M_TB",
}
SIMULATION_ROOT = "/home/meow/IC/simulation/SAR_16B_5M_TB"


def parse_cds_lib(text: str) -> dict[str, str]:
    """Return direct DEFINE entries from one cds.lib file."""
    libraries: dict[str, str] = {}
    for raw_line in text.splitlines():
        match = re.match(r"(?i)^\s*DEFINE\s+(\S+)\s+(\S+)", raw_line)
        if match:
            libraries[match.group(1)] = match.group(2)
    return libraries


def collect_library(vm: VMConnection, name: str, root: str) -> dict[str, object]:
    """Collect OA cell/view names without opening or modifying the library."""
    if not vm.is_dir(root):
        return {"name": name, "path": root, "exists": False}

    result = vm.run(
        f"find {shlex.quote(root)} -mindepth 1 -maxdepth 3 -type d -printf '%P\n' | sort",
        timeout=120,
    )
    relative_dirs = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    cells: dict[str, list[str]] = {}
    for relative in relative_dirs:
        parts = relative.split("/")
        if len(parts) == 1:
            cells.setdefault(parts[0], [])
        elif len(parts) == 2:
            cells.setdefault(parts[0], []).append(parts[1])

    for views in cells.values():
        views.sort()

    return {
        "name": name,
        "path": root,
        "exists": True,
        "cell_count": len(cells),
        "cells": dict(sorted(cells.items())),
        "find_stderr": result.stderr.strip(),
    }


def collect_simulation_tree(vm: VMConnection, root: str) -> dict[str, object]:
    """Collect simulation file metadata and small text-file candidates."""
    if not vm.is_dir(root):
        return {"path": root, "exists": False}

    files_result = vm.run(
        f"find {shlex.quote(root)} -maxdepth 8 -type f "
        "-printf '%s\t%TY-%Tm-%TdT%TH:%TM:%TS\t%p\n' | sort -k3",
        timeout=180,
    )
    files: list[dict[str, object]] = []
    for line in files_result.stdout.splitlines():
        fields = line.split("\t", 2)
        if len(fields) != 3:
            continue
        size, modified, path = fields
        files.append({"path": path, "size_bytes": int(size), "modified": modified})

    candidate_names = {
        "input.scs",
        "netlist",
        "spectre.out",
        "runSimulation",
        "runObjFile",
        "logFile",
        "psfRun",
    }
    text_candidates = [
        item
        for item in files
        if Path(str(item["path"])).name in candidate_names
        or str(item["path"]).endswith((".scs", ".ocn", ".tcl", ".log"))
    ]

    return {
        "path": root,
        "exists": True,
        "file_count": len(files),
        "total_size_bytes": sum(int(item["size_bytes"]) for item in files),
        "files": files,
        "text_candidates": text_candidates,
        "find_stderr": files_result.stderr.strip(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    report: dict[str, object] = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "host": args.host,
        "mode": "read_only",
    }

    with VMConnection(host=args.host) as vm:
        report["hostname"] = vm.run("hostname").stdout.strip()

        cds_find = vm.run(
            "find /home/meow -maxdepth 5 -type f -name cds.lib -print 2>/dev/null | sort",
            timeout=120,
        )
        cds_libraries: dict[str, object] = {}
        for cds_path in [line.strip() for line in cds_find.stdout.splitlines() if line.strip()]:
            text = vm.read_file(cds_path)
            cds_libraries[cds_path] = {
                "defines": parse_cds_lib(text),
                "text": text,
            }
        report["cds_libraries"] = cds_libraries

        report["libraries"] = {
            name: collect_library(vm, name, root)
            for name, root in LIBRARY_PATHS.items()
        }
        report["simulation"] = collect_simulation_tree(vm, SIMULATION_ROOT)

        process_result = vm.run(
            "ps -eo pid,lstart,args | grep -E '[v]irtuoso|[s]pectre'",
            timeout=30,
        )
        report["cadence_processes"] = [
            line.strip() for line in process_result.stdout.splitlines() if line.strip()
        ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(f"Wrote {args.output}")
    for name, library in report["libraries"].items():
        print(f"{name}: {library.get('cell_count', 0)} cells")
        for cell, views in library.get("cells", {}).items():
            print(f"  {cell}: {', '.join(views) if views else '(no view directory)'}")
    simulation = report["simulation"]
    print(
        f"Simulation tree: {simulation.get('file_count', 0)} files, "
        f"{simulation.get('total_size_bytes', 0)} bytes"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
