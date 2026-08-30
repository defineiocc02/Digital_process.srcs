#!/usr/bin/env python3
"""Read the SAR_16B_5M top Maestro setup in a temporary background session."""

from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.maestro import close_session, open_session
from virtuoso_bridge.virtuoso.maestro.reader.bundle import full_bundle


LIBRARY = "SAR_16B_5M_TB"
CELL = "TEST_TRAN_ALL_TRANSISTOR_wFLash_ver6"
VIEW = "maestro"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=120)
    session = open_session(client, LIBRARY, CELL)
    error: BaseException | None = None
    try:
        bundle = full_bundle(
            client,
            sess=session,
            lib=LIBRARY,
            cell=CELL,
            view=VIEW,
        )
        report = {
            "captured_utc": datetime.now(timezone.utc).isoformat(),
            "mode": "read_only_background_maestro",
            "library": LIBRARY,
            "cell": CELL,
            "view": VIEW,
            "session": session,
            "test": bundle.get("test", ""),
            "current_history": bundle.get("current_history", ""),
            "hist_files": bundle.get("hist_files", []),
            "hist_files_mtime": bundle.get("hist_files_mtime", []),
            "raw_sections": bundle.get("raw_sections", []),
        }
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"Wrote {args.output}")
    except BaseException as exc:
        error = exc
        raise
    finally:
        try:
            close_session(client, session)
        except Exception:
            if error is None:
                raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
