"""Fail-closed entry to published metrics; historical files remain byte-frozen.

This is an evidence reader, not a campaign runner or an artifact downloader.
The registry hash is for the checked-in snapshot, not the upstream summary.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = "docs/METRICS_CURRENT.json"
METRIC_DEFINITION = "coherent-one-sided-v1"
SCOPES = {"physical_cdac.ideal": "ideal_acceptance", "physical_cdac.main": "main_summary"}
SOURCES = {
    "analysis/coherent_metrics.py",
    "analysis/full_sar_behavioral_20260729/full_sar_model.py",
    "analysis/physical_cdac_mismatch_20260729/physical_cdac.py",
    "analysis/physical_cdac_mismatch_20260729/run_revalidation.py",
}
DECODERS = {
    "NOMINAL_SRM", "CAL_CURRENT_SRM", "CAL_SUM_NORM_SRM",
    "CAL_HEADROOM_GUARD_SRM", "CAL_ZERO_COMP_ERROR_SRM", "ORACLE_SRM",
}


class EvidenceError(ValueError):
    """Missing, obsolete, unsupported or inconsistent metric evidence."""


def _path(root: Path, name: str | Path) -> Path:
    path = Path(name)
    path = (root / path).resolve() if not path.is_absolute() else path.resolve()
    if not path.is_relative_to(root.resolve()):
        raise EvidenceError(f"Evidence path escapes repository: {name}")
    return path


def _verified_bytes(root: Path, record: dict) -> bytes:
    path = _path(root, record["path"])
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != record["sha256"]:
        raise EvidenceError(f"SHA-256 mismatch: {record['path']}")
    return data


def _registry(root: Path) -> dict:
    registry = json.loads((root / REGISTRY).read_bytes())
    if registry.get("schema_version") != 1:
        raise EvidenceError("Unsupported metric registry schema_version")
    if registry.get("metric_definition") != METRIC_DEFINITION:
        raise EvidenceError("Unsupported metric_definition")
    entry = registry["current"]
    if entry.get("status") != "current" or set(entry.get("scopes", [])) != set(SCOPES):
        raise EvidenceError("Invalid current evidence status/scopes")
    frozen_paths = [r["path"] for r in registry["frozen_evidence"]]
    if len(frozen_paths) != len(set(frozen_paths)) or entry["path"] in frozen_paths:
        raise EvidenceError("Duplicate or conflicting evidence classification")
    for record in registry["frozen_evidence"]:
        if record.get("status") != "historical":
            raise EvidenceError("Frozen evidence must remain historical")
    return registry


def _validate_snapshot(snapshot: dict, entry: dict, root: Path) -> None:
    if snapshot.get("date") != entry["date"] or snapshot.get("tested_head_commit") != entry["tested_head_commit"]:
        raise EvidenceError("Snapshot date/tested commit differs from registry")
    if snapshot.get("provenance") != entry["provenance"]:
        raise EvidenceError("Snapshot provenance differs from registry")
    if set(entry["provenance"]["source_sha256"]) != SOURCES:
        raise EvidenceError("Incomplete source provenance")
    for path, digest in entry["provenance"]["source_sha256"].items():
        _verified_bytes(root, {"path": path, "sha256": digest})
    if snapshot.get("main_completed_chips") != 512 or snapshot["config"].get("n_chips") != 512:
        raise EvidenceError("Incomplete physical CDAC evidence")
    rate_decoders = {"CAL_CURRENT_SRM", "CAL_SUM_NORM_SRM", "CAL_HEADROOM_GUARD_SRM"}
    if set(snapshot["main_summary"]) != DECODERS or set(snapshot["pass_rates"]) != rate_decoders:
        raise EvidenceError("Incomplete physical CDAC decoder matrix")
    ideal = snapshot["ideal_acceptance"]
    if ideal.get("passed") is not True:
        raise EvidenceError("Ideal acceptance did not pass")
    for name in ("direct_quantizer_full_scale", "direct_quantizer_backoff", "segmented_cdac_no_srm", "segmented_cdac_exact_physical_residue", "segmented_cdac_expected_srm"):
        _ordering(ideal[name]["snr_db"], ideal[name]["sndr_db"], name)
    for decoder, values in snapshot["main_summary"].items():
        for prefix in ("fullscale", "backoff"):
            snr, sndr = values[prefix + "_snr_db"], values[prefix + "_sndr_db"]
            if set(snr) != set(sndr):
                raise EvidenceError(f"Incompatible SNR/SNDR statistics: {decoder}/{prefix}")
            for stat in sndr:
                # Standard deviations need not be ordered like quantiles/means.
                if stat != "std":
                    _ordering(snr[stat], sndr[stat], f"{decoder}/{prefix}/{stat}")
    for decoder, rates in snapshot["pass_rates"].items():
        if any(rates[p].get("total") != 512 for p in ("fullscale", "backoff")):
            raise EvidenceError(f"Incomplete pass-rate denominator: {decoder}")


def _ordering(snr: float, sndr: float, name: str) -> None:
    if not (math.isfinite(snr) and math.isfinite(sndr)) or snr < sndr - 1e-10:
        raise EvidenceError(f"Invalid SNR/SNDR ordering: {name}")


def load_current_metrics(path: str | Path | None = None, *, scope: str = "physical_cdac.main", root: Path = ROOT) -> dict:
    """Return a labelled current result or fail; never fall back to old summaries."""
    try:
        registry = _registry(root)
        entry = registry["current"]
        if scope not in SCOPES:
            raise EvidenceError(f"No published current evidence for scope {scope!r}; a new revalidation is required")
        if path is not None and _path(root, path) != _path(root, entry["path"]):
            raise EvidenceError(f"Not registered current evidence: {path}; use {REGISTRY}")
        snapshot = json.loads(_verified_bytes(root, entry))
        _validate_snapshot(snapshot, entry, root)
        return {
            "evidence_id": entry["id"], "status": "current",
            "metric_definition": METRIC_DEFINITION, "scope": scope,
            "path": entry["path"], "sha256": entry["sha256"],
            "config": {"behavioral": snapshot["config"], "physical": snapshot["physical_config"]},
            "provenance": snapshot["provenance"],
            "data": snapshot[SCOPES[scope]],
            **({"pass_rates": snapshot["pass_rates"], "completed_chips": snapshot["main_completed_chips"]} if scope == "physical_cdac.main" else {}),
        }
    except EvidenceError:
        raise
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise EvidenceError(f"Invalid/missing metric evidence: {exc}") from exc


def check_frozen_evidence(*, root: Path = ROOT, directory: Path | None = None) -> int:
    """Verify exact checked-in bytes, optionally for one historical input bundle."""
    try:
        records = _registry(root)["frozen_evidence"]
        if directory is not None:
            directory = _path(root, directory)
            records = [r for r in records if _path(root, r["path"]).is_relative_to(directory)]
        if not records:
            raise EvidenceError("Unregistered historical evidence bundle")
        for record in records:
            _verified_bytes(root, record)
        return len(records)
    except EvidenceError:
        raise
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise EvidenceError(f"Invalid/missing frozen evidence: {exc}") from exc


def require_historical_report(summary_path: Path) -> Path:
    """Explicit archival reproduction only; verify companions before any writes."""
    parser = argparse.ArgumentParser(description="Reproduce frozen historical report assets (erratum applies).")
    parser.add_argument("--historical-evidence", action="store_true", help="Acknowledge obsolete spectral metrics; output is not current evidence")
    parser.add_argument("--outdir", type=Path, help="New or empty directory for historical report assets")
    args = parser.parse_args()
    if not args.historical_evidence:
        parser.error(f"Historical evidence refused. Read current metrics with python -m analysis.metric_evidence; archival reproduction requires --historical-evidence --outdir NEW_DIRECTORY")
    if args.outdir is None:
        parser.error("Historical reproduction requires --outdir NEW_DIRECTORY")
    try:
        registry = _registry(ROOT)
        name = summary_path.resolve().relative_to(ROOT).as_posix()
        if name not in {r["path"] for r in registry["frozen_evidence"]}:
            raise EvidenceError("Unregistered historical summary")
        check_frozen_evidence(root=ROOT, directory=summary_path.parent)
        output = args.outdir.resolve()
        if output.exists() and (not output.is_dir() or any(output.iterdir())):
            raise EvidenceError("Historical --outdir must be new or empty")
        if any(_path(ROOT, r["path"]).is_relative_to(output) or output.is_relative_to(_path(ROOT, r["path"]).parent) for r in registry["frozen_evidence"]):
            raise EvidenceError("Historical --outdir overlaps frozen evidence")
        output.mkdir(parents=True, exist_ok=True)
    except (EvidenceError, OSError, ValueError) as exc:
        parser.error(str(exc))
    print("HISTORICAL EVIDENCE: spectral erratum applies; these assets are not current metrics.", file=sys.stderr)
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", help="Explicit source path; only the registered current snapshot is accepted")
    parser.add_argument("--scope", default="physical_cdac.main")
    parser.add_argument("--check", action="store_true", help="Also check every frozen evidence file")
    args = parser.parse_args(argv)
    try:
        result = load_current_metrics(args.path, scope=args.scope)
        if args.check:
            count = check_frozen_evidence()
            print(f"PASS: current evidence and {count} frozen files verified")
        else:
            print(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False))
        return 0
    except EvidenceError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
