#!/usr/bin/env python3
"""Export small text HDL/model views from the live VM without modifying it."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

VM_REMOTE = Path(r"D:\ReedZhao\vm-remote")
if str(VM_REMOTE) not in sys.path:
    sys.path.insert(0, str(VM_REMOTE))

from vm_base import VMConnection  # noqa: E402


REMOTE_ROOTS = (
    "/home/meow/IC/SAR_16B_5M_CORE",
    "/home/meow/IC/SAR_16B_5M_EXP",
    "/home/meow/IC/SAR_16B_5M_TB",
)
TEXT_VIEW_NAMES = {
    "systemVerilog",
    "functional",
    "veriloga",
    "config",
    "ams_state1",
    "spectre_state1",
    "spectre_state2",
}
MAX_TEXT_BYTES = 2 * 1024 * 1024


def relative_snapshot_path(remote_path: str) -> Path:
    parts = PurePosixPath(remote_path).parts
    try:
        ic_index = parts.index("IC")
    except ValueError as exc:
        raise ValueError(f"Path is outside /home/meow/IC: {remote_path}") from exc
    return Path(*parts[ic_index + 1 :])


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    records: list[dict[str, object]] = []

    with VMConnection(host=args.host) as vm:
        for root in REMOTE_ROOTS:
            result = vm.run(
                f"find '{root}' -type f -printf '%s\\t%p\\n' | sort -k2",
                timeout=180,
            )
            for line in result.stdout.splitlines():
                fields = line.split("\t", 1)
                if len(fields) != 2:
                    continue
                size = int(fields[0])
                remote_path = fields[1]
                path_parts = set(PurePosixPath(remote_path).parts)
                if not (path_parts & TEXT_VIEW_NAMES):
                    continue

                record: dict[str, object] = {
                    "remote_path": remote_path,
                    "size_bytes": size,
                }
                if size > MAX_TEXT_BYTES:
                    record["status"] = "skipped_too_large"
                    records.append(record)
                    continue

                try:
                    content = vm.read_file(remote_path)
                except Exception as exc:
                    record["status"] = "read_failed"
                    record["error"] = f"{type(exc).__name__}: {exc}"
                    records.append(record)
                    continue

                local_path = args.output_dir / relative_snapshot_path(remote_path)
                local_path.parent.mkdir(parents=True, exist_ok=True)
                local_path.write_text(content, encoding="utf-8")
                digest = hashlib.sha256(content.encode("utf-8")).hexdigest()
                record.update(
                    {
                        "status": "exported",
                        "local_path": str(local_path),
                        "sha256": digest,
                    }
                )
                records.append(record)
                print(f"Exported {remote_path} -> {local_path}")

    manifest = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "host": args.host,
        "mode": "read_only_remote_export",
        "records": records,
    }
    args.manifest.parent.mkdir(parents=True, exist_ok=True)
    args.manifest.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote manifest {args.manifest} ({len(records)} records)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
