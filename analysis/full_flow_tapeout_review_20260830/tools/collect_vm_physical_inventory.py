#!/usr/bin/env python3
"""Collect a read-only SAR_16B physical-deliverable inventory over SSH."""

from __future__ import annotations

import argparse
import json
import subprocess
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath


ROOTS = (
    "/home/meow/IC/SAR_16B_5M_CORE",
    "/home/meow/IC/SAR_16B_5M_EXP",
    "/home/meow/IC/SAR_16B_5M_TB",
    "/home/meow/IC/simulation/SAR_16B_5M_TB",
)


def classify(path: str) -> list[str]:
    lower = path.lower()
    suffix = PurePosixPath(lower).suffix
    categories: list[str] = []
    if lower.endswith("/layout/layout.oa"):
        categories.append("oa_layout")
    if suffix in {".gds", ".gdsii", ".oas", ".oasis"}:
        categories.append("stream_out")
    if suffix in {".lef", ".def"}:
        categories.append("place_route_exchange")
    if suffix in {".spef", ".sdf", ".dspf", ".spf", ".pxi", ".pex"}:
        categories.append("extracted_or_timing")
    basename = PurePosixPath(lower).name
    signoff_tokens = ("drc", "lvs", "antenna", "density", "erc", "emir", "irdrop", "ir_drop")
    if any(token in basename for token in signoff_tokens):
        categories.append("signoff_named_file")
    return categories


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="192.168.38.140")
    parser.add_argument("--user", default="meow")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    remote_command = "find " + " ".join(ROOTS) + " -type f -printf '%p\\t%s\\t%TY-%Tm-%TdT%TH:%TM:%TS%Tz\\n' 2>/dev/null"
    proc = subprocess.run(
        [
            "ssh",
            "-o",
            "BatchMode=yes",
            "-o",
            "ConnectTimeout=30",
            f"{args.user}@{args.host}",
            remote_command,
        ],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    files = []
    categorized: dict[str, list[dict[str, object]]] = defaultdict(list)
    for line in proc.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 3:
            continue
        path, size, modified = fields
        entry = {"path": path, "size_bytes": int(size), "modified": modified}
        files.append(entry)
        for category in classify(path):
            categorized[category].append(entry)

    expected_categories = (
        "oa_layout",
        "stream_out",
        "place_route_exchange",
        "extracted_or_timing",
        "signoff_named_file",
    )
    payload = {
        "schema": "sar16b-vm-physical-inventory/1",
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": {"host": args.host, "user": args.user, "roots": ROOTS},
        "read_only": True,
        "ssh_exit_code": proc.returncode,
        "ssh_stderr": proc.stderr.strip(),
        "total_files_scanned": len(files),
        "categories": {name: categorized.get(name, []) for name in expected_categories},
        "interpretation_rule": (
            "Absence from this inventory means no matching file was found under the four "
            "declared SAR_16B roots. It does not prove absence elsewhere on the VM."
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps({key: len(value) for key, value in payload["categories"].items()}, indent=2))
    return proc.returncode


if __name__ == "__main__":
    raise SystemExit(main())
