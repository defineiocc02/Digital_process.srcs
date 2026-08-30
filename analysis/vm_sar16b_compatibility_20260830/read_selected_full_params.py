#!/usr/bin/env python3
"""Read unfiltered CDF parameters for selected SAR 16-bit hierarchy cells."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.schematic.reader import read_schematic


CELLS = (
    "test_16bit5MSAR_ideal",
    "CDAC",
    "SWITCH_ideal",
    "SAR_LOGIC_ideal",
    "DEC_ideal",
    "COM_ideal",
    "SYNC_ideal",
    "SNDR_DAC",
)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=90)
    cells: dict[str, object] = {}
    for cell in CELLS:
        print(f"Reading all CDF parameters: {cell}", flush=True)
        cells[cell] = read_schematic(
            client,
            "12bit_50M_SAR",
            cell,
            include_positions=False,
            param_filters=None,
        )

    report = {
        "captured_utc": datetime.now(timezone.utc).isoformat(),
        "mode": "read_only_oa_unfiltered_cdf",
        "library": "12bit_50M_SAR",
        "cells": cells,
    }
    args.output.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
