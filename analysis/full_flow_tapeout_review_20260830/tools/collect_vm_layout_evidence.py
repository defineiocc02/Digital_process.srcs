#!/usr/bin/env python3
"""Collect read-only Virtuoso OA layout evidence through virtuoso-bridge.

The script never opens a cellview for write and never saves database changes.
It is intended to distinguish a populated OA layout from an empty placeholder;
it is not a DRC, LVS, extraction, or tapeout signoff tool.
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from virtuoso_bridge import VirtuosoClient
from virtuoso_bridge.virtuoso.layout.ops import (
    layout_read_geometry,
    layout_read_summary,
)
from virtuoso_bridge.virtuoso.layout.reader import parse_layout_geometry_output


def _bounds(objects: list[dict[str, Any]]) -> list[list[float]] | None:
    boxes = []
    for obj in objects:
        bbox = obj.get("bbox")
        if (
            isinstance(bbox, list)
            and len(bbox) == 2
            and all(isinstance(point, tuple) and len(point) == 2 for point in bbox)
        ):
            boxes.append(bbox)
    if not boxes:
        return None
    return [
        [min(box[0][0] for box in boxes), min(box[0][1] for box in boxes)],
        [max(box[1][0] for box in boxes), max(box[1][1] for box in boxes)],
    ]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", required=True)
    parser.add_argument("--cell", required=True)
    parser.add_argument("--view", default="layout")
    parser.add_argument("--port", type=int, default=65441)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    client = VirtuosoClient.local(port=args.port, timeout=60)
    summary_result = client.execute_skill(
        layout_read_summary(args.library, args.cell, view=args.view), timeout=60
    )
    geometry_result = client.execute_skill(
        layout_read_geometry(args.library, args.cell, view=args.view), timeout=120
    )

    objects = (
        parse_layout_geometry_output(geometry_result.output)
        if geometry_result.ok
        else []
    )
    shapes = [obj for obj in objects if obj.get("kind") == "shape"]
    instances = [obj for obj in objects if obj.get("kind") == "instance"]
    layer_purpose_counts = Counter(
        f"{obj.get('layer')}/{obj.get('purpose')}" for obj in shapes
    )
    shape_type_counts = Counter(str(obj.get("objType")) for obj in shapes)
    master_counts = Counter(
        f"{obj.get('lib')}/{obj.get('cell')}/{obj.get('view')}" for obj in instances
    )

    payload = {
        "schema": "sar16b-oa-layout-evidence/1",
        "collected_at_utc": datetime.now(timezone.utc).isoformat(),
        "source": {
            "transport": "virtuoso-bridge read-only SKILL",
            "library": args.library,
            "cell": args.cell,
            "view": args.view,
            "local_bridge_port": args.port,
        },
        "scope_warning": (
            "Geometry inventory only. This does not establish DRC, LVS, PEX, "
            "antenna, density, ERC, IR/EM, ESD, or foundry signoff status."
        ),
        "summary_call": {
            "status": str(summary_result.status.value),
            "errors": summary_result.errors,
            "warnings": summary_result.warnings,
            "raw_output": summary_result.output,
        },
        "geometry_call": {
            "status": str(geometry_result.status.value),
            "errors": geometry_result.errors,
            "warnings": geometry_result.warnings,
        },
        "inventory": {
            "object_count": len(objects),
            "shape_count": len(shapes),
            "instance_count": len(instances),
            "aggregate_bbox": _bounds(objects),
            "shape_type_counts": dict(sorted(shape_type_counts.items())),
            "layer_purpose_counts": dict(sorted(layer_purpose_counts.items())),
            "instance_master_counts": dict(sorted(master_counts.items())),
            "instances": instances,
        },
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2), encoding="utf-8")
    print(json.dumps(payload["inventory"], indent=2))
    return 0 if summary_result.ok and geometry_result.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
