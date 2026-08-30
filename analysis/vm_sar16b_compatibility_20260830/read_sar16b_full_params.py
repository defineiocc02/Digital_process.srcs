#!/usr/bin/env python3
"""Read unfiltered CDF parameters for the live SAR_16B_5M integration path."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.schematic.reader import read_schematic


DESIGNS = (
    ("SAR_16B_5M_TB", "TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6"),
    ("SAR_16B_5M_CORE", "CDAC_MAIN_20b"),
    ("SAR_16B_5M_CORE", "CDAC_SWITCH_DRIVER_NEW"),
    ("SAR_16B_5M_CORE", "CDAC_SWITCH_DRIVER_NEW_GATES"),
    ("SAR_16B_5M_CORE", "SAR_Logic_transistor_woflash"),
    ("SAR_16B_5M_CORE", "SS_MAIN"),
    ("SAR_16B_5M_CORE", "COMP_AZ"),
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=120)
    designs: dict[str, object] = {}
    for library, cell in DESIGNS:
        key = f"{library}/{cell}"
        print(f"Reading all CDF parameters: {key}", flush=True)
        designs[key] = read_schematic(
            client,
            library,
            cell,
            include_positions=False,
            param_filters=None,
        )

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "read_only_oa_unfiltered_cdf",
        "designs": designs,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
