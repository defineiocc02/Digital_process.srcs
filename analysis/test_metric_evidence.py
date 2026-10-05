"""Adversarial controls for evidence routing, identity and frozen-byte retention."""
import hashlib
import json
from pathlib import Path
import subprocess
import sys

import pytest

from analysis import metric_evidence as evidence

ROOT = evidence.ROOT
OLD = "analysis/physical_cdac_mismatch_20260729/outputs_revalidation/summary.json"
BASELINE = "f180d8a4e3ec21bfcc84b904e3672553344b0114"
REPORTS = [
    "analysis/calibration_effectiveness_20260729/generate_report_assets.py",
    "analysis/full_sar_behavioral_20260729/report/generate_report_assets.py",
    "analysis/physical_cdac_mismatch_20260729/report_revalidation/generate_report_assets.py",
]


@pytest.fixture
def isolated(tmp_path):
    registry = json.loads((ROOT / evidence.REGISTRY).read_bytes())
    for path in [evidence.REGISTRY, registry["current"]["path"], *evidence.SOURCES]:
        target = tmp_path / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes((ROOT / path).read_bytes())
    return tmp_path, registry


def save_registry(root, registry):
    (root / evidence.REGISTRY).write_text(json.dumps(registry), encoding="utf-8")


def mutate_snapshot(root, registry, change):
    path = root / registry["current"]["path"]
    data = json.loads(path.read_bytes())
    change(data)
    path.write_text(json.dumps(data), encoding="utf-8")
    registry["current"]["sha256"] = hashlib.sha256(path.read_bytes()).hexdigest()
    save_registry(root, registry)


def test_current_ideal_regression_and_source_identity():
    result = evidence.load_current_metrics(scope="physical_cdac.ideal")
    ideal = result["data"]["direct_quantizer_full_scale"]
    assert result["status"] == "current"
    assert result["sha256"] == "bba44e9f3834f5cc01c572f189ec545de5ff3382f3febc4eab5b5e9901b888dc"
    assert ideal["snr_db"] == pytest.approx(98.07978061038199, abs=1e-10)
    assert ideal["sndr_db"] == pytest.approx(98.0791126132558, abs=1e-10)
    assert result["sha256"] != result["provenance"]["summary_sha256"]
    assert evidence.load_current_metrics()["completed_chips"] == 512


@pytest.mark.parametrize("path", [OLD, "delivery/physical_cdac_revalidation_20260729/evidence/summary.json", "unknown/summary.json"])
def test_historical_mirror_and_unknown_source_are_never_current(path):
    with pytest.raises(evidence.EvidenceError, match="Not registered current"):
        evidence.load_current_metrics(path)


@pytest.mark.parametrize("scope", ["full_sar.main", "self_cal.main", "physical_cdac.sigma", "physical_cdac.amplitude"])
def test_missing_current_scope_does_not_fall_back(scope):
    with pytest.raises(evidence.EvidenceError, match="No published current"):
        evidence.load_current_metrics(scope=scope)


def test_missing_snapshot_does_not_fall_back(isolated):
    root, registry = isolated
    (root / registry["current"]["path"]).unlink()
    with pytest.raises(evidence.EvidenceError, match="Invalid/missing"):
        evidence.load_current_metrics(root=root)


def test_snapshot_bytes_cannot_change_silently(isolated):
    root, registry = isolated
    with (root / registry["current"]["path"]).open("ab") as handle:
        handle.write(b"\n")
    with pytest.raises(evidence.EvidenceError, match="SHA-256 mismatch"):
        evidence.load_current_metrics(root=root)


def test_old_summary_cannot_be_promoted_by_repointing_and_rehashing(isolated):
    root, registry = isolated
    old = root / OLD
    old.parent.mkdir(parents=True)
    old.write_bytes((ROOT / OLD).read_bytes())
    registry["frozen_evidence"] = [r for r in registry["frozen_evidence"] if r["path"] != OLD]
    registry["current"]["path"] = OLD
    registry["current"]["sha256"] = hashlib.sha256(old.read_bytes()).hexdigest()
    save_registry(root, registry)
    with pytest.raises(evidence.EvidenceError, match="Snapshot date/tested commit"):
        evidence.load_current_metrics(root=root)


@pytest.mark.parametrize("field,value,error", [("schema_version", 2, "schema_version"), ("metric_definition", "legacy-toolbox", "metric_definition")])
def test_unsupported_versions_fail(isolated, field, value, error):
    root, registry = isolated
    registry[field] = value
    save_registry(root, registry)
    with pytest.raises(evidence.EvidenceError, match=error):
        evidence.load_current_metrics(root=root)


def test_source_drift_fails(isolated):
    root, _ = isolated
    with (root / "analysis/coherent_metrics.py").open("ab") as handle:
        handle.write(b"\n# source drift\n")
    with pytest.raises(evidence.EvidenceError, match="SHA-256 mismatch"):
        evidence.load_current_metrics(root=root)


