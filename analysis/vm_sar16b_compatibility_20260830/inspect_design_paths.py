#!/usr/bin/env python3
"""Locate OA views and simulation artifacts for the VM 16-bit SAR design."""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

VM_REMOTE = Path(r"D:\ReedZhao\vm-remote")
if str(VM_REMOTE) not in sys.path:
    sys.path.insert(0, str(VM_REMOTE))

from vm_base import VMConnection  # noqa: E402


def lines(text: str) -> list[str]:
    return sorted(line.strip() for line in text.splitlines() if line.strip())


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    lib_root = "/home/meow/jxy/12bit_50M_SAR"
    cell = "test_16bit5MSAR_ideal"
    cell_root = f"{lib_root}/{cell}"
    sim_root = "/home/meow/IC/simulation/12bit_50M_SAR"

    report: dict[str, object] = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "host": args.host,
        "mode": "read_only",
        "library_root": lib_root,
        "cell": cell,
    }

    print(f"Connecting to {args.host}...", flush=True)
    with VMConnection(host=args.host) as vm:
        if not vm.is_dir(cell_root):
            raise FileNotFoundError(cell_root)

        views = sorted(vm.list_dir(cell_root, hidden=True))
        report["cell_root"] = cell_root
        report["cell_size"] = vm.du_size(cell_root)
        report["cell_entries"] = views

        view_inventory: dict[str, object] = {}
        for view in views:
            view_path = f"{cell_root}/{view}"
            if vm.is_dir(view_path):
                view_inventory[view] = {
                    "path": view_path,
                    "entries": sorted(vm.list_dir(view_path, hidden=True)),
                    "size": vm.du_size(view_path),
                }
        report["view_inventory"] = view_inventory

        sim_find = vm.run(
            f"find {sim_root} -maxdepth 3 -type d -iname '*16bit*' -print",
            timeout=120,
        )
        simulation_dirs = lines(sim_find.stdout)
        report["simulation_dirs"] = simulation_dirs

        netlists: list[str] = []
        state_files: list[str] = []
        for sim_dir in simulation_dirs:
            net_find = vm.run(
                f"find {sim_dir} -maxdepth 12 -type f "
                "\\( -name 'input.scs' -o -name 'netlist' -o -name '*.scs' \\) -print",
                timeout=120,
            )
            netlists.extend(lines(net_find.stdout))

            state_find = vm.run(
                f"find {sim_dir} -maxdepth 8 -type f "
                "\\( -name 'active.state' -o -name '*.rdb' -o -name '*.sdb' \\) -print",
                timeout=120,
            )
            state_files.extend(lines(state_find.stdout))

        report["netlist_candidates"] = sorted(set(netlists))
        report["maestro_state_candidates"] = sorted(set(state_files))

        shell_find = vm.run(
            f"find {lib_root} -maxdepth 2 -type d "
            "\\( -iname '*dac*' -o -iname '*cdac*' -o -iname '*sar*logic*' "
            "-o -iname '*comparator*' -o -iname '*comp*' -o -iname '*srm*' \\) -print",
            timeout=120,
        )
        report["named_candidate_cells"] = lines(shell_find.stdout)

    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
