#!/usr/bin/env python3
"""Collect small SAR_16B_5M Maestro history logs from the VM read-only."""

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


HISTORY_ROOT = (
    "/home/meow/IC/SAR_16B_5M_TB/"
    "TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6/maestro/results/maestro"
)
MAX_LOG_BYTES = 5 * 1024 * 1024


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    records: list[dict[str, object]] = []
    with VMConnection(host=args.host) as vm:
        result = vm.run(
            f"find '{HISTORY_ROOT}' -maxdepth 2 -type f "
            "-printf '%s\\t%TY-%Tm-%TdT%TH:%TM:%TS\\t%p\\n' | sort -k3",
            timeout=120,
        )
        for line in result.stdout.splitlines():
            fields = line.split("\t", 2)
            if len(fields) != 3:
                continue
            size_text, modified, path = fields
            size = int(size_text)
            record: dict[str, object] = {
                "path": path,
                "size_bytes": size,
                "modified": modified,
            }
            if path.endswith(".log") and size <= MAX_LOG_BYTES:
                try:
                    record["text"] = vm.read_file(path)
                except Exception as exc:
                    record["read_error"] = f"{type(exc).__name__}: {exc}"
            records.append(record)

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "host": args.host,
        "mode": "read_only",
        "history_root": HISTORY_ROOT,
        "records": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.output}: {len(records)} history files")
    for record in records:
        print(f"{record['size_bytes']:>10}  {record['path']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
