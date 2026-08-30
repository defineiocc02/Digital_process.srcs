#!/usr/bin/env python3
"""Read-only inventory of SAR_16B Cadence assets in the configured VM."""

from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

VM_REMOTE = Path(r"D:\ReedZhao\vm-remote")
if str(VM_REMOTE) not in sys.path:
    sys.path.insert(0, str(VM_REMOTE))

from vm_base import VMConnection  # noqa: E402


def parse_cds_lib(text: str) -> dict[str, str]:
    """Return direct DEFINE entries from cds.lib."""
    libraries: dict[str, str] = {}
    for raw_line in text.splitlines():
        line = raw_line.strip()
        match = re.match(r"(?i)^DEFINE\s+(\S+)\s+(\S+)", line)
        if match:
            libraries[match.group(1)] = match.group(2)
    return libraries


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

    print(f"Connecting to {args.host}...", flush=True)
    with VMConnection(host=args.host) as vm:
        print("Connected; collecting host and library metadata...", flush=True)
        report["hostname"] = vm.run("hostname").stdout.strip()
        report["ip_addresses"] = vm.run("hostname -I").stdout.strip().split()
        report["disk_home"] = vm.disk_usage("/home/meow")
        report["virtuoso_running"] = vm.is_virtuoso_running()
        report["spectre_running"] = vm.is_spectre_running()

        cds_path = "/home/meow/jxy/cds.lib"
        cds_text = vm.read_file(cds_path) if vm.exists(cds_path) else ""
        libraries = parse_cds_lib(cds_text)
        report["cds_lib_path"] = cds_path
        report["libraries"] = libraries

        user_libraries: dict[str, object] = {}
        for name, path in libraries.items():
            if not path.startswith("/home/meow/jxy/") or not vm.is_dir(path):
                continue
            entries = vm.list_dir(path, hidden=False)
            cell_dirs = sorted(
                entry
                for entry in entries
                if vm.is_dir(f"{path}/{entry}") and not entry.startswith(".")
            )
            matches = [cell for cell in cell_dirs if "sar_16b" in cell.lower()]
            candidates = [
                cell
                for cell in cell_dirs
                if re.search(r"(?i)(16\s*bit|16b|sar.*16|16.*sar)", cell)
            ]
            user_libraries[name] = {
                "path": path,
                "cell_count": len(cell_dirs),
                "sar_16b_cells": matches,
                "candidate_16b_cells": candidates,
            }
        report["user_library_inventory"] = user_libraries

        print("Scanning /home/meow/jxy for SAR_16B directories...", flush=True)
        find_cmd = (
            "find /home/meow/jxy -maxdepth 7 -type d "
            "\\( -iname '*sar*16b*' -o -iname '*16b*sar*' "
            "-o -iname '*16bit*' -o -iname '*16*bit*sar*' \\) -print"
        )
        result = vm.run(find_cmd, timeout=120)
        report["matching_directories"] = sorted(
            line.strip() for line in result.stdout.splitlines() if line.strip()
        )
        report["find_stderr"] = result.stderr.strip()

        home_find = vm.run(
            "find /home/meow -maxdepth 8 -type d "
            "\\( -iname '*sar*16b*' -o -iname '*16b*sar*' "
            "-o -iname '*16bit*' -o -iname '*16*bit*sar*' \\) "
            "-print 2>/dev/null",
            timeout=180,
        )
        report["matching_directories_home"] = sorted(
            line.strip() for line in home_find.stdout.splitlines() if line.strip()
        )

        process_result = vm.run(
            "ps -eo pid,lstart,args | grep -E '[v]irtuoso|[s]pectre'",
            timeout=30,
        )
        report["cadence_processes"] = [
            line.strip() for line in process_result.stdout.splitlines() if line.strip()
        ]

    print("Writing checkpoint...", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