def test_provenance_drift_with_new_snapshot_hash_still_fails(isolated):
    root, registry = isolated
    mutate_snapshot(root, registry, lambda d: d["provenance"].update(python="0.0"))
    with pytest.raises(evidence.EvidenceError, match="provenance"):
        evidence.load_current_metrics(root=root)


def test_metric_ordering_even_with_valid_hash_fails(isolated):
    root, registry = isolated
    mutate_snapshot(root, registry, lambda d: d["ideal_acceptance"]["direct_quantizer_full_scale"].update(snr_db=95.6391892))
    with pytest.raises(evidence.EvidenceError, match="SNR/SNDR ordering"):
        evidence.load_current_metrics(root=root)


def test_incomplete_matrix_even_with_valid_hash_fails(isolated):
    root, registry = isolated
    mutate_snapshot(root, registry, lambda d: d.update(main_summary={}))
    with pytest.raises(evidence.EvidenceError, match="decoder matrix"):
        evidence.load_current_metrics(root=root)


def test_frozen_bytes_and_inventory_cannot_be_rewritten_together():
    registry = json.loads((ROOT / evidence.REGISTRY).read_bytes())
    frozen = {r["path"] for r in registry["frozen_evidence"]}
    assert evidence.check_frozen_evidence() == len(frozen)
    assert registry["baseline_commit"] == BASELINE
    # Independent Git anchor defeats changing a historical file and its registry digest together.
    diff = subprocess.run(["git", "diff", "--exit-code", BASELINE, "--", *sorted(frozen)], cwd=ROOT, capture_output=True, text=True)
    assert diff.returncode == 0, diff.stdout + diff.stderr
    tracked = set(subprocess.check_output(["git", "ls-files"], cwd=ROOT, text=True).splitlines())
    baseline = set(subprocess.check_output(["git", "ls-tree", "-r", "--name-only", BASELINE], cwd=ROOT, text=True).splitlines())
    old_output_dirs = {str(Path(p).parent) + "/" for p in baseline if p.endswith("/summary.json")}
    must_remain_frozen = {
        p for p in baseline
        if p.startswith(("delivery/", "archive/"))
        or Path(p).suffix in {".pdf", ".tex", ".csv", ".npz"}
        or (Path(p).suffix == ".json" and not p.startswith("docs/"))
        or any(p.startswith(directory) for directory in old_output_dirs)
        or Path(p).name.startswith("SHA256SUMS")
    }
    assert must_remain_frozen <= frozen, "Baseline evidence must not disappear from the freeze inventory"
    nonhistorical_json = {evidence.REGISTRY, registry["current"]["path"], "docs/LEGACY_SOURCE_MAP.json"}
    machine_records = {p for p in tracked if Path(p).suffix in {".json", ".csv", ".npz"} and p not in nonhistorical_json}
    assert machine_records <= frozen, "Unclassified machine-readable evidence must be registered explicitly"
    assert {p for p in tracked if p.startswith(("delivery/", "archive/"))} <= frozen


@pytest.mark.parametrize("report", REPORTS)
def test_report_defaults_fail_before_any_write(report):
    result = subprocess.run([sys.executable, str(ROOT / report)], cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0
    assert "Historical evidence refused" in result.stderr


@pytest.mark.parametrize("report", REPORTS)
def test_historical_report_requires_fresh_output_and_is_labelled(report, tmp_path):
    output = tmp_path / "report"
    command = [sys.executable, str(ROOT / report), "--historical-evidence", "--outdir", str(output)]
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "HISTORICAL" in result.stderr + result.stdout
    generated = list(output.glob("*.tex"))
    assert generated and all("HISTORICAL" in path.read_text() for path in generated)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0 and "new or empty" in result.stderr


def test_changed_csv_fails_before_report_output(isolated, monkeypatch):
    root, registry = isolated
    rows = root / "old/per_chip.csv"
    rows.parent.mkdir()
    rows.write_bytes(b"snr_db,sndr_db\n100,99\n")
    summary = rows.with_name("summary.json")
    summary.write_bytes(b"{}")
    registry["frozen_evidence"] = [{"path": p.relative_to(root).as_posix(), "sha256": hashlib.sha256(p.read_bytes()).hexdigest(), "status": "historical"} for p in (rows, summary)]
    save_registry(root, registry)
    rows.write_bytes(b"snr_db,sndr_db\n99,100\n")
    monkeypatch.setattr(evidence, "ROOT", root)
    output = root / "new-report"
    monkeypatch.setattr(sys, "argv", ["report", "--historical-evidence", "--outdir", str(output)])
    with pytest.raises(SystemExit) as error:
        evidence.require_historical_report(summary)
    assert error.value.code != 0 and not output.exists()


def test_cli_old_path_is_nonzero_and_emits_no_metrics():
    result = subprocess.run([sys.executable, "-m", "analysis.metric_evidence", "--path", OLD], cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 1
    assert not result.stdout
    assert "Not registered current" in result.stderr
